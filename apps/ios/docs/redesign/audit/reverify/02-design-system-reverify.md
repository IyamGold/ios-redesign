# Re-verify — 02-design-system.md

## Scorecard

| metric | value |
|---|---|
| originalDefectCount | 25 |
| resolvedCount | 25 |
| unresolved | 0 |
| newErrors | 0 |
| remainingOmissions | 0 |

## Resolved Defects

All 25 original defects (1 critical + 17 major + 7 minor) are resolved. Evidence summary:

**C15 (major — UINavigationBar inline title family):** Doc §1.3 now correctly says "Display opticalSemiBold (Red Hat Display), `.headline`-relative". Code: `scaledDisplayUIFont(weight: Display.opticalSemiBold, size: 17, relativeTo: .headline, maximumPointSize: 22)` → `OpenClawTypography.swift:158–162`. ✓

**C40 (critical — drawer scrim height):** Doc §3.2 now documents the two-row table showing chat = fixed 110 pt and drawer = dynamic `topInset + headerReserve = safeAreaInsets.top + 62 pt`. Code: `ChatDrawer.swift:227` `.frame(height: topInset + Self.headerReserve)` where `headerReserve` = 62 (`ChatDrawer.swift:195`). ✓

**C117 (minor — `.stroke` vs `.strokeBorder` in `openClawCraftSurface`):** Doc §4.4 now explicitly calls out `.stroke(...)` (not `.strokeBorder`) on both overlays, with an explanation of why the distinction matters. Code: `OpenClawBrand.swift:266` `.stroke(Color.white.opacity(0.36), lineWidth: 0.5)` and `:271` `.stroke(OpenClawBrand.activationHairline, lineWidth: 0.5)`. ✓

**Major omission — `.stroke` vs `.strokeBorder` per-surface note:** Covered in §4.4, which also correctly notes that `proInsetSurface` (§4.5) uses `strokeBorder` while `openClawCraftSurface` uses `.stroke`. ✓

**Major omission — `OpenClawPrimaryActionButtonStyle` disabled foreground + highlight:** Doc §6.8 now documents disabled foreground as `Color.secondary` (NOT white), disabled top-highlight opacity 0.06. Code: `OpenClawBrand.swift:288` `Color.secondary` when `!isEnabled`; `:311` `0.06` when disabled. ✓

**Major omission — `OpenClawSecondaryActionButtonStyle` two shadow layers:** Doc §6.8 now documents two shadow layers both at `black.opacity(shadowOpacity)`: `(radius: 1, y: 1)` and `(radius: 2, y: 2)`. Code: `OpenClawBrand.swift:374–383` matches. ✓

**Major omission — `OpenClawCloseButtonStyle` `.fixedSize` and `.contentShape`:** Doc §6.8 now documents both. Code: `OpenClawBrand.swift:429` `.fixedSize(horizontal: true, vertical: false)` and `:456` `.contentShape(Capsule(style: .continuous))`. ✓

**Major omission — `ProSectionHeader`:** Documented in §6.7a. Code: `OpenClawProComponents.swift:69–98` matches all details (footnoteMedium, .secondary, .uppercase default true, pagePadding, accent action button). ✓

**Major omission — `ProCard` defaults:** Documented in §6.7b. Code: `OpenClawProComponents.swift:100–116` — padding 12, radius `cardRadius` (16 pt). ✓

**Major omission — `proInsetSurface`:** Documented in §4.5. Code: `OpenClawProComponents.swift:146–163` — fill `tertiarySystemGroupedBackground` (not secondary), border `strokeBorder(tint.opacity(0.18 dark / 0.10 light), lineWidth: 1)`. ✓

**Major omission — `openClawGlassButton`:** Documented in §4.3a. Code: `OpenClawProComponents.swift:165–194` — all four branches apply `subheadSemiBold` font; iOS 26 uses `.glass`/`.glassProminent`; pre-26 uses `.bordered`/`.borderedProminent`. ✓

