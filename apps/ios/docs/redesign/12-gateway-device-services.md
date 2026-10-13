# Gateway Connection & Device Services

This section documents the complete connection plumbing and device-capability service layer that sits beneath the visible UI: how the iOS app discovers, trusts, authenticates, and connects to a gateway over WebSocket; how it tracks health; how credentials are persisted in the Keychain; how pre-connect TCP and TLS fingerprint probes work; what the connection-issue model looks like; and how each device service (network status, location, photo library, screen/canvas, push relay) fulfills its contract with the gateway node session.

---

## 1. GatewayConnectConfig

**File:** `Sources/Gateway/GatewayConnectConfig.swift`

`GatewayConnectConfig` is the immutable, single-source-of-truth parameter bundle handed to `NodeAppModel.applyGatewayConnectConfig(_:)`. It represents one complete "connect attempt," covering both sessions the app maintains simultaneously:

- A `role=node` WebSocket for device-capability invocations (`node.invoke.*`).
- A `role=operator` WebSocket for chat/talk/config events.

### Fields

| Field | Type | Purpose |
|---|---|---|
| `url` | `URL` | WebSocket endpoint (`wss://` or `ws://`). |
| `stableID` | `String` | Caller-supplied route identifier. Drives credential and TLS pin lookups. |
| `tls` | `GatewayTLSParams?` | TLS pin and TOFU policy; `nil` = unauthenticated plaintext. |
| `token` | `String?` | Operator auth token. |
| `bootstrapToken` | `String?` | One-time pairing bootstrap token. |
| `password` | `String?` | Password credential (used when token is absent). |
| `nodeOptions` | `GatewayConnectOptions` | Node-role session options: caps, commands, permissions, clientId, role, clientMode, display name, device auth policy. |

### effectiveStableID

```swift
var effectiveStableID: String {
    let trimmed = self.stableID.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return self.url.absoluteString }
    return trimmed
}
```

Falls back to URL identity when the caller provides no stable ID. Used for UI ownership and event routing.

### Equality / change detection

`hasSameConnectionInputs(as:)` does a field-by-field comparison including:
- `url`, `stableID`, `token`, `bootstrapToken`, `password`
- TLS params (required, expectedFingerprint, allowTOFU, storeKey)
- Node options: role, scopesAreExplicit, clientId, clientMode, clientDisplayName, deviceIdentityProfile, includeDeviceIdentity, allowStoredDeviceAuth, deviceAuthGatewayID, sorted+trimmed scopes/caps/commands, permissions

Scopes, caps, and commands are normalized before comparison: each element is whitespace-trimmed, empty strings are dropped, and the result is sorted. This means order changes do not trigger a reconnect.

---

## 2. GatewayConnectionController

**File:** `Sources/Gateway/GatewayConnectionController.swift`

`@MainActor @Observable final class GatewayConnectionController`

This is the top-level orchestrator. It owns Bonjour discovery, TLS fingerprint probing, trust prompt state, auto-connect logic, reconnect suppression, gateway forget/cleanup, and ultimately calls `NodeAppModel.applyGatewayConnectConfig(_:)` to activate a connection.

### Key constants

| Constant | Value | Context |
|---|---|---|
| `GatewayTLSFingerprintProbeBudget.tcpConnectTimeoutSeconds` | `3.0` | TCP reachability step before TLS fingerprint probe. |
| `GatewayTLSFingerprintProbeBudget.tlsHandshakeTimeoutSeconds` | `10.0` | Full TLS handshake budget during fingerprint capture. |
| `GatewaySetupRouteProbeBudget.tcpConnectTimeoutSeconds` | `2.0` | Setup-link multi-endpoint TCP route selection. |

### Observable published state

| Property | Type | Updated by |
|---|---|---|
| `gateways` | `[GatewayDiscoveryModel.DiscoveredGateway]` | Discovery observation loop. |
| `discoveryStatusText` | `String` | Discovery observation loop. |
| `discoveryDebugLog` | `[GatewayDiscoveryModel.DebugLogEntry]` | Discovery observation loop. |
| `pendingTrustPrompt` | `TrustPrompt?` | Set when a first-time TLS fingerprint must be reviewed by the user. |

### TrustPrompt

```swift
struct TrustPrompt: Identifiable, Equatable {
    let stableID: String
    let gatewayName: String
    let host: String
    let port: Int
    let fingerprintSha256: String
    let isManual: Bool
    var id: String { self.stableID }
}
```

### AutoConnectSuppressionLease

```swift
struct AutoConnectSuppressionLease {
    fileprivate let generation: UInt64
    fileprivate let previousAutoReconnectEnabled: Bool
    fileprivate let restoresAutoReconnect: Bool
    fileprivate let suspendedConfig: GatewayConnectConfig?
}
```

The generation system prevents stale connect attempts from racing each other. Every explicit connect attempt, trust probe, and cancellation atomically advances a `connectAttemptGeneration: UInt64` counter. All async work compares against the generation that was current at dispatch time; generation mismatch means the result is silently discarded.

### Initialization

```swift
init(
    appModel: NodeAppModel,
    startDiscovery: Bool = true,
    deferDiscoveryUntilLocalNetworkRequest: Bool = false,
    tcpReachabilityProbe: GatewayTCPReachabilityProbe = defaultGatewayTCPReachabilityProbe,
    tlsFingerprintProbe: GatewayTLSFingerprintProbeFunction = defaultGatewayTLSFingerprintProbe,
    serviceEndpointResolver: GatewayServiceEndpointResolver? = nil,
    forceReconnectReset: GatewayForceReconnectReset = ...,
    persistTLSFingerprint: GatewayTLSFingerprintPersist = ...)
```

On init:
1. Calls `GatewaySettingsStore.bootstrapPersistence()` — ensures stable instance ID, migrates legacy gateway registry, migrates legacy credential bundles.
2. Calls `migrateLegacyDeviceAuth()` — migrates unscoped device auth tokens and relay credentials to the current scoped format.
3. Reads `UserDefaults.standard.bool(forKey: "gateway.discovery.debugLogs")` to configure debug logging.
4. Calls `updateFromDiscovery()` and `observeDiscovery()` to pull the initial (empty) discovery state.
5. Starts the Bonjour browser if `discoveryEnabled && localNetworkAccessRequested`.

