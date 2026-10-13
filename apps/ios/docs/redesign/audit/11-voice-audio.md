# Audit — 11-voice-audio.md

## Scorecard

| metric | value |
|---|---|
| precision | 0.968 |
| recall | 0.708 |
| F | 0.818 |
| critical | 0 |
| major | 12 |
| minor | 47 |
| certified | false |
| claims | 118 |

## Defects (fix these)

### Wrong / Unsupported Claims

1. **minor** — Doc claims `matchesSessionKey` treats `"agent:main:main"` and `"main"` as equivalent; no function named `matchesSessionKey` was found in `TalkRealtimeWebRTCSession.swift` — claim is unsupported. — `Sources/Voice/TalkRealtimeWebRTCSession.swift`

2. **minor** — §11.3 implies the timer task drives waveform metering; metering is driven by a separate `meterTask` (started via `startMetering()` at line 247), not the `timerTask` (started via `startTimer()` at line 229) — both run at 100 ms intervals but are independent tasks. — `apps/shared/OpenClawKit/Sources/OpenClawChatUI/VoiceNoteRecorder.swift`

### Omissions

3. **minor** — Doc omits `.listRowBackground(Color.clear)` on the `Section` content wrapping the hero `VStack`. — `Sources/Design/TalkProTab.swift:148`

4. **major** — Doc omits `.frame(maxWidth: .infinity)` applied inside the primary button's label builder, which makes the button fill its full width. — `Sources/Design/TalkProTab.swift:139`

5. **major** — `.enablePermission` action calls `stopTalk()` before setting `showPermissionPrompt = true`; doc says only "shows the permission sheet" without mentioning the preceding stop. — `Sources/Design/TalkProTab.swift:309-311`

6. **minor** — Doc presents `openVoiceSettings` and `openSettings` as two separate independent closures; the initializer assigns `self.openVoiceSettings = openVoiceSettings ?? openSettings`, so `openVoiceSettings` falls back to `openSettings` when `nil`. — `Sources/Design/TalkProTab.swift:26`

7. **major** — `gatewayConnected` additionally requires `!self.appModel.isAppleReviewDemoModeEnabled`; demo mode forces `false` regardless of gateway status. The `TalkProState` table omits this guard. — `Sources/Design/TalkProTab.swift:201-204`

8. **major** — `fallbackIssue` is only non-nil when `gatewayConnected` is also `true` (early `guard self.gatewayConnected else { return nil }`); doc omits this conditional, which would cause a rebuilder to show the banner when offline. — `Sources/Design/TalkProTab.swift:206-209`

9. **minor** — `transportText` collapse logic checks both `provider` and `transport` independently against empty string OR the exact sentinel `"Not loaded"` on each side; doc says "collapses to either value alone when the other is empty or \"Not loaded\"" but does not specify the sentinel is checked on both sides independently. — `Sources/Design/TalkProTab.swift:237-243`

10. **major** — `permissionText` uses `gatewayTalkPermissionState.failureMessage` first; if non-nil it is shown instead of `statusLabel`; doc §1.6 does not mention `permissionText` at all. — `Sources/Design/TalkProTab.swift:265-269`

11. **minor** — `alignPersistedTalkState` third branch triggers on `talkEnabled != appModel.talkMode.isEnabled` and calls `appModel.setTalkEnabled(self.talkEnabled)` — doc says "sync @AppStorage talkEnabled → appModel.setTalkEnabled(_:)" but does not describe the exact condition distinguishing this branch from the branches that call `stopTalk()`. — `Sources/Design/TalkProTab.swift:288-290`

12. **minor** — `TalkProState.color`: the `!isConfigLoaded → OpenClawBrand.warn` mapping lives inside the `default:` branch of the permission switch, not as a peer row; doc table layout implies peer-level precedence but the nesting matters for exact reconstruction. — `Sources/Design/TalkProTab.swift:424-428`

13. **minor** — `TalkProState.waveformMode`: no separate case exists for `statusText` containing "connecting"/"thinking" when `isEnabled = false`; the two `.indeterminate` conditions are independent `if` checks irrespective of `isEnabled`. Doc conflates status-text checks with an enabled check. — `Sources/Design/TalkProTab.swift:507-510`

14. **major** — The `Voice & Talk Settings` button uses `.buttonStyle(.plain)`; without it the button renders as a tappable highlight. Doc omits this button style. — `Sources/Design/TalkProTab.swift:196`

15. **minor** — The `Voice & Talk Settings` button's trailing chevron is styled with `OpenClawType.footnoteSemiBold` and `.tertiary` foreground (not `.secondary`). Doc says "chevron.forward trailing" but omits the typography token and exact foreground role. — `Sources/Design/TalkProTab.swift:191-193`

16. **minor** — `Voice & Talk Settings` button label foreground is `.primary`; doc omits this modifier. — `Sources/Design/TalkProTab.swift:189`

17. **major** — `Voice & Talk Settings` uses an `HStack` + `Spacer()` + `.contentShape(Rectangle())` to make the full row tappable; doc omits these layout modifiers. — `Sources/Design/TalkProTab.swift:185-196`

18. **minor** — `TalkModeManager` mic level smoothing formula (`micLevel * 0.80 + raw * 0.20`, `raw = clamp(Float(level) * 10.0, 0, 1)`) is computed inside `AudioTapDiagnostics`'s RMS tap callback, not directly in `startRecognition`. The level input is `Float(level)` from the RMS tap, not from `averagePower`. Doc §5.7 attributes the formula to the speech recognition setup. — `Sources/Voice/TalkModeManager.swift:903-904`

