# Onboarding Flow

The onboarding wizard is the mandatory gateway-connection flow that is presented at first launch when no saved gateway exists. It guides the user from a branded welcome screen through QR-code or manual setup, a multi-state feedback/connection screen, and a success screen; the entire flow is built as a `NavigationStack` with each logical step rendered as a full-screen SwiftUI view, using a private step enum to drive transitions.

---

## 1. Architecture Overview

### 1.1 Container: `OnboardingWizardView`

`OnboardingWizardView` (`Sources/Onboarding/OnboardingWizardView.swift`) is the single root view. It is initialized with:

| Parameter | Type | Meaning |
|---|---|---|
| `allowSkip` | `Bool` | When `true`, a Close button is shown; when `false` (first-run), the user cannot dismiss without connecting. |
| `autoOpenScanner` | `Bool` | When `true`, the QR scanner sheet opens automatically 300 ms after the view appears (one-shot). |
| `onRequestLocalNetworkAccess` | `(String) -> Void` | Called with a reason string to trigger the local-network permission prompt. |
| `onClose` | `() -> Void` | Invoked when the user taps Close on a skippable presentation. |
| `onComplete` | `() -> Void` | Invoked once the success step auto-advances. |

The initializer always sets the initial step to `.welcome` (`_step = State(initialValue: .welcome)`). The `.intro` case exists in the enum but is no longer the entry point; it can be navigated to indirectly but the flow comment confirms "gateway connection is mandatory, so there is no separate first-run intro."

### 1.2 Step Enum

```swift
private enum OnboardingStep: Int, CaseIterable {
    case intro      // rawValue 0 — legacy/unused entry point
    case welcome    // rawValue 1 — initial step; QR + manual
    case mode       // rawValue 2 — manual setup code / mode picker
    case feedback   // rawValue 3 — connection progress / auth / pairing / error
    case success    // rawValue 4 — post-connection confirmation
}
```

Navigation title is `""` for all full-screen steps (`.intro`, `.welcome`, `.mode`, `.feedback`, `.success`); the `.navigationBarTitleDisplayMode(.inline)` is always set. The `canGoBack` predicate returns `false` for all current active steps (`.intro`, `.welcome`, `.success`, `.mode`, `.feedback`), meaning the back-button is never shown during the normal flow.

### 1.3 Layout Shell

The whole wizard is wrapped in a `NavigationStack`. Over the top of it:

- **Leading chrome button** (`.overlay(alignment: .topLeading)`): Back chevron if `step.canGoBack`; Close button if `allowSkip`; nothing otherwise. Positioned `.padding(.leading, 16)`, `.padding(.top, 10)`. Both use `OpenClawCloseButtonStyle`.
- **Keyboard dismiss control** (`.safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0)`): A capsule pill button showing `keyboard.chevron.compact.down` SF Symbol at `OpenClawType.headline` weight. Visible only while a text field is focused (`focusedField != nil`). Fill: `.ultraThinMaterial`. Stroke: `OpenClawBrand.activationNeutralStroke` at `lineWidth: 0.6`. Shadow: `Color.black.opacity(0.08)`, radius 14, y-offset 4. Padding trailing 20, bottom 10. Transition: `.opacity.combined(with: .scale(scale: 0.96))`. Animation: `.smooth(duration: 0.16)`. Foreground: `OpenClawBrand.activationPrimaryAction`.
- **TLS trust prompt alert**: Hosted on a `Color.clear` background layer (`.background { Color.clear.gatewayTrustPromptAlert() }`). This is separated from the scanner-error alert so they do not shadow each other.
- **Scanner error alert**: Title "QR Scanner Unavailable", OK button (`OpenClawType.subheadSemiBold`), message body (`OpenClawType.subhead`).
- **QR scanner sheet**: `.sheet(isPresented: $showQRScanner)` — see Section 4.
- **Gateway problem details sheet**: `.sheet(isPresented: $showGatewayProblemDetails)` showing `GatewayProblemDetailsSheet`.

### 1.4 Persistent Timer

`pairingAutoResumeTicker` is a class-level `Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()`. While on the `.feedback` step with a pairing issue and no active connection, this fires `attemptAutomaticPairingResumeIfNeeded()` every 2 seconds. Minimum inter-attempt interval is 6 seconds (`now.timeIntervalSince(last) < 6`).

---

## 2. Step-by-Step Specification

### 2.1 Welcome Step (`OnboardingWelcomeStep`)

**File:** `Sources/Onboarding/OnboardingWizardSteps.swift:283`

**Purpose:** Full-screen branded entry point. User scans a QR code or proceeds to manual setup.

#### 2.1.1 Background

The background is `OpenClawBrand.welcomeCanvas` applied via `.ignoresSafeArea()`. In dark mode only, a `ZStack` overlays two images at full bleed (`scaledToFill`):

1. `Image("OnboardingDustCloud")` — resizable, `scaledToFill`
2. `Image("OnboardingStars")` — resizable, `scaledToFill`

Both are accessibility-hidden. This overlay is absent in light mode; the comment explains: "Full-screen background paint kept out of the layout so the footer anchors identically in light and dark mode, regardless of the dark-only starfield art."

#### 2.1.2 Center Content

