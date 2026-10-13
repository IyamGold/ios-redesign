# Audit — 07-settings.md

## Scorecard

| Metric | Value |
|---|---|
| Precision | 0.981 |
| Recall | 0.855 |
| F-score | 0.914 |
| Critical defects | 2 |
| Major defects | 7 |
| Minor defects | 30 |
| Certified | false |
| Claims audited | 80 |

## Defects (fix these)

### Wrong / Unsupported Claims

**major** — §5.6 says the full-access confirmation dialog title is `"Switch to full access mode requires you to scan a new QR code."` — code at `ConnectionSheet.swift:245` shows the actual title is `"Switch to full access?"` and the spec's phrasing is the message body at line 256: `"Switching to full access mode requires you to scan a new QR code to take effect."` — citation: `ConnectionSheet.swift` (§5.6)

### Omissions

**major** — §1.7 claims `OpenClawToggleIndicator` is "used by all toggle rows in destination screens (`settingsToggle`)" — `VoiceSettingsScreen` uses native SwiftUI `Toggle(isOn:)` for both the master switch and all sub-toggles (see `toggleRow` at line 643); a rebuilder following §1.7 would incorrectly use the custom indicator for all voice toggles — citation: `SettingsDestinationScreens.swift:581-648`

**major** — §5.6 documents the full-access confirmation dialog action button label as "Switch" but the source button label is `"Scan QR Code"` (`ConnectionSheet.swift:248-257`); the spec also gives the wrong message wording (`"Switch to full access mode requires you to scan a new QR code."` vs actual `"Switching to full access mode requires you to scan a new QR code to take effect."`) — citation: `ConnectionSheet.swift:248-257`

**major** — §4.3 states `authorized = true` only when authorization status is `.authorized` — source `refreshAuthorization()` sets `self.authorized = status == .authorized || status == .provisional`; the `.provisional` case is omitted, so a rebuilder would fail to show "Enabled" for provisional authorization — citation: `SettingsDestinationScreens.swift:287-291`

**major** — §4.5 documents the between-accounts divider as `Divider().padding(.leading, 38)` but omits the between-channels (per `SettingsChannelRow`) divider which uses `Divider().padding(.leading, 58)`; a rebuilder would apply 38pt leading to all dividers and miss the 58pt channel-level inset — citation: `SettingsChannelsDestination.swift:96-98`

**major** — §4.4 documents `reloadKey` as `"\(isConnected)-\(scenePhase == .active)"` — source uses `"\(appModel.isOperatorGatewayConnected)-\(scenePhase == .active)"`; the property name `isConnected` does not exist at the call site, so wiring based on the spec would not compile — citation: `SettingsDestinationScreens.swift:491-493`

**major** — §3.7 says the default-agent display label falls back to `agent.id` when the name is empty — source display label is `self.defaultAgent?.name ?? "—"` (em dash); the `agent.id` fallback occurs only inside `SettingsRootContainer.agentOptions` when building picker options, not in the displayed label; a rebuilder following the spec would render `agent.id` instead of `"—"` — citation: `SettingsRootScreen.swift:244-251`

**minor** — §3.3 documents `.padding(.leading, 17)` as applying to the section-header `Text` but does not state this padding is on the `Text` inside the `VStack`, not on the `VStack` itself; a rebuilder could place it at the wrong level — citation: `SettingsRootScreen.swift:154-157`

**minor** — §4.7 documents the add-word alert but omits the alert message body text `"The phrase your gateway listens for."`; a rebuilder would not know what message to put in the alert — citation: `SettingsDestinationScreens.swift:815-818`

**minor** — §4.7 describes the add-button flow but omits that `newWord` state is reset to `""` before `showsAddAlert = true`; without this pre-reset a reopened alert shows the previously typed word — citation: `SettingsDestinationScreens.swift:838-839`

