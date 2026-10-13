# Chat State, Data & Transport

This document specifies the full behavior layer behind the iOS chat surface. It covers every gateway RPC issued by `IOSGatewayChatTransport`, the lifecycle owned by `OpenClawChatViewModel` and its extensions (history reconciliation, reply dedupe, gateway-seq ordering, pending-run timeout, transcript cache, attachment staging), and all invariants that govern session routing, derived titles, and the thinking-level omission rule. A competent engineer should be able to rebuild this layer exactly from this document without reading the source.

---

## 1. Transport Layer: `IOSGatewayChatTransport`

File: `Sources/Chat/IOSGatewayChatTransport.swift`

`IOSGatewayChatTransport` is a `struct` conforming to the `OpenClawChatTransport` protocol. It wraps a `GatewayNodeSession` and encodes every RPC as a typed `Codable` params object before calling `gateway.request(method:paramsJSON:timeoutSeconds:)`.

### 1.1 Initialization

| Property | Type | Description |
|---|---|---|
| `gateway` | `GatewayNodeSession` | The active WebSocket gateway session. |
| `globalAgentId` | `String?` | Agent id injected at construction, normalized as **trimmed then lowercased**; stored as `nil` when the normalized result is empty (not an empty string). Used as the `agentId` field for alias keys (e.g., `"main"`, `"global"`). |
| `outboxGatewayID` | `String?` | Gateway identity injected at construction, normalized as **trimmed only** (no lowercasing); stored as `nil` when the trimmed result is empty. When set, all outbox-route lease acquisition is gated on this specific gateway identity so stale routes never replay durable commands. |

Init normalization (`IOSGatewayChatTransport.swift:142-152`):
```swift
let normalized = globalAgentId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
self.globalAgentId = normalized?.isEmpty == false ? normalized : nil
let normalizedGatewayID = outboxGatewayID?.trimmingCharacters(in: .whitespacesAndNewlines)
self.outboxGatewayID = normalizedGatewayID?.isEmpty == false ? normalizedGatewayID : nil
```

`outboxRequiresSessionRoutingContract` returns `true` unconditionally, meaning every outbox lease requires the gateway to support `chatSendRoutingContract`. (`IOSGatewayChatTransport.swift:15-17`)

### 1.2 Constants

| Constant | Value | Meaning |
|---|---|---|
| `defaultChatSendTimeoutMs` | `30000` | Passed as `timeoutMs` in every `ChatSendParams` payload. |
| `compactionRequestTimeoutSeconds` | `0` | Zero = no timeout on `sessions.compact`. |
| Logger subsystem | `ai.openclawfoundation.app` | OSLog subsystem for this transport. |
| Logger category | `ios.chat.transport` | OSLog category. |

### 1.2.1 Outbox Route Lease (`acquireOutboxRouteLease`)

The durable outbox needs a stable, capability-confirmed route before it can replay queued commands. `acquireOutboxRouteLease()` (`IOSGatewayChatTransport.swift:154-188`) returns an `OpenClawChatTransportRouteLeaseResult`:

1. Require a non-nil `outboxGatewayID` and resolve the current route via `gateway.currentRoute(ifGatewayID:)`. If either is missing → `.unavailable(reason: nil)`.
2. Query `gateway.supportsServerCapability(.chatSendRoutingContract, ifCurrentRoute: route)`. If the capability probe itself fails (nil) → `.unavailable(reason: nil)`; if the gateway does not support the contract → `.unavailable(reason: OpenClawChatTransportUpgradeMessage.routingContract)` (prompts an upgrade).
3. Acquire the session routing contract string via `sessionRoutingContract(ifCurrentRoute:)` (see below). On failure → `.unavailable(reason: nil)`.
4. On success → `.available(OpenClawChatTransportRouteLease(...))`. The lease captures the route and contract and exposes three closures bound to that exact route: `sendTargetedMessage`, `requestTargetedHistory`, and the raw `sessionRoutingContract`. The send closure calls `sendMessage(..., ifCurrentRoute: route, distinguishPreDispatchRouteChange: true)` so a route change before dispatch surfaces as `notDispatched`.

#### `agents.list` (routing-contract acquisition)

Method: `agents.list`
Timeout: 15 s
Params: `"{}"` (literal empty object)
Route-pinned: called with `ifCurrentRoute: route`.

`sessionRoutingContract(ifCurrentRoute:)` (`IOSGatewayChatTransport.swift:190-209`) issues this RPC solely to build the routing contract. The response decodes to `AgentsListResult` (fields `scope`, `mainkey`, `defaultid`), then `OpenClawChatSessionRoutingContract.make(scope:mainKey:defaultAgentID:)` produces the contract string. A nil result throws `CancellationError`. This RPC is used only by the outbox lease path; ordinary live chat does not call it.

### 1.3 Session RPCs

#### `sessions.create`

Method: `sessions.create`  
Timeout: 15 s  
Params struct: `CreateSessionParams`

| Field | Type | Notes |
|---|---|---|
| `key` | `String` | The resolved session key from `sessionTarget(for:)`. |
| `agentId` | `String?` | From target or parent target's agentId. |
| `label` | `String?` | User-supplied label, can be `nil`. |
| `parentSessionKey` | `String?` | Resolved parent key, can be `nil`. |
| `worktree` | `Bool?` | `true` for worktree sessions, omitted otherwise. |

Returns `OpenClawChatCreateSessionResponse` (`ok: Bool?`, `key: String`, `sessionId: String?`).

#### `sessions.list`

Method: `sessions.list`  
Timeout: 15 s  
Params struct: `ListSessionsParams`

| Field | Value |
|---|---|
| `includeGlobal` | `true` (always) |
| `includeUnknown` | `false` (always) |
| `limit` | caller-supplied or `nil` |
| `search` | trimmed search string or `nil` if empty |
| `archived` | `true` only when fetching archived; omitted (`nil`) for normal fetch |
| `includeDerivedTitles` | `true` (always) |

**`includeDerivedTitles` is critical.** Without it, the gateway does not read the transcript file and `derivedTitle` returns `nil`, so untitled sessions fall back to a generic dated placeholder. The flag triggers a file-I/O read on the gateway side. (`IOSGatewayChatTransport.swift:39-43`)

Returns `OpenClawChatSessionsListResponse` which contains the `defaults` object (`OpenClawChatSessionsDefaults`) including `mainSessionKey`, as well as the session array.

#### `sessions.patch`

Method: `sessions.patch`  
Timeout: 15 s

The patch method accepts an open `[String: Any]` dictionary (not a closed struct) so `NSNull` can express explicit `nil` for `label` and `category`. Any field that is not provided is not sent. Called for:

- Renaming a session (`label`)
- Pinning / unpinning (`pinned`)
- Archiving / restoring (`archived`)
- Marking read/unread (`unread`)
- Changing model (`model`, uses `SessionPatchModelParams` which force-encodes `nil` as JSON `null`)

For the `"global"` session key, `agentId` is set to `globalAgentId`; for all other keys it is omitted. (`IOSGatewayChatTransport.swift:399-403`)

#### `sessions.delete`

Method: `sessions.delete`  
Timeout: 15 s  
`deleteTranscript: true` always. `agentId` is set only for the `"global"` key.

#### `sessions.messages.subscribe`

Method: `sessions.messages.subscribe`  
Timeout: 10 s

Sends `{ key: resolvedSessionKey, agentId? }`. This is the "set active session" call. The gateway then pushes `session.message` events for that session over the existing WebSocket. (`IOSGatewayChatTransport.swift:536-548`)

#### `sessions.reset`

Method: `sessions.reset`  
Timeout: 10 s  
Params: `{ key, agentId? }` via `SessionKeyParams`.

#### `sessions.compact`