A `ZStack` fills the screen (`maxWidth: .infinity, maxHeight: .infinity`). Inside, a `VStack(spacing: 21)` is horizontally padded 24 pt and has `.padding(.bottom, 120)`. It is constrained to `maxWidth: OnboardingVisual.maxWidth` (430 pt).

The comment for the 120 pt bottom padding reads: "Bottom padding lifts the centered block above true center so it reads as balanced against the bottom footer link."

| Element | Spec |
|---|---|
| Mascot image | `Image("openclaw mascot")`, resizable, `scaledToFit`, 146×146 pt, accessibility-hidden. Shadow: `OpenClawBrand.welcomeGlow`, radius 10, x 0, y 0. |
| Tagline text | `"Run "openclaw qr" in your terminal."` (uses proper Unicode curly quotes U+201C / U+201D). Font: `.system(size: 30, weight: .semibold)`. Foreground: `Color.primary.opacity(0.9)`. Alignment: `.center`. Fixed width: 266 pt. |
| Button stack | `VStack(spacing: 13)` containing the two buttons below. |

**Scan QR Code button** (`OnboardingWelcomePillButtonStyle`):

- Fill: `OpenClawBrand.welcomePrimaryAction`. Foreground: `.white`.
- Height: 50 pt, `maxWidth: .infinity`. Shape: `Capsule(style: .continuous)`.
- Idle label: `Image("QRCodeGlyph")` (template, resizable, 24×24 pt) + `Text("Scan QR Code")` at `.system(size: 17)` in `HStack(spacing: 7)`.
- While `isConnecting`: `ProgressView` (circular, `.tint(.white)`) + `Text("Connecting…")` at `.system(size: 17)`.
- Disabled while `isConnecting`.

**Set Up Manually button** (`OnboardingWelcomePillButtonStyle`):

- Fill: `OpenClawBrand.welcomeSecondaryAction`. Foreground: `OpenClawBrand.welcomeSecondaryActionText`.
- Same height/shape as primary button.
- Label: `Text("Set Up Manually")` at `.system(size: 17)`.
- Disabled while `isConnecting`.

**Button style press animation:** `.opacity(0.85)` + `.scaleEffect(0.98)` when pressed. Animation: `.smooth(duration: 0.14)`.

#### 2.1.3 Footer

Anchored `.overlay(alignment: .bottom)` with `.padding(.bottom, 24)`:

- `AttributedString`: "If you don't understand what this means, please go **here** to install OpenClaw."
- "here" is a link to `https://openclaw.ai/` with `OpenClawBrand.welcomeLink` foreground color and `.single` underline.
- Font: `.system(size: 14)`. Foreground: `Color.primary.opacity(0.7)`. Alignment: `.center`. Fixed width: 289 pt.

---

### 2.2 Gateway Setup Step (`OnboardingSetupStep`)

**File:** `Sources/Onboarding/OnboardingWizardSteps.swift:535`

Reached by tapping "Set Up Manually." Full-screen view with `OpenClawBrand.welcomeCanvas` background.

#### 2.2.1 Header

A `ZStack` containing:

- Centered `VStack(spacing: 20)`:
  - Title: `"Manual Set Up"`, `.system(size: 20, weight: .medium)`, `Color.primary`.
  - Progress indicator: `HStack(spacing: 4)` of 4 capsule pills, each 32×3 pt. Active pills (`index < activeSegments`) fill with `progressActive`; inactive fill with `progressInactive`.
    - Dark `progressActive`: `Color(red: 163/255, green: 163/255, blue: 163/255)`.
    - Light `progressActive`: `Color(red: 82/255, green: 82/255, blue: 82/255)`.
    - Dark `progressInactive`: `Color(red: 38/255, green: 38/255, blue: 38/255)`.
    - Light `progressInactive`: `.white`.
  - `activeSegments` = 1 while fields are not revealed; 2 once endpoint fields appear.
- Leading back button: `Image(systemName: "chevron.left")`, `.system(size: 17, weight: .semibold)`, `OpenClawBrand.welcomePrimaryAction`, 40×40 pt circle background (dark: `Color(red: 30/255, green: 30/255, blue: 30/255).opacity(0.2)`; light: `Color.white.opacity(0.2)`).

#### 2.2.2 Setup Field Layout

`VStack(alignment: .leading, spacing: 14)` with `.padding(.top, 60)` and `.padding(.horizontal, 24)`.

Each field is a capsule with `height: 50`, `leading: 21`, `trailing: 16` padding:

- Fill (dark): `Color(red: 23/255, green: 23/255, blue: 23/255)`. Fill (light): `.white`.
- Border (dark): `.clear`. Border (light): `Color.black.opacity(0.2)`, `lineWidth: 0.5`.
- Error border: `Color(red: 211/255, green: 21/255, blue: 21/255)` (`#D31515`), `lineWidth: 0.5`.
- Shape: `Capsule(style: .continuous)` for both fill and border.

**Validation lifecycle:**

| State | `CodeValidation` case | Trailing icon | Border |
|---|---|---|---|
| Empty | `.idle` | None | Neutral |
| Text entered, debouncing (800 ms) | `.scanning` | `SetupScanningSpinner` | Neutral |
| Valid, no endpoint extracted | `.validated(revealsEndpoint: false)` | `SetupCheckIcon` | Neutral |
| Valid + endpoint extracted | `.validated(revealsEndpoint: true)` | `SetupCheckIcon` | Neutral |
| Invalid | `.invalid` | `SetupErrorIcon` (tappable, clears field) | Error red |

