# Audit — 05-destinations-automation-usage.md

## Scorecard

| metric | value |
|---|---|
| precision | 0.993 |
| recall | 0.773 |
| F | 0.869 |
| critical defects | 1 |
| major defects | 4 |
| minor defects | 16 |
| certified | false |
| claims audited | 116 |

## Defects (fix these)

### Wrong / Unsupported Claims

**minor** — Doc says duration label else-branch is "else seconds" (using `(s)` shorthand). Code produces `"\(seconds) second\(seconds == 1 ? "" : "s")"` — full singular/plural English, not the bare label "seconds". — `CronJobsScreen.swift:430–445`

### Omissions

**major** — Doc documents Cron filter menu titles only. Code renders a `Image(systemName: "checkmark")` next to the currently-selected filter option; the active-state indicator is entirely undocumented. — `Sources/Design/CronJobsScreen.swift:99–101`

**major** — Doc always shows `DreamEntryDetailSheet` subheading as `categoryLabel + " · " + when`. Code only emits the `" · "` separator when at least one of `promotedAt` or `lastRecalledAt` is non-nil; when both are nil the subheading is `categoryLabel` alone. The conditional is never noted. — `Sources/Design/DreamingScreen.swift:357–362`

**major** — Doc says the close button in `DreamEntryDetailSheet` has `.padding(.leading, 25).padding(.top, 22)`. In code those paddings are applied to the outer `HStack` (which also contains a trailing `Spacer()`), not to the `Button` itself. Placing the padding on the button directly produces a different layout. — `Sources/Design/DreamingScreen.swift:336–338`

**critical** — Doc states "All value text: `Color.primary.opacity(0.6)`" and groups the `statusRow` value with other detail rows. In code the `statusRow` value foreground is `PresenceFormatting.color(entry)` (brand accent or warn color), not `Color.primary.opacity(0.6)`. — `Sources/Design/InstancesScreen.swift:309`

**major** — Doc states "All value text: `lineLimit(1)`, `truncationMode(.middle)`, `textSelection(.enabled)`" and implies this applies to the status row. The `statusRow` in code has none of those modifiers. — `Sources/Design/InstancesScreen.swift:301–311`

**minor** — `DreamingScreen` `entryRow` snippet `Text` applies `.multilineTextAlignment(.leading)`. The spec mentions `.leading` in the hierarchy diagram but omits the modifier name, which a rebuilder must set explicitly. — `Sources/Design/DreamingScreen.swift:143–144`

**minor** — `DreamEntryDetailSheet` body snippet `Text` has `.frame(maxWidth: .infinity, alignment: .leading)`. Not documented in the spec's body layout table. — `Sources/Design/DreamingScreen.swift:303`

**minor** — `DreamEntryDetailSheet` header: the `safeAreaInset` closure contains `ZStack(alignment: .top)`, not a plain `ZStack`. The inner `HStack` wrapping the close button contains a trailing `Spacer()`. Spec omits the alignment parameter and the `Spacer`. — `Sources/Design/DreamingScreen.swift:315–347`

**minor** — `NodeDetailScreen` `listSection` outer `VStack` uses `spacing: 6` between the section header and the card. Spec documents the outer scroll `VStack` spacing (34) but does not specify this inner spacing for Scopes/Roles/Tags sections. — `Sources/Design/InstancesScreen.swift:329`

**minor** — `NodeDetailScreen` list-section empty-state `Text` has `.frame(maxWidth: .infinity, alignment: .leading)`. Spec documents only the text content and style, omitting the frame modifier. — `Sources/Design/InstancesScreen.swift:336–339`

**minor** — `NodeDetailScreen` list-section value rows apply `.frame(maxWidth: .infinity, alignment: .leading)` on each `Text`. Not documented in the spec. — `Sources/Design/InstancesScreen.swift:344–345`

**minor** — `NodeDetailScreen` title falls back to the string literal `"Instance"` when `PresenceFormatting.label(entry)` returns `nil`. Spec mentions `SettingsDestinationChrome` usage but does not document the fallback value. — `Sources/Design/InstancesScreen.swift:246–248`

**minor** — `InstancesScreen` main scroll `VStack` has only `.padding(.top, 4)` and `.padding(.horizontal, 24)`; no `.padding(.bottom, 40)`. The cross-screen table notes "none explicit" which is correct, but the spec body hierarchy omits this asymmetry while other screens call out bottom 40 explicitly. — `Sources/Design/InstancesScreen.swift:112–115`

**minor** — `costLabel` returns `"0$"` for any cost ≤ 0 (guard is `cost > 0`), not only for `nil` or exactly `0`. Negative values are also coerced to `"0$"`. — `Sources/Design/UsageScreen.swift:199–201`

**minor** — `DreamingScreenHost` `mapEntry`: when `lines.count == 1` the snippet body falls back to the full `trimmed` string, meaning `body` equals `title` in that case (identical text in both fields). Spec notes the one-line fallback correctly but does not flag that title and snippet then contain the same text. — `Sources/Design/DreamingScreen.swift:245–246`

**minor** — `CronJobsScreenHost` derives `createdAt` by dividing `job.createdatms` by `1000.0` (milliseconds to seconds). Spec documents descending sort by `createdAt` but omits the ms-to-seconds conversion needed for correct date construction. — `Sources/Design/CronJobsScreen.swift:333`

**minor** — `PresenceFormatting.color` treats a blank/whitespace-only `reason` field as `nil` (via `normalized(entry.reason) == nil`), yielding accent color rather than warn color. Spec states only "reason == nil → accent, else warn", missing the blank-string case. — `Sources/Design/InstancesScreen.swift:210–211`

**minor** — `InstancesScreen` instance list card has no `.frame(maxWidth: .infinity)` wrapper on the card `VStack`, unlike the `UsageScreen` card which has `.frame(maxWidth: .infinity, alignment: .leading)`. Spec does not call out this difference between the two card implementations. — `Sources/Design/InstancesScreen.swift:69–110`

**minor** — `NodeDetailScreen` card helper has `.frame(maxWidth: .infinity, alignment: .leading)` on its `VStack`, paralleling the Usage card, but the spec does not explicitly document this modifier for `NodeDetailScreen`. — `Sources/Design/InstancesScreen.swift:289–290`

**minor** — `DreamEntryDetailSheet` `metaCard` `VStack` uses `spacing: 14` between rows. The spec shows the structure in a code block but the prose table for the meta card does not list the spacing value. — `Sources/Design/DreamingScreen.swift:366`

## Verdict

NEEDS-REPAIR — 5 blocking defects (1 critical, 4 major).
