# Settings (root + destinations)

This section specifies the redesigned Settings surface on iPhone: the root menu (`SettingsRootScreen` / `SettingsRootContainer`), every pushed destination screen (Approvals, Permissions, Notifications, Channels / Integrations, Voice Settings, Wake Words, Licenses), the modal Connection sheet (`ConnectionSheet`), and the license-file discovery/loader rules. The spec is written so a competent engineer can rebuild all screens pixel- and behavior-accurate without access to the source code.

---

## 1  Design Token Reference

Before describing individual screens, the shared constants are listed here so later sections can reference them by name.

### 1.1  Color Palette

All colors are fully adaptive (light / dark). RGB values are integers in 0–255.

| Token | Role | Light | Dark |
|---|---|---|---|
| `canvas` | Page background | rgb(245, 244, 250) | rgb(23, 23, 23) |
| `cardFill` | Card / section background | `.white` | rgb(10, 10, 10) |
| `glassFill` | Liquid Glass nav-button tint | rgb(245, 244, 250) @ 0.2 opacity | rgb(30, 30, 30) @ 0.2 opacity |
| `OpenClawBrand.welcomeLink` | Accent blue (Connection pill, Notifications enable link) | rgb(37, 99, 235) | rgb(37, 99, 235) |
| `OpenClawBrand.accent` | Interactive tint (toggles on, pickers, action buttons) | rgb(183, 56, 51) adaptive | rgb(198, 62, 56) adaptive |
| `OpenClawBrand.ok` | Success indicator | rgb(19, 122, 62) | rgb(48, 209, 88) |
| `OpenClawBrand.warn` | Warning indicator | rgb(154, 87, 0) | rgb(255, 214, 10) |
| `OpenClawBrand.danger` | Destructive indicator | rgb(185, 28, 28) | rgb(252, 165, 165) |
| `destructiveRed` (Channels / Connection) | Destructive action | rgb(197, 62, 56) constant | rgb(197, 62, 56) constant |
| `noteRed` (Connection access note) | Inline warning tint | rgb(195, 63, 51) constant | rgb(195, 63, 51) constant |
| `radioBlue` (Connection gateway radio) | Selected radio button | rgb(37, 99, 235) constant | rgb(37, 99, 235) constant |
| `WakeWords.resetRed` | Wake Words "Reset Defaults" action | rgb(195, 63, 51) constant | rgb(195, 63, 51) constant |

Sources: `SettingsRootScreen.swift:326–343`, `ConnectionSheet.swift:25–27`, `SettingsDestinationScreens.swift:333,781`, `OpenClawBrand.swift:79–138`.

### 1.2  Layout Metrics

| Constant | Value | Where used |
|---|---|---|
| `OpenClawProMetric.pagePadding` | 16 pt | Horizontal padding for `SettingsChannelsDestination` cards |
| `OpenClawProMetric.cardRadius` | 16 pt | `SettingsLayout.cardRadius`; ProCard radius in Channels |
| `OpenClawSectionStyle.cornerRadius` | 12 pt | `openClawSectionBackground` modifier (all section cards) |
| `OpenClawSectionStyle.dividerHeight` | 2 pt | `OpenClawRowDivider` height |
| `SettingsLayout.rowHeight` | 58 pt | ProCard preview fact-row height |
| Section content `VStack spacing` | 17 pt | Spacing between rows inside a section card |
| Section content `.padding(.vertical, 12)` | 12 pt | Top + bottom inset inside section cards (root screen) |
| Root screen horizontal page padding | 24 pt | `ScrollView` content `.padding(.horizontal, 24)` |
| Root screen top content padding | 72 pt | Clear space below floating header |
| Root screen bottom content padding | 40 pt | Scroll overscroll clearance |
| Header `.padding(.top, 8)` | 8 pt | Space above header |
| Header `.padding(.bottom, 21)` | 21 pt | Space below header (root screen) |
| Row leading inset | 17 pt | `rowInset` leading (root screen) |
| Row trailing inset | 12 pt | `rowInset` trailing (root screen) |

Sources: `SettingsRootScreen.swift:79–83,145–149,159–165`, `SettingsProTabSupport.swift:22–25`, `OpenClawProComponents.swift:4–32`.

### 1.3  Typography Tokens

All tokens are Dynamic-Type scaled. Base faces: **Red Hat Display** (Display tokens), **Inter** (Body tokens), **JetBrains Mono** (Mono tokens). If a named font is unavailable the system font is substituted.

| Token | Face | Base size | Weight | DT style |
|---|---|---|---|---|
| `OpenClawType.body` | Inter | 17 pt | 400 | `.body` |
| `OpenClawType.callout` | Inter | 16 pt | 400 | `.callout` |
| `OpenClawType.subhead` | Inter | 15 pt | 400 | `.subheadline` |
| `OpenClawType.subheadMedium` | Inter | 15 pt | 500 | `.subheadline` |
| `OpenClawType.subheadSemiBold` | Red Hat Display | 15 pt | opt-650 | `.subheadline` |
| `OpenClawType.headline` | Red Hat Display | 17 pt | opt-650 | `.headline` |
| `OpenClawType.footnote` | Inter | 13 pt | 400 | `.footnote` |
| `OpenClawType.caption` | Inter | 12 pt | 400 | `.caption1` |
| `OpenClawType.captionSemiBold` | Inter | 12 pt | 600 | `.caption1` |
| `OpenClawType.captionBold` | Inter | 12 pt | 700 | `.caption1` |
| `OpenClawType.caption2` | Inter | 11 pt | 400 | `.caption2` |
| `OpenClawType.caption2Medium` | Inter | 11 pt | 500 | `.caption2` |
| `OpenClawType.monoFootnote` | JetBrains Mono Regular | 13 pt | — | `.footnote` |
| Header / section-header title | SF Pro | 20 pt | `.medium` | — |
| Header back-button chevron | SF Pro | 17 pt | `.semibold` | — |

Sources: `OpenClawTypography.swift:5–443`.

### 1.4  Shared Component: `OpenClawRowDivider`

A full-width `Rectangle` filled with the **canvas color** (adaptive: dark `rgb(23,23,23)`, light `rgb(245,244,250)`) at 100% opacity, fixed height `OpenClawSectionStyle.dividerHeight` = 2 pt. It visually reads as a gap of page background between rows, not a hairline. It must be a direct child of the section card's `VStack` so it spans edge-to-edge; horizontal padding lives on the rows themselves.

Source: `OpenClawProComponents.swift:38–49`.

### 1.5  Shared Component: `openClawSectionBackground(_:)`

A `ViewModifier` that adds a `.background` of `RoundedRectangle(cornerRadius: 12, style: .continuous).fill(fill)`. Applied to every section card (connection pill, each section block, channel pill card, etc.).

Source: `OpenClawProComponents.swift:54–59`.

### 1.6  Shared Chrome: `SettingsDestinationChrome`

All pushed destinations (Approvals, Permissions, Notifications, Voice Settings, Wake Words, Licenses, License detail) use this wrapper:

- **ZStack** with top alignment: `canvas` color `ignoresSafeArea()` behind content.
- Content inset via `.safeAreaInset(edge: .top, spacing: 0)` with the shared header (so the header is always above the scroll area, not inside it).
- `.toolbar(.hidden, for: .navigationBar)` — native nav bar is hidden; this header owns navigation chrome.