Debounce duration: `scanDuration = .milliseconds(800)`. Reveal delay after validation: `revealDelay = .milliseconds(100)`. Apply spinner duration: `applyDuration = .milliseconds(800)`.

**Shake animation** (on invalid): `KeyframeTrack` — `CubicKeyframe(6, duration: 0.08)`, `CubicKeyframe(-6, duration: 0.06)`, `CubicKeyframe(4, duration: 0.08)`, `CubicKeyframe(0, duration: 0.06)`. Triggered by incrementing `shakeCount`. Suppressed when `accessibilityReduceMotion` is true.

**Endpoint field reveal** (when `fieldsRevealed`):
- Host field and Port field appear with `.transition(.opacity.combined(with: .move(edge: .top)))`.
- Reveal animation: `.spring(duration: 0.35)`.

**Haptics:**
- Valid code → `OpenClawHaptics.play(.secured2)`.
- Invalid code → `OpenClawHaptics.play(.secured4)`.

**Icons:**

| View | Asset | Size |
|---|---|---|
| `SetupScanningSpinner` | `Image("SetupSpinnerGlyph")`, template | 24×24 pt, rotates 360° with `.linear(duration: 0.9).repeatForever(autoreverses: false)` |
| `SetupCheckIcon` | `Image("SetupCheckGlyph")` (light) or `Image("SetupCheckDarkGlyph")` (dark) | 24×24 pt |
| `SetupErrorIcon` | `Image("SetupErrorGlyph")` (light) or `Image("SetupErrorDarkGlyph")` (dark) | 21×21 pt |

**Apply code button:**

- Style: `OnboardingWelcomePillButtonStyle`.
- Enabled fill: `OpenClawBrand.welcomePrimaryAction.opacity(1.0)`, foreground `Color.primary`.
- Disabled fill: `OpenClawBrand.welcomePrimaryAction.opacity(0.6)`, foreground `Color.primary.opacity(0.6)`.
- Label: `Text("Apply code")`, `.system(size: 17, weight: .medium)`. While applying: `SetupScanningSpinner`.

**Helper text** (`.padding(.leading, 21)`, `.font(.system(size: 12))`, `.opacity(0.8)`):

- `.idle`: "If you don't have a set up code, run "openclaw qr" into your terminal." (`"openclaw qr"` in blue `Color(red: 0, green: 122/255, blue: 255/255)`).
- `.validated(revealsEndpoint: true)`: Tailscale instructions with `"tailscale up"` and `"tailscale serve"` in `Color(red: 0, green: 98/255, blue: 204/255)`.
- `.invalid`: "Seems like your setup code is not correct." in `#D31515`.
- Scanning: no helper text shown.

---

### 2.3 Feedback Step (`OnboardingFeedbackStep`) — State Machine

**File:** `Sources/Onboarding/OnboardingWizardSteps.swift:904`

This single view hosts all connection-progress states. It transitions between them using the `OnboardingFeedbackContent` enum, which is driven by the parent's `desiredFeedbackContent` computed property.

#### 2.3.1 State Enum

```swift
enum OnboardingFeedbackContent: Equatable {
    case loading
    case passwordRequired(rejected: Bool)
    case awaitingApproval(requestId: String?)
    case installTailscale
    case error
}
```

Internal case-ID for haptic deduplication:

| Case | ID |
|---|---|
| `.loading` | 0 |
| `.passwordRequired` | 1 |
| `.awaitingApproval` | 2 |
| `.installTailscale` | 3 |
| `.error` | 4 |

#### 2.3.2 State Machine Transitions

The parent (`OnboardingWizardView`) computes `desiredFeedbackContent` and then calls `setFeedbackContent(_:)` which enforces a minimum 2-second dwell before committing the transition (`.smooth(duration: 0.3)` animation). This prevents flash-through when a response arrives quickly.

**Transition logic (source: `desiredFeedbackContent`):**

```
if issue.needsPairing                → .awaitingApproval(requestId:)
if issue.needsAuthToken              → .passwordRequired(rejected: credentialSubmitted)
if issue == .network && tailnetHost  → .installTailscale
if issue == .network || .unknown     → .error
default (no issue):
  if loadingDidFail                  → .error
  else                               → .loading
```

**Stall timeout:** If the step stays `.loading` for 120 seconds with no resolution, `loadingDidFail` is set to `true` and the state transitions to `.error`.

**On `appModel.gatewayServerName` becoming non-nil (connected):**
- If currently on `.feedback` step: waits `max(0, 2.0 - elapsedSinceFeedbackShown)` seconds, then navigates to `.success`.
- Otherwise: navigates to `.success` immediately.

**Issue stickiness rules (source: `updateConnectionIssue`):**
- Once in `.pairingRequired`, the issue remains pairing until the user explicitly retries or connects.
- Once in an auth-required issue, it remains until retry or successful connection.
- This prevents UI flip-flop during reconnect churn.

#### 2.3.3 Background

`OpenClawBrand.welcomeCanvas` with `.ignoresSafeArea()`.

