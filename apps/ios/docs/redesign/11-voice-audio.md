# Voice, Talk Mode & Audio

This section covers every voice surface in the iOS app: the Talk tab that drives realtime voice conversation through either a direct WebRTC session or a gateway-relay session, the permission prompt that gates Talk when the gateway requires an explicit device approval, the voice-note recorder and waveform that lives in the chat composer, and the on-device transcription pipeline that converts recorded notes to text. Together these surfaces give the user a continuous voice loop — speak to the agent, hear it speak back, or record a note that arrives as a text attachment — without ever sending audio to a network transcription service outside the configured voice provider.

---

## 1. TalkProTab

**File:** `Sources/Design/TalkProTab.swift`

### 1.1 Role and entry point

`TalkProTab` is the root view rendered inside the "Talk" tab. It accepts an optional `OpenClawSidebarHeaderAction` for the leading toolbar button on phone (the drawer reveal), an `ownsNavigationStack: Bool` flag that controls whether it wraps itself in a `NavigationStack`, and two closures: `openSettings` (general connection settings) and `openVoiceSettings` (voice-specific settings). When `ownsNavigationStack` is `true` (default), the tab provides its own navigation stack; when `false` (iPad sidebar re-use case), it renders naked content.

### 1.2 Persistent state (AppStorage)

| Key | Type | Default | Purpose |
|---|---|---|---|
| `talk.enabled` | `Bool` | `false` | Cross-launch enabled state |
| `TalkSpeechLocale.storageKey` | `String` | `TalkSpeechLocale.automaticID` | User-selected speech recognition locale |
| `TalkDefaults.speakerphoneEnabledKey` (`talk.speakerphone.enabled`) | `Bool` | `true` | Whether built-in speaker is preferred |
| `talk.background.enabled` | `Bool` | `false` | Background listening toggle |

### 1.3 Transient state

| Property | Type | Purpose |
|---|---|---|
| `showPermissionPrompt` | `@State Bool` | Presents the gateway-permission sheet |
| `showTalkIssueDetails` | `@State Bool` | Presents the runtime issue details sheet |

### 1.4 TalkProState

`TalkProState` is a pure `Equatable` value type computed from live `TalkModeManager` properties on every render. It drives all derived UI without direct access to the manager in subviews.

| Property | Source |
|---|---|
| `gatewayConnected` | `GatewayStatusBuilder.build(appModel:) == .connected && !isDemoMode` |
| `isDemoMode` | `appModel.isAppleReviewDemoModeEnabled` |
| `isEnabled` | `appModel.talkMode.isEnabled || talkEnabled` |
| `statusText` | `appModel.talkMode.statusText` |
| `isConfigLoaded` | `appModel.talkMode.gatewayTalkConfigLoaded` |
| `isListening` | `appModel.talkMode.isListening` |
| `isSpeaking` | `appModel.talkMode.isSpeaking` |
| `isUserSpeechDetected` | `appModel.talkMode.isUserSpeechDetected` |
| `permissionState` | `appModel.talkMode.gatewayTalkPermissionState` |

#### 1.4.1 TalkProState.title

The title shown above the primary button:

| Condition (in priority order) | Title |
|---|---|
| `isDemoMode` | "Demo mode only" |
| `!gatewayConnected` | "Gateway offline" |
| `.missingScope` or `.requestFailed` | "Gateway permission required" |
| `.requestingUpgrade` | "Requesting approval" |
| `.upgradeRequested` | "Approval requested" |
| `.apiKeyMissing` | "Voice API key missing" |
| `.loadFailed` | "Voice config failed" |
| `!isConfigLoaded` | "Voice config unavailable" |
| `isSpeaking` | "Speaking" |
| `isListening` | "Listening" |
| `statusText` contains "connecting" (case-insensitive) | "Connecting" |
| `statusText` contains "thinking" | "Asking OpenClaw" |
| `isEnabled` | "Ready to talk" |
| default | "Talk is off" |

#### 1.4.2 TalkProState.color

The tint applied to the primary button:

| Condition | Color |
|---|---|
| `isDemoMode` or `!gatewayConnected` | `.secondary` |
| `.requestFailed` or `.loadFailed` | `OpenClawBrand.danger` |
| `.missingScope`, `.requestingUpgrade`, `.upgradeRequested`, `.apiKeyMissing` | `OpenClawBrand.warn` |
| `!isConfigLoaded` | `OpenClawBrand.warn` |
| `isEnabled` | `OpenClawBrand.ok` |
| default | `OpenClawBrand.accentHot` |

#### 1.4.3 TalkProPrimaryAction enum and button text

```
enum TalkProPrimaryAction: Equatable {
    case start, stop, enablePermission, openSettings, waiting
}
```

| Action | Button title | SF Symbol |
|---|---|---|
| `.start` | "Start Talk" | `play.fill` |
| `.stop` | "Stop Talk" | `stop.fill` |
| `.enablePermission` | "Enable Talk" | `key.fill` |
| `.openSettings` (gateway connected) | "Open Voice Settings" | `gearshape.fill` |
| `.openSettings` (gateway offline) | "Open Gateway Settings" | `gearshape.fill` |
| `.waiting` (demo) | "Demo Mode Only" | `lock.fill` |
| `.waiting` (approval) | "Waiting for Approval" | `hourglass` |

Action selection rules (in priority order):

1. `isDemoMode` → `.waiting`
2. `!gatewayConnected` → `.openSettings`
3. `.missingScope` or `.requestFailed` → `.enablePermission`
4. `.requestingUpgrade` or `.upgradeRequested` → `.waiting`
5. `.apiKeyMissing` or `.loadFailed` → `.openSettings`
6. `isEnabled` → `.stop`
7. default → `.start`

#### 1.4.4 TalkProWaveformMode and waveform drive

```
enum TalkProWaveformMode: Equatable {
    case level(Double)   // mic level 0…1 from TalkModeManager.micLevel
    case inputSpeech     // user speaking detected
    case speaking        // agent is speaking
    case indeterminate   // connecting / thinking
    case still           // inactive
}
```

Waveform mode selection from `TalkProState.waveformMode(micLevel:)`:

| Condition | Mode |
|---|---|
| `isDemoMode` or `!gatewayConnected` | `.still` |
| `.missingScope`, `.requestFailed`, `.apiKeyMissing`, `.loadFailed` | `.still` |
| `.requestingUpgrade` or `.upgradeRequested` | `.indeterminate` |
| `!isConfigLoaded` | `.still` |
| `isSpeaking` | `.speaking` |
| `isListening && isUserSpeechDetected` | `.inputSpeech` |
| `isListening` | `.level(micLevel)` |
| status contains "connecting" or "thinking" | `.indeterminate` |
| `isEnabled` | `.indeterminate` |
| default | `.still` |

### 1.5 View hierarchy and layout

```
TalkProTab.body
└── Group
    └── NavigationStack (when ownsNavigationStack)         // or naked content
        └── List
            ├── Section (optional — only when fallbackIssue != nil)
            │   └── TalkRuntimeIssueBanner                 // listRowInsets(EdgeInsets()), listRowBackground(.clear)
            ├── heroSection  (Section)
            │   └── VStack(spacing: 16)                    // frame(maxWidth: .infinity), padding(.vertical, 8)
            │       ├── TalkSiriWaveView(mode:)            // frame(height: 130), accessibilityHidden(true)
            │       ├── VStack(spacing: 4)
            │       │   ├── Text(state.title)              // OpenClawType.title3SemiBold, multilineTextAlignment(.center)
            │       │   └── Text(heroSubtitle)             // OpenClawType.subhead, .secondary, multilineTextAlignment(.center)
            │       └── Button (primary action)            // borderedProminent, large, tint = state.color
            │           └── Label(title, systemImage: icon)// OpenClawType.subheadSemiBold, .white foreground
            │                                              // disabled when primaryAction == .waiting
            ├── conversationSection  (Section "Conversation")
            │   ├── SettingsDetailRow("Agent", value: chatAgentName)
            │   ├── SettingsDetailRow("Session", value: chatSessionKey)
            │   └── SettingsDetailRow("Runtime", value: talkMode.statusText)
            ├── voiceModeSection  (Section "Voice Mode")
            │   ├── SettingsDetailRow("Configured", value: gatewayTalkVoiceModeTitle)
            │   ├── SettingsDetailRow("Active", value: activeModeText)
            │   ├── SettingsDetailRow("Transport", value: transportText)
            │   ├── SettingsDetailRow("Last issue", value: talkIssueText)  // omitted if nil
            │   ├── SettingsDetailRow("Permission", value: permissionText)
            │   └── SettingsDetailRow("Speech language", value: speechLocaleText)
            └── controlsSection  (Section "Controls")
                ├── Toggle "Speakerphone"                  // OpenClawType.body, accessibilityIdentifier: "talk-speakerphone-control"
                ├── Toggle "Background listening"          // OpenClawType.body, accessibilityIdentifier: "talk-background-listening-control"
                └── Button "Voice & Talk Settings"        // systemImage "slider.horizontal.3", chevron.forward trailing
                                                           // accessibilityIdentifier: "talk-voice-settings-control"
```

Navigation title: `"Talk"`. Toolbar has optional leading `OpenClawSidebarRevealButton` when `headerLeadingAction` is set.

### 1.6 Derived display strings

**heroSubtitle** priority:
1. `prefersPermissionCopy` → "Gateway approval is required before this phone can capture voice."
2. `isAppleReviewDemoModeEnabled` → "Voice is disabled in Apple Review demo mode."
3. `!gatewayConnected` → "Connect to your gateway to start a voice conversation."
4. `!gatewayTalkConfigLoaded` → "Open Voice settings after the gateway loads Talk configuration."
5. `gatewayTalkVoiceModeSubtitle` (non-empty, trimmed) → use that
6. default → "Routes voice to \(chatAgentName)."

**transportText**: `"\(provider) • \(transport)"`, collapses to either value alone when the other is empty or `"Not loaded"`.

**activeModeText**: `"\(title) • \(subtitle)"` or just title if subtitle is empty; `"Not active"` if title is empty.

**speechLocaleText**: `"Automatic"` when locale is `TalkSpeechLocale.automaticID`, otherwise the raw locale string.

### 1.7 Sheets

**Permission sheet** (`showPermissionPrompt`):
- Style: `.sheet`, `presentationDetents([.medium, .large])`, `.openClawSheetChrome()`
- Wraps in `NavigationStack`, `navigationTitle("Enable Talk")`
- Leading toolbar: Button "Not Now" (`OpenClawType.subheadSemiBold`) that dismisses
- Content: `TalkPermissionPromptView(style: .sheet)` + `.padding()`
- On `onPermissionReady`: dismisses and calls `startTalk()`

**Runtime issue sheet** (`showTalkIssueDetails`):
- Shows only when `fallbackIssue != nil`
- Content: `TalkRuntimeIssueDetailsSheet(issue:onOpenSettings:)`, `.openClawSheetChrome()`

### 1.8 Lifecycle

`onAppear` calls `alignPersistedTalkState()` which:
1. If demo mode and talk is somehow enabled → stop.
2. If `requiresTalkPermissionAction` and talk is enabled → stop.
3. Otherwise sync `@AppStorage talkEnabled` → `appModel.setTalkEnabled(_:)`.

**startTalk()**: guards `!isAppleReviewDemoModeEnabled`, sets `talkEnabled = true`, calls `appModel.talkMode.updateMainSessionKey(appModel.chatSessionKey)`, then `appModel.setTalkEnabled(true)`.

**stopTalk()**: sets `talkEnabled = false`, calls `appModel.setTalkEnabled(false)`.

**Speakerphone binding**: writes to `@AppStorage` and calls `appModel.setTalkSpeakerphoneEnabled(_:)` in a single transaction.

---

## 2. TalkSiriWaveView

**File:** `Sources/Design/TalkSiriWave.swift`

An iOS 9-style Siri waveform drawn with SwiftUI `Canvas` + `TimelineView`. Math adapted from noahchalifour/swiftui-siri-waveform-view (MIT) / alfianlosari/SiriWaveView.

### 2.1 Animation driver

`TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: frozen))` — 30 fps maximum. Frozen when `reduceMotion == true` or `mode == .still`. When frozen, `time = 0`; otherwise `time = timeline.date.timeIntervalSince(TalkSiriWaveView.born)` where `born` is a `static let Date()` set once at type definition time, so animation phase is continuous across view re-renders.

### 2.2 Colors

| State | Colors |
|---|---|
| `.still` | `[Color(uiColor: .systemGray2), Color(uiColor: .systemGray3), Color(uiColor: .systemGray4)]` |
| all other modes | `[OpenClawBrand.accent, Color(red: 0.95, green: 0.45, blue: 0.30), Color(red: 0.45, green: 0.08, blue: 0.12)]` |