**Header-attachment pattern is `.safeAreaInset`, not `.overlay`, everywhere.** The screens with custom headers (Channels §4.4, Wake Words §4.7) do NOT use `SettingsDestinationChrome` but still attach their header the same way: `.safeAreaInset(edge: .top, spacing: 0) { header }` on the body `ZStack`. A rebuilder must not substitute `.overlay` for the header on any of these screens — the Connection sheet's close button (§5.3) is the only Settings header element that uses `.overlay`.

**Header** (same markup for root screen and all destinations):

```
ZStack {
    Text(title)                                    // SF Pro medium 20pt, Color.primary
    HStack {
        Button(onBack) {
            Image(systemName: "chevron.left")      // SF Pro semibold 17pt, Color.primary
                .frame(40×40)
                .background { ChatGlassBackground(shape: Circle(), fill: glassFill) }
                .shadow(color: .black.opacity(0.15), radius: 25, x: 0, y: 0)
        }
        Spacer()
    }
    .padding(.horizontal, 24)
}
.padding(.top, 8)
.padding(.bottom, 21)
```

Source: `SettingsDestinationScreens.swift:16–68`.

### 1.7  Shared Component: `OpenClawToggleIndicator`

- `Capsule()` frame 52×32 pt. Fill: `OpenClawBrand.accent` when on, `Color.secondary.opacity(0.35)` when off.
- Overlay `Circle()` 28×28 pt with `Color.white` fill, 2 pt padding, `shadow(color: .black.opacity(0.14), radius: 1, x: 0, y: 1)`. Aligned `.trailing` when on, `.leading` when off.

Toggle rows that use this indicator wrap it in a full-width `Button` (`.buttonStyle(.plain)`) because native `Toggle` misses whole-row taps on iOS 26.

**Scope — do NOT assume universal use in the redesigned destinations.** `OpenClawToggleIndicator` (and the `settingsToggle` helper) belongs to the legacy `SettingsProTab` list surface. The redesigned **`VoiceSettingsScreen`** does NOT use it: both its master switch ("Talk Mode") and every sub-toggle ("Voice Wake", "Background Listening", "Speakerphone") are bare SwiftUI `Toggle(isOn:)` controls — see §4.6. A rebuilder must use native `Toggle` for Voice Settings, not the custom indicator.

Source: `OpenClawProComponents.swift:536–551`, `SettingsProTabSections.swift:1174–1198`, `SettingsDestinationScreens.swift:581–648` (native-`Toggle` carve-out).

---

## 2  Navigation Architecture

### 2.1  Entry Point

The Settings surface is accessed from `RootTabs.phoneTabContent` via a `PhoneTabSettingsHost`. This wraps a `NavigationStack(path: $settingsPath)` containing the chat root; when the user taps the Settings icon the host pushes `SettingsRoute.home` onto the stack, rendering `SettingsRootContainer` as a destination. All subsequent row taps from the root screen append additional `SettingsRoute` values to the same stack. Back is always `settingsPath.removeLast()`.

**Critical design rule:** `SettingsRootContainer` does NOT own its own `NavigationStack`. It renders inside the host's existing stack and pushes via `onOpenRoute`. A nested stack mis-renders and glitches the back gesture.

Source: `SettingsRootScreen.swift:346–401`, `RootTabs.swift:1631–1697`.

### 2.2  Route Map (`SettingsRoute` enum)

| Case | Rendered by |
|---|---|
| `.home` | `SettingsRootContainer` → `SettingsRootScreen` |
| `.approvals` | `ApprovalsScreen` (redesigned) |
| `.permissions` | `PermissionsScreen` (redesigned) |
| `.notifications` | `NotificationsScreen` (redesigned) |
| `.channels` | `ChannelsScreenHost` → `ChannelsScreen` (redesigned) |
| `.voice` | `VoiceSettingsScreenHost` → `VoiceSettingsScreen` (redesigned) |
| `.wakeWords` | `WakeWordsScreenHost` → `WakeWordsScreen` (redesigned) |
| `.licenses` | `LicensesScreen` (redesigned) |
| `.gateway`, `.diagnostics`, `.privacy`, `.about` | `SettingsProTab(directRoute:)` (legacy `List`-based) |
| Connection | `ConnectionSheetHostView` → `ConnectionSheet` (modal, not pushed) |

Source: `SettingsProTabSupport.swift:6–20`, `RootTabs.swift:1640–1676`.

### 2.3  Connection Sheet Presentation

The Connection sheet is presented as a **page-sheet from the window root** (`phoneTabContent`), not from inside the Settings navigation stack. This is intentional: presenting from the window root produces the native iOS page-sheet card-recede animation (the app view recedes behind the sheet), which is suppressed when presented from deep in a navigation stack.

Source: `SettingsRootScreen.swift:351–357` (comment at line 356).

### 2.4  Swipe-to-go-back

Every pushed destination inside `PhoneTabSettingsHost` has a `SwipeToGoBack` modifier applied. This is a full-screen left→right swipe that calls `settingsPath.removeLast()`. While a swipe is in progress (`swipeBackActive = true`) row taps are gated out to prevent a race condition where a swipe gesture passing over a list row both pushes AND pops the stack, leaving a dangling destination.

Source: `RootTabs.swift:1607–1608,1677–1681`.

---

## 3  Settings Root Screen (`SettingsRootScreen`)

### 3.1  View Hierarchy

```
ZStack(alignment: .top)
├── canvas (Color)                        ignoresSafeArea
├── ScrollView
│   └── VStack(alignment: .leading, spacing: 26)
│       ├── connectionPill
│       ├── section("Control") { … }
│       ├── section("App settings") { … }
│       ├── section("Appearance") { … }
│       ├── section("Reference") { … }
│       └── section("Licenses & agreements") { … }
│   .padding(.horizontal, 24)
│   .padding(.top, 72)       // clear the floating header
│   .padding(.bottom, 40)
├── .overlay(topScrim)       // frosted gradient band at top
└── .overlay(header)         // floating nav header
```

Source: `SettingsRootScreen.swift:37–89`.

### 3.2  Frosted Top Scrim

Layered above the content scroll via `.overlay(alignment: .top)`. Never intercepts taps (`.allowsHitTesting(false)`).

- **Material:** `.ultraThinMaterial`
- **Dark-mode tint:** in dark mode, the canvas color (`rgb(23,23,23)`) overlaid at opacity **0.72** (`colorScheme == .dark ? 0.72 : 0`). This prevents the light-colored blur material from making the dark header band look washed out.
- **Mask gradient:** `LinearGradient` top→bottom:
  - stop 0 → `.black.opacity(0.6)`, location 0
  - stop 1 → `.black.opacity(0.6)`, location 0.55
  - stop 2 → `.clear`, location 1
- **Frame:** height 110 pt, max-width infinite, `ignoresSafeArea(edges: .top)`.

Source: `SettingsRootScreen.swift:92–112`.

### 3.3  Section Builder

`func section(_ title: String, @ViewBuilder content: () -> some View) -> some View`:

```
VStack(alignment: .leading, spacing: 5)
├── Text(title)                           // SF Pro medium 17pt, Color.primary.opacity(0.5)
│   .padding(.leading, 17)                // ← 17pt leading is on the Text, NOT the VStack
└── VStack(spacing: 17)                  // row spacing = 17pt → ~34pt between row centers
    { content() }
    .padding(.vertical, 12)
    .openClawSectionBackground(cardFill)  // cornerRadius 12, continuous
```

The `.padding(.leading, 17)` is applied to the header `Text` itself (inside the outer `VStack`), not to the `VStack`. The section card uses `.openClawSectionBackground` which provides `cornerRadius: 12`. Horizontal padding is **NOT** on the card; it lives on each row via `rowInset()` so `OpenClawRowDivider` spans the full card width edge-to-edge.

Source: `SettingsRootScreen.swift:151–165`.

### 3.4  Connection Pill (top row, outside all sections)

```
Button(onOpenConnection) {
    HStack(spacing: 12)
    ├── Image("SettingsWifiGlyph")       // 22×22pt, template, OpenClawBrand.welcomeLink blue
    └── Text("Connection")               // OpenClawType.body, OpenClawBrand.welcomeLink blue
    Spacer(minLength: 0)
    .padding(.leading, 16)               // leading-only; NO trailing padding
    .frame(height: 50, maxWidth: .infinity)
    .openClawSectionBackground(cardFill)
}                                        // NO .buttonStyle(.plain) — default iOS button style
```

Padding is **leading-only** (`.padding(.leading, 16)`); do not add symmetric trailing padding. The right edge is produced by `Spacer(minLength: 0)` expanding inside `.frame(maxWidth: .infinity)`. The button also **does not** apply `.buttonStyle(.plain)` (unlike the card rows in §3.6), so the pill shows the default iOS tap-highlight state; this absence is intentional, not an oversight.

Source: `SettingsRootScreen.swift:168–188`.

### 3.5  Section Inventory

| Section title | Row title | Glyph asset | Trailing |
|---|---|---|---|
| Control | Approvals | `SettingsShieldGlyph` | `SettingsChevronRightGlyph` (20×20) |
| Control | Permissions | `SettingsToggleGlyph` | `SettingsChevronRightGlyph` |
| Control | Default Agent | `SettingsUsersGlyph` | Menu with agent names (admin + >1 agent) or plain value label |
| App settings | Notifications | `SettingsBellGlyph` | `SettingsChevronRightGlyph` |
| App settings | Channels & Integrations | `SettingsUnplugGlyph` | `SettingsChevronRightGlyph` |
| App settings | Voice settings | `SettingsWaveformGlyph` | `SettingsChevronRightGlyph` |
| Appearance | Theme | `SettingsSunGlyph` | Menu with "System / Light / Dark" + `SettingsChevronsUpDownGlyph` |
| Reference | Docs | `SettingsBookGlyph` | `SettingsArrowUpRightGlyph` (20×20) — opens `https://docs.openclaw.ai` via `openURL` |
| Licenses & agreements | Licenses | `SettingsFileWarningGlyph` | `SettingsChevronRightGlyph` |

All icon images use `.renderingMode(.template)`, `.resizable()`, `.scaledToFit()`, frame 22×22 pt, `.foregroundStyle(Color.primary.opacity(0.7))`. Trailing chevron / arrow: 20×20 pt, `.foregroundStyle(Color.primary)`. Row separators are `OpenClawRowDivider()` between rows within the same section.

Source: `SettingsRootScreen.swift:43–78`.

### 3.6  Standard Card Row (`cardRow`)

```
Button(action) {
    rowInset(
        HStack(spacing: 12)
        ├── Image(icon) — 22×22pt, template, Color.primary.opacity(0.7)
        ├── Text(title) — OpenClawType.body, Color.primary
        ├── Spacer(minLength: 0)
        └── Image("SettingsChevronRightGlyph") — 20×20pt, Color.primary
        .contentShape(Rectangle())
    )
}
.buttonStyle(.plain)
```

`rowInset` = `.padding(.leading, 17).padding(.trailing, 12)`.

Source: `SettingsRootScreen.swift:190–222`.

### 3.7  Default Agent Row

Non-tappable row (no `Button` wrapper). Trailing varies:
- If `hasAdminScope == true` AND `agentOptions.count > 1`: a `Menu` listing all agents. Menu label uses `pickerTrailing(defaultAgent?.name ?? "—")` (see §3.8).
- Otherwise: plain `Text(defaultAgent?.name ?? "—")` in `OpenClawType.callout`, `Color.primary.opacity(0.6)`.

**Displayed label fallback is the em dash `"—"`, NOT `agent.id`.** Both the `Menu` label and the plain-text branch render `self.defaultAgent?.name ?? "—"`. The `agent.id` fallback is a different thing: it is used only inside `SettingsRootContainer.agentOptions` when *building picker option labels* (so each menu entry has a stable display string), never in the trailing display label. A rebuilder must render `"—"` when there is no default agent, not an id.

The displayed name itself is the agent's `name` as stored. The selection resolves: `selectedAgentId` > `gatewayDefaultAgentId` > first in list.

Source: `SettingsRootScreen.swift:224–252` (display label), `SettingsRootScreen.swift:382–401` (`agentOptions` id fallback).

### 3.8  Theme Row and Picker Trailing

```
rowInset(
    HStack(spacing: 12)
    ├── Image("SettingsSunGlyph") — 22×22pt, template, Color.primary.opacity(0.7)
    ├── Text("Theme") — OpenClawType.body, Color.primary
    ├── Spacer(minLength: 0)
    └── Menu { … System / Light / Dark … } label: { pickerTrailing(theme.rawValue) }
    .frame(height: 26)
)
```

`pickerTrailing(_ value: String)`:
```
HStack(spacing: 7)
├── Text(value) — OpenClawType.callout, Color.primary.opacity(0.6)
└── Image("SettingsChevronsUpDownGlyph") — 20×20pt, template, Color.primary (full strength; glyph bakes its own opacity)
```

Source: `SettingsRootScreen.swift:256–322`.

### 3.9  Link Pill Row (Docs)

Like `cardRow` but uses `openURL` instead of navigation. Trailing glyph is `SettingsArrowUpRightGlyph` (20×20) at `Color.primary` full strength (same comment: glyph bakes its own 0.3 opacity).

Source: `SettingsRootScreen.swift:281–307`.

---

## 4  Destination Screens

All destinations share:
- `SettingsDestinationChrome` for canvas + header (§1.6).
- Section cards use `VStack(spacing: 17) { rows }.padding(.vertical, 14).openClawSectionBackground(cardFill)`.
- Row horizontal insets are on the **rows** (not the card) so `OpenClawRowDivider` is full-bleed.
- `.onAppear` and `NotificationCenter.didBecomeActive` refresh live permission data where applicable.

### 4.1  Approvals Screen (`ApprovalsScreen`)

Current state: empty-state only design. Body is `SettingsDestinationChrome(title: "Approvals")` containing a `VStack` with `Text("No approvals yet.")` in `OpenClawType.body`, `Color.primary`, `.padding(.top, 32)`. Full-featured design is pending.

Source: `SettingsDestinationScreens.swift:72–86`.

### 4.2  Permissions Screen (`PermissionsScreen`)