Method: `sessions.compact`  
Timeout: `compactionRequestTimeoutSeconds` = 0 (no timeout)  
Params: `{ key, agentId? }` via `SessionKeyParams`. Callers use a 60 s cooldown guard on the UI side.

After the request returns, the transport calls `OpenClawSessionsCompactResponse.requireSuccess(from: response)` (`IOSGatewayChatTransport.swift:559-564`), which decodes the response and throws if the gateway did not report success. A failed compaction therefore propagates as a thrown error rather than silently resolving.

#### `sessions.create` (fork path)

Called via `forkSession(parentKey:)`. Uses `ForkSessionParams`:

| Field | Value |
|---|---|
| `parentSessionKey` | **raw `parentKey` (not run through `sessionTarget`)** |
| `fork` | `true` (always) |
| `agentId` | `Self.agentID(fromSessionKey: parentKey) ?? self.selectedGlobalAgentId(for: parentKey)` |

The `agentId` resolution (`IOSGatewayChatTransport.swift:528-534`) first tries to extract an embedded agent id from the parent key (`agentID(fromSessionKey:)` — see §1.6; returns the segment after `agent:` when the key splits into ≥3 `:`-separated parts with `parts[0] == "agent"`). If the parent key carries no embedded agent, it falls back to `selectedGlobalAgentId(for: parentKey)`, which returns `globalAgentId` **only when the parent key is exactly `"global"`** and `nil` otherwise. Unlike the other session calls, `forkSession` passes the un-resolved `parentKey` directly as `parentSessionKey`.

Returns the new session key from `OpenClawChatCreateSessionResponse.key`.

### 1.4 Chat RPCs

#### `chat.send`

Method: `chat.send`  
Timeout: **35 s** (note: different from the 30 s `timeoutMs` sent in the payload)  
Params struct: `ChatSendParams`

| Field | Type | Notes |
|---|---|---|
| `sessionKey` | `String` | Resolved by `sessionTarget(for:overrideAgentID:)`. |
| `agentId` | `String?` | From the resolved target; nil if already embedded in key. |
| `expectedSessionRoutingContract` | `String?` | Set when `supportsRoutingContract` capability is confirmed. Omitted on legacy gateways. |
| `message` | `String` | The user text. |
| `thinking` | `String?` | **Omitted entirely when the client sends `""`** — which is the signal for "no explicit user choice." This omission lets the gateway apply the model's default. Reasoning-mandatory models such as `xai/grok-4.6` reject an explicit `"off"`. (`IOSGatewayChatTransport.swift:103-105`) |
| `attachments` | `[OpenClawChatAttachmentPayload]?` | Omitted (nil) when empty. |
| `timeoutMs` | `Int` | `defaultChatSendTimeoutMs` = 30 000. |
| `idempotencyKey` | `String` | The local run UUID, used for at-least-once deduplication. |

Returns `OpenClawChatSendResponse` (`runId: String`, `status: String`).

When a `GatewayNodeSessionRequestError` is thrown (meaning the captured route changed before dispatch), the error is re-thrown as `OpenClawChatTransportSendError.notDispatched` so the caller knows the message was never sent and can retry cleanly. (`IOSGatewayChatTransport.swift:692-695`)

Diagnostic strings are written to both `OSLog` and `GatewayDiagnostics.log` at start, success, and failure.

#### `chat.history`

Method: `chat.history`  
Timeout: 15 s  
Params: `{ sessionKey, agentId? }` resolved via `sessionTarget(for:overrideAgentID:)`.

Returns `OpenClawChatHistoryPayload`:

| Field | Type | Notes |
|---|---|---|
| `sessionKey` | `String` | Echo of the requested key. |
| `sessionId` | `String?` | Opaque session identity, stored on the view model. |
| `messages` | `[AnyCodable]?` | Raw decoded message array. |
| `thinkingLevel` | `String?` | Gateway's current thinking level for this session. |
| `sessionInfo` | `OpenClawChatSessionInfo?` | Contains `hasActiveRun: Bool?`. |
| `inFlightRun` | `OpenClawChatInFlightRun?` | Contains `runId` and buffered `text` for the currently streaming run. |

#### `chat.abort`

Method: `chat.abort`  
Timeout: 10 s  
Best-effort. Errors are silently swallowed.

#### `health`

