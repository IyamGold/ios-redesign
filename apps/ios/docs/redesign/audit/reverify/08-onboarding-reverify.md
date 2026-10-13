# Re-verify — 08-onboarding.md

## Scorecard

| metric | value |
|---|---|
| originalDefectCount | 21 |
| resolvedCount | 21 |
| unresolved | 0 |
| newErrors | 0 |
| remainingOmissions | 1 (minor) |

---

## Unresolved Original Defects

None. All 21 original defects (3 critical + 7 major + 11 minor) are confirmed resolved in the repaired doc.

Resolution evidence for each group:

- **6-second pairing-resume threshold** (was major): Section 1.4 now quotes the exact guard `if let last = lastPairingAutoResumeAttemptAt, now.timeIntervalSince(last) < 6 { return }` with citation `OnboardingWizardView.swift:1216–1228`. Confirmed at source line 1223.
- **`SetupScanningSpinner` body** (was major): Section 2.2 icons table now documents `Image("SetupSpinnerGlyph")`, 24×24 pt, `.linear(duration: 0.9)`, `.foregroundStyle(Color.primary.opacity(0.8))`. Confirmed at source lines 856–871.
- **`OnboardingSuccessStepView` vs `OnboardingSuccessStep` confusion** (was critical): Section 2.4 now names `OnboardingSuccessStepView` as the live view; Section 2.6.6 documents `OnboardingSuccessStep` as unused/never-instantiated with full description. Confirmed by live switch at source line 620: `OnboardingSuccessStepView(onFinished:)`.
- **`becameUnavailableWithError` message** (was minor): Section 3.2 now cites `QRScannerView.swift:254–259` for `"Camera is not available on this device."`. Confirmed at source lines 254–259.
- **`beginScan()` increment semantics** (was major): Section 3.3 now correctly states the increment happens inside `cancel()`, not `beginScan()` itself, and returns the already-incremented value. Confirmed at source lines 62–65.
- **Mode defaults location** (was major): Section 4 now correctly states `OnboardingConnectionMode` has no host/port/TLS properties; defaults are applied by `applyModeDefaults(_:)` at `OnboardingWizardView.swift:1596–1632`. Confirmed at source lines 1596–1632.
- **Mode step UI undocumented** (was critical): Section 2.6.1 now fully documents `modeStep` @ViewBuilder including `OnboardingModeRow` rows, section headers, Continue button, and disabled state. Confirmed unused (not referenced in the live `switch self.step` at source lines 189–201).
- **`setupCodeSection` undocumented** (was critical): Section 2.6.4 now fully documents `setupCodeSection` including header/footer, `onboardingTextField`, Apply button with `ProgressView`/`Text("Apply")`, `setupCodeStatus` row. Confirmed at source lines 635–678.
- **`OnboardingModeRow` trailing indicator** (was major): Section 2.6.2 now documents `"checkmark.circle.fill"` / `"circle"` with exact font and color values. Confirmed at source lines 520–525.
- **`manualConnectionFieldsSection` undocumented** (was major): Section 2.6.5 now fully documents the section including segmented TLS picker, `manualTransport.helperText`, token/password secure fields, and `manualConnectButton`. Confirmed at source lines 685–814.
- **Validation-state animation curves** (was major): Section 2.2 now contains a full five-row table for all transitions (idle, scanning, validated-false, validated-true, invalid). Confirmed at source lines 790–836.
- **`SetupScanningSpinner` foreground style** (was minor): Section 2.2 icons table now includes `.foregroundStyle(Color.primary.opacity(0.8))`. Confirmed at source line 865.
- **Loading view inner `VStack(spacing: 10)`** (was minor): Section 2.3.5 now documents the inner `VStack(spacing: 10)` grouping title and status. Confirmed at source lines 985–999.
- **`FeedbackCopyChip` font size** (was minor): Section 2.3.7 now documents `.font(.system(size: 13))`. Confirmed at source line 1336.
- **`OnboardingCommandChip` copy button frame + font** (was minor): Section 6.4 now documents `.frame(width: 38, height: 38)` and `OpenClawType.subheadSemiBold`. Confirmed at source lines 199–203.
- **Keyboard dismiss 50×44 frame** (was minor): Section 1.3 now documents `.frame(width: 50, height: 44)`. Confirmed at source line 440.
- **`OnboardingIntroStep` `VStack(spacing: 14)` button wrapper** (was minor): Section 2.5 now documents this wrapper. Confirmed at source lines 269–277.
- **`beginApplying()` animation** (was minor): Section 2.2 now documents `withAnimation(.smooth(duration: 0.2))` for both `isApplying = true` and `isApplying = false`. Confirmed at source lines 843, 851.
- **`setupField` `.font(.system(size: 17))`** (was minor): Section 2.2 now documents the TextField font. Confirmed at source line 771.
- **Back chevron `OpenClawType.subheadSemiBold`** (was minor): Section 1.3 now documents `.font(OpenClawType.subheadSemiBold)` on the symbol. Confirmed at source line 413.
- **Unused `OnboardingSuccessStep` struct** (was minor): Section 2.6.6 now fully documents the struct. Confirmed at source lines 411–470.

---

## New Errors Introduced by the Repair

None found. A broad sample of newly-added content was verified against source:

- Section 2.6.1 `modeStep` dead-code claim: confirmed — `case .mode: self.setupStep` at source line 195; `modeStep` property has no call site in the live render path.
- Section 4 `applyModeDefaults` coercion conditions: confirmed at source lines 1596–1632.
- Section 2.3.6 error border `lineWidth: 1`: confirmed at source line 1293–1294 (`lineWidth: showError ? 1 : 0.5`).
- Section 2.3.7 `FeedbackCopyChip` dark/light inversion (dark=white bg/black fg; light=`Color(16,16,16)` bg/white fg): confirmed at source lines 1179–1186.
- Section 3.3 `processAfterDismissal` nil-result path calls `cancel()`: confirmed at source lines 83–86.
- Section 2.4 `OnboardingSuccessStepView` 1.5-second auto-advance: confirmed at source line 1425.

---

## Remaining Omissions

| fact | severity | sourceRef |
|---|---|---|
| `OnboardingWelcomeStep` center layout has an intermediate `VStack(spacing: 31)` wrapping the tagline text and button stack inside the outer `VStack(spacing: 21)`. The doc describes the outer spacing and the button stack but never mentions this intermediate container, whose 31 pt spacing separates tagline from buttons. | minor | `Sources/Onboarding/OnboardingWizardSteps.swift:300–307` |

---

## Verdict

CERTIFIED — zero critical or major defects remain across unresolved original defects, new errors, and remaining omissions.
