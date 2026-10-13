# Audit — 02-design-system.md

## Scorecard

| metric | value |
|---|---|
| precision | 0.968 |
| recall | 0.633 |
| F | 0.766 |
| critical | 1 |
| major | 17 |
| minor | 7 |
| certified | false |
| claims | 119 |

## Defects (fix these)

### Wrong / Unsupported Claims

**C15 — major**
Doc says: `UINavigationBar` inline title uses Inter SemiBold font family (`| UINavigationBar inline title | Inter SemiBold, .headline-relative | 17 | 22 |`).
Code says: `self.scaledDisplayUIFont(weight: Display.opticalSemiBold, size: 17, relativeTo: .headline, maximumPointSize: 22)` — `scaledDisplayUIFont` uses `Display.postScriptName` = `"RedHatDisplay-Regular"`, not Inter.
Citation: `OpenClawTypography.swift:158–162`

---

**C40 — critical**
Doc says: Drawer `drawerTopScrim` frame height is fixed at 110 pt (same as chat).
Code says: `ChatDrawer.swift:227` — `.frame(height: topInset + Self.headerReserve)` — the drawer scrim height is dynamic (`safeAreaInsets.top + 62`), not a fixed 110 pt. The chat scrim is 110 pt; the drawer scrim is parameterized.
Citation: `Sources/Design/ChatDrawer.swift:227`

---

**C117 — minor**
Doc says: `openClawCraftSurface` layer 2 uses `strokeBorder` API — `.overlay(alignment: .top): strokeBorder(Color.white.opacity(0.36), lineWidth: 0.5)` with `.blendMode(.plusLighter)`.
Code says: `RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous).stroke(Color.white.opacity(0.36), lineWidth: 0.5).blendMode(.plusLighter)` — uses `.stroke`, not `.strokeBorder`. These differ: `stroke` draws along the path edge; `strokeBorder` insets inside the shape.
Citation: `Sources/Design/OpenClawBrand.swift:265–267`

---

### Omissions

**major** — `openClawCraftSurface` overlay uses `.stroke(...)` (not `.strokeBorder`) on `RoundedRectangle` for both the white-0.36 plusLighter overlay and the activationHairline overlay. `.stroke` straddles the shape edge (half inside, half outside); `.strokeBorder` stays fully inset. The spec says "strokeBorder" in section 4.4, which is materially wrong — it changes whether the stroke is clipped by the shape.
Citation: `Sources/Design/OpenClawBrand.swift:266-272`

**major** — `OpenClawPrimaryActionButtonStyle` disabled foreground color is `Color.secondary` (not `activationPrimaryActionText`/white), and disabled top-highlight opacity drops to 0.06 (not 0.14). The spec only documents the enabled foreground; a rebuilder will use white for the disabled state too, producing wrong contrast.
Citation: `Sources/Design/OpenClawBrand.swift:288-291`

**major** — `OpenClawSecondaryActionButtonStyle` has two shadow layers: `(shadowOpacity, radius: 1, y: 1)` and `(shadowOpacity, radius: 2, y: 2)`. The spec only mentions "Shadow opacity default: 0.035 (configurable)" with no layering detail. A rebuilder will produce a single-layer shadow.
Citation: `Sources/Design/OpenClawBrand.swift:374-383`

**major** — `OpenClawCloseButtonStyle` applies `.fixedSize(horizontal: true, vertical: false)` and `.contentShape(Capsule(style: .continuous))` on the label. Without `fixedSize`, multi-word button labels may wrap. Without `contentShape`, hit target falls to the visual label bounds only. Neither is mentioned in the spec.
Citation: `Sources/Design/OpenClawBrand.swift:429-456`

**major** — `ProSectionHeader` component is entirely absent from the spec. It renders `footnoteMedium` font in `.secondary` color with `.uppercase` text case, optional right-side action button in `OpenClawBrand.accent`, padded with `pagePadding` horizontally. A rebuilder creating grouped-list screens cannot derive this component.
Citation: `Sources/Design/OpenClawProComponents.swift:69-98`

**major** — `ProCard` default padding is 12 pt (configurable via `padding:` parameter) and default radius is `OpenClawProMetric.cardRadius` (16 pt). These defaults are absent from the spec; a rebuilder using `ProCard` without knowing the defaults will produce wrong spacing.
Citation: `Sources/Design/OpenClawProComponents.swift:100-116`

**major** — `proInsetSurface` modifier uses `UIColor.tertiarySystemGroupedBackground` as fill (not `secondarySystemGroupedBackground`) and tint border opacity 0.18 dark / 0.10 light. This modifier is not mentioned anywhere in the spec, yet it is used by `ProMetricTile` and would be needed by any rebuilder adding tinted inset panels.
Citation: `Sources/Design/OpenClawProComponents.swift:146-163`

**major** — `openClawGlassButton` modifier: on iOS 26+ uses `.glass` / `.glassProminent` button styles; pre-iOS 26 falls back to `.bordered` / `.borderedProminent`. Both branches apply `OpenClawType.subheadSemiBold` font. This behavior (and its iOS-version branching) is entirely absent from the spec.
Citation: `Sources/Design/OpenClawProComponents.swift:165-194`