Method: `health`
Timeout: `max(1, ceil(timeoutMs / 1000))` seconds (derived from the caller's `timeoutMs`).
Params: none (`paramsJSON: nil`).

`requestHealth(timeoutMs:)` (`IOSGatewayChatTransport.swift:772-776`) issues the `health` RPC and decodes `OpenClawGatewayHealthOK`, returning its `ok` flag. **If decoding fails, it defaults to `true`** (`(try? ...)?.ok ?? true`) — an undecodable-but-returned response is treated as healthy. The view model's health polling (`pollHealthIfNeeded`, driven by `tick` events and forced during bootstrap) calls this RPC.

### 1.5 Agent Wait RPC

Method: `agent.wait`  
Timeout: `max(1, ceil(timeoutMs / 1000)) + 5` seconds (always 5 s above the payload timeout).

Params: `{ runId, timeoutMs }` where `timeoutMs` is `pendingRunTimeoutMs` (120 000 ms).

Returns `AgentWaitCompletion`. Terminal statuses: `"ok"`, `"completed"`, `"success"`, `"succeeded"` (case-insensitive, whitespace-trimmed). (`IOSGatewayChatTransport.swift:133-140`)

### 1.6 Session Routing and Key Resolution

`sessionTarget(for:selectedAgentID:overrideAgentID:)` is the canonical key resolver.

The key, `selectedAgentID`, and `overrideAgentID` are each trimmed; `selectedAgentID` and `overrideAgentID` are also lowercased. The resolver checks the following branches **in order** (first match wins):

| # | Input pattern (checked in order) | Output `sessionKey` | Output `agentID` |
|---|---|---|---|
| 1 | `agentID(fromSessionKey:) != nil` — i.e. key splits into ≥3 `:`-parts with `parts[0] == "agent"` and a non-empty `parts[1]` (already canonical) | unchanged | `override` only (ignores `selected`; nil when no override) |
| 2 | key (lowercased) `hasPrefix("agent:")` but **no** parseable embedded agent segment | unchanged | `nil` |
| 3 | key (lowercased) `== "unknown"` | unchanged | `nil` |
| 4 | key (lowercased) `== "global"` | `"global"` | `targetAgentID` = `override ?? (non-empty selected)` |
| 5 | any other alias and `targetAgentID` is known | `"agent:<targetAgentID>:<key>"` | `nil` (now embedded in key) |
| 6 | any other alias and `targetAgentID` is nil | unchanged | `nil` |

(`IOSGatewayChatTransport.swift:410-435`)

The distinction between rows 1 and 2 matters for `overrideAgentID` injection: a canonical key that already embeds an agent still accepts an `overrideAgentID` as its `agentID` output, whereas a bare `agent:`-prefixed key with no parseable segment never emits an `agentID`.

`agentID(fromSessionKey:)` (`IOSGatewayChatTransport.swift:300-307`): splits the trimmed key on `:` **without** omitting empty subsequences, requires `parts.count >= 3` and `parts[0].lowercased() == "agent"`, then returns trimmed `parts[1]` (or `nil` if empty).

The instance overload `sessionTarget(for:overrideAgentID:)` passes `globalAgentId` as `selectedAgentID`.

When the resolved `sessionKey` is exactly `"global"`, `selectedGlobalAgentId(for:)` injects `globalAgentId` as the `agentId` for patch/delete calls; for every other key it returns `nil`.

### 1.7 Event Subscription

`events()` returns an `AsyncStream<OpenClawChatTransportEvent>` that maps `EventFrame` events from `gateway.subscribeServerEvents()`.

| `evt.event` | Mapped to |
|---|---|
| `"tick"` | `.tick` |
| `"seqGap"` | `.seqGap` |
| `"health"` | `.health(ok:)` (decoded from payload) |
| `"chat"` | `.chat(OpenClawChatEventPayload)` |
| `"session.message"` | `.sessionMessage(OpenClawSessionMessageEventPayload)` |
| `"agent"` | `.agent(OpenClawAgentEventPayload)` |
| anything else | dropped (`nil`) |

(`IOSGatewayChatTransport.swift:798-840`)

Decode rules per case: `health`, `chat`, `session.message`, and `agent` all drop the frame (`nil`) when `evt.payload` is missing. For `chat`/`session.message`/`agent`, a payload that fails to decode to the typed struct also drops the frame. For `health`, a present-but-undecodable payload yields `.health(ok: true)` (the `ok` flag defaults to `true` when decoding fails).

### 1.8 Model and Command Catalog RPCs

| Method | Timeout | Notes |
|---|---|---|
| `models.list` | 15 s | Params `nil` (none sent). Returns `ModelsListResponse.models` decoded to `[OpenClawChatModelChoice]`. |
| `commands.list` | 15 s | `{ scope: "text", includeArgs: true, agentId? }`. See agent-id extraction below. |

**`models.list` name handling** (`IOSGatewayChatTransport.swift:318-329`): each model's `name` is trimmed. If the **trimmed** name is empty, the choice's `name` becomes `model.id`; otherwise the choice uses the **original un-trimmed** `model.name` (not the trimmed copy). A rebuilder must preserve the original name's surrounding whitespace when non-empty. Other mapped fields: `modelID` ← `model.id`, `provider`, `contextWindow`, `reasoning`.

**`commands.list` agent-id extraction** (`IOSGatewayChatTransport.swift:290-298, 591-594`): the `agentId` param is `agentID(fromSessionKey: sessionKey) ?? globalAgentId`. That is, if the session key is canonical (`parts.count >= 3`, `parts[0] == "agent"`), `parts[1]` is used; otherwise it falls back to `globalAgentId`.

**Command choice mapping** (`mapCommandChoice`, `IOSGatewayChatTransport.swift:703-732`):

- Source: the `"source"` field is trimmed+lowercased, then `"native"` → `.command`, `"skill"` → `.skill`, `"plugin"` → `.plugin`, anything else → `.unknown`.
- `textAliases`: each entry trimmed; empty entries dropped.
- `id`: a compound string built as `[source.rawValue, trimmedName, aliases.first ?? ""].joined(separator: ":")`. This non-obvious composite id must be reproduced exactly, since it is the `Identifiable` id for the slash-command catalog.
- `name` ← `entry.name` (un-trimmed), `description` ← `entry.description`, `acceptsArgs` ← `entry.acceptsargs`.

`OpenClawChatCommandChoice` exposes two computed properties that govern how a picked command is inserted into the composer (`ChatModels.swift:53-60`):

- `preferredInvocation`: the first `textAlias` whose trimmed value starts with `/`, falling back to `"/\(name)"` when no alias qualifies.
- `displayInvocation`: `preferredInvocation` trimmed of surrounding whitespace.

---

## 2. View Model: `OpenClawChatViewModel`

File: `apps/shared/OpenClawKit/Sources/OpenClawChatUI/ChatViewModel.swift` (and extensions)

`@MainActor @Observable public final class OpenClawChatViewModel`. All state reads and mutations happen on the MainActor. Background fetches jump back to MainActor before touching any stored property.

### 2.1 Key Observable Properties

| Property | Access | Description |
|---|---|---|
| `messages` | `internal(set)` | Ordered `[OpenClawChatMessage]` — the live transcript. Mutated only through `replaceMessages(_:)`. |
| `input` | `public var` | Composer text. Cleared immediately on send before any network await. |
| `thinkingLevel` | `private(set)` | Current thinking level string. `"off"` when no gateway metadata forces otherwise. |
| `thinkingLevelOptions` | `internal(set)` | Array of `OpenClawChatThinkingLevelOption` for the picker. Each option has both `id` and `label`. The base set `baseThinkingLevelOptions` (`ChatViewModel.swift:564-570`) is five options whose `label` equals its `id`: `(id:"off",label:"off")`, `(id:"minimal",label:"minimal")`, `(id:"low",label:"low")`, `(id:"medium",label:"medium")`, `(id:"high",label:"high")`. |
| `showsThinkingPicker` | `internal(set)` | Whether the picker is visible; `false` when gateway metadata allows only `"off"` or the model reports `reasoning: false`. |
| `modelSelectionID` | `private(set)` | Provider-qualified model ID or `"__default__"`. |
| `modelChoices` | `private(set)` | `[OpenClawChatModelChoice]` from `models.list`. |
| `sessions` | `internal(set)` | `[OpenClawChatSessionEntry]` organized by `OpenClawChatSessionListOrganizer`. |
| `sessionKey` | `private(set)` | Active session key. Changing it calls `syncContextUsageFraction()`. |
| `sessionId` | `private(set)` | Opaque id from history payload. |
| `pendingRunCount` | `private(set)` | Count of in-flight run IDs; drives "thinking" indicator. |
| `streamingAssistantText` | `private(set)` | Accumulated text from the current `chat.delta` stream. |
| `isLoading` | `private(set)` | True during bootstrap. |
| `isSending` | `private(set)` | True between send initiation and transport return. |
| `isAborting` | `private(set)` | True while `chat.abort` RPCs are in flight. |
| `isShowingCachedTranscript` | `internal(set)` | `true` while the transcript came from the offline SQLite cache and has not yet been replaced by a live response. |
| `hasAppliedLiveHistory` | `internal` | Guard preventing a late cache read from overwriting a live response. |
| `contextUsageFraction` | `internal(set)` | `totalTokens / contextTokens`, clamped to `[0,1]`, or `nil` when not computable. |
| `healthOK` | `internal(set)` | Reflects the most recent gateway health event. |
| `errorText` | `public var` | User-visible error string; nil on success. |
| `attachments` | `public var` | Staged `[OpenClawPendingAttachment]`. |

Constants:

| Constant | Value |
|---|---|
| `defaultModelSelectionID` | `"__default__"` |
| `maxAttachmentBytes` | 5 000 000 (5 MB) |
| `sessionListFetchLimit` | 200 |
| `pendingRunTimeoutMs` | 120 000 ms (2 minutes) |
| `postSendRefreshDelaysMs` | `[1500, 4000, 9000, 20000, 45000, 90000]` ms |
| `compactCooldown` | 60 s |
| `maxOutboxSendAttempts` | 3 |

### 2.2 Session Generation and Snapshot

Every switch to a new session increments `sessionGeneration: UInt64`. Every async operation captures `currentSessionSnapshot()` at the moment it starts. Before applying any result the operation calls `isCurrentSession(snapshot)`, which checks:

1. `sessionKey == snapshot.key`
2. `sessionGeneration == snapshot.generation`
3. `!usesMutableAgentRouting || activeAgentId == snapshot.agentID`
4. `!contractSensitive || sessionRoutingContract == snapshot.sessionRoutingContract`

Condition 4's `contractSensitive` flag is computed **bidirectionally** (`ChatViewModel.swift:673-680`): it is true when `usesMutableContractRouting` holds for **either** the snapshot's contract **or** the current contract:

```swift
let contractSensitive = self.usesMutableContractRouting(for: snapshot.sessionRoutingContract) ||
    self.usesMutableContractRouting(for: self.sessionRoutingContract)
```

So the contract equality check engages whenever either side uses mutable contract routing, not only when the snapshot does. This prevents stale network responses from overwriting a session the user has already navigated away from.

`SessionSnapshot` (inner struct in `ChatViewModel+TranscriptCache.swift:8-14`):
```swift
struct SessionSnapshot {
    var key: String
    var generation: UInt64
    var agentID: String?
    var deliveryAgentID: String?
    var sessionRoutingContract: String?
}
```

`deliveryAgentID` is the agent used on the wire: extracted from the session key if canonical (`"agent:<id>:<key>"`), otherwise `activeAgentId`.

### 2.3 Bootstrap Flow

Called on `load()`, `refresh()`, and after any session switch.

```
startBootstrap()
  ↓ increment bootstrapGeneration, cancel previous bootstrapTask
  ↓ isLoading = true, healthOK = false, clear pending runs / streaming text / sessionId
  ↓ paintFromCacheIfNeeded(session)   [async, non-blocking]
  ↓ restoreOutboxMessages(session)
  ↓ Task: bootstrap(context)
       ↓ syncActiveSessionSubscription(sessionKey)   [sends sessions.messages.subscribe, retrying on key drift]
       ↓ transport.requestHistory(sessionKey)        [chat.history RPC]
       ↓ applyHistoryPayload(preservingOptimisticLocalMessages: false, syncThinkingOptions: true)
       ↓ pollHealthIfNeeded(force: true)
       ↓ fetchSessions(limit: 50)     [sessions.list with includeDerivedTitles: true]
       ↓ fetchModels()                [models.list]
       ↓ isLoading = false
```

`syncActiveSessionSubscription` loops until the session key that was subscribed matches the current session key, retrying when it detects drift. This ensures that if the user switches sessions while the subscribe RPC is in flight, the final state is consistent. (`ChatViewModel.swift:943-963`)

### 2.4 Session Switching

`switchSession(to:)` calls `applySessionSwitch(to:intent:.userInitiated)`.  
`syncSession(to:)` calls `applySessionSwitch(to:intent:.externalSync)`.

Switching is blocked when `blocksAttachmentOwnerChange` is true (camera/mic active, attachment staging in progress, or non-empty attachment list, or `isSendingAttachmentDraft`). User-initiated switches surface an error; external syncs are deferred into `deferredExternalSessionKey` and applied once the block clears.

On switch:
1. `advanceSessionGeneration()`
2. `sessionKey = next`
3. Fire `onSessionChanged?(next)` (user-initiated only)
4. `clearSessionOwnedState()` — zeroes messages, pending runs, provisional finals, streaming text, model selection, slash catalog, outbox presentation state, etc.
5. `startBootstrap(sessionKey: next)`

### 2.5 Session Model (`OpenClawChatSessionEntry`)

Key fields relevant to behavior:

| Field | Type | Notes |
|---|---|---|
| `key` | `String` | Unique session key; used as `id`. |
| `derivedTitle` | `String?` | Gateway-derived first-message title, only present when `includeDerivedTitles: true` was sent in `sessions.list`. |
| `displayName` | `String?` | User-set label or gateway display name. |
| `label` | `String?` | Explicit user-set label. |
| `pinnedAt` | `Double?` | Epoch ms; used for sort order. |
| `updatedAt` | `Double?` | Epoch ms; secondary sort key. |
| `model` | `String?` | Currently active model ID. |
| `modelProvider` | `String?` | Currently active provider. |
| `thinkingLevel` | `String?` | Per-session thinking level from gateway. |
| `thinkingLevels` | `[OpenClawChatThinkingLevelOption]?` | Gateway-supplied thinking options (authoritative when present). |
| `totalTokens` | `Int?` | Used for context usage fraction. |
| `contextTokens` | `Int?` | Token budget; denominator for usage fraction. |
| `totalTokensFresh` | `Bool?` | When `false`, usage fraction is not computed (stale data). |

Additional decoded fields on `OpenClawChatSessionEntry` (`ChatSessions.swift:82-201`), several of which affect sort/display/filter logic: `kind`, `category`, `archived`, `archivedAt`, `unread`, `surface`, `subject`, `room`, `space`, `lastReadAt`, `lastActivityAt`, `sessionId`, `systemSent`, `abortedLastRun`, `verboseLevel`, `inputTokens`, `outputTokens`, `thinkingOptions` (`[String]?`), `thinkingDefault`. Convenience computed flags: `isPinned` = `pinned == true`, `isArchived` = `archived == true`, `id` = `key`.

Session list ordering (`OpenClawChatSessionListOrganizer.organize`, `ChatSessions.swift:207-221`): sort by `pinnedAt desc → updatedAt desc → key asc`. The effective pinned sort value is `pinnedAt ?? (isPinned ? .greatestFiniteMagnitude : 0)`:

- `pinnedAt` present → used as-is.
- `pinnedAt` nil **and** `isPinned == true` → `Double.greatestFiniteMagnitude` (floats to top).
- `pinnedAt` nil **and** `isPinned == false` → `0`, so an unpinned session with no `pinnedAt` sorts normally by `updatedAt` (nil `updatedAt` → `0`), then `key` ascending.

`OpenClawChatSessionListOrganizer.filter(_:search:)` (`ChatSessions.swift:225-239`) is the **offline fallback** for the server-side `sessions.list` search, used only when the gateway is unreachable. The query is trimmed+lowercased; an empty query returns the input unchanged. A session matches if any of `displayName`, `label`, `subject`, `sessionId`, or `key` (lowercased) **contains** the query substring.

`resolvedMainSessionKey` reads `sessionDefaults?.mainSessionKey`, trimmed; falls back to `"main"` if nil or empty.

`OpenClawChatSessionsListResponse` (`ChatSessions.swift:242-262`) decodes `ts` (`Double?`), `path` (`String?`), `count` (`Int?`), `defaults` (`OpenClawChatSessionsDefaults?`), and `sessions` (`[OpenClawChatSessionEntry]`).

### 2.6 Main Session Aliasing

Sessions `"main"`, `"global"`, `"agent:main:main"`, and the gateway-supplied `mainSessionKey` from `OpenClawChatSessionsDefaults` are treated as aliases of each other by `matchesCurrentSessionKey`. The routing match logic (`ChatViewModel+SessionKeys.swift:84-141`) handles:

- Exact key equality (with optional agent-id cross-check)
- `matchesMainAlias`: `"main"` ↔ `mainSessionKey`, and `"main"` ↔ `"agent:main:main"`
- `matchesSelectedAgentWrapper`: `"agent:<id>:<key>"` ↔ `"<key>"` for the same underlying key
- `matchesSelectedAgentGlobal`: incoming `"global"` + an `agentId` matches `"agent:<agentId>:global"`

This prevents gateway events published with a canonical key from being dropped when the client is tracking an alias key, which would otherwise leave the UI permanently stuck in "thinking."

---

## 3. Message Model (`OpenClawChatMessage`)

File: `apps/shared/OpenClawKit/Sources/OpenClawChatUI/ChatModels.swift:190`

| Field | Wire key | Notes |
|---|---|---|
| `id` | (local UUID, not encoded) | Client-only stable bubble identity; survives all reconciliation. |
| `role` | `role` | `"user"` or `"assistant"`. |
| `content` | `content` | `[OpenClawChatMessageContent]` or a plain string on some log formats. |
| `timestamp` | `timestamp` | Epoch ms as `Double?`. |
| `idempotencyKey` | `idempotencyKey` or `__openclaw.idempotencyKey` | Present on user turns (the run UUID) and on some assistant turns. |
| `serverMessageId` | `__openclaw.id` (wire) / `serverMessageId` (cache) | Durable gateway-assigned row id; nil until canonical row arrives. |
| `serverSeq` | `__openclaw.seq` (wire) / `serverSeq` (cache) | Session-global monotonic transcript position; nil on transient rows. |
| `stopReason` | `stopReason` | `"error"`, `"aborted"`, or nil. |
| `errorMessage` | `errorMessage` | Non-nil only when `stopReason == "error"`. |
| `toolCallId` | `toolCallId` or `tool_call_id` | Both forms decoded. |
| `toolName` | `toolName` or `tool_name` | Both forms decoded. |
| `usage` | `usage` | `OpenClawChatUsage` — see nested-struct note below. |

**`OpenClawChatUsage`** (`ChatModels.swift:63-110`) has token counts as `Int?`: `input`, `output`, `cacheRead`, `cacheWrite`, and `total`. `total` is decoded from the `total` key, falling back to `totalTokens` when `total` is absent. `cost` is **not a scalar** — it is a nested `OpenClawChatUsageCost` struct whose five fields (`input`, `output`, `cacheRead`, `cacheWrite`, `total`) are all `Double?`. A rebuilder must model cost as a nested object, not a number. On encode, `OpenClawChatUsage` writes `total` under the `total` key only (never `totalTokens`).

Audio attachments (`ChatModels.swift:320-353`): the message decoder reads `MediaPaths`/`MediaPath` (array or single, into a `[String]`) and `MediaTypes`/`MediaType` (likewise). For each index where the paired media type is an `audio/*` MIME, it appends a content item of `type: "file"`, `mimeType:` the trimmed MIME, and **`fileName:` derived from `(mediaPath as NSString).lastPathComponent`** — the last path component of the media path. This appending is skipped entirely when the decoded `content` array already contains any `audio/*` item (`alreadyContainsAudio`).

---

## 4. History Reconciliation

File: `apps/shared/OpenClawKit/Sources/OpenClawChatUI/ChatViewModel+HistoryReconciliation.swift`

All mutations to the `messages` array funnel through `replaceMessages(_:)`, which first calls `orderedBySequence(_:)` and then assigns the result.

### 4.1 Gateway-Seq Ordering (`orderedBySequence`)

`orderedBySequence` sorts by `serverSeq`, which is a session-global monotonic counter the gateway assigns to every persisted row. (`ChatViewModel+HistoryReconciliation.swift:86-103`)

- If **no** message has a `serverSeq`, the array is returned unchanged (order preserved).
- Otherwise, a "carried seq" is propagated forward: each message's sort key is its own `serverSeq` if present, or the `serverSeq` of the immediately preceding message in the original array. Tie-breaks go by original array index.
- This ensures transient rows (optimistic user echo, in-flight streaming text) hold their position relative to adjacent canonical rows rather than jumping to the end.
- The algorithm is idempotent: an already-ordered, fully-seq'd list returns unchanged.

**Why this matters:** A `sessions_send`-routed reply from another surface can arrive at the client with an earlier `serverSeq` than a message already displayed. Without this sort, it would appear at the bottom of the transcript instead of its true chronological position.

### 4.2 Message Identity Key (`messageIdentityKey`)

Priority order for message deduplication and reconciliation:

1. **`serverMessageId`** — uniquely identifies a persisted gateway row; preferred above all. Key format: `"<role>|serverid|<serverMessageId>"`.
2. **`idempotencyKey`** — the client's run UUID (user turns) or gateway-stamped assistant key. Key format: `"<role>|idempotency|<key>"`.
3. **Timestamp + content fingerprint + tool fields** — last resort for rows with neither (`ChatViewModel+HistoryReconciliation.swift:141-152`). Key format: `"<role>|<timestamp>|<toolCallId>|<toolName>|<contentFingerprint>"`. The `role` is first trimmed+lowercased; a message whose trimmed role is empty returns `nil` up front. The `timestamp` segment is formatted `String(format: "%.3f", value)` **only when the timestamp is non-nil and finite**, otherwise the empty string. `toolCallId` and `toolName` are trimmed. The key returns `nil` **only when `timestamp`, `contentFingerprint`, `toolCallId`, and `toolName` are all empty simultaneously** — a present content fingerprint (or tool field) alone is enough to produce a key even with no timestamp.

Content fingerprint (`messageContentFingerprint`): for each content item joins `type`, `text`, `id`, `name`, `fileName` with unit separator `\u{001F}`, and joins items with record separator `\u{001E}`.

Two related helper keys:
- `userRefreshIdentityKey` (`:155-166`): user rows only; `"<role>|<toolCallId>|<toolName>|<contentFingerprint>"` (no timestamp); `nil` when fingerprint and both tool fields are empty.
- `finalMessageReconciliationKey` (`:168-182`): assistant rows only; same shape as `userRefreshIdentityKey` but uses `finalMessageContentFingerprint`; `nil` when fingerprint and both tool fields are empty.

### 4.3 Reply Dedupe (`dedupeMessages` / `dedupeKey`)

`dedupeKey` (`ChatViewModel+HistoryReconciliation.swift:768-783`) follows the same priority but its fallback differs from `messageIdentityKey`:

1. `serverMessageId` → `"<role>|serverid|<serverMessageId>"` (role here is the raw, un-normalized `message.role`).
2. `idempotencyKey` → `"<role>|idempotency|<idempotencyKey>"`.
3. Fallback → `"<role>|<timestamp>|<text>"`, where `text` is the message's content items' `text` values joined by newline (`\n`) then trimmed. This fallback is **plain role + timestamp + joined text** — it does **not** include `toolCallId`, `toolName`, or a content fingerprint.

The fallback returns `nil` (row passes through, never deduped) in two cases: **(a) `timestamp` is nil** — a nil timestamp alone forces pass-through even when text is present; or **(b)** the trimmed joined `text` is empty. `serverMessageId` and `idempotencyKey` are normalized (trimmed, nil-if-empty) before use.

The first occurrence of a key in the array wins; later duplicates are dropped. Rows that resolve to no key are appended unchanged.

### 4.4 ID Reconciliation (`reconcileMessageIDs`)

When incoming messages and previous messages share an identity key but different `UUID`s, the incoming message is "adopted" over the existing one: `id` is taken from the existing message (preserving SwiftUI's stable identity for animations), while all other fields come from the incoming (canonical) message. (`ChatViewModel+HistoryReconciliation.swift:621-649`)

Adoption also carries over `serverMessageId` and `serverSeq` from the incoming if present, upgrading the optimistic row so future reconciliation keys on the canonical id.

Audio attachment `durationSeconds` is preserved from the local row if the canonical row omits it (the gateway does not return local-computed durations). (`ChatViewModel+HistoryReconciliation.swift:227-257`)

### 4.5 Run-Refresh Reconciliation (`reconcileRunRefreshMessages`)

Used when `preservingOptimisticLocalMessages: true` — i.e., all post-send history refreshes where the user echo must survive until canonical history confirms it. Signature: `reconcileRunRefreshMessages(previous:incoming:pendingLocalUserEchoIDs:)` (`ChatViewModel+HistoryReconciliation.swift:651-746`). Edge cases: empty `previous` → return `incoming`; empty `incoming` → return `previous`.

The algorithm counts how many of each user-turn identity the incoming set can "explain" and only preserves trailing/pending local rows beyond that count, so repeated identical-text sends do not consume a single canonical row twice:

1. Run `reconcileMessageIDs(previous:incoming:)` → `reconciled`.
2. Build `incomingIdempotencyKeys` (set), `incomingIdentityKeys` (set of `messageIdentityKey`), and `remainingIncomingUserRefreshCounts` = per-`userRefreshIdentityKey` occurrence counts over `reconciled`.
3. **Canonical rows claim their count first.** For each `previous` message that has an identity key present in `incomingIdentityKeys` and a `userRefreshIdentityKey` with remaining count > 0, decrement that count. This ensures exact history rows own their incoming user count before any local-echo matching.
4. **Pending local echoes** (`previous` user rows whose `id` ∈ `pendingLocalUserEchoIDs`): if the row's idempotency key is **not** in `incomingIdempotencyKeys`, keep it (ambiguous/uncorrelated → never lose a turn). If it **is** matched, it is considered adopted (dropped); and if it also has a `userRefreshIdentityKey` with remaining count > 0, decrement that count.
5. **Trailing local users**: find the index of the last `previous` row whose identity key ∈ `incomingIdentityKeys` (`lastCanonicalPreviousIndex`); candidates are the `previous` rows **after** that index. Among those, keep a user row only when: it is not a pending-echo id (those handled in step 4); and either it has no identity key, or its identity key is absent from the incoming set, or (if it has a `userRefreshIdentityKey`) the remaining count is 0 — otherwise it is explained by the incoming and dropped (decrementing the count when consumed).
6. `optimisticUserMessages` = pending-local survivors ++ trailing-local survivors. If empty, return `reconciled`.
7. Re-insert each surviving optimistic user row into `reconciled` by timestamp: insert before the first existing row whose timestamp is strictly greater, else append. Rows with no timestamp are appended.
8. Return `dedupeMessages(reconciled)`.

### 4.6 Provisional Final Messages

When `chat.final` arrives from the gateway, the view model appends a "provisional final" assistant bubble (the optimistic streamed text made permanent) and stores metadata in `provisionalFinalMessagesByID`. Later, when the canonical `session.message` arrives (which may carry different text, a different timestamp, or no idempotency key), `adoptProvisionalFinalMessage` correlates it to the provisional row by:

1. Run-identity key set: the provisional row stores the bare `runId`, while the canonical `session.message` arrives keyed `"<runId>:assistant"`; the match uses `assistantRunIdentityKeys(for: provisionalRunId)` = `{runId, "<runId>:assistant"}` and checks membership of the incoming's normalized idempotency key (not raw equality).
2. Fallback: `provisional.reconciliationKey == finalMessageReconciliationKey(incoming)` **and** `isSameUserTurnBoundary(provisional.scope.latestUserTurn, currentRunMessageScope().latestUserTurn)`.

The match scans `messages.indices` from the **last** index backward for a row that both carries a `provisionalFinalMessagesByID` entry and satisfies (1) or (2). The guard requires that the incoming has at least one of a normalized idempotency key or a reconciliation key.

**Positioning (important):** on match, the provisional row is **removed from its current position and the adopted canonical row is appended at the end** of the array (`updated.remove(at:)` then `updated.append(adoptingCanonicalMessage(incoming, over: existing))`) — it does **not** replace in place. The adopted row keeps the provisional row's `UUID` (via `adoptingCanonicalMessage`, which also takes `serverMessageId`/`serverSeq`/content/etc. from the canonical incoming), so SwiftUI identity is stable, but its ordinal moves to the tail. The durable `session.message` arrives at its true transcript position and the subsequent `replaceMessages` → `orderedBySequence` re-sorts by `serverSeq`, so the final on-screen order is corrected; the append honors the case where a steering row was delivered after `chat.final`. The provisional marker is removed from `provisionalFinalMessagesByID`, the run's entry in `runMessageScopesByRunID` is dropped, then `replaceMessages(dedupeMessages(updated))`, `pruneProvisionalFinalMessages()`, and `pruneRunMessageScopes()` run. (`ChatViewModel+HistoryReconciliation.swift:581-619`)

**Why this is necessary:** `chat.final` and `session.message` represent the same row but may serialize it differently (different timestamps, different content id fields). Without the provisional final correlation, the UI would show two bubbles for one reply.

### 4.7 Canonical Reply Tracking

When a `session.message` event arrives carrying an assistant message with a `serverMessageId`, and there is exactly one pending run, that run is inserted into:

- `runsWithDeliveredCanonicalReply` — consumed once to prevent the subsequent `chat.final` optimistic append from duplicating the bubble.
- `runsAnsweredViaLiveStream` — retained for the life of the session so both `chat.final` and agent-terminal lifecycle handlers can skip their post-run history refetch (avoiding a redundant full transcript replacement). (`ChatViewModel.swift:2233-2239`)

Runs absent from `runsAnsweredViaLiveStream` still trigger a refetch, preserving the fallback for silent gateways.

### 4.8 Run-Scope Bounded Cleanup (`pruneRunMessageScopes`)

`pruneRunMessageScopes` (`ChatViewModel+HistoryReconciliation.swift:473-488`) bounds two per-run maps:

1. First, `runMessageScopesByRunID` is filtered to entries whose `session` snapshot still passes `isCurrentSession` (stale-session scopes are always dropped).
2. If `runMessageScopesByRunID` still exceeds **64** entries, it is further filtered to only entries referenced by a current need — `pendingRuns` ∪ the `runId`s of live `provisionalFinalMessagesByID` values.
3. If `runsAnsweredViaLiveStream` exceeds **64** entries, it is replaced by its intersection with `pendingRuns` (completion handlers read it synchronously before this prune, so dropping already-retired runs once the set grows large is safe).

---

## 5. Pending Run Lifecycle

File: `apps/shared/OpenClawKit/Sources/OpenClawChatUI/ChatViewModel+PendingRunTimeout.swift`

`pendingRuns: Set<String>` holds active run IDs. `pendingRunCount` is a derived count updated each time `pendingRuns` changes.

### 5.1 Timeout

`armPendingRunTimeout(runId:)` starts a `Task` that sleeps for `pendingRunTimeoutMs` (120 000 ms = 2 minutes). Each arm call increments `nextPendingRunTimeoutArmID`; the sleeping task checks its `armID` before firing and does nothing if a newer arm superseded it. On timeout:

1. `errorText = "Timed out waiting for a reply; try again or refresh."`
2. `clearPendingRun(runId, hapticEvent: .runFailed)`

`clearPendingRun` cancels the timeout task, removes the run from `pendingRuns`, clears `pendingLocalUserEchoMessageIDsByRunID[runId]`, and fires the haptic if the run was actually pending and no other runs remain. (`ChatViewModel+PendingRunTimeout.swift:4-51`)

`clearPendingRuns` (plural) bulk-clears all runs and their timeout tasks at once (used on bootstrap, seqGap, and session switch).

### 5.2 Send Flow

1. Gate: `canSend` = `!isSubmittingDraft && !isSending && pendingRunCount == 0 && hasDraftToSend` (`ChatViewModel.swift:593-604`). Note it checks `pendingRunCount == 0`, not `pendingRuns.isEmpty` directly.
   - `hasDraftToSend` = `(!input.trimmed.isEmpty) || (!attachments.isEmpty)` — a whitespace-only draft with no attachments cannot be sent.
   - A sibling predicate `canSendDraft` = `!isSubmittingDraft && !isSending && hasDraftToSend` omits the `pendingRunCount == 0` check; it gates draft submission paths that are allowed while a run is still pending.
2. Set `isSubmittingDraft = true` (gate against duplicate enqueues during slash catalog lookup).
3. Handle local slash commands (`/new`, `/reset`, `/clear`, `/compact`) before network.
4. Validate slash command draft (blocks commands with attachments).
5. Set `isSending = true`, `isSendingAttachmentDraft` if attachments present.
6. If offline, poll health; if still offline and outbox exists, enqueue durably and return.
7. FIFO ordering: if outbox has un-failed queued rows (or restore has not yet completed), route even live sends through the outbox to maintain ordering.
8. Generate local run UUID (`runId = UUID().uuidString`).
9. Insert into `pendingRuns`, arm timeout.
10. Append optimistic user echo message with `idempotencyKey: "\(runId):user"`.
11. Clear input and sent attachments immediately.
12. Await any pending model patches (`waitForPendingModelPatches`).
13. Resolve `effectiveThinkingLevelForSend` for the stored level.
14. Call `transport.sendMessage(...)`.
15. On response: if `response.runId != runId`, re-key local state to the gateway's run id (gateway may reuse an active identical run). Fire haptic `messageSent` on non-error/timeout status.
16. On `status == "ok"`: refresh history, then `finishPendingRunAfterTerminalOkSendAck`.
17. On other statuses: probe history, arm fallback refresh timers and `agent.wait` completion refresh if no in-flight run snapshot confirms the run is still active.
18. On transport error: attempt to move the message to the offline outbox (`preserveFailedLiveSend`). If preserved, mark health bad and return. Otherwise restore draft text.

### 5.3 Post-Send Refresh Fallback

If the gateway does not deliver either `chat.final` or a confirmed `session.message` for the run, the fallback arms two parallel paths:

- **Timed retries** at `[1500, 4000, 9000, 20000, 45000, 90000]` ms delays, each calling `refreshHistoryAfterRun`.
- **`agent.wait` completion refresh**: calls `transport.waitForRunCompletion(runId:timeoutMs:)` which issues `agent.wait` and on confirmed completion triggers one more history refresh.

Each fallback refresh checks `pendingRuns.contains(runId)` before fetching and stops as soon as the run is no longer pending.

---

## 6. Thinking-Level Omission Rule

File: `apps/shared/OpenClawKit/Sources/OpenClawChatUI/ChatViewModel+Thinking.swift`

### 6.1 `effectiveThinkingLevelForSend`

```swift
func effectiveThinkingLevelForSend(_ storedLevel: String, sessionKey: String? = nil) -> String {
    let showsPicker: Bool = ...   // from thinkingPickerIsAvailable
    return showsPicker ? storedLevel : "off"
}
```

When `showsThinkingPicker` is `false` (model metadata disallows reasoning), the effective level sent is `"off"`.

### 6.2 Wire Omission (`makeChatSendParamsJSON`)

```swift
thinking: thinking.isEmpty ? nil : thinking
```

The `thinking` field on `ChatSendParams` is `String?`. An empty string becomes `nil`, which `JSONEncoder` omits entirely from the JSON body. (`IOSGatewayChatTransport.swift:282-286`)

**Invariant:** An empty string signals "no user choice → omit the field → gateway applies model default." Reasoning-mandatory models (`xai/grok-4.6` and similar) will reject `"off"` and must receive the omitted field to work. (`IOSGatewayChatTransport.swift:103-105`, CLAUDE.md architecture section)

### 6.3 Thinking Level From History

When a history response contains `thinkingLevel` and the view model was not constructed with an explicit initial thinking level (`prefersExplicitThinkingLevel == false`), `applyHistoryPayload` applies the gateway's value and syncs the picker options. (`ChatViewModel.swift:779-787`)

Base thinking options: `["off", "minimal", "low", "medium", "high"]`. Gateway-supplied `thinkingLevels` on a session or the `sessionDefaults` override the base set when present and non-empty.

---

## 7. Transcript Cache

File: `apps/shared/OpenClawKit/Sources/OpenClawChatUI/ChatTranscriptCache.swift` (SQLite implementation), `ChatViewModel+TranscriptCache.swift` (integration)

`OpenClawChatSQLiteTranscriptCache` is a Swift `actor` backed by a SQLite database file (one file per gateway identity). It also implements `OpenClawChatCommandOutbox`.

### 7.1 Cache Bounds

| Constant | Value |
|---|---|
| `maxCachedSessions` | 50 |
| `maxCachedTranscripts` | 50 |
| `maxCachedMessagesPerSession` | 200 |
| `maxQueuedCommands` | 50 (outbox) |
| `maxAttachmentBytesPerCommand` | 40 000 000 (40 MB) |
| `maxQueuedAttachmentBytes` | 50 000 000 (50 MB) |
| `outboxCommandMaxAge` | 172 800 s (48 hours) |

### 7.2 Schema Version

Schema version 6 (as of this branch). Earlier versions: v2 adds durable outbox; v3 adds delivery ownership; v4 binds replay to main-routing contract; v5 persists routing identity; v6 keeps bounded attachment bytes inside the same command owner.

Three main tables:
- `cached_sessions` — single JSON payload row per gateway.
- `cached_transcripts` — keyed by `(gateway_id, session_key, agent_id)`.
- `outbox_commands` — durable send queue.
- `gateway_routing_identity` — persisted routing contract (scope, main key, default agent).

### 7.3 Cache-First Cold Open (`paintFromCacheIfNeeded`)

Called at bootstrap start. Two parallel async reads:

1. If `sessions.isEmpty && !hasAppliedLiveSessions`: load cached session list. Apply only if still empty and live has not arrived.
2. If `messages.isEmpty && !hasAppliedLiveHistory`: load cached transcript. Apply only if still empty, still the same session, and live has not arrived.

When cached rows are displayed, `isShowingCachedTranscript = true`. Live history always clears this flag. (`ChatViewModel+TranscriptCache.swift:66-90`)

**Guard:** `hasAppliedLiveHistory` is set to `true` the moment any live history response is applied. A delayed cache read that fires after this is unconditionally discarded, preventing stale cache rows from overwriting live content. (`ChatViewModel.swift:789-792`)

### 7.4 Write Path

`persistTranscriptToCache` chains writes through `pendingCacheWriteTask` (a serial task chain) so older snapshots cannot land after newer ones despite Swift concurrency's lack of ordering guarantees across awaits. (`ChatViewModel+TranscriptCache.swift:33-51`)

Cached messages strip binary attachment/tool argument payloads (`content` field, `thinkingSignature`, `arguments`), keeping only scalars (`text`, `mimeType`, `fileName`, `durationSeconds`, `id`, `name`, `serverMessageId`, `serverSeq`). The last 200 messages per session are kept.

Cache entries are evicted when the count exceeds 50 transcripts, keeping the 50 most recently written by `updated_at DESC, rowid DESC` (rowid tie-breaks equal timestamps, and `INSERT OR REPLACE` mints a fresh rowid, so the latest write always survives).

### 7.5 Agent ID Scoping in the Cache

`transcriptCacheAgentID(sessionKey:agentID:)` returns `nil` for canonical agent keys (`"agent:<id>:<key>"`) because the session key already disambiguates the owner. For alias keys (e.g., `"main"`), the `agentID` dimension is preserved to prevent cross-agent cache pollution when multiple agents share the same alias. (`ChatViewModel+TranscriptCache.swift:92-97`)

### 7.6 Cancellation Safety

`CanonicalMessageProofHub` (inside the SQLite cache actor, thread-safe via `NSLock`) records idempotency keys from canonical gateway history. When the user cancels an outbox command, the cancellation decision is made inside the SQLite transaction using `withProofDecision(for:)` which synchronously checks whether canonical evidence arrived before the cancellation. This closes the race window where a delivered message could be scrubbed by a concurrent cancel. (`ChatTranscriptCache.swift:53-79`)

---

## 8. Attachments

File: `apps/shared/OpenClawKit/Sources/OpenClawChatUI/ChatViewModel+Attachments.swift`

### 8.1 Size Limit

`maxAttachmentBytes = 5_000_000` (5 MB). Applied before staging for images (after JPEG re-encoding) and after reading for voice notes and file attachments.

### 8.2 Image Attachments

Photos and images go through `addImageAttachment(url:data:fileName:mimeType:)`:
1. Requires MIME conformance to `.image` UTType; rejects non-images with an error.
2. Re-encodes via `ChatImageProcessor.processForUpload(data:)` on a detached high-priority task (JPEG normalization and resizing).
3. Output MIME is always `"image/jpeg"`. Filename extension is changed to `.jpg`.
4. Preview thumbnail generated via `UIImage(data:)`.

### 8.3 File Attachments

`addFileAttachment(data:fileName:mimeType:)` stages raw bytes verbatim. Used for documents and animated GIFs that must reach the gateway unmodified. A thumbnail preview is generated only for MIME types conforming to `.image`. Type field is `"file"`.

### 8.4 Voice Notes

`addVoiceNoteAttachment(fileURL:durationSeconds:)` reads the m4a file, removes the temp file, caps duration at `OpenClawVoiceNoteRecorder.maximumDurationSeconds`, normalizes finite-only durations, and stages as `mimeType: "audio/mp4"`.

### 8.5 Attachment Staging Guard

`attachmentStagingCount` is incremented for each async staging operation and decremented on completion via `beginAttachmentStaging()` / `endAttachmentStaging()`. While non-zero, `blocksAttachmentOwnerChange` is `true`, which prevents session switches and delivery identity changes from racing with an attachment that is still being loaded. When staging completes, `applyDeferredExternalStateIfReady()` is called to flush any deferred state.

### 8.6 Wire Encoding

Each `OpenClawPendingAttachment` is encoded as `OpenClawChatAttachmentPayload`:
- `type`: from the attachment (usually `"file"`)
- `mimeType`: from the attachment
- `fileName`: from the attachment
- `content`: `data.base64EncodedString()`

The `attachments` field on `ChatSendParams` is omitted entirely when the array is empty.

---

## 9. Event Handling

### 9.1 `chat` Events

State machine on `chat.state`:

| State | Action |
|---|---|
| `"delta"` | `adoptRun(runId:bufferedText:)` — adopts the run into `pendingRuns` if not already present, updates `streamingAssistantText` only when the buffered text is longer than current (to prevent stale snapshots from regressing a mid-stream reply). |
| `"final"` | Appends provisional final message, clears streaming text, triggers `refetchHistoryUnlessAnsweredLive`. |
| `"aborted"` | Same as final. |
| `"error"` | Sets `errorText`, clears streaming text, triggers refetch. |

Session key matching for `chat` events uses `matchesCurrentSessionKey`. The event is not dropped if `isOurRun` is true even on a session key mismatch, preventing the UI from getting stuck in "thinking" when the gateway publishes a canonical key that differs from the alias the client tracks. (`ChatViewModel.swift:2276-2285`)

### 9.2 `session.message` Events

Processes a fully durable message record pushed by the gateway:

1. Strips inbound metadata from user messages (`stripInboundMetadata`).
2. Attaches `serverMessageId` and `serverSeq` from the envelope (top-level fields in the event payload).
3. Confirms any matching outbox command (cross-session, before the session-key guard).
4. If assistant with `serverMessageId` and exactly one pending run: mark `runsWithDeliveredCanonicalReply` and `runsAnsweredViaLiveStream`.
5. Invalidates history snapshots.
6. Try `adoptCorrelatedUserMessage` — if the incoming is the gateway echo of the user turn the client just sent (matched by `idempotencyKey`), update in-place and return early.
7. Try `adoptProvisionalFinalMessage` — if the incoming is the canonical version of a provisional assistant reply, replace in-place.
8. Otherwise append, reconcile IDs, and dedupe.

### 9.3 `agent` Events

Routes on `evt.stream`:

| Stream | Action |
|---|---|
| `"assistant"` | Accumulates `streamingAssistantText` from `data["text"]`. |
| `"lifecycle"` | Checks phase/status for terminal/failure signals; on terminal clears pending run and streaming text, fires appropriate haptic, triggers history refetch. |
| `"tool"` | `phase == "start"`: adds to `pendingToolCallsById` (sorted by `startedAt`). `phase == "result"`: removes. |

Legacy session-stream mode: if `pendingRuns.isEmpty && sessionId == evt.runId`, the event is still processed. (`ChatViewModel.swift:2438-2440`)

### 9.4 `seqGap` Events

Indicates a gap in the gateway's WebSocket sequence numbers — possible missed events. Immediately:
1. Clears all pending runs (without a haptic or error text).
2. Invalidates history and run snapshots.
3. Clears streaming text and tool calls.
4. Triggers a full history refresh.
5. Polls health.

### 9.5 `tick` Events

Triggers `pollHealthIfNeeded(force: false)`. The health poll uses a cooldown to avoid hammering the gateway.

---

## 10. Session Management Operations

| Operation | Transport RPC | Side Effects |
|---|---|---|
| New session (`/new`) | `sessions.create` | Falls back to `sessions.reset` if the transport does not support create. New key follows pattern `"ios-<uuid>"` or `"agent:<id>:ios-<uuid>"`. |
| Reset (`/reset`, `/clear`) | `sessions.reset` | Clears run scopes and provisional finals, then bootstraps. |
| Compact (`/compact`) | `sessions.compact` | 60 s cooldown guard. Sets `isLoading = true`, then bootstraps on success. |
| Rename | `sessions.patch(label:)` | Optimistically updates `sessions[i].label` and `displayName`. Rolls back on error. Refreshes sessions on success. |
| Pin/Unpin | `sessions.patch(pinned:)` | Optimistically re-organizes sessions list. Rolls back on error. |
| Archive | `sessions.patch(archived:true)` | Removes from list immediately. If archiving the active session, switches to `resolvedMainSessionKey`. |
| Restore (unarchive) | `sessions.patch(archived:false)` | Refreshes sessions. Returns `Bool` so callers avoid switching to still-archived sessions. |
| Delete | `sessions.delete` | Removes from list. If deleting active session and a different main session exists, switches to it. If deleting the active main session, re-bootstraps in place. |
| Fork | `sessions.create(fork:true)` | Returns new session key. |

---

## 11. Model and Thinking Selection

### 11.1 Model Selection

`selectModel(_:selectionID:)` optimistically sets `modelSelectionID` and calls `sessions.patch(model:)`. In-flight patches are tracked per session by `inFlightModelPatchCountsBySession`. The live send path and outbox flush path both call `waitForPendingModelPatches(in:)` before dispatching, ensuring the model patch has landed on the server before the next message is sent. (`ChatViewModel.swift:1994-1999`)

Multiple rapid model changes within one session produce sequential requests, each tagged with a request ID. A stale response (request ID mismatch) does not overwrite the latest desired state. On failure, the model reverts to the last successful selection for that session.

Model selection ID format: `"<provider>/<modelID>"` (e.g., `"anthropic/claude-sonnet-4-6"`). The sentinel `"__default__"` means "no explicit model; gateway chooses."

### 11.2 Context Usage Fraction

Computed as `min(max(totalTokens / contextTokens, 0), 1)`. Only computed when `totalTokensFresh != false`. Synced whenever `sessionKey` or `sessions` changes.

---

## 12. Key Data Flow Summary

```
User taps Send
  → performSend()
  → effectiveThinkingLevelForSend() → "" if picker hidden, stored level otherwise
  → transport.sendMessage(thinking: "" → omit field on wire)
  → gateway issues chat.send RPC (timeoutMs: 30000, HTTP timeout: 35s)
  → response.runId adopted into pendingRuns
  → arm pendingRunTimeout (120s)

Gateway sends events (WebSocket):
  chat.delta  → streamingAssistantText grows
  session.message (user echo) → adoptCorrelatedUserMessage (reuse bubble UUID)
  session.message (assistant) → mark runsWithDeliveredCanonicalReply
                              → adoptProvisionalFinalMessage
  chat.final  → appendFinalChatMessageIfPresent (provisional)
              → refetchHistoryUnlessAnsweredLive
                  (skipped if runsAnsweredViaLiveStream contains runId)
  agent.lifecycle terminal → clearPendingRun → haptic
                           → refetchHistoryUnlessAnsweredLive

All history responses:
  → decodeMessages → stripInboundMetadata → dedupeMessages
  → orderedBySequence (by serverSeq, carry-forward for transient rows)
  → reconcile IDs (preserve local UUIDs, adopt canonical fields)
  → persistTranscriptToCache (chained writes, strips binary payloads)
```
