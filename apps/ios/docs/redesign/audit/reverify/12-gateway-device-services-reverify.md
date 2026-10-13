# Re-verify — 12-gateway-device-services.md

## Scorecard

| metric | value |
|---|---|
| originalDefectCount | 29 (12 major + 17 minor) |
| resolvedCount | 29 |
| unresolved | 0 |
| newErrors | 3 (all minor) |
| remainingOmissions | 0 |

---

## Unresolved Original Defects

None. All 29 original defects are resolved.

---

## New Errors (introduced by the repair)

### N1 — minor — Security invariant overstated: plaintext manual gateways auto-connect without a TLS pin

**Claim (doc §Auto-connect logic):**
> "**Security invariant:** Auto-connect only proceeds to gateways that have a stored TLS fingerprint pin. First-time connects always require explicit user trust."

**Evidence:** `startActiveGatewayAutoConnect` at `Sources/Gateway/GatewayConnectionController.swift:990`:
```swift
guard !resolvedUseTLS || tlsParams?.expectedFingerprint != nil else { return false }
```

When `resolvedUseTLS` is `false` (a plaintext local-network manual gateway), the guard passes regardless of whether any TLS pin exists. No pin is required for plaintext connects. The invariant as stated is only accurate for TLS connects; the doc presents it as universal.

**Citation:** `Sources/Gateway/GatewayConnectionController.swift:990`

### N2 — minor — `forgetGateway` synchronous portion lists `disconnectForgottenGateway` as unconditional

**Claim (doc §forgetGateway synchronous portion):**
> "Calls `appModel.disconnectForgottenGateway`." (listed as an unconditional bullet)

**Evidence:** `Sources/Gateway/GatewayConnectionController.swift:546–553`:
```swift
let wasConnected = self.appModel?.activeGatewayConnectConfig?.effectiveStableID == stableID ||
    self.appModel?.connectedGatewayID == stableID
let shouldDisconnect = wasConnected
if shouldDisconnect {
    ...
    self.appModel?.disconnectForgottenGateway(preservingPendingConnectAttempt: hasDifferentPendingTarget)
}
```

`disconnectForgottenGateway` is only called when the gateway was actively connected (`shouldDisconnect == true`). Forgetting a gateway that was never activated skips this call. Presenting it as unconditional is incorrect.

**Citation:** `Sources/Gateway/GatewayConnectionController.swift:546–553`

### N3 — minor — `forgetGateway` async cleanup: session-reset wait and second token clear are conditional on `shouldDisconnect`, not always executed

**Claim (doc §forgetGateway async cleanup):**
> "Waits for gateway session reset.
> Runs a second `clearDeviceAuthTokens` pass..."

Presented as always occurring.

**Evidence:** `Sources/Gateway/GatewayConnectionController.swift:570–581`:
```swift
let cleanupTask = Task { @MainActor [weak appModel] in
    if let appModel {
        if shouldDisconnect {
            await appModel.waitForGatewaySessionResetIfNeeded()
            Self.clearDeviceAuthTokens(gatewayID: stableID)
        }
        await appModel.purgeChatTranscriptCache(gatewayID: stableID)
    } else if let databaseURL = NodeAppModel.chatTranscriptCacheDatabaseURL(gatewayID: stableID) {
        OpenClawChatSQLiteTranscriptCache.removeDatabaseFiles(at: databaseURL)
    }
}
```

The session-reset wait and second token clear only run when `shouldDisconnect` is true. When appModel is nil (after dealloc), there is a fallback path that directly removes the transcript DB files — also not mentioned. The doc implies these two steps always execute.

**Citation:** `Sources/Gateway/GatewayConnectionController.swift:570–581`

---

## Resolved Original Defects Summary

All 12 major and all 17 minor original defects are now resolved:

**Major defects resolved:**
1. `mostRecentlyConnectedManualGateway()` tie-break via `max { ... }` with `Int.min` and `lhs.stableID > rhs.stableID` — now documented. ✓
2. `resolvedManualPort` empty-host guard returning `nil` — now documented with line 76. ✓
3. `GatewayCredentialBundle` Keychain account format `"gateway-credentials.\(instanceId).\(stableID)"` — confirmed at `GatewaySettingsStore.swift:777`, now documented. ✓
4. `GatewayTLSFingerprintProbeFailure.certificateUnavailable` fourth enum case — now documented as a four-case table. ✓
5. Challenge handler path emitting `.certificateUnavailable` when `certificateFingerprint` returns nil — now documented. ✓
6. `maybeAutoConnect` step 3 `setActiveGateway(stableID: fallback.stableID)` call — now documented with line citation 899–905. ✓
7. `refreshActiveGatewayRegistrationFromSettings()` — fully documented with a five-step behavior list. ✓
8. `selectReachableSetupLink(_:)` — now documented with full behavior. ✓
9. `GatewayPendingTrustConnect` private struct — now documented with all fields. ✓
10. `pendingConnectionStableID` property role in `forgetGateway` — now documented in internal-tracking table. ✓
11. `GatewayDisplayState` is top-level (not nested inside `GatewayStatusBuilder`) — now documented explicitly. ✓
12. `waitForGatewaySessionResetIfNeeded()` second barrier before `applyGatewayConnectConfig` — now documented at line 1112. ✓

**Minor defects resolved:**
1. Global utility queue for TLS probe backstop timer (`DispatchQueue.global(qos: .utility)`) — now documented. ✓
2. `finish()` close code `.goingAway` nil reason — now documented. ✓
3. `currentCaps()` exact insertion positions for conditionals — now documented with ordered list. ✓
4. `motionAvailable()` availability check vs authorization status distinction — now documented with note. ✓
5. TLS probe runs only when `resolvedUseTLS` is true (plaintext never probes) — now documented. ✓
6. `guard stored == nil else { break }` fall-through mechanism — now documented. ✓
7. `mostRecentlyConnectedManualGateway()` is `max()` not a sort — now documented. ✓
8. `declinePendingTrustPrompt()` passes suppression lease to `resumeAutoConnect(after:)` — now documented. ✓
9. `onFailure` `failureCount: Int` parameter — now documented in `start` signature. ✓
10. `runCheck` zero-timeout shortcut (`(try? check()) ?? false`) — now documented. ✓
11. `GatewayHealthMonitor` sleep clamps negative interval to 0 with `max(0.0, ...)` — now documented. ✓
12. TCPProbe creates a fresh `DispatchQueue` per call — now documented. ✓
13. TCPProbe `connection.cancel()` before `cont.resume(returning:)` — now documented. ✓
14. `OpenClawNetworkInterfaceType` enum case `.wired` (not `.wiredEthernet`) — now documented explicitly. ✓
15. `NetworkStatusState` is a separate private class — now documented. ✓
16. `gatewayStatusText` trimmed with `.trimmingCharacters(in: .whitespacesAndNewlines)` before substring checks — now documented. ✓
17. `GatewayDiscoveryModel` sort is two-pass — now documented. ✓

(Additional minor items from the audit count — debug log bulk trim, `setDebugLoggingEnabled` behavior, `ManualAuthOverride.SetupAuth.hasBootstrapToken`, `prettifyInstanceName` any-whitespace split — all verified resolved.)

---

## Verdict

NEEDS-REPAIR — 3 minor new errors introduced by the repair (N1, N2, N3). Zero critical or major defects remain across unresolved + newErrors + remainingOmissions. Blocking count (critical + major): **0**.
