# Audit — 12-gateway-device-services.md

## Scorecard

| metric | value |
|---|---|
| precision | 0.912 |
| recall | 0.439 |
| F | 0.593 |
| critical | 0 |
| major | 12 |
| minor | 29 |
| certified | false |
| claims | 89 |

## Defects (fix these)

### Wrong / Unsupported Claims

**major** — Doc says auto-connect step 3 falls back to most recently connected manual gateway by `lastConnectedAtMs`, tie-broken by reverse stableID order. Code at `Sources/Gateway/GatewayConnectionController.swift:1026–1040` shows `mostRecentlyConnectedManualGateway()` filters entries with `kind == .manual`; no tie-breaking by reverse stableID order is visible in the readable code window. The claim cannot be confirmed. — `Sources/Gateway/GatewayConnectionController.swift`

**minor** — Doc says `waitForGatewaySessionResetIfNeeded()` is called again after permissions are resolved, before `applyGatewayConnectConfig`, citing line 1111. Line 1111 was outside the confirmed readable range; the second barrier call could not be verified at that precise line number. — `Sources/Gateway/GatewayConnectionController.swift:1111`

**minor** — Doc says `GatewayTLSFingerprintProbe` fires a DispatchQueue timer on "the probe's own queue" at `timeoutSeconds`. Code at line 1879 shows `DispatchQueue.global(qos: .utility).asyncAfter(...)` — the timer fires on the global utility queue, not a private probe queue. — `Sources/Gateway/GatewayConnectionController.swift:1879`

**major** — Doc says `GatewayCredentialBundle` Keychain account format is `gateway-credentials.<instanceId>.<stableID>`. The function `gatewayCredentialBundleAccount` is referenced but not visible in the read windows; the exact format string could not be confirmed. — `Sources/Gateway/GatewaySettingsStore.swift`

### Omissions

**major** — `GatewayTLSFingerprintProbeFailure` has a fourth enum case `.certificateUnavailable`, distinct from `.tlsUnavailable`. The spec omits this case entirely except in the error message table. — `Sources/Gateway/GatewayConnectionController.swift:20–25`

**minor** — `GatewayTLSFingerprintProbe` fires its DispatchQueue timer on `DispatchQueue.global(qos: .utility)`; the spec says "a DispatchQueue timer fires at timeoutSeconds" without specifying the global utility QoS queue. — `Sources/Gateway/GatewayConnectionController.swift:1879`

**major** — When `certificateFingerprint` returns nil (cert chain unavailable), the challenge handler emits `.failure(.certificateUnavailable)`, not `.tlsUnavailable`. The spec's URL-error mapping table does not cover this challenge-handler path at all. — `Sources/Gateway/GatewayConnectionController.swift:1896–1903`

**minor** — `GatewayTLSFingerprintProbe.finish()` calls `task.cancel(with: .goingAway, reason: nil)` then `session.invalidateAndCancel()`; the specific WebSocket close code `.goingAway` with nil reason is not documented. — `Sources/Gateway/GatewayConnectionController.swift:1925–1926`

**minor** — `currentCaps()` ordering: the actual order is canvas, screen, [camera if enabled], [voiceWake if enabled], [location if enabled], device, talk, [watch if supported], photos, contacts, calendar, reminders, [motion if available]. The spec lists "always included" as canvas, screen, device, talk, photos, contacts, calendar, reminders — omitting the specific insertion positions of conditionals. — `Sources/Gateway/GatewayConnectionController.swift:1628–1668`

**minor** — The `motionAvailable()` capability gate checks `CMMotionActivityManager.isActivityAvailable() || CMPedometer.isStepCountingAvailable()`; the permissions map checks `CMMotionActivityManager.authorizationStatus() == .authorized || CMPedometer.authorizationStatus() == .authorized`. The spec's permissions table says `CMMotionActivityManager.authorized || CMPedometer.authorized` without specifying these are `.authorizationStatus()` calls on each type. — `Sources/Gateway/GatewayConnectionController.swift:1750–1753`

**major** — `resolvedManualPort`: when host is empty after trimming, the function returns `nil` (not 18789). The spec describes port 0 or negative falling back to 18789 without mentioning the empty-host guard that returns nil. — `Sources/Gateway/GatewayConnectionController.swift:71–81`

**minor** — `connectManual` TLS probe is triggered when `resolvedUseTLS && (stored == nil || forceReconnect)`. The spec says "TLS probe runs on first-time connects and on forceReconnect" without stating that plaintext manual connects never probe (probe only runs when `resolvedUseTLS` is true). — `Sources/Gateway/GatewayConnectionController.swift:410`

**minor** — In `connectManual`, when `forceReconnect` is true and the probe fingerprint matches the stored pin, the code falls through via `break` (line 424: `guard stored == nil else { break }`). The spec documents the fall-through but does not mention it is implemented as a `break` exiting the probe block. — `Sources/Gateway/GatewayConnectionController.swift:424`

**minor** — `mostRecentlyConnectedManualGateway()` tie-break uses `lhs.stableID > rhs.stableID` as a max() comparison (not a sort). The spec calls out "reverse stableID order" correctly but does not document that the mechanism is a `max()` comparison rather than a sort. — `Sources/Gateway/GatewayConnectionController.swift:1026–1037`

**minor** — `declinePendingTrustPrompt()` calls `resumeAutoConnect(after: lease)` — not just `resumeAutoConnect()`. The spec omits that the suppression lease from `pendingTrustConnect` is passed to `resumeAutoConnect`. — `Sources/Gateway/GatewayConnectionController.swift:796–803`