19. **minor** — Noise floor calibration triggers at `>= 22` samples (not "after exactly 22"). Doc says "After 22 samples are gathered" which could imply exactly 22. — `Sources/Voice/TalkModeManager.swift:910-921`

20. **minor** — Default noise threshold before calibration is `0.18`; after calibration: `clamp(noiseFloor + 0.10, 0.12, 0.35)`. Doc §5.5 states this correctly — noted as confirmatory. — `Sources/Voice/TalkModeManager.swift:925-929`

21. **minor** — Silence monitor wake interval is `200_000_000 ns` (200 ms); doc says 200 ms — correct. — `Sources/Voice/TalkModeManager.swift:1082`

22. **minor** — Realtime restart: when `attempt >= 3`, `scheduleRealtimeRestart(after: nil, ...)` is still called (the session restarts but falls back to speech on next `start()`); doc says "set bypassRealtimeOnNextStart = true, fall back to speech pipeline" but omits that a restart is still scheduled. — `Sources/Voice/TalkModeManager.swift:296-307`

23. **minor** — `stop()` clears `gatewayTalkLastIssueText = nil` and `pendingRealtimeIssue = nil`; doc §5.9 omits these fields being cleared on stop. — `Sources/Voice/TalkModeManager.swift:574-576`

24. **minor** — `stop()` calls `Task { await self.unsubscribeAllChats() }`; doc omits this. — `Sources/Voice/TalkModeManager.swift:605`

25. **minor** — TTS route: `runtimeRoute.usesGatewayTalkSpeak` is a computed property on `TalkModeRuntimeRoute`; doc enumeration does not include `usesGatewayTalkSpeak` as a property on that type. — `Sources/Voice/TalkModeManager.swift:1709`

26. **minor** — PCM → MP3 fallback: `pcmFormatUnavailable = true` is set on 403 subscription_required errors and persists for the session so subsequent requests use `effectiveDefaultOutputFormat` instead of retrying PCM. Doc describes the retry but omits the per-session persistence of this flag. — `Sources/Voice/TalkModeManager.swift:1791-1796`

27. **minor** — `chat.send` payload includes `"idempotencyKey": UUID().uuidString` in addition to `thinking` and `timeoutMs`; doc §5.12 omits `idempotencyKey`. — `Sources/Voice/TalkModeManager.swift:1557-1563`

28. **minor** — WebRTC audio session uses `mode = .default` (not `.voiceChat`); doc §9.2 correctly states `.default`. — `Sources/Voice/TalkRealtimeWebRTCSession.swift:938`

29. **minor** — `session.ignoresPreferredAttributeConfigurationErrors = true` is set; doc correctly states this. — `Sources/Voice/TalkRealtimeWebRTCSession.swift:948`

30. **minor** — After SDP exchange, delegate receives `didChangeStatus("Listening")`; doc §9.4 step 9 correctly states this. — `Sources/Voice/TalkRealtimeWebRTCSession.swift:163`

31. **major** — ICE state change handling is not documented: `.disconnected` → "Reconnecting" status; `.failed` or `.closed` → "Realtime disconnected" then `stop()`. Doc §9.5 omits ICE state change behavior entirely. — `Sources/Voice/TalkRealtimeWebRTCSession.swift:974-991`

32. **major** — DataChannel state change handling is not documented: `.open` → "Listening" status (if not `assistantAudioActive`); `.closed` → "Realtime disconnected" then `stop()`. Doc §9.5 omits data channel state change behavior entirely. — `Sources/Voice/TalkRealtimeWebRTCSession.swift:1004-1020`

33. **minor** — `openclaw_agent_control` tool call falls back to a hardcoded error message "OpenClaw could not update the active run." and does NOT show "Still asking OpenClaw" status on failure; doc §9.6 omits these behavioral differences. — `Sources/Voice/TalkRealtimeWebRTCSession.swift:608-641`

34. **minor** — Tool result submission sends two events (`conversation.item.create` with `function_call_output`, then `response.create`); doc §9.6 correctly states this. — `Sources/Voice/TalkRealtimeWebRTCSession.swift:901-913`

35. **minor** — Realtime prefetch expiry leeway is `realtimePrefetchExpiryLeewaySeconds = 30.0` s before `expiresAt`; doc §9.8 correctly states "30-second leeway". — `Sources/Voice/TalkModeManager.swift:41`

36. **minor** — `RealtimeTalkRelaySession` barge-in: when mic suppression is active (`shouldSuppressMicrophoneDuringOutput()` returns true), `handleInputLevelDuringOutput` (the barge-in check) is also skipped entirely, not just the send path. Doc §8.6 says suppressed frames are "counted and logged but not sent" but does not state that suppression also bypasses the barge-in level check. — `Sources/Voice/RealtimeTalkRelaySession.swift:703-713`

37. **minor** — `scheduleOutputPlaybackIdle` delay is `max(350, expectedEndMs - nowMs + 500)` ms — 500 ms extra buffer plus a 350 ms floor. Doc §8.4 does not describe this idle scheduling mechanism or its timing formula. — `Sources/Voice/RealtimeTalkRelaySession.swift`

## Verdict

NEEDS-REPAIR — 12 major defects must be resolved before certification.