### Port resolution

```swift
static func resolvedManualPort(host: String, port: Int) -> Int? {
    if port > 0 { return port <= 65535 ? port : nil }
    let lower = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if lower.hasSuffix(".ts.net") || lower.hasSuffix(".ts.net.") { return 443 }
    return 18789
}
```

- Port `0` or negative → default: `.ts.net` hosts get 443, everything else gets 18789.
- Port `> 65535` → invalid, returns `nil`.

### TLS policy for manual connects

```swift
static func manualTransportPresentation(host: String, requestedTLS: Bool) -> GatewayManualTransportPresentation
```

```
requiresTLS = host is non-empty AND NOT a local-network host (loopback / RFC-1918 / .local)
effectiveTLS = requestedTLS || requiresTLS
helperText = "Secure connection is required for this host." (when requiresTLS)
           | nil (when effectiveTLS && !requiresTLS)
           | "Use only on a trusted private network." (when !effectiveTLS)
```

### Manual stable ID

`manual|<host.lowercased()>|<port>` — keyed in `ManualAuthOverride.manualStableID(host:port:)`.

### Connect flows

#### connectDiscoveredGateway

1. Begins a connect attempt (suppression lease + generation reservation).
2. Waits for any pending forget-cleanup on the same stableID.
3. Reads `node.instanceId` from `UserDefaults`; returns an error if empty.
4. Resolves the service endpoint via DNS SRV/A/AAAA (NWBrowser `.service` endpoint).
5. Discovery connects always require TLS (`tlsRequired = true`). Refuses to connect if neither `gateway.tlsEnabled` nor a stored TLS pin exists.
6. If TLS required and no stored pin exists: runs `probeTLSFingerprint` (TCP first, then TLS handshake). On fingerprint result → sets `pendingTrustPrompt` so the UI can present the trust dialog. On failure → returns a user-facing error string.
7. If a stored pin exists: builds `GatewayTLSParams(required: true, expectedFingerprint: stored, allowTOFU: false, storeKey: stableID)`.
8. Upserts a `GatewayRegistryEntry(kind: .discovered)` and calls `startAutoConnect`.

#### connectManual

Same structure but:
- Uses `resolvedManualPort` and `resolveManualUseTLS`.
- Computes stableID as `manual|<host>|<port>`.
- TLS probe runs on first-time connects (no stored pin) **and** on `forceReconnect`.
- For `forceReconnect` with an existing pin: probe confirms reachability. If the fingerprint is already trusted, falls through to connect without re-prompting. If there is no stored pin yet, prompts trust.
- Includes `ManualAuthOverride` handling: setup-link credentials are endpoint-scoped and suppress device auth.

#### connectActiveGateway

Reconnects the entry recorded as active in `GatewaySettingsStore`. For discovered gateways, falls back to the most recently connected manual gateway if the discovered gateway is not currently visible on the network.

#### switchToGateway(stableID:)

Loads the registry entry, sets it active in the registry, then dispatches to `connectManual` or `connectDiscoveredGateway`.

#### forgetGateway(stableID:)

Synchronous portion:
- Removes from `GatewaySettingsStore` registry.
- Cancels any in-flight connect attempt for this gateway.
- Calls `appModel.disconnectForgottenGateway`.
- Clears legacy UserDefaults keys, gateway credentials, custom headers, TLS pin, clientId override, selected agent ID, share relay config.
- Clears device auth tokens for both primary and share-extension identities, for both `node` and `operator` roles.

Async cleanup task:
- Waits for gateway session reset.
- Runs a second `clearDeviceAuthTokens` pass (a handshake racing teardown can persist a token after the first cleanup — see inline comment at `Sources/Gateway/GatewayConnectionController.swift:575`).
- Purges the chat transcript cache for this gateway.

Forget cleanups are tracked in `pendingForgetCleanups: [String: (id: UUID, task: Task<Void, Never>)]`. If `connectDiscoveredGateway` or `connectManual` is called for an ID with a pending forget cleanup, it awaits the cleanup task before proceeding.

### Auto-connect logic

`maybeAutoConnect()` fires whenever discovery updates occur and no suppression is active, `didAutoConnect == false`, the app model has no active server name, and `UserDefaults.standard.bool(forKey: "gateway.autoconnect")` is true:

1. If the active registry entry is a manual gateway with a saved host/port and a stored TLS pin → auto-connect.
2. If the active entry is discovered and visible in `gateways` with a stored TLS pin → `connectDiscoveredGateway`.
3. If the active entry is discovered but not visible → fall back to the most recently connected manual gateway (by `lastConnectedAtMs`; tie-broken by reverse stableID order).
4. Check `gateway.manual.enabled` (legacy UserDefaults) and `gateway.manual.host`/`port`/`tls`.
5. Check `gateway.preferredStableID` and `gateway.lastDiscoveredStableID` against current discovered gateways.
6. If exactly one discovered gateway has a stored TLS pin → auto-connect to it.

**Security invariant:** Auto-connect only proceeds to gateways that have a stored TLS fingerprint pin. First-time connects always require explicit user trust.

`attemptAutoReconnectIfNeeded()` is called on scene becoming active and on local network access grant. It resets `didAutoConnect` and calls `maybeAutoConnect()`.

### Scene phase handling

| Phase | Discovery | Auto-reconnect |
|---|---|---|
| `.background` | `discovery.stop()` | No |
| `.active` / `.inactive` | `discovery.start()` | Yes |

Discovery is never started before `localNetworkAccessRequested` is set to true. The flag is set by `requestLocalNetworkAccess(reason:)`, which is called explicitly before every connect attempt.

### Trust prompt lifecycle