### 2.3 Blend mode

Dark mode: `context.blendMode = .screen`, opacity `0.9`. Light mode: `context.blendMode = .normal`, opacity `0.55`.

### 2.4 View-level opacity

`mode == .still` → `.opacity(0.6)`. All other modes → `1.0`.

### 2.5 Baseline stroke

A 1-point horizontal line at `midY` is stroked with `.secondary.opacity(0.30)` before the waves.

### 2.6 Power function per mode

| Mode | Power formula |
|---|---|
| `.still` | `0.05` |
| `.indeterminate` | `0.16 + 0.10 × (0.5 + 0.5 × sin(time × 1.6))` — breathes slowly |
| `.level(level)` | `0.30 + 0.65 × clamp(level, 0, 1)` |
| `.inputSpeech` | `0.95` |
| `.speaking` | `0.70 × (0.55 + 0.45 × |sin(time × 5.0)|)` |

### 2.7 Wave path algorithm

Three color layers are rendered. For each layer, `seed = Double(index) × 7.31` and the following lobes are computed:

```
(0..<3).map { index in
    ampPhase = time × (0.9 + 0.23×f) + seed×2.4 + f×2.1
    amp      = 0.30 + 0.70 × (0.5 + 0.5 × sin(ampPhase))
    k        = 0.62 + 0.11×f
    driftPhase = time × (0.45 + 0.17×f) + seed + f×1.9
    t        = 2.8 × sin(driftPhase)
}
```

Each pixel column is computed at `x += 2` steps from `-midX` to `midX`. For each column the per-lobe contribution is `max(y, attenuatedSine(x: graphX, A: amp×midY×power, k: k, t: t))`. The attenuation envelope is `|A·sin(kx−t)| × (4/(4+(kx−t′)²))^4` where `t′ = t − π/2`. Upper and lower halves are mirrored around `midY` to form a filled `Path`. `graphX = x / (midX/9.0)` maps canvas pixels to the wave's coordinate space.

---

## 3. TalkPermissionPromptView

**File:** `Sources/Voice/TalkPermissionPromptView.swift`

Shown either as a `.card` embedded in a screen or `.sheet` in the modal. Both styles share the same layout; only typography and the `background`/`overlay` differ on `card`/`sheet` vs default.

### 3.1 Layout

```
VStack(alignment: .leading, spacing: 16 / 12)   // sheet = 16, card = 12
├── HStack(alignment: .top, spacing: 12)
│   ├── Image(systemName: iconSystemName)         // OpenClawType.title3, frame(28×28)
│   │                                             // warn color when requestIsPending, else accent
│   └── VStack(alignment: .leading, spacing: 6)
│       ├── Text(titleText)                       // sheet → OpenClawType.title3SemiBold; card → OpenClawType.headline
│       └── Text(messageText)                     // OpenClawType.footnote, .secondary, fixedSize(h: false, v: true)
├── Label(failureMessage, "exclamationmark.triangle.fill")  // only if state.failureMessage != nil
│                                                 // OpenClawType.footnote, OpenClawBrand.danger
├── LabeledContent ("Request ID") { monospaceText }         // only if state.requestId != nil
│                                                 // OpenClawType.monoSmall, .secondary, .textSelection(.enabled)
│                                                 // label: OpenClawType.footnoteSemiBold
└── HStack(spacing: 10)
    ├── Button (primary — send/retry approval)   // borderedProminent, disabled while .requestingUpgrade
    │   └── Label or ProgressView+Text           // OpenClawType.subheadSemiBold
    └── Button "Retry" "arrow.triangle.2.circlepath"  // bordered, OpenClawType.subheadSemiBold
```

Padding: `.padding(16)` when `style == .card || style == .sheet`.

Background (card/sheet only): `RoundedRectangle(cornerRadius: OpenClawRadius.md, style: .continuous)` filled with `.thinMaterial`.

Overlay (card/sheet only): same `RoundedRectangle` stroked with `OpenClawBrand.accent.opacity(0.20)`, lineWidth `1`.

### 3.2 Dynamic content by permission state

| `TalkGatewayPermissionState` | Icon | Title | Primary button |
|---|---|---|---|
| `.requestingUpgrade` | `paperplane.fill` | "Sending approval request" | ProgressView + "Sending…" |
| `.upgradeRequested` | `hourglass` | "Approval sent" | "Request Again" / `arrow.clockwise` |
| `.requestFailed` | `exclamationmark.triangle.fill` | "Could not request approval" | "Send Approval Request" / `paperplane.fill` |
| default | `key.fill` | "Enable Talk" | "Send Approval Request" / `paperplane.fill` |

Icon foreground: `OpenClawBrand.warn` when `requestIsPending`, else `OpenClawBrand.accent`.

Message:
- `.requestingUpgrade` → "Sending a new pairing request to your gateway..."
- `.upgradeRequested` → "Approve this request on your gateway. Talk will start automatically when approval lands."
- default → "This device needs gateway approval before Talk can use realtime voice. Audio will go directly from this device to the voice provider."

### 3.3 Polling behavior

A `.task(id: pollTaskKey)` fires when the state is `.requestingUpgrade` or `.upgradeRequested`. It polls every 3 seconds (`3_000_000_000 ns`) via `appModel.pollTalkPermissionUpgrade()`. Polling stops when `requiresTalkPermissionAction` becomes `false`. When state changes to `.ready`, `onPermissionReady?()` is called via `onChange`.

`pollTaskKey` is `"requesting"` for `.requestingUpgrade`, `"pending:\(requestId ?? "")"` for `.upgradeRequested`, `"idle:\(state.statusLabel)"` otherwise — ensuring the task restarts only when the pending-request identity changes.

---

## 4. TalkGatewayPermissionState

**File:** `Sources/Voice/TalkGatewayPermissionState.swift`

```swift
enum TalkGatewayPermissionState: Equatable {
    case unknown
    case ready
    case missingScope(String)
    case requestingUpgrade
    case upgradeRequested(requestId: String?)
    case requestFailed(String)
    case apiKeyMissing
    case loadFailed(String)
}
```

`requiresTalkPermissionAction` is `true` for `.missingScope`, `.requestingUpgrade`, `.upgradeRequested`, `.requestFailed`. Start is blocked whenever this returns `true`.

`isApprovalRequestInProgress` is `true` for `.requestingUpgrade`, `.upgradeRequested`. Used to show ProgressView and disable the primary button.