**minor** — `GatewayHealthMonitor.onFailure` callback receives a `failureCount: Int` parameter. The spec describes `onFailure` being called but omits this parameter. — `Sources/Gateway/GatewayHealthMonitor.swift:28`

**minor** — `GatewayHealthMonitor.runCheck` when `timeoutSeconds == 0` calls `(try? check()) ?? false` directly without a timeout wrapper. The spec does not mention this special zero-timeout behavior. — `Sources/Gateway/GatewayHealthMonitor.swift:70–73`

**minor** — `GatewayHealthMonitor` sleep uses `max(0.0, config.intervalSeconds)` before converting to nanoseconds; negative interval is clamped to 0. Not documented in spec. — `Sources/Gateway/GatewayHealthMonitor.swift:50`

**minor** — TCPProbe creates a fresh `DispatchQueue(label: queueLabel)` per call (not a shared queue), using `queueLabel` as the label. The spec does not mention the per-call queue creation. — `Sources/Gateway/TCPProbe.swift:7–14`

**minor** — TCPProbe: `connection.cancel()` is called inside the `finish` closure before resuming the continuation, not after. The spec does not document the ordering of cancel relative to resume. — `Sources/Gateway/TCPProbe.swift:24–27`

**minor** — `NetworkStatusService`: the `OpenClawNetworkInterfaceType` enum case for wired Ethernet is `.wired`, not `.wiredEthernet`. The spec correctly names the NWInterface path check as `wiredEthernet` but uses `.wiredEthernet` as the enum value name, which is wrong. — `Sources/Device/NetworkStatusService.swift:37–47`

**minor** — `NetworkStatusService`: `NetworkStatusState` is a separate private class (not inlined). The spec does not mention this. — `Sources/Device/NetworkStatusService.swift:66–79`

**minor** — `GatewayStatusBuilder`: `gatewayStatusText` is trimmed with `.trimmingCharacters(in: .whitespacesAndNewlines)` before case-insensitive string contains checks. The spec omits this trimming step. — `Sources/Status/GatewayStatusBuilder.swift:32`

**minor** — `GatewayDisplayState` is a top-level `enum` in the same file, not nested inside `GatewayStatusBuilder`. The spec presents it as nested, which would mislead a rebuilder. — `Sources/Status/GatewayStatusBuilder.swift:4–9`

**major** — `maybeAutoConnect` step 3: when falling back from discovered to manual, `setActiveGateway(stableID: fallback.stableID)` is also called to update the active selection. The spec describes the fallback logic but omits this active-gateway update. — `Sources/Gateway/GatewayConnectionController.swift:899–905`

**major** — `refreshActiveGatewayRegistrationFromSettings()` / `refreshActiveGatewayRegistrationFromSettingsAsync()` — a public method allowing callers to re-apply the active gateway config with refreshed capabilities/permissions — is entirely absent from the spec. — `Sources/Gateway/GatewayConnectionController.swift:639–665`

**major** — `selectReachableSetupLink(_:)` — probes multiple connection endpoints from a setup deep link and returns the first reachable one using `GatewaySetupRouteProbeBudget.tcpConnectTimeoutSeconds` (2 s) — is not documented in the spec. — `Sources/Gateway/GatewayConnectionController.swift:176–193`

**major** — `GatewayPendingTrustConnect` private struct — holding url, stableID, isManual, authOverride, allowStoredDeviceAuth, suppressionLease, and gatewayGeneration needed to complete a trust-accepted connect — is not documented in the spec. — `Sources/Gateway/GatewayConnectionController.swift:1521–1529`

**major** — `pendingConnectionStableID` property tracks the stableID of any in-flight connection attempt and is used in `forgetGateway` to decide whether to cancel and release suppression. The spec documents `forgetGateway` behavior but omits this property and its role. — `Sources/Gateway/GatewayConnectionController.swift:129`

**minor** — `GatewayDiscoveryModel.prettifyInstanceName` whitespace normalization uses `split(whereSeparator: \.isWhitespace).joined(separator: " ")`, splitting on any whitespace (tabs, newlines) not just spaces. The spec says "collapse internal whitespace runs to single spaces" which is correct but incomplete. — `Sources/Gateway/GatewayDiscoveryModel.swift:165–169`

**minor** — `GatewayDiscoveryModel` sort is two-pass: once in `onResults` (per-domain) and again in `recomputeGateways` (merged). The spec documents the sort only once in the lifecycle section. — `Sources/Gateway/GatewayDiscoveryModel.swift:99, 122`

**minor** — `GatewayDiscoveryModel` debug log trim when the 200-entry bound is exceeded removes `debugLog.count - 200` entries from the front in one operation (not one at a time). The spec implies oldest-dropped-one-at-a-time. — `Sources/Gateway/GatewayDiscoveryModel.swift:160–162`

**minor** — `GatewayDiscoveryModel.setDebugLoggingEnabled`: when disabled, clears `debugLog = []` immediately; when enabled from disabled state, appends two snapshot log entries. Neither behavior is documented in the spec. — `Sources/Gateway/GatewayDiscoveryModel.swift:43–51`

**minor** — `ManualAuthOverride.SetupAuth` inner struct has a `hasBootstrapToken: Bool` computed property. Not mentioned in the spec. — `Sources/Gateway/GatewayConnectionController.swift:1401–1403`

## Verdict

NEEDS-REPAIR — 12 major blocking defects.