1. `probeTLSFingerprint(host:port:url:queueLabel:)` is called: TCP reachability first (3s budget), then TLS handshake probe (10s budget).
2. On `.fingerprint(fp)`: `pendingTrustPrompt` and `pendingTrustConnect` are both set.
3. User taps **Accept** → `acceptPendingTrustPrompt()`: persists the fingerprint via `persistTLSFingerprint`, upserts registry entry, clears prompt, calls `startAutoConnect`.
4. User taps **Decline** → `declinePendingTrustPrompt()`: clears prompt, sets status to "Offline", calls `resumeAutoConnect`.
5. Clearing the prompt also atomically increments `trustProbeGeneration`, so any late-arriving probe result from a superseded probe cannot restore a stale prompt.

### TLS certificate rotation

`trustRotatedGatewayCertificate(from:)` replaces the stored pin for the active gateway and calls `applyGatewayConnectConfig` with a refreshed `GatewayTLSParams`. If no active config exists, falls back to `connectActiveGateway()`.

### Connect options assembly

`makeConnectOptions(stableID:deviceAuthGatewayID:allowStoredDeviceAuth:)` builds `GatewayConnectOptions`:

- **role**: always `"node"`
- **clientMode**: always `"node"`
- **clientId**: `gateway.clientIdOverride.<stableID>` from UserDefaults, or `gateway.manual.clientId` from UserDefaults, or `"openclaw-ios"` as the hardcoded default.
- **clientDisplayName**: resolved via `NodeDisplayName.resolve(existing:deviceName:interfaceIdiom:)` from `UIDevice.current.name`. If the existing stored name is empty or "generic," it is overwritten with the resolved value and saved to `node.displayName` in UserDefaults.

#### Capability list (currentCaps)

Always included:
- `canvas`, `screen`, `device`, `talk`, `photos`, `contacts`, `calendar`, `reminders`

Conditionally included:
- `camera` — if `UserDefaults.object(forKey: "camera.enabled")` is nil (default on) OR `bool(forKey: "camera.enabled")` is true.
- `voiceWake` — if `VoiceWakePreferences.enabledKey` bool is true.
- `location` — if `location.enabledMode` (stored as String in UserDefaults) parses to any `OpenClawLocationMode` value other than `.off`.
- `watch` — if `WatchMessagingService.isSupportedOnDevice()`.
- `motion` — if `CMMotionActivityManager.isActivityAvailable() || CMPedometer.isStepCountingAvailable()`.

#### Command list (currentCommands)

Always included: `canvas.present`, `canvas.hide`, `canvas.navigate`, `canvas.evalJS`, `canvas.snapshot`, `canvas-a2ui.push`, `canvas-a2ui.pushJSONL`, `canvas-a2ui.reset`, `screen.record`, `system.notify`, `chat.push`, `talk.pttStart`, `talk.pttStop`, `talk.pttCancel`, `talk.pttOnce`.

Conditionally (mirrors capability gates): `camera.list`, `camera.snap`, `camera.clip` (camera); `location.get` (location); `device.status`, `device.info` (device); `watch.status`, `watch.notify` (watch); `photos.latest` (photos); `contacts.search`, `contacts.add` (contacts); `calendar.events`, `calendar.add` (calendar); `reminders.list`, `reminders.add` (reminders); `motion.activity`, `motion.pedometer` (motion).

#### Permissions dictionary (currentPermissions)

Populated by reading system authorization status at connect time (async; runs on a detached utility task for `CLLocationManager.locationServicesEnabled()`):

| Key | Source |
|---|---|
| `"camera"` | `AVCaptureDevice.authorizationStatus(for: .video) == .authorized` |
| `"microphone"` | `AVCaptureDevice.authorizationStatus(for: .audio) == .authorized` |
| `"speechRecognition"` | `SFSpeechRecognizer.authorizationStatus() == .authorized` |
| `"location"` | `locationServicesEnabled && status == .authorizedAlways\|.authorizedWhenInUse` |
| `"screenRecording"` | `RPScreenRecorder.shared().isAvailable` |
| `"photos"` | `PhotoLibraryAccess.canRead(status)` — `.authorized` or `.limited` |
| `"contacts"` | `CNContactStore.authorizationStatus == .authorized\|.limited` |
| `"calendar"` | `EKAuthorizationStatus == .fullAccess\|.writeOnly` |
| `"reminders"` | `EKAuthorizationStatus == .fullAccess\|.writeOnly` |
| `"motion"` | `CMMotionActivityManager.authorized \|\| CMPedometer.authorized` |
| `"watchSupported"` | `WatchMessagingService.currentStatusSnapshot().supported` |
| `"watchPaired"` | `WatchMessagingService.currentStatusSnapshot().paired` |
| `"watchAppInstalled"` | `WatchMessagingService.currentStatusSnapshot().appInstalled` |
| `"watchReachable"` | `WatchMessagingService.currentStatusSnapshot().reachable` |

Because permission reads can suspend long enough for a model-owned reconnect reset to start, `waitForGatewaySessionResetIfNeeded()` is called again immediately after the permissions are resolved, before the synchronous `applyGatewayConnectConfig` call (see inline comment at `Sources/Gateway/GatewayConnectionController.swift:1111`).

### GatewayTLSFingerprintProbe (private inner class)

```swift
private final class GatewayTLSFingerprintProbe: NSObject, URLSessionDelegate, URLSessionTaskDelegate
```

- Uses an ephemeral `URLSession` configured with `timeoutIntervalForRequest` and `timeoutIntervalForResource` both set to `tlsHandshakeTimeoutSeconds` (10 s).
- Opens a `webSocketTask(with:)` to trigger the TLS handshake.
- In `urlSession(_:didReceive:completionHandler:)`: extracts the leaf certificate from `SecTrustCopyCertificateChain`, computes SHA-256 of its DER data (CryptoKit `SHA256.hash`), formats as 64 lowercase hex characters.
- Calls `completionHandler(.cancelAuthenticationChallenge, nil)` to abort the connection after reading the cert.
- On task completion without a challenge (TLS unavailable) → `.failure(.tlsUnavailable)`.
- On URL error mapping:
  - `.timedOut` → `.tlsHandshakeTimeout`
  - `.cannotFindHost`, `.dnsLookupFailed`, `.cannotConnectToHost`, `.notConnectedToInternet`, `.internationalRoamingOff`, `.callIsActive`, `.dataNotAllowed` → `.endpointUnreachable`
  - `.networkConnectionLost`, `.secureConnectionFailed`, `.cannotParseResponse`, `.badServerResponse` → `.tlsUnavailable`
  - Unknown → `.tlsUnavailable`