---

## 5. TalkModeManager

**File:** `Sources/Voice/TalkModeManager.swift`

`@MainActor @Observable final class TalkModeManager: NSObject`. Centralized talk state and behavior. Intentionally kept in one file to preserve `private` visibility across many members.

### 5.1 Published observable state

| Property | Type | Notes |
|---|---|---|
| `isEnabled` | `Bool` | Talk mode on/off |
| `isListening` | `Bool` | Microphone active, waiting for speech |
| `isSpeaking` | `Bool` | Agent TTS playback active |
| `isUserSpeechDetected` | `Bool` | Speech above threshold detected |
| `isPushToTalkActive` | `Bool` | PTT capture in progress |
| `statusText` | `String` | Human-readable status for display |
| `micLevel` | `Double` | 0..1 smoothed amplitude for UI; `raw × 10.0`, smoothed with 0.80/0.20 EMA |
| `gatewayTalkConfigLoaded` | `Bool` | Config fetched from gateway |
| `gatewayTalkPermissionState` | `TalkGatewayPermissionState` | Gateway scope/key state |
| `gatewayTalkVoiceModeTitle` | `String` | Configured voice mode display name |
| `gatewayTalkVoiceModeSubtitle` | `String?` | Subtitle |
| `gatewayTalkActiveModeTitle` | `String` | Currently active mode title |
| `gatewayTalkActiveModeSubtitle` | `String?` | Active mode subtitle |
| `gatewayTalkCurrentFallbackIssue` | `TalkRuntimeIssue?` | Current iOS fallback cause |
| `gatewayTalkLastIssueText` | `String?` | Diagnostic summary of last issue |

### 5.2 Private constants

| Constant | Value |
|---|---|
| `defaultModelIdFallback` | `"eleven_v3"` |
| `defaultRealtimeModelIdFallback` | `"gpt-realtime-2"` |
| `defaultTalkProvider` | `"elevenlabs"` |
| `defaultSilenceTimeoutMs` | `TalkDefaults.silenceTimeoutMs` = `900` |
| `realtimeStableSessionSeconds` | `30.0` |
| `realtimeRestartDelaysNanoseconds` | `[500_000_000, 2_000_000_000]` (0.5 s, 2 s) |

### 5.3 Capture modes

```swift
private enum CaptureMode {
    case idle
    case continuous   // Always-on speech recognition
    case pushToTalk   // Explicit PTT session
}
```

### 5.4 Session start sequence

`start()` is `async` and guarded by `isEnabled`, `captureMode != .pushToTalk`, `foregroundAudioCaptureAllowed`, `!isListening`, `!isStarting`, and `gatewayConnected`. When guards pass:

1. Request microphone permission (`AVAudioApplication.requestRecordPermission`).
2. Call `ensureTalkConfigLoadedForStart()` to fetch gateway config if not already loaded.
3. Block if `gatewayTalkPermissionState.requiresTalkPermissionAction`.
4. If `runtimeRoute.usesRealtime && !bypassRealtimeOnNextStart`:
   - `.realtimeRelay` → `startRealtimeRelayIfAvailable()`
   - `.realtimeWebRTC` → `startRealtimeIfAvailable()`
   - On `.started` or `.ignored` → return early.
   - On `.unavailable(issue)` → record issue, fall through to speech fallback.
5. Request speech recognition permission (`SFSpeechRecognizer.requestAuthorization`).
6. Configure audio session, start speech recognition tap, set `captureMode = .continuous`, start silence monitor.

### 5.5 Noise floor calibration

While `isListening && !isSpeaking && !noiseFloorReady`, each mic sample is collected. After 22 samples are gathered:
- Sort ascending, take the lower half (min 6 samples).
- Average them → `noiseFloor`.
- `threshold = clamp(noiseFloor + 0.10, 0.12, 0.35)`.
- Before calibration, `threshold = 0.18` (hardcoded default).
- `lastAudioActivity` is updated whenever `raw >= threshold`.

### 5.6 Silence window and endpointing

`silenceWindow` is initialized from `TalkDefaults.silenceTimeoutMs / 1000.0` = `0.9 s`. The silence monitor task wakes every 200 ms. In `continuous` mode: if a transcript exists and `max(lastHeard, lastAudioActivity)` is more than `silenceWindow` ago, `processTranscript` is called. In `pushToTalk` mode with `pttAutoStopEnabled`: same check, but calls `endPushToTalk`.

### 5.7 Speech recognition setup

`SFSpeechAudioBufferRecognitionRequest` with `shouldReportPartialResults = true`, `taskHint = .dictation`. Audio tap bufferSize: `2048` frames, format matching the input node's native format. The mic level computation:

```swift
raw = clamp(Float(level) × 10.0, 0, 1)
micLevel = micLevel × 0.80 + raw × 0.20
```

### 5.8 Realtime restart policy

On `handleRealtimeSessionFinish()`:
- `activeDuration >= 30 s` → `attempt = 1` (treated as "stable", restart after 0.5 s).
- Otherwise `attempt = previousRapidRestartCount + 1`.
- `attempt == 1` → delay `500_000_000 ns`, restart.
- `attempt == 2` → delay `2_000_000_000 ns`, restart.
- `attempt >= 3` → no delay, set `bypassRealtimeOnNextStart = true`, fall back to speech pipeline.

### 5.9 Session stop

`stop()` clears all state, cancels tasks, deactivates the audio session with `.notifyOthersOnDeactivation`, and calls `TalkSystemSpeechSynthesizer.shared.stop()`. Any in-flight PTT continuation is resumed with status `"cancelled"`.

### 5.10 Background handling

`suspendForBackground(keepActive: Bool)`: when `keepActive = false`, stops recognition and frees the audio session while keeping `isEnabled = true`. `statusText` set to `"Paused"`. Returns `wasActive`. `resumeAfterBackground(wasSuspended:)` calls `start()` again.

### 5.11 Push-to-talk API

`beginPushToTalk()` → async throws `OpenClawTalkPTTStartPayload(captureId: UUID().uuidString)`. Sets `captureMode = .pushToTalk`, starts recognition, `isPushToTalkActive = true`, `statusText = "Listening (PTT)"`.

`endPushToTalk()` → async returns `OpenClawTalkPTTStopPayload` with captured transcript and status `"queued"` / `"empty"` / `"offline"` / `"idle"`.

