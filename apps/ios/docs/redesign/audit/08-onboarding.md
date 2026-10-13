# Audit — 08-onboarding.md

## Scorecard

| metric | value |
|---|---|
| precision | 0.882 |
| recall | 0.754 |
| F | 0.813 |
| critical | 3 |
| major | 7 |
| minor | 11 |
| certified | false |
| claims | 91 |

## Defects (fix these)

### Wrong / Unsupported Claims

**major** — Doc claims `pairingAutoResumeTicker` fires `attemptAutomaticPairingResumeIfNeeded()` and that the minimum inter-attempt interval is 6 seconds (`now.timeIntervalSince(last) < 6`). The ticker itself is confirmed at line 113, but the 6-second threshold is inside `attemptAutomaticPairingResumeIfNeeded()` which was not visible in the read windows; the 6 s value cannot be confirmed from code. — `Sources/Onboarding/OnboardingWizardView.swift`

**major** — Doc claims `SetupScanningSpinner` rotates `Image("SetupSpinnerGlyph")` 360° with `.linear(duration: 0.9).repeatForever(autoreverses: false)` at 24×24 pt. The struct is referenced at lines 651, 721, 860–870 but the actual body definition was not captured in any read window; none of these values can be confirmed from code. — `Sources/Onboarding/OnboardingWizardSteps.swift:535`

**critical** — Doc claims the success step is `OnboardingSuccessStepView` (auto-advancing). The wizard navigates to `.success` (lines 328/331) and a separate `OnboardingSuccessStep` struct exists (line 411 in OnboardingWizardSteps.swift) which is `OnboardingActivationCanvas`-based and shows gateway name/address with a "Go to Chat" button. `OnboardingSuccessStepView` (line 1397) is the simpler auto-advancing variant. Section 2.4 describes the auto-advancing view correctly but the separate `OnboardingSuccessStep` struct that also exists is never described, which is misleading. — `Sources/Onboarding/OnboardingWizardView.swift`

**minor** — Doc lists three pre-condition check error messages; the first two (`isSupported` → `"QR scanning is not supported on this device."` and `isAvailable` → `"Camera scanning is currently unavailable."`) are confirmed at lines 117–124, but the `becameUnavailableWithError` delegate message (`"Camera is not available on this device."`) is inside the Coordinator body not captured in the read window and cannot be confirmed. — `Sources/Onboarding/QRScannerView.swift:111`

**major** — Doc says `beginScan()` increments `activeScanID` then returns it. Lines 62–65 show `beginScan()` calls `self.cancel()` (which increments `activeScanID`) then returns `self.activeScanID`; beginScan itself does not increment — cancel does. On a fresh state with no pending scan, beginScan returns the current unchanged `activeScanID`. — `Sources/Onboarding/QRScannerView.swift:50`

**major** — Doc attributes mode defaults (homeNetwork: host `"openclaw.local"`, port 18789, TLS on; remoteDomain: host `""`, port 18789, TLS on; developerLocal: host `"localhost"`, port 18789, TLS off) to `OnboardingConnectionMode` in `OnboardingStateStore`. These defaults are actually set in `OnboardingWizardView.initializeState()` (lines 1358–1387) conditionally, not as properties of `OnboardingConnectionMode` in the state store. — `Sources/Onboarding/OnboardingStateStore.swift`

### Omissions

**critical** — The entire Mode step UI is undocumented. `modeStep` @ViewBuilder contains a setup-code Section and mode-picker rows, `OnboardingModeRow` (HStack spacing 12, leading VStack spacing 2 for title/subtitle, trailing checkmark indicator), and `OnboardingModeIcon` (34×34 RoundedRectangle cornerRadius 12, `activationPrimaryGradient` when selected, `activationNeutralGradient` otherwise, `activationGlow` shadow opacity 0.18 radius 5 y 2 when selected, white 0.30 stroke when selected). No section 2.x for the mode step exists in the doc. — `Sources/Onboarding/OnboardingWizardView.swift:517-571`