- A DispatchQueue timer fires at `timeoutSeconds` and calls `finish(.failure(.tlsHandshakeTimeout))` as a hard backstop in case URLSession never delivers a delegate callback.
- `OSAllocatedUnfairLock<ProbeState>` ensures exactly one `finish` call is honored (idempotent).

### ManualAuthOverride

```swift
struct ManualAuthOverride: Equatable {
    let token: String?
    let bootstrapToken: String?
    let password: String?
    let targetStableID: String?
    let suppressStoredDeviceAuth: Bool
}
```

- `explicit(token:bootstrapToken:password:targetStableID:suppressStoredDeviceAuth:)` — trims and nils-out empty values.
- `normalized(token:bootstrapToken:password:)` — returns `nil` if all three are nil/empty.
- `persisted(instanceId:targetStableID:)` — loads the current credential bundle and returns a matching override.
- `SetupAuth` inner struct bundles credentials from a deep link. Its `manualAuthOverride` always sets `suppressStoredDeviceAuth: true` because setup-link credentials are endpoint-scoped and must not fall back to device auth.
- `currentManualInput(token:pendingOverride:password:targetStableID:)` — when the endpoint changes relative to a pending setup-link override, it strips any field the user did not explicitly replace to prevent forwarding source credentials to a different gateway.

---

## 3. GatewayDiscoveryModel

**File:** `Sources/Gateway/GatewayDiscoveryModel.swift`

`@MainActor @Observable final class GatewayDiscoveryModel`

Wraps `NWBrowser` for Bonjour gateway discovery.

### DiscoveredGateway

```swift
struct DiscoveredGateway: Identifiable, Equatable {
    var name: String
    var endpoint: NWEndpoint
    var stableID: String
    var debugID: String
    var lanHost: String?
    var tailnetDns: String?
    var gatewayPort: Int?
    var canvasPort: Int?
    var tlsEnabled: Bool
    var tlsFingerprintSha256: String?
    var cliPath: String?
}
```

Identity is `stableID` (derived from the NWEndpoint via `GatewayEndpointID.stableID`).

### TXT record parsing

| TXT key | Field | Type |
|---|---|---|
| `displayName` | `name` (preferred over Bonjour service name) | String |
| `lanHost` | `lanHost` | String |
| `tailnetDns` | `tailnetDns` | String |
| `gatewayPort` | `gatewayPort` | Int |
| `canvasPort` | `canvasPort` | Int |
| `gatewayTls` | `tlsEnabled` | Bool (`"1"`, `"true"`, `"yes"`) |
| `gatewayTlsSha256` | `tlsFingerprintSha256` | String |
| `cliPath` | `cliPath` | String |

TXT values are whitespace-trimmed; empty values are treated as nil/absent. The comment `"TXT is unauthenticated; do not route via TXT"` (at `Sources/Gateway/GatewayConnectionController.swift:269`) means TXT data informs the display and hint fields only; routing decisions go through the resolved SRV/A/AAAA target.

### Name prettification

`prettifyInstanceName` applied to the decoded Bonjour service name and to `displayName` TXT:
1. Collapse internal whitespace runs to single spaces.
2. Strip ` (OpenClaw)` suffix.
3. Strip trailing ` (N)` numeric suffix using regex `\s+\(\d+\)$`.
4. Trim leading/trailing whitespace.

### Domains and service type

Uses `OpenClawBonjour.gatewayServiceDomains` (from `OpenClawKit`) and `OpenClawBonjour.gatewayServiceType`. One `NWBrowser` per domain.

### Debug log

Bounded at 200 entries (oldest dropped when exceeded). Enabled via `setDebugLoggingEnabled(true)`. The enabled flag is read from `UserDefaults.standard.bool(forKey: "gateway.discovery.debugLogs")` in `GatewayConnectionController.init`.

### Lifecycle

- `start()`: idempotent (returns immediately if browsers already exist). Creates one browser per domain.
- `stop()`: cancels all browsers, clears `gatewaysByDomain`, `statesByDomain`, resets `gateways = []`, sets `statusText = "Stopped"`.
- `recomputeGateways()`: merges all per-domain result lists, sorts by `localizedCaseInsensitiveCompare`, logs added/removed counts.

---

## 4. GatewayHealthMonitor

**File:** `Sources/Gateway/GatewayHealthMonitor.swift`

`@MainActor final class GatewayHealthMonitor`

A simple periodic health-check runner. Not observable — callers hold a reference and call `start`/`stop`.

### Default configuration

```swift
Config(intervalSeconds: 15, timeoutSeconds: 5, maxFailures: 3)
```

### Behavior

- Runs a loop: execute `check()` with a timeout, increment/reset failure counter, sleep for `intervalSeconds`.
- `onFailure` is called when `failures >= max(1, config.maxFailures)`, then `failures` is reset to 0.
- Each check is wrapped with `AsyncTimeout.withTimeout(seconds: timeoutSeconds, onTimeout: { timeoutError })`. Any error from `check()` or the timeout counts as a failure.
- Sleep uses `nanoseconds = UInt64(intervalSeconds * 1_000_000_000)`. If `intervalSeconds == 0`, calls `Task.yield()` instead.
- `stop()` cancels the task and sets `task = nil`; calling `start()` again after `stop()` creates a fresh task.

---

## 5. GatewaySettingsStore

**File:** `Sources/Gateway/GatewaySettingsStore.swift`

`enum GatewaySettingsStore` — all static methods, no stored state.