**Structure:**

```
SettingsDestinationChrome(title: "Permissions")
└── ScrollView
    └── VStack(spacing: 17)
        ├── row("PermissionsPinGlyph",       "Location",    statuses.location)
        ├── OpenClawRowDivider()
        ├── row("PermissionsCalendarGlyph",  "Calendar",    statuses.calendar)
        ├── OpenClawRowDivider()
        ├── row("PermissionsClipboardGlyph", "Reminders",   statuses.reminders)
        ├── OpenClawRowDivider()
        ├── row("PermissionsContactGlyph",   "Contacts",    statuses.contacts)
        ├── OpenClawRowDivider()
        ├── row("PermissionsMicGlyph",       "Microphone",  statuses.microphone)
        ├── OpenClawRowDivider()
        ├── row("PermissionsImageGlyph",     "Photos",      statuses.photos)
        ├── OpenClawRowDivider()
        └── row("PermissionsCameraGlyph",    "Camera",      statuses.camera)
        .padding(.vertical, 14)
        .openClawSectionBackground(cardFill)
        .padding(.horizontal, 24)
        .padding(.top, 4)
```

**Permission row anatomy:**

```
Button(action: openSettingsURL) {
    HStack(spacing: 12)
    ├── Image(icon) — 22×22pt, template, Color.primary.opacity(0.7)
    ├── Text(title) — OpenClawType.body, Color.primary
    ├── Spacer(minLength: 0)
    ├── Text(value) — OpenClawType.callout, Color.primary.opacity(0.6)
    └── Image("SettingsChevronRightGlyph") — 20×20pt, Color.primary
    .padding(.horizontal, 12)
    .contentShape(Rectangle())
}
.buttonStyle(.plain)
```