#### 2.3.4 Shared Chrome (present on all non-loading states)

**Back pill** (top-leading, `.padding(.horizontal, 24)`, `.padding(.top, 8)`):
- `Image(systemName: "chevron.left")`, `.system(size: 17, weight: .semibold)`, `OpenClawBrand.welcomePrimaryAction`.
- 40×40 pt circle. Background (dark): `Color(red: 30/255, green: 30/255, blue: 30/255).opacity(0.2)`. Background (light): `Color.white.opacity(0.2)`.
- Hidden on `.loading` (`showsBackPill` returns `false` for `.loading`).

**Progress bar** (`.padding(.top, 56)`):
- 4 capsule pills, 32×3 pt each, `HStack(spacing: 4)`, `maxWidth: .infinity`.
- Active pills (dark): `Color(red: 163/255, green: 163/255, blue: 163/255)`.
- Active pills (light): `Color(red: 82/255, green: 82/255, blue: 82/255)`.
- Inactive pills (dark): `Color(red: 38/255, green: 38/255, blue: 38/255)`.
- Inactive pills (light): `.white`.
- Shown only for `.installTailscale` (3 active) and `.awaitingApproval` (4 active). Hidden for all other states.

**Bottom button** (`.overlay(alignment: .bottom)`, `.padding(.horizontal, 24)`, `.padding(.bottom, 20)`, `maxWidth: OnboardingVisual.maxWidth`):
- Style: `OnboardingWelcomePillButtonStyle`. Fill (dark): `Color(red: 23/255, green: 23/255, blue: 23/255)`. Fill (light): `.white`. Foreground: `Color.primary`.
- Label: `.system(size: 17, weight: .medium)`.

All state views use `.transition(.opacity)` for content transitions.

#### 2.3.5 State: `.loading`

`VStack(spacing: 31)` centered vertically with `.offset(y: -52)`:

- `FeedbackLoaderSpinner`: `Image("FeedbackLoaderGlyph")`, 70×70 pt, rotates 360° with `.linear(duration: 1.2).repeatForever(autoreverses: false)`.
- Title: `"Scanning your code"`, `.system(size: 30, weight: .medium)`, `Color.primary`, `lineLimit(1)`, `fixedSize(horizontal: true, vertical: false)`.
- Status line (if non-empty after trim): `.system(size: 15)`, `.secondary`, centered, `maxWidth: 300 pt`.

No back pill. No bottom button. No progress bar.

#### 2.3.6 State: `.passwordRequired(rejected:)`

`VStack(spacing: 32)` centered with `.offset(y: -20)`, horizontal padding 24, `maxWidth: OnboardingVisual.maxWidth`:

- Title: `"Your Gateway requires authentication to continue."`, width 347 pt.
- `VStack(spacing: 14)`:
  - Credential field (see below).
  - Continue button: `OnboardingWelcomePillButtonStyle`. Enabled when field is non-empty (after trim). Fill opacity 1.0 when enabled, 0.6 when empty. Label: `"Continue"`, `.system(size: 17, weight: .medium)`.

**Credential field layout:**

- `HStack(spacing: 11)`: `SecureField` + trailing `SetupErrorIcon` (when rejected and not locally dismissed).
- Padding: leading 21, trailing 16. Height: 50. `maxWidth: .infinity`.
- Fill (dark): `Color(red: 23/255, green: 23/255, blue: 23/255)`. Fill (light): `.white`.
- Normal border (dark): `.clear`, `lineWidth: 0.5`. Normal border (light): `Color.black.opacity(0.2)`, `lineWidth: 0.5`.
- Error border: `#D31515`, `lineWidth: 1`.
- Placeholder: `"Gateway auth token or password..."`.

**Rejection behavior:**
- On entering `rejected: true` state: `credentialShakeCount` incremented (triggers same keyframe shake animation as setup step), `credentialErrorDismissed = false`.
- Haptic: `OpenClawHaptics.play(.secured4)`.
- Error styling clears locally the instant the user edits the field (via `credentialErrorDismissed` flag) without waiting for the next connect.

**SecureField write guard:** The field only accepts writes while focused (`credentialFieldFocused`). This prevents the iOS SwiftUI SecureField from wiping the stored credential when it mounts/unmounts during the loading transition.

The single credential binding routes the value to the token or password slot depending on what `gatewayAuthMethod` reports. If the gateway later changes auth method (e.g., from token to password), the credential migrates to the correct slot automatically, and the attempt is re-submitted once (guarded by `autoRetriedAfterMethodFlip`).

#### 2.3.7 State: `.awaitingApproval(requestId:)`

`VStack(spacing: 0)` with inner `VStack(spacing: 31)` at `.offset(y: -40)`:

- State glyph: `Image("FeedbackInfoGlyph")`, 70×70 pt.
- `VStack(spacing: 21)`:
  - Title: `"Follow the instructions below to continue."`, width 317 pt.
  - `VStack(spacing: 14)`, `.font(.system(size: 16))`:
    - Step 1 row: `HStack(spacing: 4)` — `"1. Copy your ID:"` (opacity 0.6) + inline copy button.
    - Copy button uses a ZStack of two labels — `""Click here to copy""` and `""Copied!""` — only one visible at a time (via `.opacity`). The wider label fixes the layout width so the row never reflows. Color: `Color(red: 37/255, green: 99/255, blue: 235/255)` (link blue). No animation on swap.
    - Step 2 row: `"2. Run "` (opacity 0.6) + `""openclaw devices approve <your ID>""` in link blue.
  - `FeedbackCopyChip`: Copies the full `"openclaw devices approve <requestId>"` command.