### Keychain services

| Service identifier | Purpose |
|---|---|
| `"ai.openclawfoundation.app.gateway"` | Gateway registry, credentials, custom headers, preferred/last-discovered IDs. |
| `"ai.openclawfoundation.app.node"` | Stable instance ID. |
| `"ai.openclawfoundation.app.talk"` | Talk provider API keys. |
| `"ai.openclawfoundation.app.gateway.custom-headers"` | Per-gateway proxy custom headers (Cloudflare Access-style tokens). |

In DEBUG builds under XCTest, the gateway service is suffixed with `.tests` to keep test fixtures isolated from installed-app state.

### UserDefaults keys (canonical)

| Key | Purpose |
|---|---|
| `"node.instanceId"` | Instance ID (mirrored from Keychain). |
| `"gateway.preferredStableID"` | Preferred gateway for auto-connect. |
| `"gateway.lastDiscoveredStableID"` | Last gateway seen via Bonjour. |
| `"gateway.clientIdOverride.<stableID>"` | Per-gateway client ID override. |
| `"gateway.selectedAgentId.<stableID>"` | Per-gateway selected agent. |
| `"gateway.autoconnect"` | Bool: auto-connect enabled. |

Legacy keys (cleared after migration): `gateway.last.kind`, `gateway.last.host`, `gateway.last.port`, `gateway.last.tls`, `gateway.last.stableID`, `gateway.manual.host`, `gateway.manual.port`, `gateway.manual.tls`, `gateway.manual.enabled`.

### GatewayRegistry

```swift
struct GatewayRegistry: Codable, Equatable {
    var version: Int = 1
    var activeStableID: String?
    var entries: [GatewayRegistryEntry] = []
}
```

Stored as a single JSON string in Keychain account `"gateway-registry"` under the gateway service. Registry version must equal `1` to decode; any other version returns `.empty`.

On write, entries are:
1. Validated and normalized (empty stableID → dropped; manual entries without valid host/port → dropped; port must be in `1...65535`).
2. De-duplicated by stableID (first wins after normalization).
3. Sorted by `name` ascending (tie-broken by `stableID` ascending).
4. Encoded with `JSONEncoder` using `.sortedKeys` formatting.

`activeStableID` is cleared if it no longer matches any entry after normalization.

### GatewayRegistryEntry

```swift
struct GatewayRegistryEntry: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case manual, case discovered }
    var stableID: String
    var kind: Kind
    var name: String
    var host: String?   // nil for discovered
    var port: Int?      // nil for discovered
    var useTLS: Bool
    var lastConnectedAtMs: Int?
}
```

For `kind == .discovered`, `host` and `port` are always nil (discovered gateways are addressed by Bonjour resolution, not a saved host/port).

### Credential bundle

Credentials are stored as a single JSON object in one Keychain item (atomically, to avoid cross-gateway credential leakage if a partial update occurred):

```swift
private struct GatewayCredentialBundle: Codable {
    let gatewayStableID: String
    let suppressStoredDeviceAuth: Bool
    let token: String?
    let bootstrapToken: String?
    let password: String?
}
```

Keychain account format: `"gateway-credentials.<instanceId>.<stableID>"`.

**Migration path:** Legacy per-field accounts (`gateway-token.<instanceId>`, `gateway-bootstrap-token.<instanceId>`, `gateway-password.<instanceId>`) and legacy bundle account (`gateway-credentials.<instanceId>`) are cleaned up after successful migration to scoped accounts.

`saveGatewayCredentials` deletes the Keychain item when all three credential fields are nil/empty AND `suppressStoredDeviceAuth` is false. If `saveString` fails (replacement failure), the prior item is left unchanged — callers treat this as an uncommitted update.

`completeGatewayCredentialHandoff` clears `bootstrapToken` and sets `suppressStoredDeviceAuth = false` after device-token issuance. This is a durable one-way transition: a relaunch must never see a spent bootstrap token while stored device auth is still disabled.

### GatewayDiagnostics

A dual-sink logger: `os.Logger(subsystem: "ai.openclawfoundation.app", category: "GatewayDiag")` plus a rolling file log at `<Caches>/openclaw-gateway.log`:

- Max file size: 512 KB (`maxLogBytes = 512 * 1024`).
- Keep tail size: 256 KB (`keepLogBytes = 256 * 1024`).
- Truncation check: every 50 writes (`logSizeCheckEveryWrites = 50`), checked on a serial `DispatchQueue`.
- Truncation algorithm: seek to `max(0, size - 256KB)`, read tail, drop the first partial line, write atomically.
- File protection: `FileProtectionType.completeUntilFirstUserAuthentication`.
- Scoped logger (`ScopedLogger`) strips and collapses whitespace, truncates messages to 320 characters (`maxScopedMessageCharacters`).

---

## 6. KeychainStore

**File:** `Sources/Gateway/KeychainStore.swift`

`enum KeychainStore` — thin wrapper over `GenericPasswordKeychainStore` from `OpenClawKit`.

### API surface

| Method | Signature | Notes |
|---|---|---|
| `loadString` | `(service:account:) -> String?` | Returns the stored generic password string. |
| `saveString` | `(_ value:service:account:) -> Bool` | Creates or replaces the item. |
| `delete` | `(service:account:) -> Bool` | Removes one item. Returns true if deleted or already absent. |
| `deleteAll` | `(service:) -> Bool` | Removes all items under a service. |
| `deleteAccounts` | `(service:accountPrefix:) -> Bool` | Queries all items for the service, filters by account prefix, deletes matching. Uses `kSecMatchLimitAll` + `kSecReturnAttributes` to enumerate. |

`deleteAccounts` with prefix: queries `kSecClassGenericPassword` with `kSecAttrService`, returns `kSecReturnAttributes` for all matches (`kSecMatchLimitAll`), filters `kSecAttrAccount` by `hasPrefix`, deletes each. Returns `true` if `errSecItemNotFound` (already empty) or all deletions succeeded.

---

## 7. TCPProbe

