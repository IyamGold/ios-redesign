# Re-verify — 14-assets-glyphs.md

## Scorecard

| metric | value |
|---|---|
| originalDefectCount | 1 |
| resolvedCount | 1 |
| unresolved | 0 |
| newErrors | 0 |
| remainingOmissions | 2 (both minor) |

---

## Resolved defects

**C42 — RESOLVED.**
The original audit said the doc incorrectly grouped `SettingsChevronsUpDownGlyph`, `ChannelWhatsappGlyph`, and `FeedbackTailscaleGlyph` together as "rendered Original", when in fact all three override to `.renderingMode(.template)`.

The repair correctly disentangles these:
- `SettingsChevronsUpDownGlyph` — all three call sites (`ConnectionSheet.swift:232`, `SettingsRootScreen.swift:315`, `SettingsDestinationScreens.swift:679`) explicitly use `.renderingMode(.template)`. The doc now says so.
- `ChannelWhatsappGlyph` — rendered via `Image(asset)` with no renderingMode modifier at `SettingsDestinationScreens.swift:409` (comment: "full-color brand mark (Original)"). The doc correctly leaves it in the Original group.
- `FeedbackTailscaleGlyph` — rendered via `stateGlyph()` at `OnboardingWizardSteps.swift:1236–1241`, which performs no renderingMode override. The doc correctly leaves it in the Original group.

The rendering-conventions section and summary table row 53 are now accurate.

---

## Unresolved defects

None.

---

## New errors

None found. Sampled claims verified:

- `DrawerClockGlyph` at `ChatDrawer.swift:284` — confirmed.
- `DrawerFilesGlyph` at `ChatDrawer.swift:287` — confirmed.
- `CronJobsCheckGlyph`/`CronJobsDisableGlyph` toggle logic (`job.enabled` branch) at `CronJobsScreen.swift:163` — confirmed.
- `CronJobsReloadGlyph` 16×16 tinted `Color(red: 52/255, green: 199/255, blue: 89/255)` at `CronJobsScreen.swift:207–208` — confirmed.
- `CanvasFileGlyph` at `CanvasArtifacts.swift:154` and `:396` — confirmed.
- `CanvasPanelHeader` default `leadingGlyph = "ChatCloseGlyph"` at `CanvasArtifacts.swift:172` — confirmed.
- `SettingsChevronRightGlyph` source file `li_chevron-left.svg` — confirmed by asset catalog `Contents.json`.
- `SettingsChevronsUpDownGlyph` source file `li_chevrons-up-down.png` (PNG) — confirmed by asset catalog `Contents.json`.
- `ChannelWhatsappGlyph` 22×22 Original (no renderingMode) at `SettingsDestinationScreens.swift:408–411,420` — confirmed.
- `FeedbackCopyGlyph` at `ChatRootSurface.swift:2758` — confirmed.
- `UsageFilterGlyph` at `DreamingScreen.swift:74`, `UsageScreen.swift:82`, `CronJobsScreen.swift:105` — confirmed.
- `SkillScrollGlyph` at `SkillsScreen.swift:157` — confirmed.
- `FilesFileGlyph`/`FilesFolderGlyph` at `FilesGridScreen.swift:137` — confirmed.

---

## Remaining omissions

**O1 — minor.**
`FeedbackCopyGlyph` has a second call site not listed in the doc: `OnboardingWizardSteps.swift:1330` (a copy button in the credential/onboarding flow). The doc only cites `ChatRootSurface.swift:2758`. Source: `OnboardingWizardSteps.swift:1330` — `self.icon(.asset("FeedbackCopyGlyph"), visible: !self.copied)`.

**O2 — minor.**
The section heading "## Summary table (all 71 imagesets)" overcounts. The asset catalog contains exactly 70 `.imageset` directories; the doc's own footnote acknowledges entry 71 is the catalog root `Contents.json`, not an imageset. The heading should read "all 70 imagesets". Source: `ls Sources/Assets.xcassets/*.imageset | wc -l` → 70.

---

## Verdict

CERTIFIED — zero critical or major defects remain across unresolved, newErrors, and remainingOmissions. Two minor omissions (one missing call-site, one off-by-one in a section heading) do not block certification.
