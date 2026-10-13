# Design System & Tokens

This document is the single authoritative reference for every reusable design primitive used in the OpenClaw iOS redesign. It covers the branded typography system (`OpenClawType`), all named color tokens, glass and material backgrounds (`ChatGlassBackground`, `ChatGlassPanel`), scrim gradients, spacing and corner-radius constants, shared component styles, and the haptic vocabulary (`OpenClawHaptics`). An engineer rebuilding any surface from scratch should be able to derive every visual and motion decision from this document without consulting the source files.

---

## 1. Branded Typography — `OpenClawType`

**Source:** `apps/ios/Sources/Design/OpenClawTypography.swift`

### 1.1 Font Families

Three families are bundled as variable/static TTF files inside `apps/ios/Sources/Fonts/`.

| Family | Role | File(s) | PostScript base name |
|---|---|---|---|
| Red Hat Display | Display: titles, subhead semibold/bold | `RedHatDisplay[wght].ttf` | `RedHatDisplay-Regular` |
| Inter | Body: body, callout, subhead regular/medium, footnote, caption | `Inter[opsz,wght].ttf`, `Inter-Italic[opsz,wght].ttf` | `Inter-Regular`, `Inter-Italic` |
| JetBrains Mono | Mono: code, request IDs | `JetBrainsMono-Regular.ttf`, `JetBrainsMono-Medium.ttf`, `JetBrainsMono-SemiBold.ttf` | `JetBrainsMono-Regular`, `JetBrainsMono-Medium`, `JetBrainsMono-SemiBold` |

Both Red Hat Display and Inter are variable fonts. The implementation instantiates a specific variation axis value via `kCTFontVariationAttribute` on a `UIFontDescriptor` and then scales the result through `UIFontMetrics`. Inter additionally sets the optical-size axis (`opsz`) clamped to `[14, 32]` pt to match the requested point size.

Internal axis constants (private, not exposed publicly):

| Name | Axis | Value |
|---|---|---|
| `Display.opticalSemiBold` | `wght` | 650 |
| `Display.opticalBold` | `wght` | 750 |
| `Display.heavyTitle` | `wght` | 800 |
| `Body.regular` | `wght` | 400 |
| `Body.medium` | `wght` | 500 |
| `Body.semiBold` | `wght` | 600 |
| `Body.bold` | `wght` | 700 |
| Font weight axis NSNumber | `wght` | `2_003_265_652` |
| Optical size axis NSNumber | `opsz` | `1_869_640_570` |

### 1.2 Type Scale — `OpenClawType` Static Properties

All `Font` values are `UIFontMetrics`-scaled (Dynamic Type) relative to the stated `UIFont.TextStyle`. The "family" column shows which font family backs each token.

#### Display face (Red Hat Display)

| Token | Size (pt) | wght axis | Relative to | Family |
|---|---|---|---|---|
| `title1` | 34 | 800 (heavyTitle) | `.largeTitle` | Display |
| `title2` | 28 | 800 (heavyTitle) | `.title1` | Display |
| `title2SemiBold` | 28 | 650 (opticalSemiBold) | `.title1` | Display |
| `title3` | 22 | 750 (opticalBold) | `.title2` | Display |
| `title3SemiBold` | 22 | 650 (opticalSemiBold) | `.title2` | Display |
| `headline` | 17 | 650 (opticalSemiBold) | `.headline` | Display |
| `headlineBold` | 17 | 750 (opticalBold) | `.headline` | Display |
| `subheadSemiBold` | 15 | 650 (opticalSemiBold) | `.subheadline` | Display |
| `subheadBold` | 15 | 750 (opticalBold) | `.subheadline` | Display |
| `caption2Bold` | 11 | 750 (opticalBold) | `.caption2` | Display |

#### Body face (Inter)

| Token | Size (pt) | wght axis | Relative to | Family |
|---|---|---|---|---|
| `body` | 17 | 400 | `.body` | Inter |
| `callout` | 16 | 400 | `.callout` | Inter |
| `subhead` | 15 | 400 | `.subheadline` | Inter |
| `subheadMedium` | 15 | 500 | `.subheadline` | Inter |
| `footnote` | 13 | 400 | `.footnote` | Inter |
| `footnoteMedium` | 13 | 500 | `.footnote` | Inter |
| `footnoteSemiBold` | 13 | 600 | `.footnote` | Inter |
| `caption` | 12 | 400 | `.caption1` | Inter |
| `captionMedium` | 12 | 500 | `.caption1` | Inter |
| `captionSemiBold` | 12 | 600 | `.caption1` | Inter |
| `captionBold` | 12 | 700 | `.caption1` | Inter |
| `avatar(size:)` | dynamic | 700 | `.caption1` | Inter |
| `caption2` | 11 | 400 | `.caption2` | Inter |
| `caption2Medium` | 11 | 500 | `.caption2` | Inter |
| `caption2SemiBold` | 11 | 600 | `.caption2` | Inter |

#### Mono face (JetBrains Mono)

