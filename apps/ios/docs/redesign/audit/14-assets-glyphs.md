# Audit — 14-assets-glyphs.md

## Scorecard

| metric | value |
|---|---|
| precision | 0.968 |
| recall | 1 |
| F | 0.984 |
| critical | 0 |
| major | 1 |
| minor | 0 |
| certified | false |
| claims | 92 |

## Defects (fix these)

**C42** — major — Doc states SettingsChevronsUpDownGlyph (and the broader PNG rendering-conventions exception group including ChannelWhatsappGlyph and FeedbackTailscaleGlyph) render Original because they are PNG raster or brand-mark artwork. In fact all three call sites explicitly override to template rendering: `ConnectionSheet.swift:232` `.renderingMode(.template)`, `SettingsRootScreen.swift:315` `.renderingMode(.template)`, `SettingsDestinationScreens.swift:679` `.renderingMode(.template)`. The assets are PNG but they do not render Original; they render as template.

## Verdict

NEEDS-REPAIR — 1 major defect blocking certification.