Row inset is 12 pt horizontal (unlike root screen's 17/12 split; here both sides are 12 via `.padding(.horizontal, 12)`).

**Permission status labels** (`PermissionStatuses`):

| Permission | Possible values |
|---|---|
| Location | "Always" / "While Using" / "Never" |
| Calendar | "Allowed" / "Write Only" / "Not allowed" |
| Reminders | "Allowed" / "Write Only" / "Not allowed" |
| Contacts | "Allowed" / "Limited" / "Never" |
| Microphone | "While Using" / "Never" |
| Photos | "Always Allowed" / "Limited" / "Never" |
| Camera | "While Using" / "Never" |

**Refresh triggers:** `.onAppear` + `UIApplication.didBecomeActiveNotification` (to reflect changes made in Settings.app while the app was backgrounded). Reading statuses does NOT trigger a permission prompt; tapping any row opens `UIApplication.openSettingsURLString`.

Source: `SettingsDestinationScreens.swift:90–242`.

### 4.3  Notifications Screen (`NotificationsScreen`)

**Structure:**

```
SettingsDestinationChrome(title: "Notifications")
└── ScrollView
    └── Button(action: requestOrOpenSettings) {   // Button is a DIRECT child of ScrollView — no wrapper VStack
        HStack
        ├── Text("Allow Notifications") — OpenClawType.body, OpenClawBrand.welcomeLink
        ├── Spacer(minLength: 0)
        └── Text(authorized ? "Enabled" : "Disabled") — OpenClawType.callout, Color.primary.opacity(0.6)
        .padding(.horizontal, 16)        // ↓ these four modifiers are all on the Button, NOT a wrapper view
        .frame(height: 50)
        .openClawSectionBackground(cardFill)
    }
    .padding(.horizontal, 24)
    .padding(.top, 4)
```

The `Button` is the only (direct) child of the `ScrollView`; there is no enclosing `VStack`. The pill geometry modifiers (`.padding(.horizontal, 16)`, `.frame(height: 50)`, `.openClawSectionBackground`) are on the button's label content, and the outer `.padding(.horizontal, 24)` / `.padding(.top, 4)` are on the button itself.

**Button behavior (`requestOrOpenSettings`):**
- If authorization status is `.notDetermined`: calls `UNUserNotificationCenter.requestAuthorization(options: [.alert, .badge, .sound])`. On grant, sets `authorized = true`.
- Any other status: opens `UIApplication.openSettingsURLString`.

**Authorized determination (`refreshAuthorization`):** `authorized = (status == .authorized || status == .provisional)`. Both `.authorized` **and `.provisional`** render "Enabled"; a rebuilder that treats only `.authorized` as enabled would wrongly show "Disabled" for provisionally authorized users.

**Refresh triggers:** `.onAppear` + `UIApplication.didBecomeActiveNotification`.

Source: `SettingsDestinationScreens.swift:246–311` (provisional at `287–291`; button-as-direct-child at `255–270`).

### 4.4  Channels Screen (`ChannelsScreen` / `ChannelsScreenHost`)

`ChannelsScreenHost` fetches live data via `channels.status` gateway RPC and maps entries to `SettingsChannelItem`. `ChannelsScreen` is a pure display component with injected data.

**Header** (custom, not `SettingsDestinationChrome`):

```
ZStack {
    Text("Channels") — SF Pro medium 20pt, Color.primary
    HStack {
        back button — 40×40 glass circle; Image(systemName: "chevron.left") SF Pro semibold 17pt,
                       .background { ChatGlassBackground(shape: Circle(), fill: glassFill) }
                       — NO individual .shadow on the button
        Spacer()
        if hasAdminScope && !channels.isEmpty:
            Button("Edit" / "Done") {
                withAnimation(.smooth(duration: 0.2)) { editing.toggle() }
            }
            .font(OpenClawType.subhead)
            .foregroundStyle(Color.primary)
            .frame(width: 55, height: 33)
            .background { ChatGlassBackground(fill: glassFill) }   // shape: OMITTED (default shape, NOT Circle())
    }
    .padding(.horizontal, 24)
    .shadow(color: .black.opacity(0.15), radius: 25, x: 0, y: 0)   // shadow is on the HStack, not any button
}
.padding(.top, 8)
.padding(.bottom, 29)
```

Header bottom padding is **29 pt** (vs 21 pt for other destinations).

**Shadow placement (differs from `SettingsDestinationChrome`):** In the shared chrome (§1.6) the glass circle back button carries its own `.shadow(…radius: 25…)`. Here the back button has **no** individual shadow; the `.shadow(color: .black.opacity(0.15), radius: 25, x: 0, y: 0)` sits on the enclosing `HStack` (after `.padding(.horizontal, 24)`). The same structural pattern applies to the Wake Words header (§4.7).

**Edit/Done glass background:** the `Edit`/`Done` button's `ChatGlassBackground(fill: glassFill)` **omits the `shape:` argument**, so it uses `ChatGlassBackground`'s default shape — do **not** pass `shape: Circle()` (which is used only for the 40×40 circular buttons).

**Body:**

```
ZStack(alignment: .top)
├── canvas.ignoresSafeArea()
└── ScrollView
    └── VStack(spacing: 29)               // 29pt between channel pills
        ├── channelPill(channel) × N
        └── addChannelPill (if hasAdminScope)
    .padding(.horizontal, 24)
    .padding(.top, 4)
```

**Channel Pill:**

```
HStack(spacing: 12)
├── Image(iconAsset OR "SettingsUnplugGlyph")    // 22×22pt
│   (iconAsset: Original rendering; fallback: template at Color.primary.opacity(0.7))
├── Text(channel.name) — OpenClawType.body, Color.primary
├── Spacer(minLength: 0)
└── editing:
│     Button { haptics.error(); onRemoveChannel(channel) }
│     Image(systemName: "minus.circle.fill") — size 20pt, destructiveRed
    not editing && connected:
│     Image("SetupCheckGlyph") — 20×20pt (scaledToFit)
.padding(.horizontal, 17)
.frame(height: 50)
.background { Capsule(style: .continuous).fill(pillFill) }
```

`pillFill`: same as `cardFill` (dark: `rgb(10,10,10)`, light: `.white`). **Shape is a `Capsule`**, not a `RoundedRectangle`.

**Known brand asset IDs:** `"telegram"` → `"ChannelTelegramGlyph"`, `"discord"` → `"ChannelDiscordGlyph"`, `"whatsapp"` → `"ChannelWhatsappGlyph"`. Any unknown id uses the `nil` fallback glyph (`SettingsUnplugGlyph`).

**Add Channel Pill** (admin only, shown when `hasAdminScope`):

Same capsule geometry as channel pill, but uses `ChatPlusGlyph` in `OpenClawBrand.welcomeLink` blue, text "Add Channel" in `welcomeLink`, opens `https://docs.openclaw.ai/start/getting-started` via `openURL`.

**Remove flow:** Tapping the remove button fires `OpenClawHaptics.error()` immediately, then calls `onRemoveChannel`. The host calls `channels.logout` for every account of the channel, then reloads.

**Data reload:** re-fetches on `task(id: reloadKey)` where the `ChannelsScreenHost` reload key is exactly:

```swift
private var reloadKey: String {
    "\(self.appModel.isOperatorGatewayConnected)-\(self.scenePhase == .active)"
}
```

The connection term is `appModel.isOperatorGatewayConnected` — there is **no** `isConnected` property at this call site, so wiring based on a generic `isConnected` boolean would not compile. Refreshes when gateway connection state or scene phase changes.

Source: `SettingsDestinationScreens.swift:313–557`.

### 4.5  Channels Destination – List view (`SettingsChannelsDestination`)

Used inside `SettingsProTabSections.destination(for: .channels)` and `ChatDrawer`. This is a richer list-style view with summary card and per-account controls.

**Layout:** `VStack(alignment: .leading, spacing: 14)` containing:
1. `summaryCard` (optional, `showsSummaryCard: Bool`): `ProCard` with `ProIconBadge`, title "Channels / Integrations", detail text, `ProValuePill` status chip.
2. `channelsCard`: `ProCard(padding: 0, radius: SettingsLayout.cardRadius)` with `ProPanelHeader("Message Routing", value: count)` and per-channel `SettingsChannelRow`.

**Two distinct dividers — note the different leading insets:**
- **Between `SettingsChannelRow`s** (channel-to-channel, inside `channelsCard`): `Divider().padding(.leading, 58)`. Rendered only for `index > 0` in the `ForEach` over channel entries. If no channel plugins are reported, a `ProStatusRow` empty state is shown instead (icon `"tray"`, title "No channel plugins reported", detail "Install or enable channel plugins on the gateway, then refresh.", value "empty", color `.secondary`).
- **Between accounts** (inside a single `SettingsChannelRow`): `Divider().padding(.leading, 38)` (see per-account section below).

A rebuilder must not apply 38 pt to all dividers; the channel-level divider is 58 pt.

Source: `SettingsChannelsDestination.swift:88–98` (channel-level 58pt divider + empty state).

**Per-channel row** (`SettingsChannelRow`):

```
VStack(alignment: .leading, spacing: 10)
├── HStack(alignment: .top, spacing: 12)
│   ├── ProIconBadge(systemName, color)
│   ├── VStack(alignment: .leading, spacing: 4)
│   │   ├── Text(label) — OpenClawType.subheadSemiBold
│   │   ├── Text(detailText) — OpenClawType.caption, .secondary
│   │   └── [Text(lastError) — OpenClawType.caption2Medium, OpenClawBrand.warn]
│   ├── Spacer(minLength: 8)
│   └── ProValuePill(statusValue, color)
└── if !accounts.isEmpty:
    VStack(spacing: 0)
    ForEach accounts:
        [Divider().padding(.leading, 38)]
        accountRow(account)
.padding(.horizontal, 14)
.padding(.vertical, 10)
```

**Per-account row:**

```
HStack(spacing: 10)
├── Image(systemName: running||connected ? "checkmark.circle.fill" : "circle")
│   — OpenClawType.captionSemiBold, account.color, frame 28×28
├── VStack(alignment: .leading, spacing: 2)
│   ├── Text(displayName) — OpenClawType.captionSemiBold
│   └── Text(detailText) — OpenClawType.caption2, .secondary
├── Spacer(minLength: 8)
└── Menu { Start/Stop/Logout buttons } label: { Image(systemName: actionMenuIcon(account)) }
    .buttonStyle(.bordered).controlSize(.mini)
    .disabled(!canAdmin || isBusy(account))
.padding(.vertical, 8)
```

**Menu icon precedence (`actionMenuIcon`) — exact branch order:**
1. If `isBusy(account)` → `"hourglass"` (checked first).
2. Else if `!canAdmin` → `"lock.shield"`.
3. Else → `"ellipsis.circle"`.

`isBusy(account)` is true when `busyOperation?.channelID == entry.id && busyOperation?.accountID == account.id`. A rebuilder cannot infer this precedence from the icon set alone; busy always wins over the admin-lock icon.

Source: `SettingsChannelsDestination.swift:448–460`.

**Channel status values:** "connected" → "running" → "linked" → "configured" → "not set". Color: ok (connected/running), warn (lastError), accent (configured but idle), secondary (unconfigured).

**State palettes:**
- Connected/running: `OpenClawBrand.ok`
- Error: `OpenClawBrand.warn`
- Configured idle: `OpenClawBrand.accent`
- Unconfigured: `.secondary`

Source: `SettingsChannelsDestination.swift`.

### 4.6  Voice Settings Screen (`VoiceSettingsScreen` / `VoiceSettingsScreenHost`)

**Structure:**

```
SettingsDestinationChrome(title: "Voice Settings")
└── ScrollView
    └── VStack(alignment: .leading, spacing: 26)
        ├── Toggle(isOn: $talkModeEnabled) { Text("Talk Mode") } — master switch
        │   // bare SwiftUI Toggle — NOT OpenClawToggleIndicator (see §1.7 carve-out)
        │   .padding(.horizontal, 17)
        │   .frame(height: 50)
        │   .openClawSectionBackground(cardFill)
        │
        └── Group { voiceSections }
            .opacity(talkModeEnabled ? 1 : 0.4)
            .disabled(!talkModeEnabled)
            .animation(.smooth(duration: 0.2), value: talkModeEnabled)
    .padding(.horizontal, 24)
    .padding(.top, 4)
```

**Section builder** (`voiceSection`):

```
VStack(alignment: .leading, spacing: 5)
├── Text(title) — SF Pro medium 17pt, Color.primary.opacity(0.5)
│   .padding(.leading, 15)
└── VStack(spacing: 17) { content }
    .padding(.vertical, 14)
    .openClawSectionBackground(cardFill)
```

Section leading inset is **15 pt** (vs 17 pt on the root screen). Row inset is also 15 pt via `rowInset`.

**Sections:**

`Permissions` section (rows separated by `OpenClawRowDivider()`):
- Toggle row: "Voice Wake" — bound to `$voiceWake`
- Toggle row: "Background Listening" — bound to `$backgroundListening`
- Toggle row: "Speakerphone" — bound to `$speakerphone`

`Language & Gateway` section:
- Picker row: "Language" — `Menu` (admin only) listing language display labels; without admin shows plain value.
- Picker row: "Provider" — same pattern.
- "Wake Words" → navigation button (chevron right).

**Toggle row** (`toggleRow`): a **bare SwiftUI `Toggle`** wrapped only in `rowInset` (15 pt horizontal). This screen does **not** use `OpenClawToggleIndicator` anywhere — neither the master switch nor these sub-toggles (see §1.7).
```
rowInset(Toggle(isOn: isOn) {
    Text(title) — OpenClawType.body, Color.primary
})
```

**Picker row** (`pickerRow`):
```
rowInset(
    HStack {
        Text(title) — OpenClawType.body, Color.primary
        Spacer(minLength: 0)
        if hasAdminScope:
            Menu { … } label: { pickerValue(value, withChevrons: true) }
        else:
            pickerValue(value, withChevrons: false)
    }
)
```

`pickerValue(withChevrons: true)` = `HStack(spacing: 7) { Text(value) callout+0.6opacity, Image("SettingsChevronsUpDownGlyph") 20×20 fullstrength }`.

**Master-switch side-effect:** When `talkEnabled` changes, `onChange` calls `appModel.setTalkEnabled`. When `voiceWakeEnabled` changes, `appModel.setVoiceWakeEnabled`.

Source: `SettingsDestinationScreens.swift:559–765`.

### 4.7  Wake Words Screen (`WakeWordsScreen` / `WakeWordsScreenHost`)

**Custom header** (distinct from `SettingsDestinationChrome`):

```
ZStack {
    Text("Wake Words") — SF Pro medium 20pt, Color.primary
    HStack {
        back button — standard glass circle
        Spacer()
        Button { showsAddAlert = true }
        Image("ChatPlusGlyph") — 24×24pt, template, Color.primary
            .frame(40×40)
            .background { ChatGlassBackground(shape: Circle(), fill: glassFill) }
    }
    .padding(.horizontal, 24)
    .shadow(color: .black.opacity(0.15), radius: 25, x: 0, y: 0)
}
.padding(.top, 8)
.padding(.bottom, 25)          // 25pt (vs 21pt SettingsDestinationChrome)
```

**Body:**

```
ZStack(alignment: .top)
├── canvas.ignoresSafeArea()
└── ScrollView
    └── VStack(spacing: 0)
        ├── ForEach words:
        │   wordRow(word)
        │   OpenClawRowDivider()
        └── resetButton
        .padding(.vertical, 8)
        .openClawSectionBackground(cardFill)
        .padding(.horizontal, 24)
        .padding(.top, 4)
```

**Word row:**
```
HStack {
    Text(word) — OpenClawType.body, Color.primary
    Spacer(minLength: 0)
}
.frame(height: 40)
.padding(.horizontal, 15)
.contentShape(Rectangle())
.contextMenu {
    Button(role: .destructive) { haptics.error(); onRemoveWord(word) }
    Label("Remove", systemImage: "trash")
}
```

**Reset button:**
```
HStack(spacing: 12)
├── Image("SettingsRefreshGlyph") — 22×22pt, template, WakeWords.resetRed
└── Text("Reset Defaults") — OpenClawType.body, WakeWords.resetRed
.frame(height: 44)
.padding(.horizontal, 15)
```

`WakeWords.resetRed` = `Color(red: 195/255, green: 63/255, blue: 51/255)`.

**Add button (header):** tapping the `+` button runs `self.newWord = ""` **then** `self.showsAddAlert = true`. The pre-reset to `""` is required — without it, reopening the alert would show the previously typed word.

**Add word alert:** `alert("New Wake Word", isPresented: $showsAddAlert)` with a `TextField("wake word", text: $newWord)`, "Add" / "Cancel" buttons, and a **message body** `Text("The phrase your gateway listens for.")`. "Add" trims + lowercases, skips if empty or duplicate, fires `OpenClawHaptics.tap()`, then `onAddWord(trimmed)`.

Source: `SettingsDestinationScreens.swift:810–818` (message body), `837–838` (`newWord` pre-reset).

**Storage + host:** `WakeWordsScreenHost` owns `@State var words` seeded from `VoiceWakePreferences.loadTriggerWords()`. Add/remove/reset calls `VoiceWakePreferences.sanitizeTriggerWords`, saves to prefs, and calls `appModel.setGlobalWakeWords(sanitized)` asynchronously.

Source: `SettingsDestinationScreens.swift:769–946`.

### 4.8  Licenses Screen (`LicensesScreen`)

**Structure:**

```
SettingsDestinationChrome(title: "Licenses")
└── ScrollView
    ├── if documents.isEmpty:
    │     Text("License files are not available in this build.")
    │     — OpenClawType.body, Color.primary.opacity(0.6)
    │     .padding(.top, 32)
    └── else:
          card (VStack)
          Text("OpenClaw appreciates its partners in the open-source community.")
          — OpenClawType.footnote, Color.primary.opacity(0.5)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 40)
          .padding(.top, 20)
```

**Card:**

```
VStack(spacing: 17)                           // ← all of these modifiers are on THIS inner VStack
ForEach (index, document) in documents:
├── row(document)
└── if index < count - 1: divider
.padding(.vertical, 14)
.padding(.horizontal, 15)                      // 15pt horizontal is on the inner VStack, not an outer container
.openClawSectionBackground(cardFill)           // cardFill = (dark ? .black : .white), both explicit
.padding(.horizontal, 24)                       // page inset applied AFTER the card background
.padding(.top, 4)
.accessibilityIdentifier("settings-licenses-list")
```

The `.padding(.horizontal, 15)` and `.padding(.vertical, 14)` are on the inner row `VStack` (the content inside the card background); the `.padding(.horizontal, 24)` page inset is applied **after** `.openClawSectionBackground`, so the 15 pt sits inside the card and 24 pt sits outside it.

Note: `cardFill` for `LicensesScreen` is explicitly `colorScheme == .dark ? .black : .white` — the dark value is pure `.black` (not `rgb(10,10,10)` as other section cards use) and the light value `.white` is set explicitly, not relied on as a default. Source: `LicenseDocuments.swift:155–157`.

**License row:**
```
NavigationLink {
    LicenseDocumentDetailView(document: document)
} label: {
    HStack {
        Text(document.title) — OpenClawType.body, Color.primary
        Spacer(minLength: 0)
        Image("SettingsChevronRightGlyph") — 20×20pt, Color.primary
    }
    .contentShape(Rectangle())
}
.buttonStyle(.plain)
```

**Divider:** `Rectangle().fill(Color.primary.opacity(0.3)).frame(maxWidth: .infinity).frame(height: 1/displayScale)`. This is a **crisp single-pixel hairline** at `0.3` opacity — different from `OpenClawRowDivider` (which uses the canvas color). Used only here in the Licenses redesign.

Source: `LicenseDocuments.swift:147–153`.

**License detail view (`LicenseDocumentDetailView`):**

Wrapped in `SettingsDestinationChrome(title: document.title, onBack: { dismiss() })`. Body:
```
ScrollView {
    Text(verbatim: document.body)
    — OpenClawType.monoFootnote (JetBrains Mono Regular 13pt)
    — Color.primary
    — .textSelection(.enabled)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 24)
    .padding(.top, 4)
    .padding(.bottom, 24)
}
```

Source: `LicenseDocuments.swift:160–180`.

---

## 5  Connection Sheet (`ConnectionSheet`)

### 5.1  Presentation

Presented as a **page sheet from the window root**, not from inside the settings stack. This allows the native iOS card-recede animation (app view recedes behind the sheet). The `ConnectionSheetHostView` is the data-wired wrapper; `ConnectionSheet` is a pure display view.

Source: `SettingsRootScreen.swift:356`, `RootTabs.swift:1121`.

### 5.2  Layout

```
ZStack(alignment: .top)
├── canvas.ignoresSafeArea()
├── ScrollView
│   └── VStack(spacing: 0)
│       ├── Image("ConnectionMascotImage") — 139×139pt, scaledToFit, .padding(.top, 56)
│       ├── Text(disclaimer) — OpenClawType.subhead, Color.primary.opacity(0.6)
│       │   .multilineTextAlignment(.center)
│       │   .frame(width: 301)
│       │   .padding(.top, 22)
│       ├── Button("Disconnect") — .padding(.top, 24)
│       │   SF Pro medium 17pt, .white, height 50pt, maxWidth .infinity
│       │   background: Capsule().fill(destructiveRed #C53E38)
│       ├── sectionLabel("Paired Gateways") — .padding(.top, 37)
│       ├── pairedGatewaysCard — .padding(.top, 5)
│       ├── sectionLabel("Gateway Access") — .padding(.top, 26)
│       ├── accessRow — .padding(.top, 5)
│       └── [accessNote] — .padding(.top, 12) (limited access only)
│       .padding(.horizontal, 24)
│   Spacer(minLength: 40)
└── .overlay(alignment: .topLeading) { closeButton }
```

**Disclaimer text:** "Clicking disconnect will clear all gateway credentials and reset onboarding."

### 5.3  Close Button

Positioned `.topLeading` via `.overlay`. `.padding(.leading, 25).padding(.top, 22)`.

```
Button(onClose) {
    Image("ChatCloseGlyph") — 22×22pt, template, Color.primary
    .frame(40×40)
    .background { ChatGlassBackground(shape: Circle(), fill: glassFill) }
    .shadow(color: .black.opacity(0.15), radius: 25, x: 0, y: 0)
}
```

### 5.4  Section Label

```
Text(text) — SF Pro medium 17pt, Color.primary.opacity(0.5)
.frame(maxWidth: .infinity, alignment: .leading)
.padding(.leading, 15)
```

### 5.5  Paired Gateways Card

```
VStack(spacing: 0)
ForEach (index, gateway) in gateways:
├── Button { if !isFocused { haptics.tap(); pendingSwitch = gateway } } label: {
│     HStack {
│         Text(gateway.name) — OpenClawType.body, Color.primary
│         Spacer(minLength: 0)
│         radio(filled: gateway.isFocused)
│     }
│     .frame(height: 51)
│     .contentShape(Rectangle())
│   }
│   .buttonStyle(.plain)
└── if not last:
    Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 0.5)  // thin separator
.padding(.horizontal, 15)
.openClawSectionBackground(cardFill)
```

**Radio button:**
```
ZStack {
    Circle().strokeBorder(filled ? radioBlue : Color.primary.opacity(0.5), lineWidth: 1.6)
    if filled: Circle().fill(radioBlue).frame(11×11)
}
.frame(20×20)
```

`radioBlue` = `rgb(37, 99, 235)` constant.

**Switch confirmation dialog:** `confirmationDialog("Switch to \(name)?", titleVisibility: .visible)` with "Switch" + "Cancel" buttons, message "OpenClaw will reconnect to this gateway."

### 5.6  Gateway Access Row

```
HStack {
    Text("Levels") — OpenClawType.body, Color.primary
    Spacer(minLength: 0)
    if hasFullAccess:
        Text("Full access") — OpenClawType.callout, Color.primary.opacity(0.6)
    else:
        Menu { Button("Full access") { confirmingFullAccess = true } } label: {
            HStack(spacing: 7) {
                Text("Limited access") — OpenClawType.callout, Color.primary.opacity(0.6)
                Image("SettingsChevronsUpDownGlyph") — 20×20pt, Color.primary
            }
        }
}
.padding(.horizontal, 17)
.frame(height: 50)
.openClawSectionBackground(cardFill)
```

**"Full access" confirmation dialog** (`confirmationDialog(..., isPresented: $confirmingFullAccess, titleVisibility: .visible)`):
- **Title:** `"Switch to full access?"`
- **Action button:** `"Scan QR Code"` (calls `onScanFullAccess()`) — NOT "Switch".
- **Cancel button:** `"Cancel"` (role `.cancel`).
- **Message body:** `"Switching to full access mode requires you to scan a new QR code to take effect."`

(The phrase "Switching to full access mode requires you to scan a new QR code to take effect." is the message body, not the title.)

Source: `ConnectionSheet.swift:244–258`.

### 5.7  Access Note (limited access only)

```
(Text("Switching to ").foregroundColor(Color.primary.opacity(0.6))
 + Text("full access mode").foregroundColor(noteRed)
 + Text(" requires you to scan ").foregroundColor(Color.primary.opacity(0.6))
 + Text("a new qr code").foregroundColor(noteRed)
 + Text(" to take effect").foregroundColor(Color.primary.opacity(0.6)))
 .font(OpenClawType.subhead)
 .frame(maxWidth: .infinity, alignment: .leading)
 .padding(.leading, 15)
```

`noteRed` = `rgb(195, 63, 51)`.

### 5.8  Disconnect Confirmation

`confirmationDialog("Disconnect from this gateway?", titleVisibility: .visible)` with "Disconnect" (destructive) + "Cancel", message "This clears saved gateway credentials and reopens onboarding."

On confirm, the dialog's destructive button invokes the `onDisconnect` closure. `ConnectionSheet` itself only calls `self.onDisconnect()` (`ConnectionSheet.swift:89`); the real work lives in the `ConnectionSheetHostView` closure, which runs in this exact order:

```swift
onDisconnect: {
    self.onClose()                      // 1. dismiss the sheet synchronously first
    Task { await self.disconnect() }    // 2. then async: GatewayOnboardingReset.reset(...)
}
```

So the sheet is closed **before** the async reset runs, and the reset (`GatewayOnboardingReset.reset(appModel:instanceId:)`) is wrapped in a detached `Task` — it clears all gateway credentials and re-opens onboarding. A rebuilder must dismiss first, then run the reset asynchronously, not the reverse.

Source: `ConnectionSheet.swift:84–98`, `SettingsRootScreen.swift:419–453`.

### 5.9  Data Wiring (`ConnectionSheetHostView`)

`ConnectionSheetHostView` re-reads the gateway registry **fresh on every render** (not cached) via `GatewaySettingsStore.loadGatewayRegistry()`. This is intentional: the registry may be populated a beat after the app connects, and the view re-renders on app-model changes that accompany that event. Fresh reads self-heal stale (possibly empty) snapshots.

Source: `SettingsRootScreen.swift:406–454` (comment at line 428).

---

## 6  License Document Loader (`LicenseDocumentLoader`)

### 6.1  Discovery Rules

- Reads all files from the bundle resource directory `"Licenses"` (i.e., `bundle.resourceURL + "Licenses/"`).
- Filters: non-hidden files only (no `.` prefix), extension must be `.txt` (case-insensitive), must be a regular file, body must be non-empty after whitespace trimming.
- Sorted: primary sort by `lhs.title.localizedCaseInsensitiveCompare(rhs.title)` (alphabetical, locale-aware, case-insensitive); secondary sort by `lhs.filename` (ascending) for ties.

### 6.2  Title Derivation

`LicenseDocumentLoader.title(from filename: String) -> String`:

1. Strip the extension (e.g., `"WebRTC.txt"` → `"WebRTC"`).
2. Replace `-` and `_` with spaces.
3. Re-join tokens separated by whitespace (collapses multiple spaces).
4. If the result is empty, fall back to the raw filename.

There is no numeric prefix stripping; filenames must not use numeric prefixes for ordering because ordering is derived from the title, not the filename.

### 6.3  LicenseDocument Model

```swift
struct LicenseDocument: Identifiable {
    let id: String       // = filename (e.g., "WebRTC.txt")
    let title: String    // derived display title
    let filename: String // original filename
    let body: String     // raw UTF-8 file content
}
```

### 6.4  Policy Rules

- Files must be UTF-8 `.txt`. No Markdown, HTML, RTF, or plist formats.
- No numeric filename prefixes for ordering (title comparison drives sort).
- Do NOT add entries for OpenClaw, OpenClaw Foundation, or other first-party licenses.
- License detail is rendered **verbatim** in monospace (`OpenClawType.monoFootnote`) with `.textSelection(.enabled)`.

Source: `LicenseDocuments.swift:1–70`, CLAUDE.md Licenses Screen section.

---

## 7  Shared Glyph Asset Register

Assets referenced in Settings screens. All are in `Sources/Assets.xcassets/`.

| Asset name | Context | Rendering mode |
|---|---|---|
| `SettingsWifiGlyph` | Connection pill icon | template |
| `SettingsShieldGlyph` | Approvals row icon | template |
| `SettingsToggleGlyph` | Permissions row icon | template |
| `SettingsUsersGlyph` | Default Agent row icon | template |
| `SettingsBellGlyph` | Notifications row icon | template |
| `SettingsUnplugGlyph` | Channels & Integrations row icon; fallback channel icon | template |
| `SettingsWaveformGlyph` | Voice settings row icon | template |
| `SettingsSunGlyph` | Theme row icon | template |
| `SettingsBookGlyph` | Docs row icon | template |
| `SettingsFileWarningGlyph` | Licenses row icon | template |
| `SettingsChevronRightGlyph` | Navigation chevron (all nav rows) | template |
| `SettingsArrowUpRightGlyph` | External link indicator | template |
| `SettingsChevronsUpDownGlyph` | Picker trailing chevrons | template |
| `SettingsRefreshGlyph` | Wake Words "Reset Defaults" icon | template |
| `PermissionsPinGlyph` | Location permission row | template |
| `PermissionsCalendarGlyph` | Calendar permission row | template |
| `PermissionsClipboardGlyph` | Reminders permission row | template |
| `PermissionsContactGlyph` | Contacts permission row | template |
| `PermissionsMicGlyph` | Microphone permission row | template |
| `PermissionsImageGlyph` | Photos permission row | template |
| `PermissionsCameraGlyph` | Camera permission row | template |
| `ConnectionMascotImage` | Connection sheet hero | original (not template) |
| `ChatCloseGlyph` | Connection sheet close button | template |
| `ChatPlusGlyph` | Add Channel pill; Wake Words add button | template |
| `SetupCheckGlyph` | Connected channel indicator | original |
| `ChannelTelegramGlyph` | Telegram channel brand mark | original |
| `ChannelDiscordGlyph` | Discord channel brand mark | original |
| `ChannelWhatsappGlyph` | WhatsApp channel brand mark | original |

---

## 8  SettingsIcon Component (Legacy List Destinations)

Used by `SettingsProTab` list-style destinations (gateway, diagnostics, privacy, about):

```
Image(systemName: systemName)
    .font(.system(size: 14, weight: .semibold))
    .foregroundStyle(.white)
    .frame(28×28)
    .background {
        RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color)
    }
```

Source: `SettingsProTabSections.swift:5–16`.

---

## 9  SettingsApprovalRow Component

Used by the legacy approval destination inside `SettingsProTab`:

```
HStack(spacing: 10)
├── Image(systemName: icon) — OpenClawType.captionBold, .white
│   .frame(30×30)
│   .background { RoundedRectangle(cornerRadius: 8, continuous).fill(item.color) }
├── VStack(alignment: .leading, spacing: 2)
│   ├── Text(title) — OpenClawType.subheadSemiBold, lineLimit 1
│   └── Text(detail) — OpenClawType.caption2Medium, .secondary, lineLimit 1
├── Spacer(minLength: 8)
└── Text(priority) — OpenClawType.captionBold, item.color
    .padding(.horizontal, 9).padding(.vertical, 5)
    .background { Capsule().fill(item.color.opacity(0.10)) }
.padding(.vertical, 7)
```

Source: `SettingsProTabSupport.swift:61–96`.

---

## 10  HostedPushRelayDisclosureSheet

Presented from `SettingsProTab` when notifications need the hosted relay disclosure (build-specific). Presentation detents: `.medium` + `.large`, drag indicator visible.

```
VStack(spacing: 18)
├── ScrollView
│   └── VStack(alignment: .leading, spacing: 18)
│       ├── Image(systemName: "network") — OpenClawType.title2SemiBold, OpenClawBrand.accentForeground
│       ├── Text("Enable OpenClaw Hosted Push Relay?") — OpenClawType.title3SemiBold
│       └── Text(message) — OpenClawType.body, .secondary
│       .frame(maxWidth: .infinity, alignment: .leading)
└── VStack(spacing: 10)
    ├── Button("Continue") — .borderedProminent, maxWidth .infinity
    └── Button("Not Now") — .bordered, maxWidth .infinity, role .cancel
.tint(OpenClawBrand.accent)
.padding(24)
```

Source: `SettingsProTab.swift:362–408`.

---

## 11  SettingsDetailRow Component

Canonical key–value row for the legacy `SettingsProTab` list destinations. Used throughout gateway, diagnostics, voice, and about screens.

```
LabeledContent {
    Text(value) — OpenClawType.subhead, lineLimit 1, .truncationMode(.middle)
} label: {
    Text(label) — OpenClawType.body
}
```

Source: `SettingsProTabSupport.swift:29–50`.