| Token | Size (pt) | File weight | Relative to |
|---|---|---|---|
| `mono` | 14 | Regular | `.body` |
| `monoSmall` | 12 | Regular | `.caption1` |
| `monoSmallMedium` | 12 | Medium | `.caption1` |
| `monoCaption2` | 11 | Regular | `.caption2` |
| `monoFootnote` | 13 | Regular | `.footnote` |

### 1.3 UIKit Appearance Overrides

`OpenClawType.installUIKitAppearance()` is called at launch; `OpenClawType.refreshUIKitAppearance(in:)` is called on `UIContentSizeCategory.didChangeNotification` to propagate Dynamic Type changes into already-rendered windows. All UIKit element fonts are capped with `maximumPointSize` so they don't blow out navigation bars.

| UIKit context | Font token | Base size | Max point size |
|---|---|---|---|
| `UINavigationBar` inline title | Inter SemiBold, `.headline`-relative | 17 | 22 |
| `UINavigationBar` large title | Display heavyTitle, `.largeTitle`-relative | 34 | 44 |
| `UITabBarItem` normal | Inter Medium, `.caption2`-relative | 11 | 13 |
| `UITabBarItem` selected | Inter SemiBold, `.caption2`-relative | 11 | 13 |
| `UISegmentedControl` normal | Inter Medium, `.footnote`-relative | 13 | 16 |
| `UISegmentedControl` selected | Inter SemiBold, `.footnote`-relative | 13 | 16 |
| `UIBarButtonItem` normal/highlighted/selected | Inter SemiBold, `.body`-relative | 17 | 22 |
| `UIBarButtonItem` disabled | Inter Regular, `.body`-relative | 17 | 22 |
| `UITextField`, `UITextView`, `UISearchTextField` | Inter Regular, `.body`-relative | 17 | 22 |

Note: `UITextView` and generic `UITextField` receive the appearance proxy font; only `UISearchTextField` instances are individually updated in the walk-and-apply path (`applyUIKitTypography`) — this is intentional (line 241–244 of `OpenClawTypography.swift` explains the distinction).

### 1.4 SF Pro Exceptions (Allowed by the Typography Test)

Certain surfaces intentionally use bare SF Pro system fonts rather than branded tokens. These are encoded as allowlist entries in `OpenClawTypographyTests.swift:440–467`:

| Surface | Allowed system font call |
|---|---|
| `SettingsRootScreen.swift` — Settings title and section headers | `.font(.system(size: 20, weight: .medium))`, `.font(.system(size: 17, weight: .medium))` |
| `ConnectionSheet.swift` — section labels + Disconnect button | `.font(.system(size: 17, weight: .medium))` |
| `SettingsDestinationScreens.swift` — destination titles + section headers | `.font(.system(size: 20, weight: .medium))`, `.font(.system(size: 17, weight: .medium))` |
| `ChatDrawer.swift` — wordmark, session titles, version chip | `.font(.system(size: 25.6, weight: .semibold))`, `.font(.system(size: 17.13))`, `.font(.system(size: 15))`, `.font(.system(size: 14.46))` |

---

## 2. Color Tokens — `OpenClawBrand`

**Source:** `apps/ios/Sources/Design/OpenClawBrand.swift`

All tokens use `UIColor(dynamicProvider:)` so they adapt at render time. RGB values are 0–255 integers. "Light" is `.light` user interface style; "dark" is `.dark`.

### 2.1 Primary Brand Colors

| Token | Light RGB | Dark RGB | Notes |
|---|---|---|---|
| `uiAccent` / `accent` | (183, 56, 51) | (198, 62, 56) | Primary tint; fill for accent surfaces |
| `uiAccentForeground` / `accentForeground` | (183, 56, 51) | (255, 107, 102) | Foreground text on dark surfaces — brighter for contrast |
| `uiAccentHot` / `accentHot` | (204, 75, 69) | (232, 92, 86) | Hotter variant for progress bars |
| `uiAccentHotForeground` / `accentHotForeground` | (166, 55, 50) | (255, 123, 115) | Foreground text on hot accent |
| `uiTeal` / `teal` | (0, 196, 176) | (0, 196, 176) | Same in both modes |
| `uiVoid` / `void` | (246, 247, 249) | (11, 12, 17) | Deep background |
| `uiObsidian` / `obsidian` | (255, 255, 255) | (19, 21, 28) | Elevated surface |
| `uiTextSecondary` / `textSecondary` | (90, 94, 110) | (168, 170, 191) | Secondary label |
| `uiOK` / `ok` | (19, 122, 62) | (48, 209, 88) | Success/connected |
| `uiWarn` / `warn` | (154, 87, 0) | (255, 214, 10) | Warning |
| `uiDanger` / `danger` | (185, 28, 28) | (252, 165, 165) | Error/destructive |
| `uiInfo` / `info` | (0, 91, 196) | (100, 168, 255) | Informational |

Aliases: `graphite` = `void`; `graphiteElevated` = `obsidian`.

### 2.2 Activation / Onboarding Surface Colors

These are specific to the gateway activation and onboarding flow.