**File:** `Sources/Gateway/TCPProbe.swift`

`enum TCPProbe` — single static method.

```swift
static func probe(host: String, port: Int, timeoutSeconds: Double, queueLabel: String) async -> Bool
```

- Validates `port` in `1...65535`; returns `false` immediately otherwise.
- Creates an `NWConnection(host:port:using: .tcp)` (plain TCP, no TLS).
- Uses `withCheckedContinuation`; `OSAllocatedUnfairLock<Bool>` guards against double-resume.
- Watches `.ready` state → `finish(true)`, `.failed` or `.cancelled` → `finish(false)`.
- Fires a `DispatchQueue.asyncAfter` on the probe's own queue at `timeoutSeconds` to call `finish(false)` as the hard backstop.
- `connection.cancel()` is called after the result is determined.

---

## 8. GatewayConnectionIssue

**File:** `Sources/Gateway/GatewayConnectionIssue.swift`

`enum GatewayConnectionIssue: Equatable` — maps typed gateway problems to a compact set of UI states.

### Cases

| Case | Meaning |
|---|---|
| `.none` | No active issue. |
| `.tokenMissing` | Gateway reports the auth token is absent. |
| `.unauthorized` | Auth failed for a credential reason or device auth reason. |
| `.pairingRequired(requestId: String?)` | Gateway requires device pairing approval; carries optional request ID. |
| `.network` | TCP/WS reachability failure or timeout. |
| `.unknown(String)` | Unrecognized error message. |

### Computed properties

- `requestId: String?` — extracts the associated value from `.pairingRequired`; nil otherwise.
- `needsAuthToken: Bool` — true for `.tokenMissing` and `.unauthorized`.
- `needsPairing: Bool` — true for `.pairingRequired`.

### detect(problem:)

Maps a `GatewayConnectionProblem` to a `GatewayConnectionIssue`:

1. `problem.needsPairingApproval` → `.pairingRequired(requestId: problem.requestId)`
2. `problem.needsCredentialUpdate` → `.tokenMissing` if `kind == .gatewayAuthTokenMissing`, else `.unauthorized`
3. `kind` matches device identity/signature/nonce/TailscaleIdentity/auth-rate cases → `.unauthorized`
4. `kind` matches timeout/connectionRefused/reachabilityFailed/websocketCancelled → `.network`
5. `kind == .unknown` → `.unknown(problem.message)`
6. Otherwise → `.none`

### detect(from: String) (fallback text scan)

Used as a fallback when only a status text string is available (not a typed problem). Performs case-insensitive substring searches:

| Pattern | Result |
|---|---|
| `"pairing required"`, `"not_paired"`, `"not paired"` | `.pairingRequired(requestId:)` — extracts requestId after `"requestId:"` marker, terminated by `)`, whitespace, `,`, or `;`. |
| `"gateway token missing"` | `.tokenMissing` |
| `"unauthorized"` | `.unauthorized` |
| `"connection refused"`, `"timed out"`, `"network is unreachable"`, `"cannot find host"`, `"could not connect"` | `.network` |
| prefix `"gateway error:"` | `.unknown(trimmed)` |
| anything else | `.none` |

---

## 9. NetworkStatusService

**File:** `Sources/Device/NetworkStatusService.swift`

`final class NetworkStatusService: @unchecked Sendable`

### API

```swift
func currentStatus(timeoutMs: Int = 1500) async -> OpenClawNetworkStatusPayload
```

- Creates a one-shot `NWPathMonitor` on a fresh `DispatchQueue(label: "ai.openclawfoundation.app.network-status")`.
- First path update → `NSLock`-guarded `markCompleted()` → cancel monitor → resume continuation.
- `timeoutMs` backstop (default 1500 ms) → if no path update arrives, resume with fallback payload.
- The `NetworkStatusState` lock prevents both the timer and the path update from resuming the continuation.

### OpenClawNetworkStatusPayload fields

| Field | Source |
|---|---|
| `status` | `NWPath.status` mapped to `OpenClawNetworkPathStatus`: `.satisfied`, `.requiresConnection`, `.unsatisfied`. |
| `isExpensive` | `NWPath.isExpensive` |
| `isConstrained` | `NWPath.isConstrained` |
| `interfaces` | `[OpenClawNetworkInterfaceType]`: checks wifi, cellular, wiredEthernet in order; if none, emits `.other`. |

Fallback payload (on timeout): `status: .unsatisfied, isExpensive: false, isConstrained: false, interfaces: [.other]`.

---

## 10. LocationService

**File:** `Sources/Location/LocationService.swift`

`@MainActor final class LocationService: NSObject, CLLocationManagerDelegate`

### Authorization flow

`ensureAuthorization(mode:) async -> CLAuthorizationStatus`:

1. If `CLLocationManager.locationServicesEnabled()` is false → return `.denied` immediately.
2. If status is `.notDetermined` → call `requestWhenInUseAuthorization()`, await `requestAuthorization(requiresDeterminedStatus: true)`.
3. If `mode == .always` and current status is `.authorizedWhenInUse` → call `requestAlwaysAuthorization()`, await `requestAuthorization(requiresDeterminedStatus: false)`.

Authorization wait timer logic (inside a Task loop, 100 ms poll):
- Deadline for "no prompt visible" fallback: 1500 ms (`noPromptDeadline`).
- Tracks `observedPrompt`: if `applicationState != .active` at any point, `observedPrompt = true` (system prompt appeared).
- Once app returns to active after prompt and status is determined → complete.
- If still undetermined after prompt dismissal + 1500 ms (`activeUndeterminedDeadline`) → complete with fallback.
- The wait ID (`UUID`) guards against stale continuations: the loop checks `self.authWaitID == waitID` before doing anything.

Comment at `Sources/Location/LocationService.swift:89`: "Install the waiter before requesting permission so a fast delegate callback cannot be lost."

### Location request

`currentLocation(params:desiredAccuracy:maxAgeMs:timeoutMs:)` delegates to `LocationCurrentRequest.resolve` (from `OpenClawKit`), which handles cached-location age checks and one-shot requests.