- Bottom button: `"Retry"` → `onRetry`.
- Progress bar: 4 of 4 active.

**`FeedbackCopyChip` details:**
- `HStack(spacing: 3)`: Icon ZStack (16×16 pt) + Text.
- Icons cross-fade with scale (1→0.25) + blur (0→4 pt) on swap. Animation: `.smooth(duration: 0.3)`.
- Text cross-fades with `.contentTransition(.opacity)`.
- Chip padding: horizontal 7, vertical 5. Background: `RoundedRectangle(cornerRadius: 5, style: .continuous)`.
- Background (dark): `.white`. Foreground (dark): `.black`. Background (light): `Color(red: 16/255, green: 16/255, blue: 16/255)`. Foreground (light): `.white`.
- Copied state resets after 2 seconds.
- Copy icon: `Image("FeedbackCopyGlyph")` (template). Copied icon: SF Symbol `"checkmark"` (semibold weight).

**ID copy flash (step 1 button):** `idCopied` set to `true` instantly (no animation), reset after 2 seconds.

#### 2.3.8 State: `.installTailscale`

`VStack(spacing: 31)` centered, `.offset(y: -52)`:

- State glyph: `Image("FeedbackTailscaleGlyph")`, 70×70 pt.
- `VStack(spacing: 6)`:
  - Title: `"Almost there!"`, width 290 pt.
  - Body: `"Please install Tailscale on your iPhone and login your account."` — "Tailscale" is an underlined link to `https://apps.apple.com/app/tailscale/id1470499037`. Font: `.system(size: 16)`. Foreground: `Color.primary.opacity(0.6)`. Tint: `Color(red: 37/255, green: 99/255, blue: 235/255)`. Width: 290 pt.
- Bottom button: `"Continue"` → `onRetry`.
- Progress bar: 3 of 4 active.

**Tailscale link construction:** Built as an `AttributedString` from Markdown. The Tailscale run is found and `.underlineStyle = .single` applied programmatically. Falls back to a plain string if `AttributedString(markdown:)` fails.

**Auto-retry on scene foreground:** When the scene becomes `.active` while on `installTailscale` state, `retryLastAttempt(silent: true)` fires automatically.

#### 2.3.9 State: `.error`

`VStack(spacing: 16)` centered, `.offset(y: -40)`:

- State glyph: `Image("FeedbackErrorGlyph")`, 70×70 pt.
- Title: `"Oops! Something went wrong somewhere."`, width 314 pt.
- Bottom button: `"Try Again"` → `onRetry`.

On explicit retry (`onRetry`), `issue` is reset to `.none` and `pairingRequestId` is cleared before the new attempt, so the next classify pass starts clean.

#### 2.3.10 Haptic Wiring

| Event | Haptic |
|---|---|
| Transition to any resolved state (from `.loading`) | `OpenClawHaptics.play(.secured2)` |
| Transition to `.passwordRequired(rejected: true)` | `OpenClawHaptics.play(.secured4)` (the above is suppressed for this case) |
| Valid setup code in `OnboardingSetupStep` | `OpenClawHaptics.play(.secured2)` |
| Invalid setup code in `OnboardingSetupStep` | `OpenClawHaptics.play(.secured4)` |

---

### 2.4 Success Step (`OnboardingSuccessStepView`)

**File:** `Sources/Onboarding/OnboardingWizardSteps.swift:1397`

Full-screen `ZStack` with `OpenClawBrand.welcomeCanvas` background (`.ignoresSafeArea()`).

Content `VStack(spacing: 0)` at `.offset(y: -52)`:

- Inner `VStack(spacing: 31)`:
  - `Image("FeedbackSuccessGlyph")`, resizable, `scaledToFit`, 70×70 pt.
  - Title: `"Connection secured."`, `.system(size: 30, weight: .medium)`, `Color.primary`, `.center` alignment, width 317 pt.
- Subtitle: `"Logging you in..."`, `.system(size: 16)`, `Color.primary.opacity(0.6)`, `.padding(.top, 27)`.

**Auto-advance:** A `.task` modifier sleeps for 1.5 seconds then calls `onFinished()` which propagates to `onComplete`.

No user interaction is possible on this step. It is a terminal step.

---

### 2.5 Intro Step (`OnboardingIntroStep`)

**File:** `Sources/Onboarding/OnboardingWizardSteps.swift:238`

Currently unused as the entry point (the wizard always opens on `.welcome`), but still compiled and navigable. Uses `OnboardingActivationCanvas`.

#### Canvas container (`OnboardingActivationCanvas`):

- `GeometryReader` wrapping `ScrollView` (hidden indicators).
- Content constrained to `maxWidth: OnboardingVisual.maxWidth` (430 pt), centered.
- `minHeight: max(0, proxy.size.height - 94)`, aligned `.top`.
- Padding: horizontal 20, top 54, bottom 40.
- Background: `OpenClawBrand.activationCanvasGradient.ignoresSafeArea()`.