| Token | Light RGB | Dark RGB |
|---|---|---|
| `activationCanvas` | (255, 255, 255) | (18, 14, 15) |
| `activationSurface` | (255, 253, 252) | (33, 29, 30) |
| `activationSecondaryActionTop` | (255, 255, 255) | (36, 32, 33) |
| `activationSecondaryActionBottom` | (248, 248, 250) | (30, 27, 28) |
| `activationInsetSurface` | (246, 241, 238) | (44, 37, 38) |
| `activationNeutralSurface` | (242, 242, 247) | (34, 34, 37) |
| `activationNeutralInsetSurface` | (247, 247, 249) | (42, 42, 45) |
| `activationNeutralStroke` | black at 8% opacity | white at 8% opacity |
| `activationNeutralDivider` | black at 9% opacity | white at 9% opacity |
| `activationPrimaryAction` | (209, 54, 51) | (238, 82, 76) |
| `activationPrimaryActionText` | `Color.white` (both modes) | `Color.white` (both modes) |
| `activationHairline` | (136, 44, 40) at 13% | (255, 210, 205) at 13% |
| `activationGlow` | (228, 78, 67) | (255, 111, 96) |

### 2.3 Welcome / Onboarding Welcome Step Colors

| Token | Light RGB | Dark RGB |
|---|---|---|
| `welcomeCanvas` | (245, 244, 250) | (0, 0, 0) |
| `welcomePrimaryAction` | (195, 63, 51) | (195, 63, 51) |
| `welcomeSecondaryAction` | (255, 255, 255) | (28, 28, 30) |
| `welcomeSecondaryActionText` | (0, 0, 0) | (255, 255, 255) |
| `welcomeGlow` | (195, 63, 51) at 50% opacity — same both modes | |
| `welcomeLink` | (37, 99, 235) | (37, 99, 235) |

### 2.4 Chat Surface Local Colors

Defined inline in `ChatRootSurface.swift` (not on `OpenClawBrand`):

| Name | Light | Dark | Usage |
|---|---|---|---|
| `canvas` (chat bg) | (245, 244, 250) | (23, 23, 23) | Full-bleed chat background |
| `glassFill` | (245, 244, 250) at 20% opacity | (30, 30, 30) at 20% opacity | Glass capsule/pill fill |
| `composerGlassFill` | (245, 244, 250) at 20% opacity | (64, 64, 64) at 20% opacity | Composer field glass |
| `bubbleRed` (static) | (195, 63, 51) — same both modes | | Send button, recording dot |
| `onlineGreen` (static) | (52, 199, 89) — same both modes | | Presence dot (system green) |
| `onlineRing` | (245, 244, 250) | (23, 23, 23) | Badge ring — matches canvas |
| `bubbleFill` (user bubble) | `.white` | `.black` | User chat bubble fill |
| `plusButtonFill` (tray open) | (64, 64, 64) at 20% opacity | (64, 64, 64) at 20% opacity | Plus button when tray open |

Drawer canvas (`ChatDrawer.swift`):

| Name | Light | Dark |
|---|---|---|
| `drawerCanvas` | (245, 244, 250) | (23, 23, 23) |

---

## 3. Gradients

**Source:** `apps/ios/Sources/Design/OpenClawBrand.swift`

### 3.1 Named `LinearGradient` Values on `OpenClawBrand`

| Token | Stops | Direction |
|---|---|---|
| `sheetBackground` | `void` → `obsidian.opacity(0.96)` → `Color(.systemBackground)` | `.topLeading` → `.bottomTrailing` |
| `activationCanvasGradient` | `activationCanvas` × 2 (flat) | `.topLeading` → `.bottomTrailing` |
| `activationInsetGradient` | `activationInsetSurface.opacity(0.94)` → `activationInsetSurface` → `activationSurface.opacity(0.36)` | `.top` → `.bottom` |
| `activationNeutralGradient` | `activationNeutralInsetSurface` → `activationNeutralSurface` | `.top` → `.bottom` |
| `activationPrimaryGradient` | `(1.0, 0.42, 0.34)` → `activationGlow` → `activationPrimaryAction` → `(0.66, 0.12, 0.12)` | `.topLeading` → `.bottomTrailing` |
| `activationDisabledGradient` | `activationNeutralInsetSurface` → `activationNeutralSurface.opacity(0.92)` | `.top` → `.bottom` |

### 3.2 Top Scrim — Chat Surface and Drawer

Both the chat `topScrim` (`ChatRootSurface.swift:996`) and the drawer `drawerTopScrim` (`ChatDrawer.swift:210`) use an identical pattern:

- **Material:** `.ultraThinMaterial` (blurs scrolling content beneath)
- **Dark-mode tint overlay:** canvas color at 72% opacity (dark mode only; light mode: opacity 0)
- **Mask gradient (linear, top → bottom):**
  - `black.opacity(0.6)` at location 0
  - `black.opacity(0.6)` at location 0.55
  - `.clear` at location 1.0
- **Effect:** mask caps blur at ~50% so content shows through dimly, then fades to invisible
- **Frame:** height 110 pt, full-width, `ignoresSafeArea(edges: .top)`, `allowsHitTesting(false)`