### Significant location changes

`startMonitoringSignificantLocationChanges(onUpdate:)` — stores callback, calls `manager.startMonitoringSignificantLocationChanges()` once (guarded by `isMonitoringSignificantChanges`).

`locationManager(_:didUpdateLocations:)` delivers to both the one-shot continuation (if any) and the significant-change callback. The comment at `Sources/Location/LocationService.swift:203`: "Don't return — also forward to significant-change callback below so both consumers receive updates when both are active."

---

## 11. PhotoLibraryService

**File:** `Sources/Media/PhotoLibraryService.swift`

### PhotoLibraryAccess

```swift
static func authorizationStatus() -> PHAuthorizationStatus  // PHPhotoLibrary.authorizationStatus(for: .readWrite)
static func canRead(_ status: PHAuthorizationStatus) -> Bool // .authorized || .limited
static func requestReadWrite() async -> PHAuthorizationStatus
```

### PhotoLibraryService.latest

`func latest(params: OpenClawPhotosLatestParams) async throws -> OpenClawPhotosLatestPayload`

Checks authorization (does NOT prompt during invoke — comment at `Sources/Media/PhotoLibraryService.swift:74`: "Don't prompt during node.invoke; prompts block the invoke and lead to timeouts"). Throws if `!canRead(status)`.

**Transport size budget constants:**

| Constant | Value | Purpose |
|---|---|---|
| `maxTotalBase64Chars` | `340 * 1024` | Total base64 chars across all returned photos. |
| `maxPerPhotoBase64Chars` | `300 * 1024` | Per-photo base64 chars. |

Comment at `Sources/Media/PhotoLibraryService.swift:22`: "The gateway WebSocket has a max payload size; returning large base64 blobs can cause the gateway to close the connection."

**Fetch options:**
- `PHAsset.fetchAssets(with: .image, ...)` sorted by `creationDate descending`.
- `fetchLimit = max(1, min(params.limit ?? 1, 20))` (capped at 20).

**Rendering pipeline:**
- `targetSize`: aspect-preserving from `maxWidth` (default 1600) and asset pixel dimensions.
- `PHImageRequestOptions`: `isSynchronous = true`, `isNetworkAccessAllowed = true`, `deliveryMode = .highQualityFormat`.
- JPEG encode at `quality = max(0.1, min(1.0, params.quality ?? 0.85))`.

**Budget enforcement (`encodeJpegUnderBudget`, up to 10 iterations):**
1. Encode at current quality. Estimate base64 length as `((byteCount + 2) / 3) * 4`.
2. If within budget → return.
3. If `quality > 0.35` → reduce quality by 0.15 (min 0.25) and retry.
4. Once quality is low → downscale by 75% (`newWidth = max(240, width * 0.75)`). If `newWidth >= currentWidth`, break.
5. After 10 iterations with no success → throw error `"photo too large for gateway transport; try smaller maxWidth/quality"`.

Cumulative budget: stops enumerating PHAssets once remaining total budget would be exceeded by the next photo.

---

## 12. ScreenController

**File:** `Sources/Screen/ScreenController.swift`

`@MainActor @Observable final class ScreenController`

Manages a `WKWebView` for the Canvas surface. Holds a weak reference (`activeWebView: WKWebView?`).

### Observable state

| Property | Type | Default |
|---|---|---|
| `urlString` | `String` | `""` |
| `errorText` | `String?` | `nil` |
| `isCanvasPresented` | `Bool` | `false` |
| `onDeepLink` | `((URL) -> Void)?` | `nil` |
| `onA2UIAction` | `(([String: Any]) -> Void)?` | `nil` |

### Navigation rules

`navigate(to urlString:)`:
- Empty string → `showDefaultCanvas()`.
- Loopback hosts → `showDefaultCanvas()` silently (security: never load loopback URLs from a remote gateway).
- `"/"` string → treated as empty.
- Otherwise: sets `urlString` and calls `reload()`.

`reload()`:
- Empty `urlString` → load `CanvasScaffold/scaffold.html` from the `OpenClawKit` bundle as a file URL (read-access to parent directory).
- Non-empty string → parse as URL; file URLs → `loadFileURL`; others → `URLRequest`.

### Scroll behavior

`applyScrollBehavior()` is called on every `reload()`:
- Empty URL (default canvas): `scrollView.isScrollEnabled = false`, `scrollView.bounces = false` — the default canvas needs raw touch events.
- Non-empty URL (external page): `isScrollEnabled = true`, `bounces = true`.

### Bundled resource URLs

| Asset | Bundle path | Usage |
|---|---|---|
| `canvasScaffoldURL` | `CanvasScaffold/scaffold.html` in `OpenClawKitResources.bundle` | Default canvas (empty URL) |
| `localA2UIURL` | `CanvasA2UI/index.html` in `OpenClawKitResources.bundle` | Local A2UI mode |

`isTrustedCanvasUIURL(_:)` returns true only for file URLs that exactly match one of these two paths (standardized). External URLs are never trusted.

### Canvas snapshot

`snapshotBase64(maxWidth:format:quality:)`:
- PNG: `image.pngData()`.
- JPEG: `image.jpegData(compressionQuality: quality.clamped(to: 0.1...1.0))` where default quality is `0.82`.
- Uses `WKSnapshotConfiguration` with `snapshotWidth` set when `maxWidth != nil`.

### A2UI readiness polling

`waitForA2UIReady(timeoutMs:)` polls every 120 ms:
```javascript
(() => {
  try {
    const host = globalThis.openclawA2UI;
    return !!host && typeof host.applyMessages === 'function';
  } catch (_) { return false; }
})()
```
Returns `true` immediately when the JS host reports ready; returns `false` on timeout.

### Home canvas state injection

`updateHomeCanvasState(json:)` / `applyHomeCanvasStateIfNeeded()` calls:
```javascript
(() => {
  try {
    const api = globalThis.__openclaw;
    if (!api || typeof api.renderHome !== 'function') return;
    api.renderHome(<payload>);
  } catch (_) {}
})()
```
`payload` is the raw JSON string or `"null"`.