`runPushToTalkOnce(maxDurationSeconds: 12)` → wraps begin/end in a `CheckedContinuation` with a PTT timeout and auto-stop on silence.

`cancelPushToTalk()` → status `"cancelled"`.

### 5.12 TTS playback routing

After receiving assistant text in `processTranscript`, TTS route is selected:

1. **`gatewayTalkSpeak`** → `playGatewayTalkSpeak()` — uses `TalkGatewaySpeechClient` to synthesize via the gateway, plays PCM or buffered audio.
2. **ElevenLabs local** → `playAssistant()` — resolves voice/model, calls `ElevenLabsTTSClient.streamSynthesize()`. Tries PCM first (sample rate from output format); if the API rejects PCM (e.g. `403 subscription_required`) sets `pcmFormatUnavailable = true` and retries with `mp3_44100_128`.
3. **System fallback** → `TalkSystemSpeechSynthesizer.shared.speak(text:language:)` — used when API key/voiceId missing or on TTS error.

The `chat.send` call includes `"thinking": "low"` and `"timeoutMs": 30000`.

---

## 6. TalkModeGatewayConfig

**File:** `Sources/Voice/TalkModeGatewayConfig.swift`

### 6.1 Execution modes

```swift
enum TalkModeExecutionMode: Equatable {
    case native          // local ElevenLabs or gateway TTS
    case realtimeWebRTC  // direct OpenAI WebRTC (no gateway in the audio path)
    case realtimeRelay   // audio relayed through the gateway
}
```

### 6.2 Runtime routes

```swift
enum TalkModeRuntimeRoute: Equatable {
    case localElevenLabs
    case gatewayTalkSpeak
    case realtimeWebRTC
    case realtimeRelay
}
```

`usesRealtime` = `.realtimeRelay` or `.realtimeWebRTC`. `gatewayOwnsCredentials` = all except `.localElevenLabs`.

### 6.3 Provider selection (AppStorage)

```
TalkModeProviderSelection.storageKey = "talk.providerSelection"
```

| Case | Raw value | Label |
|---|---|---|
| `.gatewayDefault` | `"gateway"` | "Gateway Default" |
| `.nativeElevenLabs` | `"elevenlabs"` | "ElevenLabs" |
| `.openAIRealtime` | `"openai-realtime"` | "Realtime-2 (OpenAI)" |

### 6.4 Realtime voice selection (AppStorage)

```
TalkModeRealtimeVoiceSelection.storageKey = "talk.realtime.voiceSelection"
```

Available voices (lowercased): `"alloy"`, `"ash"`, `"ballad"`, `"coral"`, `"echo"`, `"sage"`, `"shimmer"`, `"verse"`, `"marin"`, `"cedar"`. Display label: first character uppercased.

### 6.5 Routing resolution

`TalkModeRoutingResolver.resolve(parsed:providerSelection:defaultProvider:defaultRealtimeModelId:)`:

- `.gatewayDefault`: follows `parsed.executionMode` — `.realtimeWebRTC` → `.realtimeWebRTC`, `.realtimeRelay` → `.realtimeRelay`, gateway default ElevenLabs → `.localElevenLabs`, other → `.gatewayTalkSpeak`.
- `.nativeElevenLabs`: forces `.localElevenLabs`.
- `.openAIRealtime`: forces `provider = "openai"`, `model = defaultRealtimeModelId`. Route is `.realtimeRelay` if `openAIRequiresGatewayRealtimeTransport` (Azure endpoint/deployment detected, or explicit `gateway-relay`/`provider-websocket` transport), else `.realtimeWebRTC`.

### 6.6 Gateway config parsing

`TalkModeGatewayConfigParser.parse(config:...)` reads the nested gateway config structure:

- `config["talk"]` → provider config, voice aliases, model, voice, output format.
- `config["talk"]["realtime"]` → provider, model, voice, transport, `brain`.
- `config["talk"]["realtime"]["providers"]` → per-provider overrides.
- Execution mode defaults to `.native` if `realtime.mode != "realtime"` or `brain` is set to something other than `"agent-consult"`.
- `requiresGatewayRealtimeTransport = true` when `transport == "gateway-relay"`, `"provider-websocket"`, or Azure OpenAI keys detected.

`TalkModeGatewayConfigState` fields used by TalkModeManager include: `activeProvider`, `executionMode`, `realtimeProvider`, `realtimeModelId`, `realtimeVoiceId`, `defaultVoiceId`, `voiceAliases`, `interruptOnSpeech`, `silenceTimeoutMs`, `speechLocaleID`, `rawConfigApiKey`.

---

## 7. TalkDefaults

**File:** `Sources/Voice/TalkDefaults.swift`

| Constant | Value |
|---|---|
| `silenceTimeoutMs` | `900` (ms → 0.9 s silence window) |
| `speakerphoneEnabledKey` | `"talk.speakerphone.enabled"` |
| `speakerphoneEnabledByDefault` | `true` |

`TalkAudioRoute.categoryOptions(speakerphoneEnabled:)` includes `.defaultToSpeaker` when speakerphone is enabled, plus `.allowBluetoothHFP`, `.allowBluetoothA2DP`, `.allowAirPlay` always.

`TalkAudioRoute.shouldForceSpeaker(preferenceEnabled:outputPortTypes:)` forces override only when all active output ports are `.builtInReceiver` or `.builtInSpeaker` (i.e., no headset/Bluetooth).

---

## 8. RealtimeTalkRelaySession

**File:** `Sources/Voice/RealtimeTalkRelaySession.swift`

`@MainActor final class`. Manages a single gateway-relayed realtime audio session. The `RealtimeAudioSender` is an `actor` that serializes concurrent audio sends.

### 8.1 Session create payload

`talk.session.create` is called with:

```json
{
  "sessionKey": "<mainSessionKey>",
  "mode": "realtime",
  "transport": "gateway-relay",
  "brain": "agent-consult",
  "provider": "<optional>",
  "model": "<optional>",
  "voice": "<optional>"
}
```

Timeout: 20 seconds. Returns `TalkSessionCreateResult` containing `relaysessionid` and `audio` contract.

### 8.2 Audio contract

`configureAudioContract(_:)` reads from the `audio` field in the create response:

- `inputEncoding` / `outputEncoding` — expected both `"pcm16"`. Warns on mismatch.
- `inputSampleRateHz` — defaults to `24000`.
- `outputSampleRateHz` — defaults to `24000`.

### 8.3 Microphone pump