---

## 4. Glass / Material Backgrounds

### 4.1 `ChatGlassBackground<S: InsettableShape>`

**Source:** `apps/ios/Sources/Design/ChatRootSurface.swift`

Generic glass view for any `InsettableShape`. Default shape is `Capsule(style: .continuous)`.

| Property | Type | Default |
|---|---|---|
| `shape` | `S: InsettableShape` | `Capsule(style: .continuous)` |
| `fill` | `Color` | (required) |
| `hairline` | `Bool` | `false` |

**iOS 26+ rendering:**
```
shape.fill(fill).glassEffect(.regular, in: shape)
```
Plus optional hairline overlay: `shape.strokeBorder(Color.white.opacity(0.2), lineWidth: 0.3)`.

**iOS < 26 rendering:**
```
shape.fill(.regularMaterial).overlay { shape.fill(fill) }
```
Plus same optional hairline overlay.

**Usage sites:**

| Context | Shape | Fill | Hairline |
|---|---|---|---|
| Header pills / action buttons | `Capsule(style: .continuous)` | `glassFill` | No |
| Composer text field (single-line) | `RoundedRectangle(cornerRadius: 48, style: .continuous)` | `composerGlassFill` | Yes |
| Composer text field (multiline) | `RoundedRectangle(cornerRadius: 15, style: .continuous)` | `composerGlassFill` | Yes |
| Voice-note playback pill in composer | `RoundedRectangle(cornerRadius: 15, style: .continuous)` | `composerGlassFill` | Yes |

The `composerFieldCornerRadius` transitions: 48 pt when `inputHeight ≤ 44`, 15 pt once the field grows past one line.

### 4.2 `ChatGlassPanel`

A rectangular variant (no hairline), uses `RoundedRectangle`. Used for the combined attachment-strip + input-field panel when non-image/non-audio attachments are staged.

| Property | Type |
|---|---|
| `fill` | `Color` |
| `cornerRadius` | `CGFloat` |

**iOS 26+:** `RoundedRectangle.fill(fill).glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))`
**iOS < 26:** `RoundedRectangle.fill(.regularMaterial)` + `fill` overlay

Call site: `ChatGlassPanel(fill: composerGlassFill, cornerRadius: 15)`.

### 4.3 `openClawGlassSurface(radius:)` View Modifier

Defined in `OpenClawProComponents.swift`. Default `radius` = `OpenClawProMetric.controlRadius` (12).

**iOS 26+:** `.glassEffect(.regular, in: .rect(cornerRadius: radius))`
**iOS < 26:** `.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))`

Used for glass-button and drawer control surfaces not in the chat composer.

### 4.4 `openClawCraftSurface(cornerRadius:shadow:)`

Activation/onboarding card surface. Default `cornerRadius` = 24, `shadow` = true.

Layers (bottom to top):
1. `RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(activationSurface)` + optional shadow `(black.opacity(0.07), radius: 16, x: 0, y: 8)`
2. `.overlay(alignment: .top)`: `strokeBorder(Color.white.opacity(0.36), lineWidth: 0.5)` with `.blendMode(.plusLighter)`
3. `.overlay`: `strokeBorder(activationHairline, lineWidth: 0.5)`

---

## 5. Spacing and Corner Radius Constants

### 5.1 `OpenClawProMetric`

**Source:** `apps/ios/Sources/Design/OpenClawProComponents.swift:4`

| Constant | Value (pt) | Usage |
|---|---|---|
| `pagePadding` | 16 | Horizontal page/screen edge padding |
| `cardRadius` | 16 | `ProCard` and default `proPanelSurface` radius |
| `controlRadius` | 12 | Controls, `openClawGlassSurface` default |
| `compactControlSize` | 36 | Square hit target for icon buttons (`OpenClawSidebarRevealButton`) |
| `bottomScrollInset` | 96 | Reserved room at the bottom of scroll views |

### 5.2 `OpenClawSpacing`

**Source:** `apps/ios/Sources/Design/OpenClawProComponents.swift:12`

| Constant | Value (pt) |
|---|---|
| `space1` | 4 |
| `space2` | 8 |
| `space3` | 12 |
| `space4` | 16 |
| `space6` | 24 |

### 5.3 `OpenClawRadius`

**Source:** `apps/ios/Sources/Design/OpenClawProComponents.swift:20`

| Constant | Value (pt) |
|---|---|
| `xs` | 8 |
| `sm` | 10 |
| `md` | 12 |

### 5.4 `OpenClawSectionStyle`

**Source:** `apps/ios/Sources/Design/OpenClawProComponents.swift:28`

| Constant | Value | Usage |
|---|---|---|
| `cornerRadius` | 12 pt | Every settings / grouped-list section container |
| `dividerHeight` | 2 pt | The `OpenClawRowDivider` separator height |

### 5.5 Chat Surface–Specific Constants

**Source:** `apps/ios/Sources/Design/ChatRootSurface.swift`