Content `VStack(alignment: .leading, spacing: 0)`:

1. **`OnboardingHeroHeader`** (`.padding(.top, 18)`):
   - `VStack(spacing: 18)`: `OnboardingHeroGlyph` + text block.
   - `OnboardingHeroGlyph`: `OpenClawActivationGlyph(size: 78)`.
   - Text block `VStack(spacing: 8)`: title `OpenClawType.title1`, subtitle `OpenClawType.body` `.secondary` `.center`.
   - Title: `"OpenClaw"`. Subtitle: `"Securely connect this iPhone to your gateway."`.

2. **`OnboardingIntroPanel`** (`.padding(.top, 44)`): Three `OnboardingSafetyRow` items `VStack(spacing: 14)`:
   - `"link"` → `"Connect to your gateway"`.
   - `"hand.raised"` → `"Choose device permissions"`.
   - `"message.fill"` → `"Use OpenClaw from your phone"`.

3. **`OnboardingSecurityNotice`** (`.padding(.top, 18)`): Warning triangle + security notice text.

4. **`Spacer(minLength: 40)`**

5. **Continue button**: `OnboardingPrimaryButtonStyle` (= `OpenClawPrimaryActionButtonStyle`), `Text("Continue")`, `OpenClawType.subheadSemiBold`.

**Panel styles (`OnboardingIntroPanelStyle`):**

| Constant | Value |
|---|---|
| `iconSize` | 34 pt |
| `contentSpacing` | 12 pt |
| `panelPadding` | 16 pt |
| `panelCornerRadius` | 22 pt |
| `panelFill` | `OpenClawBrand.activationNeutralSurface` |
| `iconFill` | `OpenClawBrand.activationNeutralInsetSurface` |
| `stroke` | `OpenClawBrand.activationNeutralStroke` |

Panel overlay (top, inside): `Color.white.opacity(0.42)`, `lineWidth: 0.5`, `.blendMode(.plusLighter)`. Panel overlay (full, outside): `stroke` color, `lineWidth: 0.5`.

**`OnboardingIntroIcon`:** SF Symbol in circle (34×34 pt). Background: `Circle().fill(iconFill)`. Stroke: `Circle().stroke(stroke, lineWidth: 0.6)`. Icon font: `OpenClawType.subheadSemiBold`. Icon tint for safety rows: `OpenClawBrand.activationPrimaryAction`.

**`OnboardingSecurityNotice`:** `OnboardingIntroPanel` with warning icon (`exclamationmark.triangle.fill`, tint `OpenClawBrand.warn`) + `VStack(alignment: .leading, spacing: 6)` — title `"Security notice"` (`OpenClawType.subheadSemiBold`) + concatenated body text describing capabilities (`OpenClawType.footnote`, `.secondary`).

---

## 3. QR Scanner Sheet

**File:** `Sources/Onboarding/QRScannerView.swift:111`

Presented as a modal sheet over the wizard. Uses VisionKit `DataScannerViewController`.

### 3.1 Sheet Structure

`NavigationStack` with `QRScannerView` filling the full screen (`.ignoresSafeArea()`). Toolbar:

| Placement | Element |
|---|---|
| `.principal` | `Text("Scan Setup Code")`, `OpenClawType.headline` |
| `.topBarLeading` | Cancel button (`Text("Cancel")`, `OpenClawType.subheadSemiBold`) — cancels scan and dismisses |
| `.topBarTrailing` | `PhotosPicker` with `Label("Photos", systemImage: "photo")`, `OpenClawType.subheadSemiBold`, matching `.images` |

### 3.2 `QRScannerView` Implementation

A `UIViewControllerRepresentable` wrapping `QRScannerContainerViewController`:

- `DataScannerViewController` is created with `recognizedDataTypes: [.barcode(symbologies: [.qr])]` and `isHighlightingEnabled: true`.
- Camera session starts in `viewDidAppear` (after UIKit presentation completes) to avoid race with sheet teardown.
- Camera session stops in `viewWillDisappear` and on `dismantleUIViewController`.

**Pre-condition checks:**
- `DataScannerViewController.isSupported` → error if false: `"QR scanning is not supported on this device."`
- `DataScannerViewController.isAvailable` → error if false: `"Camera scanning is currently unavailable."`
- `dataScanner(_:becameUnavailableWithError:)` → error: `"Camera is not available on this device."`

**Result delivery:**

1. `dataScanner(_:didAdd:allItems:)` fires when barcodes appear. For each barcode, the payload is tested against `GatewayConnectDeepLink.fromSetupInput(_:)` first; if that fails, against `AppleReviewDemoMode.isSetupCode(_:)`.
2. On match, scanning stops immediately via `scanner.stopScanning()`, and `onResult` is called on `MainActor`.
3. `handled = true` prevents duplicate delivery.

### 3.3 Result Handoff (`QRScannerResultHandoff`)

Manages the asynchronous gap between VisionKit teardown and SwiftUI sheet dismissal:

- `beginScan()` increments `activeScanID` and returns it as a token.
- `queue(_:scanID:)` stores the result only if the `scanID` matches the current active scan and no result is pending ("Camera and Photos can finish together; the first valid result owns this scan").
- On sheet `onDismiss`, `processAfterDismissal(_:)` is called. It delays delivery by `defaultSettlingNanoseconds = 1_200_000_000` (1.2 seconds). The comment explains: "SwiftUI's onDismiss can precede VisionKit's AV capture teardown. Delay pairing UI briefly so it cannot race the scanner's camera shutdown."
- `cancel()` increments `activeScanID` (invalidating any in-flight scan) and cancels the delivery task.

### 3.4 Photo Library Fallback

The `PhotosPicker` allows selecting a photo to scan. On selection:

1. Data is loaded via `loadTransferable(type: Data.self)`.
2. `CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])` extracts the QR payload.
3. The payload is tested against `GatewayConnectDeepLink.fromSetupInput(_:)`, then `AppleReviewDemoMode.isSetupCode(_:)`.
4. On failure: scanner dismisses and `scannerError` is set to `"No valid QR code found in the selected image."`.

### 3.5 Auto-open Scanner

When `autoOpenScanner == true` (used for "Switch to full access" re-entry), the scanner opens automatically on first appear with a 300 ms delay (`try? await Task.sleep(for: .milliseconds(300))`). `didAutoOpenScanner` is set to prevent re-opening on subsequent appears.

---

## 4. State Persistence (`OnboardingStateStore`)

**File:** `Sources/Onboarding/OnboardingStateStore.swift`

All state persisted to `UserDefaults.standard`:

| Key | Type | Purpose |
|---|---|---|
| `"onboarding.completed"` | `Bool` | Set `true` on success; prevents re-presentation. |
| `"onboarding.first_run_intro_seen"` | `Bool` | Tracks whether the intro screen has been shown. |
| `"onboarding.last_mode"` | `String` | Raw value of `OnboardingConnectionMode`; restored on next open. |
| `"onboarding.last_success_time"` | `Int` | Unix timestamp of last successful connection. |

**Launch gate (`shouldPresentOnLaunch`):** Returns `true` only when `onboarding.completed` is `false` AND no active gateway entry exists in `GatewaySettingsStore` AND `appModel.gatewayServerName == nil`.

**Connection modes (`OnboardingConnectionMode`):**

| Case | Raw value | Defaults |
|---|---|---|
| `.homeNetwork` | `"home_network"` | Host: `"openclaw.local"`, port 18789, TLS on |
| `.remoteDomain` | `"remote_domain"` | Host: `""` (user-provided), port 18789, TLS on |
| `.developerLocal` | `"developer_local"` | Host: `"localhost"`, port 18789, TLS off |

Developer Local mode is hidden unless `@AppStorage("onboarding.developerMode")` is `true`.

**`markCompleted(mode:)`:** Persists `true` to `onboarding.completed`, stores the mode raw value, and stores `Int(Date().timeIntervalSince1970)` to `onboarding.last_success_time`.

---

## 5. Haptics Lab (`HapticsLabView`)

**File:** `Sources/Onboarding/HapticsLabView.swift`

A development-only audition tool (the file header reads: "TEMPORARY — haptic pattern audition lab. Delete before PR. Do not commit."). It should not be present in release builds.

**Layout:**

- `ZStack` with `OpenClawBrand.welcomeCanvas` background.
- `ScrollView` with `VStack(spacing: 13)`, horizontal padding 24, top padding 24.
- Header: `"Haptics Lab"`, `.system(size: 20, weight: .medium)`, `.padding(.bottom, 8)`.

Each candidate renders as a button:

- `HStack`: Name (`.system(size: 17, weight: .medium)`) + `Spacer` + note (`.system(size: 12)`, `.opacity(0.5)`).
- Padding: horizontal 21. Height: 50. `maxWidth: .infinity`.
- Background: `Capsule(style: .continuous).fill(Color.primary.opacity(0.06))`.
- Foreground: `Color.primary`.
- Tap: `OpenClawHaptics.play(candidate.pattern)`.

**Candidate patterns (in order):**

| Name | Note | Pattern |
|---|---|---|
| `1 · Minimalist` | one crisp click | `.secured1` |
| `2 · Handshake` | click, firmer answer | `.secured2` |
| `3 · v1 Draft` | click, answer, settling hum | `.secured3` |
| `4 · Key Turn` | rising triplet | `.secured4` |
| `5 · Echo` | double-tap, distant echo | `.secured5` |
| `6 · Warning` | firm buzz, gap, softer buzz | `.warning` |
| `7 · Lock Engaging` | swell into a click | `.secured7` |
| `8 · Heartbeat` | two soft lub-dubs | `.secured8` |
| `9 · Sealed` | low hum, stamped shut | `.secured9` |
| `10 · Sparkle` | three feather ticks, thud | `.secured10` |

---

## 6. Cross-Cutting Design Values

### 6.1 Typography

All text in the wizard uses `OpenClawType` named styles or explicit system font calls. Raw system calls are used throughout the welcome/setup/feedback screens (these predate the branded type system or are intentional raw overrides):