**critical** — The setup-code section inside the Mode step is undocumented: a Form Section with a TextField prompting "Enter setup code", a bordered capsule Apply button (showing ProgressView while `connectingGatewayID == "setup-code"`), an optional `setupCodeStatus` Text row, and a footer. — `Sources/Onboarding/OnboardingWizardView.swift:635-678`

**major** — `OnboardingModeRow` trailing selection indicator: `checkmark.circle.fill` at `.title3.weight(.semibold)` (`activationPrimaryAction` tint) when selected; `circle` at `.title3.weight(.regular)` with `Color(uiColor: .quaternaryLabel).opacity(0.55)` when unselected. Not documented anywhere. — `Sources/Onboarding/OnboardingWizardSteps.swift:519-526`

**major** — `manualConnectionFieldsSection` is entirely undocumented: segmented Picker for Unencrypted vs Secure (TLS), optional helper text from `manualTransport.helperText`, token and password SecureFields (only for remoteDomain), and a Connect button that shows ProgressView while connecting. — `Sources/Onboarding/OnboardingWizardView.swift:685-814`

**major** — `OnboardingSetupStep` validation state animations use `.smooth(duration: 0.2)` for idle/scanning/validated transitions and `.easeOut(duration: 0.15)` for the invalid transition. The doc mentions only `.spring(duration: 0.35)` for the endpoint-reveal transition; the other animation curves are absent. — `Sources/Onboarding/OnboardingWizardSteps.swift:794-835`

**minor** — `SetupScanningSpinner` has `.foregroundStyle(Color.primary.opacity(0.8))`. The doc lists the asset, size, and rotation animation but omits this foreground color. — `Sources/Onboarding/OnboardingWizardSteps.swift:865-866`

**minor** — Loading view inner structure: outer `VStack(spacing: 31)` contains `FeedbackLoaderSpinner` and an inner `VStack(spacing: 10)` grouping the title text and status line. The doc describes the outer VStack but omits the inner `VStack(spacing: 10)`. — `Sources/Onboarding/OnboardingWizardSteps.swift:983-1003`

**minor** — `FeedbackCopyChip` Copy/Copied text uses `.font(.system(size: 13))`. The doc describes padding, background colors, and icon animations but omits this font size. — `Sources/Onboarding/OnboardingWizardSteps.swift:1336`

**minor** — `OnboardingCommandChip` copy icon button has a 38×38 pt frame and `OpenClawType.subheadSemiBold` font. The doc describes the chip container dimensions and symbol-effect transition but omits these button-level specs. — `Sources/Onboarding/OnboardingWizardSteps.swift:199-204`

**minor** — Keyboard dismiss control icon label has a 50×44 pt frame. The doc gives padding, material, and shadow values but omits this frame. — `Sources/Onboarding/OnboardingWizardView.swift:440`

**minor** — `OnboardingIntroStep` wraps the Continue button in `VStack(spacing: 14)`. The doc specifies the button style but not this spacing wrapper. — `Sources/Onboarding/OnboardingWizardSteps.swift:269-277`

**minor** — `OnboardingSetupStep.beginApplying()` animates `isApplying` on/off with `.smooth(duration: 0.2)`. The doc describes the spinner behavior on apply but omits these animations. — `Sources/Onboarding/OnboardingWizardSteps.swift:838-852`

**minor** — `setupField` TextField inside `OnboardingSetupStep` uses font `.system(size: 17)`. The doc covers border colors and height but omits the text field font. — `Sources/Onboarding/OnboardingWizardSteps.swift:771`

**minor** — `leadingChromeButton` Back button applies `OpenClawType.subheadSemiBold` as the font for the chevron SF Symbol image. The doc mentions `OpenClawCloseButtonStyle` but not this font token on the symbol. — `Sources/Onboarding/OnboardingWizardView.swift:412-413`

**minor** — An unused `OnboardingSuccessStep` struct (canvas-based, `OpenClawActivationGlyph` size 86, "You're connected" title, `gatewayName`/`gatewayAddress` params, "Go to Chat" button) exists alongside the live `OnboardingSuccessStepView`. Its presence is not noted and could mislead a rebuilder. — `Sources/Onboarding/OnboardingWizardSteps.swift:411-470`

## Verdict

NEEDS-REPAIR — 10 blocking defects (3 critical + 7 major).