| Constant | Value | Usage |
|---|---|---|
| `bottomContentPadding` | 10 pt | Minimum gap below last transcript row |
| `maxBubbleWidth` | 296 pt | Maximum width of user chat bubbles |
| Chat bubble padding (text) | H: 8, V: 7 pt | Text bubble insets |
| Chat image bubble padding | 3 pt (all sides) | Image mosaic bubble insets |
| Image bubble fixed width | 250 pt | Width of image attachment bubble |
| Steps overlay top corner radius | 47 pt | `clipShape(.rect(topLeadingRadius: 47, topTrailingRadius: 47))` |
| Steps overlay title font (Figma "Paper spec") | `.system(size: 19, weight: .medium)` or per spec | Centered title above glass X |
| Composer bar padding (H) | 14 pt | Horizontal padding around the composer bar |
| Composer bar padding (V) | 10 pt | Vertical padding around the composer bar |

### 5.6 Drawer Constants

**Source:** `apps/ios/Sources/Design/ChatDrawer.swift`

| Constant | Value | Usage |
|---|---|---|
| `openOffset` | 305 pt (capped at `width × 0.78`) | Drawer open width |
| `headerReserve` | 62 pt | Space below notch for the pinned header |
| `scaleBleed` | 90 pt | Off-screen bleed so scale never clips the bottom edge |
| List top padding | `safeAreaInsets.top + headerReserve` | First row position |
| List bottom padding | `scaleBleed + 24` pt | Last row position |
| Drawer panel shadow | `black.opacity(0.25), radius: 15, x: -5, y: 0` | Chat panel shadow when drawer is open |

---

## 6. Shared Component Styles

### 6.1 `OpenClawRowDivider`

Full-bleed separator drawn at the canvas background color (not a hairline). This is intentional: it reads as a gap of page background rather than a line.

| Mode | Fill color |
|---|---|
| Dark | `(23, 23, 23)` (same as chat canvas) |
| Light | `(245, 244, 250)` (same as chat canvas) |
| Height | 2 pt (`OpenClawSectionStyle.dividerHeight`) |
| Width | `.infinity` |

### 6.2 `OpenClawToggleIndicator`

Custom toggle replacing system `Toggle` because native `Toggle` on iOS 26 only hits the switch edge, not the full row. The parent button covers the full row.

| Dimension | Value |
|---|---|
| Capsule width | 52 pt |
| Capsule height | 32 pt |
| Thumb diameter | 28 pt |
| Thumb ring inset | 2 pt padding |
| Thumb shadow | `black.opacity(0.14), radius: 1, x: 0, y: 1` |
| On fill | `OpenClawBrand.accent` |
| Off fill | `Color.secondary.opacity(0.35)` |
| Thumb fill | `Color.white` |
| Thumb alignment when on | `.trailing` |
| Thumb alignment when off | `.leading` |

### 6.3 `OpenClawStatusBadge`

Pill-shaped status indicator with a presence dot and label.

| Part | Value |
|---|---|
| Dot diameter | 7 × 7 pt |
| Dot shadow | `tone.color.opacity(0.55), radius: 3` |
| Horizontal padding | 8 pt (`OpenClawSpacing.space2`) |
| Vertical padding | 5 pt |
| Spacing (dot → text) | 6 pt (`space1 + 2`) |
| Pill fill (dark) | `tone.color.opacity(0.14)` |
| Pill fill (light) | `tone.color.opacity(0.10)` |
| Font | `OpenClawType.caption2SemiBold` |
| Shape | `Capsule` |

### 6.4 `OpenClawStatusTone` — Semantic Color Mapping

| Case | Color token |
|---|---|
| `.ok` | `OpenClawBrand.ok` |
| `.warn` | `OpenClawBrand.warn` |
| `.danger` | `OpenClawBrand.danger` |
| `.info` | `OpenClawBrand.info` |
| `.accent` | `OpenClawBrand.accent` |
| `.teal` | `OpenClawBrand.teal` |
| `.muted` | `OpenClawBrand.textSecondary` |

### 6.5 `ProValuePill`

Colored value chip used in rows (e.g., bandwidth, counts).

| Part | Value |
|---|---|
| Horizontal padding | 8 pt |
| Vertical padding | 5 pt |
| Fill (dark) | `color.opacity(0.12)` |
| Fill (light) | `color.opacity(0.08)` |
| Font | `OpenClawType.footnoteSemiBold` |
| Shape | `Capsule` |

### 6.6 `ProIconBadge`

30 × 30 pt square badge with an SF Symbol.

| Part | Value |
|---|---|
| Frame | 30 × 30 pt |
| Corner radius | `OpenClawRadius.xs` (8 pt) |
| Icon font | `OpenClawType.captionSemiBold` |
| Background fill | `color.opacity(0.12)` |

### 6.7 `proPanelSurface` / `ProPanelBackground`

Standard card panel. `isProminent` controls background fill and shadow.