| Surface | Style used |
|---|---|
| Tagline, titles, state titles | `.system(size: 30, weight: .semibold/.medium)` |
| Buttons | `.system(size: 17, weight: .medium/.semibold)` |
| Body/helper text | `.system(size: 15/.system(size: 16))` |
| Small helper/footnote | `.system(size: 12/.system(size: 13/.system(size: 14))` |
| Intro / canvas screens | `OpenClawType.title1`, `OpenClawType.body`, `OpenClawType.subheadSemiBold`, `OpenClawType.footnote`, etc. |
| Navigator/toolbar | `OpenClawType.headline`, `OpenClawType.subheadSemiBold` |

### 6.2 Max Width

`OnboardingVisual.maxWidth = 430` pt. All content inside the canvas/feedback screens is constrained to this maximum.

### 6.3 Key Color Tokens

| Token name | Where used |
|---|---|
| `OpenClawBrand.welcomeCanvas` | Background on welcome, setup, feedback, success steps |
| `OpenClawBrand.welcomePrimaryAction` | Primary button fill, back-chevron tint |
| `OpenClawBrand.welcomeSecondaryAction` | "Set Up Manually" button fill |
| `OpenClawBrand.welcomeSecondaryActionText` | "Set Up Manually" button foreground |
| `OpenClawBrand.welcomeGlow` | Mascot drop shadow color |
| `OpenClawBrand.welcomeLink` | Footer "here" link color |
| `OpenClawBrand.activationCanvasGradient` | Canvas background on intro / success canvas |
| `OpenClawBrand.activationPrimaryAction` | Tint color for whole NavigationStack |
| `OpenClawBrand.activationNeutralSurface` | Command chip and panel fills |
| `OpenClawBrand.activationNeutralStroke` | Panel/chip strokes |
| `OpenClawBrand.ok` | Success checkmark circle fill |

### 6.4 Command Chip (`OnboardingCommandChip`)

Used in the intro step to display `"openclaw qr"`:

- `HStack(spacing: 8)`: monospace text (`.textSelection(.enabled)`) + copy button.
- Height: 54 pt. Horizontal padding: 16.
- Background: `RoundedRectangle(cornerRadius: 20, style: .continuous).fill(OpenClawBrand.activationNeutralSurface)`.
- Stroke: `OpenClawBrand.activationNeutralStroke`, `lineWidth: 0.5`.
- Copy button: `Image(systemName: "doc.on.doc")` → `"checkmark"` after copy. Transition: `.symbolEffect(.replace)`. Foreground: secondary (0.56 opacity) → `OpenClawBrand.activationPrimaryAction`. Resets after 1.1 seconds (`1_100_000_000 ns`). Animation in/out: `.smooth(duration: 0.14/.16)`.

---

## 7. Behavior Notes and Non-Obvious Invariants

### 7.1 TLS Trust Prompt Alert Isolation

The TLS trust-prompt alert is attached to a `Color.clear.background` layer, not to the main content. SwiftUI honors only one `.alert` per view. Without this separation, the scanner-error alert (on the `lifecycleContent` view) would shadow the TLS trust prompt, leaving the user stuck at "Verify gateway TLS fingerprint" with no way to approve.

**Source:** `OnboardingWizardView.swift:182–183`.

### 7.2 SecureField Write Guard

The `SecureField` in the credential field is wrapped in a focus-guarded `Binding`. The `SecureField` emits an empty-string write to its binding when it mounts/unmounts during the full-screen loading transition. Without the guard, this would wipe the stored credential and clear the rejected flag, making a wrong password disappear silently.

**Source:** `OnboardingWizardSteps.swift:1252–1261`.

### 7.3 Scanner Result Settling Delay (1.2 s)

After the QR scanner sheet dismisses, delivery of the scanned result is delayed 1.2 seconds. Without the delay, the pairing UI can appear while VisionKit's AV capture session is still tearing down, causing a race condition.

**Source:** `QRScannerView.swift:50`.

### 7.4 Issue Stickiness (Pairing / Auth)

Once `issue` is `.pairingRequired` or an auth-required variant, it remains set even as the gateway sends intermediate "Offline"/"Connecting" statuses during reconnect churn. Without stickiness, the feedback UI would flip between the actionable state and the loading spinner every 2 seconds.

**Source:** `OnboardingWizardView.swift:1236–1244`.

### 7.5 Credential Auto-Migration on Auth Method Flip

When the gateway discloses its auth method after a credential was already submitted into the wrong slot, the wizard migrates the credential to the correct slot and re-submits once automatically (guarded by `autoRetriedAfterMethodFlip`). The one-shot guard prevents looping.

**Source:** `OnboardingWizardView.swift:293–305`.

### 7.6 Minimum 2-Second Dwell

`setFeedbackContent(_:)` enforces a minimum 2-second display before committing a content transition. This prevents sub-second flashes when a result arrives immediately. The timer is measured from `feedbackShownAt`, which is reset on every content commit.

**Source:** `OnboardingWizardView.swift:942–951`.

### 7.7 Keyboard Dismiss Before Step Transition

Before navigating away while a text field is focused, the wizard dismisses the keyboard and yields (`await Task.yield()`) followed by a 120 ms sleep. Without the yield, the navigation animation can fight the keyboard dismissal animation.

**Source:** `OnboardingWizardView.swift:1314–1319`.

### 7.8 Discovery Restart Debounce

Changes to `discoveryDomain` schedule a discovery restart with a 350 ms debounce (`350_000_000 ns`).

**Source:** `OnboardingWizardView.swift:1413–1420`.