**minor** — §4.4 says the Edit/Done button background uses `ChatGlassBackground(fill: glassFill)` but does not specify that `shape:` is omitted (defaults to the type's default shape, not `Circle()`); a rebuilder may incorrectly pass `shape: Circle()` as done elsewhere — citation: `SettingsDestinationScreens.swift:378-380`

**minor** — §4.4 says the back button has shadow but in source only the enclosing `HStack` carries `.shadow(color: .black.opacity(0.15), radius: 25, x: 0, y: 0)`; the back button's glass circle has no individual shadow modifier, unlike `SettingsDestinationChrome` buttons — citation: `SettingsDestinationScreens.swift:365-387`

**minor** — §4.5 documents the per-account row menu icon conditions (`ellipsis.circle`, `hourglass`, `lock.shield`) but does not state their precedence order: busy is checked first → `hourglass`; then `!canAdmin` → `lock.shield`; otherwise `ellipsis.circle`; a rebuilder cannot infer the correct branching — citation: `SettingsChannelsDestination.swift:448-456`

**minor** — §3.3 does not document that the connection pill `HStack` uses `.padding(.leading, 16)` only with no trailing padding; `Spacer(minLength: 0)` provides the right-edge expansion inside `.frame(maxWidth: .infinity)`; a rebuilder may add symmetric trailing padding — citation: `SettingsRootScreen.swift:168-188`

**minor** — §4.3 describes the notifications button layout as being inside a `VStack` within the `ScrollView` but source places the `Button` as a direct child of `ScrollView`; the padding modifiers are on the button, not a wrapper `VStack` — citation: `SettingsDestinationScreens.swift:255-270`

**minor** — §5.8 documents the disconnect flow as `onDisconnect()` calling `onClose()` then `GatewayOnboardingReset.reset(...)` — in source `ConnectionSheetHostView` calls `onClose()` first then `disconnect()` as an async `Task`; the Task wrapping and ordering detail is not documented — citation: `ConnectionSheet.swift:89-91`

**minor** — §4.4 channel header shadow is documented as being on the back button but source applies shadow at the `HStack` level, not the individual button; this structural difference from `SettingsDestinationChrome` is not called out — citation: `SettingsDestinationScreens.swift:365-387`

**minor** — §1.7 states `OpenClawToggleIndicator` is used by all toggle rows in destination screens — `VoiceSettingsScreen.toggleRow` (line 643) uses native SwiftUI `Toggle`; the `settingsToggle` helper exists but is not used by `VoiceSettingsScreen`; the universal claim is false — citation: `SettingsDestinationScreens.swift:643`

**minor** — §4.8 documents the Licenses card `VStack` having `.padding(.horizontal, 15)` but does not clarify this padding is on the inner `VStack` inside the card background, not on the card container; a rebuilder may apply it at the wrong hierarchy level — citation: `LicenseDocuments.swift:110-124`

**minor** — §4.8 notes `cardFill` for `LicensesScreen` is `dark: .black` — the spec note is present but does not document that `light: .white` is also explicitly set (not the default); a rebuilder relying on defaults would get the same result but the omission is a precision gap — citation: `LicenseDocuments.swift:155-157`

**minor** — §4.6 documents the Talk Mode master-switch row with `.padding(.horizontal, 17)` and `.frame(height: 50)` but does not state this is a bare SwiftUI `Toggle(isOn:)`, not a custom component; in context of §1.7's false universal claim, a rebuilder would use `OpenClawToggleIndicator` here — citation: `SettingsDestinationScreens.swift:581-595`

**minor** — §5.6 full-access dialog: the spec omits the action button label entirely (`"Scan QR Code"`); only the cancel button label is implied — citation: `ConnectionSheet.swift:248-257`

**minor** — §3.7 default-agent row: the spec says "non-tappable (no Button wrapper)" which is correct but the fallback display value documented as `agent.id` is incorrect (actual: `"—"` em dash); this conflation of option-building logic with display label would mislead a rebuilder — citation: `SettingsRootScreen.swift:244-251`

**minor** — §4.7 wake-words header: the spec correctly shows shadow on the `HStack` but does not explicitly clarify that the shadow is on the `.padding(.horizontal, 24)` enclosure of the `HStack`, not on the `HStack` modifier chain directly; structural placement matters for SwiftUI rendering — citation: `SettingsDestinationScreens.swift:847-855`

**minor** — §1.6 documents `safeAreaInset(edge: .top, spacing: 0)` for `SettingsDestinationChrome`; the Channels and Wake Words screens use the same pattern but the spec does not explicitly confirm these screens follow §1.6 rather than using `.overlay`; a rebuilder may apply `.overlay` for consistency with other patterns — citation: `SettingsDestinationScreens.swift:28-31`

**minor** — §4.5 channel-level divider: the spec documents only the between-accounts divider anatomy (`Divider().padding(.leading, 38)`); the between-`SettingsChannelRow` divider using `Divider().padding(.leading, 58)` is entirely absent; this is a structurally distinct UI element not described anywhere in the spec — citation: `SettingsChannelsDestination.swift:96-98`

**minor** — Connection pill: the spec does not mention that `.buttonStyle(.plain)` is absent from the connection pill button; on iOS the default button style applies a highlight state on tap that `.buttonStyle(.plain)` would suppress; the absence is not documented as intentional — citation: `SettingsRootScreen.swift:169-188`

**minor** — §4.3 notifications: `provisional` authorization status treated as `authorized = true` in source is not mentioned anywhere in §4.3 or §1.x; a rebuilder implementing only `.authorized` would produce wrong "Disabled" display for provisionally authorized users — citation: `SettingsDestinationScreens.swift:287-291`

**minor** — §4.5 does not document the `ChannelsScreenHost` reload-key property name (`isOperatorGatewayConnected`) as distinct from a generic `isConnected` boolean; without the exact property the data wiring cannot be reproduced — citation: `SettingsDestinationScreens.swift:491-493`

**minor** — §1.7 `OpenClawToggleIndicator` usage claim ("all toggle rows in destination screens") is not qualified or scoped; the spec should either list the screens that use it or add a carve-out for `VoiceSettingsScreen` which uses native `Toggle` exclusively — citation: `SettingsDestinationScreens.swift:581-648`

**minor** — §4.7 add-word alert: the spec documents a `TextField` and Add/Cancel buttons but omits the pre-reset of `newWord` state before alert presentation; without this detail the reopen-alert bug would be reproduced verbatim by any rebuilder following the spec — citation: `SettingsDestinationScreens.swift:838-839`

## Verdict

NEEDS-REPAIR — 9 blocking defects (2 critical + 7 major)