**major** — `OpenClawGlassControlGroup` uses `GlassEffectContainer(spacing: 8)` on iOS 26+, and plain passthrough on pre-26. The `spacing: 8` value and the iOS-version branching are absent from the spec.
Citation: `Sources/Design/OpenClawProComponents.swift:344-356`

**major** — `OpenClawSidebarRevealButton` applies `.buttonBorderShape(.circle)` and `.openClawGlassButton(tint: OpenClawBrand.accent)`. Without these the button renders as a plain icon. Also wraps in a 36×36 frame via `compactControlSize`. `OpenClawSidebarHeaderLeadingSlot` further wraps it in a 44×44 frame. Neither component nor these modifiers appear in the spec.
Citation: `Sources/Design/OpenClawProComponents.swift:307-342`

**major** — `OpenClawAdaptiveHeaderRow` uses `ViewThatFits(in: .horizontal)` to switch between horizontal and stacked layouts. Horizontal: `HStack(alignment: .top, spacing: 12)` with `Spacer(minLength: 8)`; stacked: `VStack(alignment: .leading, spacing: 10)`. Title block has `minimumScaleFactor(0.86)`, `lineLimit(2)`, title-subtitle `VStack(spacing: 4)`. Default fonts: `title3SemiBold` / `subhead`. None of this is in the spec.
Citation: `Sources/Design/OpenClawProComponents.swift:448-531`

**major** — `OpenClawNoticeBanner` layout details are absent: outer `ProCard(tint:, padding: 14)`, inner `VStack(spacing: 12)`, `HStack(alignment: .top, spacing: 12)` for icon+text, `VStack(spacing: 6)` for title/message/detail, `HStack(spacing: 10)` for action buttons. A rebuilder cannot derive the banner structure.
Citation: `Sources/Design/OpenClawProComponents.swift:363-446`

**major** — `ProMetricTile` padding is 11 pt (not 12 or 16), outer `VStack(spacing: 10)`, inner value `VStack(spacing: 2)`, icon frame 24×24 with circle background at opacity 0.18 dark / 0.10 light. None of this is in the spec.
Citation: `Sources/Design/OpenClawProComponents.swift:694-726`

**major** — `ProPanelHeader` has asymmetric padding: H: 14 pt, top: 12 pt, bottom: 8 pt. Its action control uses an icon `Button` (with image) or text `Button` (with `captionSemiBold`) depending on whether `actionIcon` is provided. These details are absent from the spec.
Citation: `Sources/Design/OpenClawProComponents.swift:763-807`

**major** — `ProStatusRow` has padding H: 14 pt, V: 10 pt, `HStack(alignment: .top, spacing: 12)`, inner `VStack(spacing: 4)` for title/detail, trailing `VStack(spacing: 6)` for pill + action button (`.bordered`, `.mini` control size). These details are absent from the spec.
Citation: `Sources/Design/OpenClawProComponents.swift:809-848`

**major** — `openClawSheetChrome()` modifier applies `.tint(OpenClawBrand.accent)` in addition to the `sheetBackground` gradient. The tint application is absent from the spec; navigation/button tint inside any sheet using this modifier will default to system blue without it.
Citation: `Sources/Design/OpenClawBrand.swift:234-243`

**minor** — `openClawTabBarBehavior` modifier applies `.tabBarMinimizeBehavior(.onScrollDown)` on iOS 26+. Not documented in the spec; a rebuilder adding new tab content won't know to apply this modifier.
Citation: `Sources/Design/OpenClawProComponents.swift:196-204`

**minor** — `ProStatusDot` (8×8 filled `Circle`) is entirely absent from the spec. It is used in multiple places as a standalone color-keyed status indicator distinct from `OpenClawStatusBadge`.
Citation: `Sources/Design/OpenClawProComponents.swift:599-607`

**minor** — `OpenClawProMark` renders `OpenClawMascotView()` at 42×42 pt with `accent.opacity(0.18)` shadow of radius 10, y = radius/3 (approximately 3.3 pt). Not documented in the spec; rebuilder cannot reproduce the branded mascot mark dimensions.
Citation: `Sources/Design/OpenClawProComponents.swift:628-638`

**minor** — `OpenClawActivationGlyph` shadow: `color: activationGlow.opacity(0.18)`, `radius: size * 0.12`, `y: size * 0.05`. These proportional formula values are absent from the spec; a rebuilder will use a fixed shadow.
Citation: `Sources/Design/OpenClawBrand.swift:219-232`

**minor** — `ChatSessionPrefs` stores the pinned `Set<String>` via `UserDefaults.stringArray(forKey:)` (as `[String]`, not JSON or a plist set). The spec says "persists a Set<String>" without documenting the array encoding. A rebuilder using a different encoding (e.g. JSON) will produce incompatible persistence.
Citation: `Sources/Design/ChatSessionPrefs.swift:14`

**minor** — `ProMetricGrid` column count: always 1 on `.compact` horizontal size class; otherwise `min(max(metrics.count, 1), 3)` flexible columns with `spacing: 10`. The spec does not document this component or its responsive behavior at all.
Citation: `Sources/Design/OpenClawProComponents.swift:737-761`

## Verdict

NEEDS-REPAIR — 18 blocking defects (1 critical + 17 major).