### WebView attachment

`attachWebView(_:)`: stores reference, calls `reload()`, applies debug status, applies home canvas state.
`detachWebView(_:)`: clears the reference only if the passed web view is the currently attached one (identity check).

### A2UIAction body parsing

`parseA2UIActionBody(_:)` accepts `[String: Any]`, `String` (JSON), or `[AnyHashable: Any]`; returns nil if empty.

---

## 13. GatewayStatusBuilder

**File:** `Sources/Status/GatewayStatusBuilder.swift`

`enum GatewayStatusBuilder` — pure static function, no storage.

### GatewayDisplayState

```swift
enum GatewayDisplayState: Equatable {
    case connected
    case connecting
    case error
    case disconnected
}
```

### build(appModel:)

Reads `appModel.gatewayServerName`, `appModel.lastGatewayProblem`, `appModel.gatewayStatusText`.

### build(gatewayServerName:lastGatewayProblem:gatewayStatusText:)

Decision table (checked in order):

| Condition | Result |
|---|---|
| `gatewayServerName != nil` | `.connected` |
| `lastGatewayProblem != nil && lastGatewayProblem.pauseReconnect == true` | `.error` |
| `statusText` contains `"connecting"` or `"reconnecting"` (case-insensitive) | `.connecting` |
| `statusText` contains `"error"` (case-insensitive) | `.error` |
| Otherwise | `.disconnected` |

---

## 14. PushRelayKeychainStore

**File:** `Sources/Push/PushRelayKeychainStore.swift`

`enum PushRelayRegistrationStore`

### Keychain service

`"ai.openclawfoundation.app.pushrelay"`

### Accounts

| Account | Content |
|---|---|
| `"registration-state"` | JSON-encoded `StoredPushRelayRegistrationState`. |
| `"app-attest-key-id-<scopeHash>"` | App Attest key ID (pre-attestation), scoped per relay context. |
| `"app-attested-key-id-<scopeHash>"` | Attested key ID (post-attestation), scoped per relay context. |

### RegistrationState

```swift
struct RegistrationState: Codable {
    var relayHandle: String
    var sendGrant: String
    var relayOrigin: String?
    var gatewayDeviceId: String
    var relayHandleExpiresAtMs: Int64?
    var tokenDebugSuffix: String?
    var lastAPNsTokenHashHex: String
    var installationId: String
    var lastTransport: String
    var apnsEnvironment: String     // default "production" on load
    var relayProfile: String        // default "production" on load
    var proofPolicy: String         // default "appleStrict" on load
}
```

Stored via `StoredPushRelayRegistrationState` (same fields but optionals for `apnsEnvironment`, `relayProfile`, `proofPolicy` to allow schema evolution). On load, nil values default to `"production"` / `"production"` / `"appleStrict"`.

### AppAttestScope

```swift
struct AppAttestScope {
    var relayOrigin: String
    var apnsEnvironment: String
    var relayProfile: String
    var proofPolicy: String
}
```

### Scope hashing

App Attest key IDs are scoped per `(relayOrigin, apnsEnvironment, relayProfile, proofPolicy)`. The account suffix is the SHA-256 hex of the four values joined with `"\n"`:

```swift
let raw = [relayOrigin, apnsEnvironment, relayProfile, proofPolicy].joined(separator: "\n")
let digest = SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
return "\(baseAccount)-\(digest)"
```

Comment at `Sources/Push/PushRelayKeychainStore.swift:155`: "A relay sees an App Attest key as attested only after receiving that key's attestation object, so keep key state isolated per relay context."

---

## 15. Connection Lifecycle Summary

The complete connect sequence from user action to live WebSocket sessions:

```
User tap / deep link / app foreground
    ↓
GatewayConnectionController.connectDiscoveredGateway | connectManual
    ↓
beginConnectAttempt()          — allocates suppression lease + generation
waitForPendingForgetCleanup()  — awaits any in-flight forget for same stableID
requestLocalNetworkAccess()    — starts Bonjour if not already running
    ↓
[discovery only] resolveServiceEndpoint()  — NWBrowser SRV/A/AAAA
    ↓
[TLS first-time / forceReconnect]
  TCPProbe.probe(timeout=3s)              — fast reachability gate
  GatewayTLSFingerprintProbe(timeout=10s) — capture leaf cert SHA-256
      ↓ fingerprint
  pendingTrustPrompt = TrustPrompt(...)   — UI presents trust dialog
      ↓ user accepts
  GatewayTLSStore.replaceFingerprint()    — pin stored in Keychain
      ↓
[TLS already pinned] load stored fingerprint
    ↓
startAutoConnect()
    ↓
beginGatewayConnectAttempt()   — NodeAppModel generation token
    ↓ (Task)
waitForGatewaySessionResetIfNeeded()
    ↓ [if forceReconnect]
forceReconnectReset(appModel)  — resetGatewaySessionsForForcedReconnect()
    ↓
makeConnectOptions()           — reads caps/commands/permissions (async; detached utility for CLLocationManager)
waitForGatewaySessionResetIfNeeded()  — second barrier (see note at line 1111)
    ↓
GatewayConnectConfig(url, stableID, tls, token, bootstrapToken, password, nodeOptions)
    ↓
NodeAppModel.applyGatewayConnectConfig()
    — spawns role=node WebSocket session
    — spawns role=operator WebSocket session
    — starts GatewayHealthMonitor (interval=15s, timeout=5s, maxFailures=3)
```

On failure or disconnect: `NodeAppModel.lastGatewayProblem` is set, `GatewayStatusBuilder` maps it to `GatewayDisplayState`, UI renders appropriate state. If `pauseReconnect == false`, auto-reconnect is attempted after the current session tears down.

On forget: sync credential/pin/registry cleanup → async disconnect + wait-for-reset + second token clear + transcript cache purge. Any new connect attempt for the same gateway awaits the cleanup task before proceeding.