| Part | Normal | Prominent |
|---|---|---|
| Fill | `UIColor.secondarySystemGroupedBackground` | `UIColor.systemBackground` |
| Border (no tint) | `separator.opacity(0.22)` dark / `separator.opacity(0.12)` light | same |
| Border (with tint) | `tint.opacity(0.10)` | `tint.opacity(0.18)` |
| Border line width | 1 pt | 1 pt |
| Shadow | none | dark mode: `black.opacity(0.14), radius: 5, y: 2` / light: `black.opacity(0.045), radius: 5, y: 2` |

### 6.8 Button Styles

#### `OpenClawPrimaryActionButtonStyle`

| Part | Value |
|---|---|
| Height default | 54 pt |
| Corner radius | `height / 2` (fully rounded) |
| Font | `OpenClawType.subheadSemiBold` |
| Foreground (enabled) | `activationPrimaryActionText` (white) |
| Background gradient | `(0.93, 0.27, 0.25)` → `(0.91, 0.25, 0.24)`, top → bottom |
| Top highlight overlay | `white.opacity(0.14)` → `white.opacity(0)` over top 48% of height |
| Bottom highlight overlay | `white.opacity(0)` → `white.opacity(0.08)` over bottom 34% of height |
| Border stroke | `activationPrimaryAction.opacity(0.72)`, line width 0.75 |
| Shadow (enabled) | `activationPrimaryAction.opacity(0.08), radius: 1, y: 1` + `radius: 2, y: 2` |
| Press scale | 0.98, `.smooth(duration: 0.14)` |
| Disabled gradient | `activationDisabledGradient` |

#### `OpenClawSecondaryActionButtonStyle`

| Part | Value |
|---|---|
| Height default | 50 pt |
| Corner radius | `height / 2` |
| Font | `OpenClawType.subheadSemiBold` |
| Foreground (enabled) | `activationPrimaryAction` |
| Background gradient | `activationSecondaryActionTop` → `activationSecondaryActionBottom`, top → bottom |
| Top highlight overlay | `white.opacity(0.42)` → `white.opacity(0)` over top 48% |
| Border stroke | `activationHairline`, line width 0.75 |
| Shadow opacity default | `0.035` (configurable) |
| Press scale | 0.98, `.smooth(duration: 0.14)` |

#### `OpenClawCloseButtonStyle`

| Part | Value |
|---|---|
| Min width | 36 pt |
| Height | 36 pt |
| Horizontal padding | 7 pt |
| Font | `OpenClawType.subheadSemiBold` |
| Foreground | `activationPrimaryAction` |
| Background | `activationNeutralGradient` capsule |
| Top highlight | `white.opacity(0.55)` stroke, `.plusLighter` blend, line width 0.5 |
| Border | `activationNeutralStroke`, line width 0.6 |
| Shadow | `black.opacity(0.045), radius: 1, y: 1` + `black.opacity(0.03), radius: 4, y: 2` |
| Press opacity | 0.66 |
| Press scale | 0.98, `.smooth(duration: 0.14)` |

### 6.9 `ProProgressBar`

| Part | Value |
|---|---|
| Height | 3 pt |
| Track fill | `Color.primary.opacity(0.10)` |
| Progress fill | `OpenClawBrand.accentHot` (configurable) |
| Shape | `Capsule` |

### 6.10 User Bubble Shape (`ChatUserBubble`)

`UnevenRoundedRectangle` with asymmetric radii producing the chat-bubble tail on the bottom-trailing corner:

| Corner | Radius |
|---|---|
| Top-leading | 12 pt |
| Bottom-leading | 12 pt |
| Bottom-trailing | 3 pt |
| Top-trailing | 12 pt |

Style: `.continuous`.

---

## 7. Animation Vocabulary

All animation values are from `ChatRootSurface.swift` unless noted.

| Interaction | Animation |
|---|---|
| Row insertion during live turn | `.spring(response: 0.42, dampingFraction: 0.82)` |
| Pinned-turn spring scroll to top (on send) | `.spring(response: 0.42, dampingFraction: 0.82)` |
| Phase crossfades (thinking/tooling/answering node) | `.easeInOut(duration: 0.25)` |
| Streaming bubble → finalized row crossfade | `.easeInOut(duration: 0.25)` |
| Thinking node mount fade (after bubble settle) | `.easeInOut(duration: 0.25)` |
| Footprint text crossfade (tool step labels) | `.easeInOut(duration: 0.3)` |
| Scroll to bottom (existing history) | `.easeOut(duration: 0.2)` |
| Attachment tray open | `.spring(duration: 0.35)` |
| Attachment tray close | `.spring(duration: 0.3)` |
| Attachment removal | `.spring(duration: 0.25)` |
| Plus button open: keyframe dip → spring | `.snappy` for 0.16 s, then `.bouncy` for 0.34 s |
| Plus button fade out (tray opening) | `.easeOut(duration: 0.1)` |
| Plus button fade in (tray closing) | `.easeOut(duration: 0.15)` |
| Attachment panel appearance change | `.spring(duration: 0.3)` |
| Steps overlay slide in/out | `.spring(response: 0.5, dampingFraction: 0.95)` (near-critically damped, matches UIKit page-sheet feel) |
| Steps drag snap-back (sub-threshold drag) | `.easeOut(duration: 0.2)` |
| Presence dot appear/disappear | `.scale.combined(with: .opacity)` (default transition) |
| Presence dot color change | `.smooth(duration: 0.25)` |
| Attachment tray entry transition | `.scale(scale: 0.1, anchor: .bottomLeading).combined(with: .opacity)` |
| Answer reveal wipe | `.linear(duration: revealDuration)` where `revealDuration = clamp(lineCount × 0.085, 0.55, 2.2)` |
| Copied-to-clipboard flash (copy button) | `.easeOut(duration: 0.15)` in / `.easeOut(duration: 0.15)` out after 1.5 s |
| Button press scale (primary/secondary/close) | `.smooth(duration: 0.14)` |
| Drawer open/close (gesture end) | `.spring(duration: 0.35)` |