`startMicrophonePump()` installs an `AVAudioNodeTapBlock` on `audioEngine.inputNode` with `bufferSize: 2048`. The tap runs on Core Audio's realtime thread and does two things:

1. Re-samples input PCM to `inputSampleRateHz` using nearest-neighbor linear interpolation per `encodePCM16(buffer:inputSampleRate:targetSampleRate:)`.
2. Computes RMS: `sqrt(sumOfSquares / sampleCount)` across all channels.

The resulting `Data` (little-endian Int16) is sent via `RealtimeAudioSender.send()` with a millisecond timestamp from `ProcessInfo.processInfo.systemUptime × 1000`.

`RealtimeAudioSender` caps concurrent sends at `maxPendingSends = 4`; additional frames are dropped. The gateway method is `talk.session.appendAudio`, timeout 8 seconds. The payload is `{"sessionId": ..., "audioBase64": ..., "timestamp": ...}`.

### 8.4 Output playback

Incoming `talk.event` events are dispatched by type:

| Event type | Action |
|---|---|
| `"ready"` | Set `hasReceivedReady = true`, resume startup waiter, `onStatus("Listening (Realtime)")` |
| `"audio"` | Decode base64, yield to `AsyncThrowingStream`, call `onSpeakingChanged(true)` |
| `"audioDone"` | Finish the output stream |
| `"clear"` | `stopOutputPlayback()` |
| `"transcript"` | If `final && role == "user"` → `onStatus("Thinking…")`, if `role == "assistant"` → `onStatus("Listening (Realtime)")` |
| `"toolCall"` | Dispatch to `handleToolCall` |
| `"error"` | Build `TalkRuntimeIssue`, call `onIssue`, resume startup waiter with `.failed` |
| `"close"` | If never received ready → fail; otherwise `onStatus("Ready")` |

Output playback uses `PCMStreamingAudioPlaying.play(stream:sampleRate:)`. Output session IDs are used to detect stale completions when playback is interrupted and restarted.

### 8.5 Barge-in detection

Constants:

| Name | Value |
|---|---|
| `bargeInRmsThreshold` | `0.08` |
| `bargeInCooldownMs` | `900` ms |
| `minOutputBeforeBargeInMs` | `250` ms |

When `isOutputPlaying` and mic RMS exceeds `bargeInRmsThreshold`, barge-in fires if at least `minOutputBeforeBargeInMs` have elapsed since output started and at least `bargeInCooldownMs` have elapsed since the last barge-in. It calls `cancelOutput(reason: "barge-in")` → `talk.session.cancelOutput`.

### 8.6 Speaker echo suppression

`shouldSuppressMicrophoneDuringOutput()` returns `true` when `AVAudioSession.currentRoute.outputs` contains `.builtInSpeaker`. When suppressed, mic frames are counted and logged but not sent. This prevents the built-in speaker from feeding back into the microphone and being treated as user input. Headsets keep barge-in because their output does not bleed into the mic.

### 8.7 Startup timeout

`startupReadyTimeoutSeconds = 12`. If neither `ready` nor an error event arrives within 12 seconds, a `TalkRuntimeIssue(code: .realtimeUnavailable, message: "Realtime did not become ready in time.", transport: "gateway-relay", phase: "connect")` is issued.

### 8.8 Tool call dispatch

Realtime tool calls arrive as `"toolCall"` events and are dispatched via `talk.client.toolCall` (timeout 30 s). The tool result is submitted via `talk.session.submitToolResult` (timeout 30 s). A special `"openclaw_agent_control"` tool name routes to `talk.session.steer` instead.

---

## 9. TalkRealtimeWebRTCSession

**File:** `Sources/Voice/TalkRealtimeWebRTCSession.swift`

`@MainActor final class`. Direct OpenAI WebRTC session using the `WebRTC` framework.

### 9.1 Configuration constants

| Constant | Value |
|---|---|
| `defaultOfferURL` | `"https://api.openai.com/v1/realtime/calls"` |
| `mediaStreamID` | `"openclaw-ios-realtime"` |
| `audioTrackID` | `"openclaw-ios-audio"` |
| `dataChannelLabel` | `"oai-events"` |
| `toolCallTimeoutSeconds` | `12` |
| `toolResultTimeoutSeconds` | `45` |
| `agentWaitSliceSeconds` | `3` |
| `agentWaitRequestGraceSeconds` | `15` |
| `historyFallbackTimeoutSeconds` | `5` |
| `stillWorkingDelaySeconds` | `6` |
| `assistantPlaybackDrainGraceSeconds` | `1.8` |

### 9.2 Audio session

`RTCAudioSessionConfiguration.webRTC()` with:
- `category = .playAndRecord`
- `mode = .default`
- `categoryOptions` from `TalkAudioRoute.categoryOptions(speakerphoneEnabled:)`
- `sampleRate = 48000`
- `ioBufferDuration = 0.01` (10 ms)

`session.ignoresPreferredAttributeConfigurationErrors = true` prevents non-fatal WebRTC audio attribute errors from throwing.

### 9.3 Session create

`talk.client.create` via gateway with `TalkRealtimeClientCreateParams(provider:model:voice:)`, timeout 12 s. Returns `TalkRealtimeClientSession` with `provider`, `transport`, `model`, `voice`, `clientSecret`, `offerUrl`, `offerHeaders`, and `expiresAt`.

If a `prefetchedSession` is provided, the `talk.client.create` call is skipped entirely — the prefetched session token is used directly.

### 9.4 WebRTC negotiation

1. Create `RTCPeerConnectionFactory` with default video codecs (audio-only usage).
2. Create `RTCPeerConnection` with `sdpSemantics = .unifiedPlan`, `continualGatheringPolicy = .gatherContinually`.
3. Add an `RTCAudioTrack` with `audioTrackID = "openclaw-ios-audio"` to stream `"openclaw-ios-realtime"`.
4. Create data channel with label `"oai-events"`.
5. Create SDP offer with constraints `OfferToReceiveAudio: true`, `OfferToReceiveVideo: false`.
6. Set local description.
7. POST the local SDP to `session.offerUrl` (or default) with `Authorization: Bearer <clientSecret>`, `Content-Type: application/sdp`, and any extra `offerHeaders`. Expects 2xx response with SDP answer body.
8. Set remote description from answer.
9. Delegate calls `didChangeStatus("Listening")`.

### 9.5 Event handling

Server events arrive as JSON on the `"oai-events"` data channel. Audio state events are handled by `handleRealtimeAudioStateEvent`:

| Event | Action |
|---|---|
| `response.audio.delta` / `response.output_audio.delta` / `conversation.output_audio.delta` | `markAssistantAudioActive()` — suppresses input-speech events while speaking |
| `response.created` | `markAssistantAudioActive()` |
| `response.audio.done` / `response.output_audio.done` / `conversation.output_audio.done` / `response.done` | Schedule `assistantAudioFinished` after `1.8 s` grace (drain) |
| `input_audio_buffer.speech_started` | If not `assistantAudioActive`: `didDetectInputSpeech(true)`, status "Listening" |
| `input_audio_buffer.speech_stopped` / `input_audio_buffer.committed` | `didDetectInputSpeech(false)` |

The 1.8-second drain grace prevents the "Listening" status from flickering during output chunking.

On `error.isMaximumDurationError`: calls `stop()` immediately to trigger a single session rotation (provider's hard limit reached before transport state catches up).

### 9.6 Tool calls (openclaw_agent_consult / openclaw_agent_control)

Tool arguments are buffered across `response.function_call_arguments.delta` events keyed by item ID or call ID. On `done` events, if args are non-empty and no task is in flight for that callId:

- `openclaw_agent_consult` → `talk.client.toolCall` → wait for chat result via event stream + `agent.wait` polling (3 s slices, up to `toolResultTimeoutSeconds = 45 s`). After 6 s shows "Still asking OpenClaw". On failure: submits error result and falls back to spoken fallback message.
- `openclaw_agent_control` → `talk.client.steer` → submit result.

Tool results are submitted back to the WebRTC session as `conversation.item.create` with `type: "function_call_output"` followed by `response.create`.

### 9.7 Session key matching

`matchesSessionKey(_:_:)` treats `"agent:main:main"` and `"main"` as equivalent to handle gateway-side session key normalization.

### 9.8 Prefetch

`TalkModeManager.prefetchRealtimeSessionIfReady(reason:shouldApply:)` calls `talk.client.create` speculatively when Talk is not yet enabled but the gateway is connected, permission is `.ready`, and the route is `.realtimeWebRTC`. The returned `TalkRealtimeClientSession` is cached. On start, if the session has not expired (compared with a 30-second leeway before `expiresAt`), it is consumed and the create round-trip is skipped.

---

## 10. VoiceWakeManager

**File:** `Sources/Voice/VoiceWakeManager.swift`

`@MainActor @Observable final class VoiceWakeManager: NSObject`. Runs continuous always-on speech recognition to detect trigger words.

### 10.1 State

| Property | Initial | Notes |
|---|---|---|
| `isEnabled` | `false` | |
| `isListening` | `false` | |
| `statusText` | `"Off"` | |
| `triggerWords` | Loaded from `VoiceWakePreferences` | Kept in sync via `UserDefaults.didChangeNotification` |
| `lastTriggeredCommand` | `nil` | Last matched wake phrase |

### 10.2 Audio session configuration

```swift
session.setCategory(.playAndRecord, mode: .measurement, options: [
    .duckOthers, .mixWithOthers, .allowBluetoothHFP, .defaultToSpeaker
])
```

### 10.3 Microphone tap

Buffer size: `1024` frames. Audio buffers are **deep-copied** on the Core Audio realtime thread into an `AudioBufferQueue` (lock-based). A `tapDrainTask` runs every 40 ms on the Swift concurrency cooperative pool, drains the queue, and appends buffers to `SFSpeechAudioBufferRecognitionRequest`. This decouples the realtime audio thread from Swift concurrency.

Deep copy handles `floatChannelData`, `int16ChannelData`, and `int32ChannelData` formats.

### 10.4 Wake word matching

`VoiceWakeManager.extractCommand(from:segments:triggers:minPostTriggerGap:)` delegates to `WakeWordGate.match(transcript:segments:config:)?.command` from `SwabbleKit`. The default `minPostTriggerGap` is `0.45` seconds — ensures some post-trigger speech before the command is extracted.

Duplicate commands are suppressed: if `cmd == lastDispatched`, the trigger is ignored.

On match:
1. `lastDispatched = cmd`, `lastTriggeredCommand = cmd`, `statusText = "Triggered"`.
2. `await onCommand?(cmd)` — caller handles the wake action.
3. `scheduleStart()` — restart listening.

### 10.5 Suppression

Two suppression reasons: `.talk` and `.voiceNote`. Each owner sets/clears only its own reason. When suppressed, listening stops and `statusText = "Paused"`. When all reasons clear and `isEnabled`, listening restarts.

This prevents Talk ending from restarting Voice Wake over an active voice-note recording.

### 10.6 External audio capture suspension

`suspendForExternalAudioCapture()` stops the pipeline temporarily (e.g., for camera video recording). `resumeAfterExternalAudioCapture(wasSuspended:)` restarts after a `externalAudioResumeDelayNs = 350_000_000 ns` (350 ms) delay.

### 10.7 Simulator guard

The iOS Simulator's audio stack is explicitly unsupported. Start is blocked on simulator (`SIMULATOR_DEVICE_NAME` or `SIMULATOR_UDID` environment variables present).

### 10.8 Permission request timeout

Both microphone and speech recognition permission requests are wrapped in `AsyncTimeout.withTimeout(seconds: 8)`. If the system does not call back within 8 seconds, the request is treated as failed.

### 10.9 Error restart delay

On recognition error: `scheduleStart(after: recognitionErrorRestartDelayNs)` = `700_000_000 ns` (700 ms) default.

---

## 11. VoiceNoteRecorder

**File:** `apps/shared/OpenClawKit/Sources/OpenClawChatUI/VoiceNoteRecorder.swift`

### 11.1 State machine

`@MainActor @Observable public final class OpenClawVoiceNoteRecorder`

```swift
public enum State: Equatable {
    case idle
    case requestingPermission
    case recording(startedAt: Date, fileURL: URL)
    case finished(recording: OpenClawVoiceNoteRecording)
    case staging(recording: OpenClawVoiceNoteRecording)
    case failed(message: String)
}
```

`ownsPendingChatAttachment` is `true` for `.requestingPermission`, `.recording`, `.finished`, `.staging` — guards the chat composer from clearing a pending note.

### 11.2 Duration limit

`voiceNoteMaximumDurationSeconds = 180` (3 minutes). Enforced by the timer task. `openClawVoiceNoteDurationLabel(_:)` formats as `"M:SS"` bounded to the maximum.

### 11.3 Timer task

Wakes every `timerIntervalNanoseconds = 100_000_000 ns` (100 ms). Computes `elapsedSeconds = now - startedAt`. Auto-finishes when `elapsedSeconds >= durationLimit`.

### 11.4 Waveform metering

`liveLevels: [Float]` — rolling window of 40 samples (`liveBarCapacity = 40`). Updated every 100 ms from `capture.currentPower()` (average dB). Level normalization: `(dB + 50) / 50` — maps −50 dB…0 dB to 0…1. Readings below −50 dB are clamped to 0.

### 11.5 Audio capture settings (AAC)

`OpenClawVoiceNoteAudioCapture` uses `AVAudioRecorder` with:

| Setting | Value |
|---|---|
| Format | `kAudioFormatMPEG4AAC` |
| Sample rate | `24000` Hz |
| Channels | `1` (mono) |
| Bit rate | `32000` bps |
| Quality | `.medium` |
| File extension | `.m4a` |

Session: `.record` category, `.measurement` mode, `.allowBluetoothHFP` option. Session is activated on start and deactivated with `.notifyOthersOnDeactivation` on stop or cancel.

Metering: `recorder.isMeteringEnabled = true`. `averagePower(forChannel: 0)` is sampled each 100 ms tick.

### 11.6 Interruption handling

`audioRecorderEncodeErrorDidOccur` and `AVAudioSession.interruptionNotification` (`.began`) both route to `captureDidFail()` which calls the installed failure handler, causing the recorder to transition to `.failed("Recording was interrupted. Try again.")`.

### 11.7 Admission handler

`setCaptureAdmissionHandler(_:)` installs a synchronous gate checked before requesting permissions. If the gate returns `false`, the recorder fails immediately with `"Push-to-talk is using the microphone."`. The check and transition to `.requestingPermission` happen in a single MainActor turn — atomically from the UI perspective.

### 11.8 File lifecycle

Temporary files: `FileManager.default.temporaryDirectory/voice-note-<UUID>.m4a`. Deleted on `cancel()` and `captureFailed()`. After `finish()`, the file URL is in `OpenClawVoiceNoteRecording.fileURL` and the recorder state is `.finished`. The chat view model claims the recording via `claimCompletedRecording()` (transitions to `.staging`), then calls `completeStaging(_:)` to return to `.idle` once it has consumed the file. The recorder does not own the file after staging.

---

## 12. VoiceNoteTranscriber

**File:** `Sources/Design/VoiceNoteTranscriber.swift`

`enum VoiceNoteTranscriber` — pure static, audio never leaves the device.

### 12.1 Entry point

`static func transcribe(data: Data) async -> String?`

1. Request `SFSpeechRecognizer` authorization; return `nil` if denied.
2. Write `data` to a temp file: `vn-transcribe-<UUID>.m4a` in `FileManager.default.temporaryDirectory`. Delete on defer.
3. iOS 26+: try `transcribeModern(url:)`.
4. Fall back to `transcribeLegacy(url:)`.
5. Return `nil` if both fail or produce empty text — the note sends without a transcript.

### 12.2 iOS 26 modern path (SpeechAnalyzer)

`@available(iOS 26.0, *)`:

1. `SpeechTranscriber.supportedLocale(equivalentTo: Locale.current)` — returns `nil` if locale unsupported.
2. `SpeechTranscriber(locale:transcriptionOptions:[]:reportingOptions:[]:attributeOptions:[])`.
3. `AssetInventory.assetInstallationRequest(supporting: [transcriber])` — downloads/installs the on-device model for the locale if not present.
4. `AVAudioFile(forReading: url)` → `SpeechAnalyzer(modules: [transcriber])`.
5. Results collected via `AsyncSequence` on `transcriber.results`: `text += String(result.text.characters)`.
6. `analyzer.analyzeSequence(from: audioFile)` — if the sequence has a last item, `finalizeAndFinish(through: last)`, otherwise `cancelAndFinishNow()`.
7. Text is trimmed; empty trimmed text returns `nil`.

### 12.3 Legacy path (SFSpeechRecognizer)

1. `SFSpeechRecognizer()` — defaults to device locale.
2. Requires `recognizer.isAvailable && recognizer.supportsOnDeviceRecognition`.
3. `SFSpeechURLRecognitionRequest(url:)` with `requiresOnDeviceRecognition = true`, `shouldReportPartialResults = false`.
4. Wrapped in `TranscriptionResumeBox` — a lock-based once-resume wrapper — to safely call `continuation.resume` from the recognition task callback which may fire on an arbitrary queue and may fire more than once.
5. Returns `result.bestTranscription.formattedString` when `result.isFinal`.

---

## 13. Voice note → chat attachment flow

1. User presses the voice-note button in `ChatRootSurface` composer.
2. `OpenClawVoiceNoteRecorder.start()` is called — checks the admission handler (blocks if PTT is active), requests mic permission, starts `AVAudioRecorder`, starts the timer and metering tasks.
3. While recording, `liveLevels` fills with normalized amplitude values; the composer renders a waveform bar chart from these values.
4. User releases the button (or the 3-minute limit fires) → `finish()` → `.finished(recording:)`.
5. The chat view model calls `claimCompletedRecording()` → `.staging(recording:)`.
6. `VoiceNoteTranscriber.transcribe(data:)` is called on the recording data (async, on-device).
7. Transcribed text (or `nil` if unavailable) is attached to the outgoing message alongside the audio file reference.
8. `completeStaging(_:)` → `.idle`.

Voice Wake is suppressed via `VoiceWakeManager.setSuppressedByVoiceNote(true)` while a recording is active, and released when the recorder returns to `.idle` or `.failed`.

---

## 14. Permission flow summary

| Permission | How requested | How used |
|---|---|---|
| Microphone (`AVAudioApplication.requestRecordPermission`) | On first `start()` or PTT begin | Talk mode continuous capture, PTT, relay session mic pump |
| Speech recognition (`SFSpeechRecognizer.requestAuthorization`) | After mic grant, before recognition start | iOS fallback ASR pipeline, Push-to-talk ASR, Voice Wake word detection, voice note transcription |
| Gateway Talk scope | Gateway RPC + `TalkPermissionPromptView` | Required before any realtime or native gateway-backed Talk session starts |

All three must be `.authorized` / `.ready` for a full Talk session. If the realtime path fails, Talk falls back to the iOS speech recognition + TTS pipeline without re-requesting permissions.