**Major omission — `OpenClawGlassControlGroup`:** Documented in §4.3b. Code: `OpenClawProComponents.swift:344–356` — `GlassEffectContainer(spacing: 8)` on iOS 26+, plain passthrough pre-26. ✓

**Major omission — `OpenClawSidebarRevealButton` / `OpenClawSidebarHeaderLeadingSlot`:** Documented in §6.7k. Code: `OpenClawProComponents.swift:307–342` — `.buttonBorderShape(.circle)`, `.openClawGlassButton(tint: accent)`, 36×36 frame, `.contentShape(Rectangle())`; slot wraps at 44×44. ✓

**Major omission — `OpenClawAdaptiveHeaderRow`:** Documented in §6.7d. Code: `OpenClawProComponents.swift:448–531` — `ViewThatFits(in: .horizontal)`, horizontal/stacked layouts, `minimumScaleFactor(0.86)`, `lineLimit(2)`, `VStack(spacing: 4)` title block, default fonts `title3SemiBold`/`subhead`. ✓

**Major omission — `OpenClawNoticeBanner` layout:** Documented in §6.7c. Code: `OpenClawProComponents.swift:363–446` — `ProCard(tint:, padding: 14)`, `VStack(spacing: 12)`, inner `HStack(spacing: 12)`, `VStack(spacing: 6)`, `HStack(spacing: 10)` for buttons. ✓

**Major omission — `ProMetricTile` layout:** Documented in §6.7g. Code: `OpenClawProComponents.swift:694–726` — padding 11, `VStack(spacing: 10)`, value `VStack(spacing: 2)`, icon 24×24 circle background at 0.18 dark / 0.10 light. ✓

**Major omission — `ProPanelHeader` asymmetric padding:** Documented in §6.7e. Code: `OpenClawProComponents.swift:785–787` — H: 14, top: 12, bottom: 8. ✓

**Major omission — `ProStatusRow` padding and layout:** Documented in §6.7f. Code: `OpenClawProComponents.swift:809–848` — H: 14, V: 10, `HStack(alignment: .top, spacing: 12)`, `VStack(spacing: 4)`, trailing `VStack(spacing: 6)`, `.buttonStyle(.bordered).controlSize(.mini)`. ✓

**Major omission — `openClawSheetChrome()` tint:** Documented in §4.6. Code: `OpenClawBrand.swift:234–243` — `.tint(OpenClawBrand.accent)` + sheetBackground gradient. ✓

**Minor omission — `openClawTabBarBehavior`:** Documented in §4.3c. Code: `OpenClawProComponents.swift:196–204` — `.tabBarMinimizeBehavior(.onScrollDown)` on iOS 26+. ✓

**Minor omission — `ProStatusDot`:** Documented in §6.7i. Code: `OpenClawProComponents.swift:599–607` — `Circle().fill(color).frame(width: 8, height: 8)`. ✓

**Minor omission — `OpenClawProMark`:** Documented in §6.7j. Code: `OpenClawProComponents.swift:628–638` — 42×42 pt default, `accent.opacity(0.18)` shadow, `radius: 10`, `y: shadowRadius / 3 ≈ 3.3`. ✓

**Minor omission — `OpenClawActivationGlyph` proportional shadow:** Documented in §6.7l. Code: `OpenClawBrand.swift:219–232` — `radius: size * 0.12`, `y: size * 0.05`. ✓

**Minor omission — `ChatSessionPrefs` UserDefaults array encoding:** Documented in §9. Code: `ChatSessionPrefs.swift:14` `stringArray(forKey:)` read, `:26` `set(Array(self.pinned), forKey:)` write. ✓

**Minor omission — `ProMetricGrid` responsive columns:** Documented in §6.7h. Code: `OpenClawProComponents.swift:737–761` — 1 column on `.compact`, else `min(max(count, 1), 3)` flexible columns, `spacing: 10`. ✓

## New Errors

None. All sampled new claims in the repair are consistent with the source code.

## Remaining Omissions

None critical or major.

## Verdict

CERTIFIED — zero critical, major, or minor defects remain across unresolved, new errors, and remaining omissions.