### 7.1 Answer Reveal Parameters

| Constant | Value |
|---|---|
| `perLine` | 0.085 s |
| `minDuration` | 0.55 s |
| `maxDuration` | 2.2 s |
| `feather` (blur radius on wipe edge) | 16 pt |
| Wipe overshoot | `feather × 2` = 32 pt |

The reveal uses `ChatRevealWipe: Shape` whose `animatableData = fraction`. This is mandatory: feeding the fraction value into gradient stops does not tween — SwiftUI only interpolates conforming `Shape` types frame-by-frame. The shape overshoots content width by ±20 pt on each side and height by `overshoot` top and bottom so the feathered blur edge falls entirely outside the text.

---

## 8. Haptics — `OpenClawHaptics`

**Source:** `apps/ios/Sources/Onboarding/OpenClawHaptics.swift`

All haptic playback is `@MainActor`. The `HapticEngineHolder` uses `CHHapticEngine` with `isAutoShutdownEnabled = true`. If the hardware does not support haptics (`CHHapticEngine.capabilitiesForHardware().supportsHaptics == false`), all `play(_:)` calls fall back to `UINotificationFeedbackGenerator().notificationOccurred(.success)`.

The engine's `resetHandler` (fired after audio-session interruptions on an arbitrary queue) hops back to `@MainActor` via a `Task` and calls `engine.start()` so the next haptic still fires.

### 8.1 Public API

| Method | Description | Implementation |
|---|---|---|
| `OpenClawHaptics.tap()` | Light selection tap for discrete UI actions (attachment tray rows) | `UIImpactFeedbackGenerator(style: .light).impactOccurred()` |
| `OpenClawHaptics.error()` | Alert-style two-buzz warning — introduces an assistant reply | Plays `.warning` pattern |
| `OpenClawHaptics.click()` | Single crisp click — closes out an assistant reply | Plays `.secured1` pattern |
| `OpenClawHaptics.success()` | Standard success notification (e.g., save to photos) | `UINotificationFeedbackGenerator().notificationOccurred(.success)` |
| `OpenClawHaptics.play(_ pattern:)` | Raw pattern playback (internal/lab use) | `CHHapticPattern` via `HapticEngineHolder` |

### 8.2 `OpenClawHapticPattern` Recipes

All events use `CHHapticEvent`. Transient events are instantaneous; continuous events have a duration. Intensity curves are `CHHapticParameterCurve` on `.hapticIntensityControl`.

| Pattern | Name / Character | Events | Curves |
|---|---|---|---|
| `.secured1` | Minimalist — one crisp click | `tap(t:0, i:1.0, s:0.9)` | none |
| `.secured2` | Handshake — click then firmer answer | `tap(0, 0.6, 0.5)`, `tap(0.12, 1.0, 0.85)` | none |
| `.secured3` | v1 Draft — click, answer, settling hum | `tap(0, 0.7, 0.6)`, `tap(0.1, 1.0, 0.8)`, `hum(0.2, dur:0.35, i:1.0, s:0.3)` | intensity 0.4→0.0 over 0.35 s from t=0.2 |
| `.secured4` | Key Turn — rising triplet | `tap(0, 0.5, 0.4)`, `tap(0.09, 0.75, 0.65)`, `tap(0.18, 1.0, 0.9)` | none |
| `.secured5` | Echo — double-tap + distant echo | `tap(0, 0.9, 0.8)`, `tap(0.08, 0.85, 0.8)`, `tap(0.34, 0.3, 0.5)` | none |
| `.warning` | Two-buzz warning (used by `error()`) | `hum(0, dur:0.04, i:0.8, s:0.5)`, `hum(0.14, dur:0.04, i:0.6, s:0.5)` | none |
| `.secured7` | Lock Engaging — swell into a click | `hum(0, dur:0.3, i:1.0, s:0.3)`, `tap(0.31, 1.0, 0.9)` | intensity 0.15→0.9 over 0.3 s from t=0 |
| `.secured8` | Heartbeat — two lub-dubs | `tap(0, 0.5, 0.3)`, `tap(0.13, 0.35, 0.25)`, `tap(0.5, 0.5, 0.3)`, `tap(0.63, 0.35, 0.25)` | none |
| `.secured9` | Sealed — low hum then stamped shut | `hum(0, dur:0.4, i:0.45, s:0.1)`, `tap(0.42, 1.0, 0.7)` | none |
| `.secured10` | Sparkle — three feather ticks + thud | `tap(0, 0.3, 1.0)`, `tap(0.07, 0.3, 1.0)`, `tap(0.14, 0.3, 1.0)`, `tap(0.28, 1.0, 0.25)` | none |

Event parameter key: `tap(t, intensity, sharpness)` → `CHHapticEvent(.hapticTransient, relativeTime: t)`. `hum(t, dur, i, s)` → `CHHapticEvent(.hapticContinuous, relativeTime: t, duration: dur)`.

The `.warning` and `.secured1` patterns are the two that ship in production (used by `error()` and `click()`). The remaining `.secured*` patterns are audition candidates; only one will survive before the PR lands.

---

## 9. `ChatSessionPrefs` — Session Pinning State

**Source:** `apps/ios/Sources/Design/ChatSessionPrefs.swift`

`@Observable @MainActor final class ChatSessionPrefs`. Singleton (`ChatSessionPrefs.shared`). Persists a `Set<String>` of pinned session keys in `UserDefaults` under the key `"chat.sessions.pinned"`.

| Method | Effect |
|---|---|
| `isPinned(_ sessionKey:) -> Bool` | Returns whether a session is pinned |
| `togglePin(_ sessionKey:)` | Inserts or removes from the set; persists immediately |
| `ordered(_ sessions: [ChatDrawerSession]) -> [ChatDrawerSession]` | Returns pinned rows (in incoming order) followed by unpinned rows |

This is a client-side annotation only; server truth is not touched.

---

## 10. `AppAppearancePreference` — Appearance Mode Selection

**Source:** `apps/ios/Sources/Design/OpenClawBrand.swift`

| Case | `rawValue` | `colorScheme` |
|---|---|---|
| `.system` | `"system"` | `nil` |
| `.light` | `"light"` | `.light` |
| `.dark` | `"dark"` | `.dark` |

Persisted in `UserDefaults` under key `"appearance.preference"`. Can be overridden at launch via `--openclaw-appearance <value>` process argument (takes precedence over stored preference and writes it back). `AppAppearanceModel.select(_:)` switches without animation (`transaction.disablesAnimations = true`).

---

## 11. Typography Test Contract

**Source:** `apps/ios/Tests/OpenClawTypographyTests.swift`

The test suite enforces the following invariants at CI time. Any surface edit must keep these passing.

| Test | Invariant enforced |
|---|---|
| `bundled fonts load from app bundle` | Every PostScript name in `OpenClawType.registeredPostScriptNames` resolves to a non-nil `UIFont` |
| `dynamic type scales display fonts` | `RedHatDisplay-Regular` scales measurably larger at `.accessibilityExtraExtraExtraLarge` vs `.large` |
| `display variable weight axis instantiates heavy weights` | wght axis 900 can be requested and is round-tripped in the descriptor |
| `app extensions register bundled branded fonts` | `project.yml` and both extension `Info.plist` files declare all 6 font files under `UIAppFonts` |
| `extension text surfaces use branded typography helpers` | Activity and Watch extensions use their own typed helpers (`OpenClawActivityType`, `WatchClawType`); no bare `.font(.subheadline)` or `.font(.system(...))` |
| `UIKit typography refreshes when Dynamic Type changes` | `OpenClawApp.swift` subscribes to `UIContentSizeCategory.didChangeNotification`; `OpenClawTypography.swift` implements `refreshUIKitAppearance` with the four `maximumPointSize` values (13, 16, 22, 44) |
| `session controls use branded typography` | `CommandCenterSupport.swift` and `CommandCenterTab.swift` use `OpenClawType.*` tokens, not shorthand controls with implicit fonts |
| `listed iOS app surfaces enforce branded control typography` | Scans `OpenClawProComponents`, Gateway sheets, Onboarding, Settings, Skills, Agents, Channels, Docs, ChatProTab, and shared ChatUI — verifies `OpenClawType.*` or `OpenClawChatTypography.*` appears within 12 lines of every `Text(...)` / `Label(...)` / shorthand control call |
| `iOS app text and control calls keep branded font boundaries` | Scans all `.swift` sources under `Sources/` and shared `OpenClawChatUI`; any `Text(`, `Label(`, `Button("`, `TextField("`, etc. without a nearby branded font token is an offender. Allowlist exceptions are narrow and named per file |
| `secure fields do not use platform placeholder text` | `SecureField("placeholder"` shorthand is banned — requires explicit overlay approach with `.accessibilityLabel` and `.accessibilityHidden(true)` on the decorative placeholder |

The bundled font files that must be present in `UIAppFonts` for all three targets (main app, Activity Widget, Watch App):

```
RedHatDisplay[wght].ttf
Inter[opsz,wght].ttf
Inter-Italic[opsz,wght].ttf
JetBrainsMono-Regular.ttf
JetBrainsMono-Medium.ttf
JetBrainsMono-SemiBold.ttf
```
