# Audit — 13-ipad.md

## Scorecard

| metric | value |
|---|---|
| precision | 0.944 |
| recall | 0.643 |
| F | 0.765 |
| critical | 2 |
| major | 12 |
| minor | 20 |
| certified | false |
| claims | 111 |

## Defects (fix these)

### Wrong / Unsupported Claims

**critical** — Doc says: when `directRoute` is not nil the body calls `directDestination(for:)`, which hides the navigation bar unless the route is `.agents` and no leading action is set. Code says: the toolbar is hidden when `route != .agents` AND `self.directHeaderLeadingAction(for: route) != nil` (i.e. hidden only when a leading action IS set and route is not agents, opposite of "no leading action"). — `Sources/Design/AgentProTab.swift:157` / lines 183-188.

**major** — Doc says: `cronSection` section header title is `"Cron Jobs"`. Code says: `ProSectionHeader(title: "Scheduled Work")`. — `Sources/Design/AgentProTab+Overview.swift:230`.

**minor** — Doc says: `clawHubResultRow` install button control size is `.mini`. Code says: `.controlSize(.small)`. — `Sources/Design/AgentProTab+Skills.swift:179`.

**minor** — Doc says: ClawHub install button has `.controlSize(.mini)`. Code says: `.controlSize(.small)`. — `Sources/Design/AgentProTab+Skills.swift:179`.

---

### Omissions

**major** — `agentFilters` view has a conditional clear-filter button (`xmark.circle.fill`, font `title3`, 44×44 frame, `contentShape Circle`, plain style) shown only when `agentFiltersActive = (agentRosterFilter != .all || agentSearchText non-empty)`. Doc describes the HStack picker but omits the clear button and the `agentFiltersActive` compound condition entirely. — `Sources/Design/AgentProTab+Overview.swift:63-92`.

**major** — `cronSection` section header title is `"Scheduled Work"` (`ProSectionHeader(title: "Scheduled Work")`). Doc treats it as a "cron section" with no title, leading to a wrong header label. — `Sources/Design/AgentProTab+Overview.swift:229-255`.

**major** — `cronSection` empty state: when the jobs list is empty the entire card body is a `NavigationLink(.cron)` wrapping `emptyCronRow` (icon `clock.badge.questionmark`, two text lines). The empty-state link and icon are not mentioned in the doc. — `Sources/Design/AgentProTab+Overview.swift:232-244`.

**minor** — `agentMenuRow` has `.padding(.vertical, 10)` on the HStack, not documented. This row is used for the Dreaming card preview; the missing padding changes row height. — `Sources/Design/AgentProTab+Overview.swift:354-377`.

**major** — `usageValue` returns `"7d"` (not `"live"`) when connected but `overview` is nil and `overviewLoading` is false. Doc says the fallback is `"live"` for that case, which is wrong. — `Sources/Design/AgentProTab+Overview.swift:647-659`.

**minor** — `metricTileContent` uses `.frame(maxWidth: .infinity, alignment: .leading)` on the inner VStack in addition to the fixed-height frame. Not mentioned in the doc. — `Sources/Design/AgentProTab+Overview.swift:441-443`.

**critical** — `skillEditorMetadata` card (key, source, filePath rendered with `OpenClawType.monoCaption2`) is a fourth section in the skill editor sheet but is not mentioned at all in the doc. A rebuilder would omit this entire card. — `Sources/Design/AgentProTab+Skills.swift:588-602`.

**major** — `skillRow` toggle is a native `Toggle` (`.switch`, `.mini`), not the iOS-26-workaround Button. The iOS-26 Button workaround is used only in `skillEditorToggleRow` inside the sheet. Doc does not distinguish these two paths; a rebuilder may apply the workaround to the list toggle incorrectly. — `Sources/Design/AgentProTab+Skills.swift:348-360`.

**major** — `skillEditorSetup` card content: "Setup" headline, missing text (or "No missing requirements reported."), and an install button using `install.label` + `wrench.and.screwdriver` icon, `.bordered .small`, disabled when busy or `install.id == nil`. Doc says there is a "setup card" section but does not describe any of these details. — `Sources/Design/AgentProTab+Skills.swift:558-586`.

**minor** — `clawHubResultRow` install button is disabled when `installing || !skillConfigBusyKeys.isEmpty`, not just `installing`. Doc describes only the `installing` condition. — `Sources/Design/AgentProTab+Skills.swift:177-183`.

**minor** — `skillsPolicyControls` status/error text are rendered by separate `if-let` blocks (statusText in accent, errorText in warn). Doc correctly notes accent/warn but omits that they appear in separate conditional blocks that can both show simultaneously. — `Sources/Design/AgentProTab+Skills.swift:51-60`.

**minor** — `AgentProNodesDestination` `summaryCard` and `totalsCard` both use `ProCard` with default padding. Doc implies specific padding values for both cards but does not document them. — `Sources/Design/AgentProNodesDestination.swift:53-88`.

**minor** — `nodePresenceRow` VStack detail text uses `lineLimit 2` (not 1) and the label title uses `lineLimit 1`. Doc correctly documents `lineLimit: 2` for detail but omits the `lineLimit: 1` on the label. — `Sources/Design/AgentProNodesDestination.swift:139-145`.

**major** — `dreamDiaryDayView` includes a title/entry-count header row above the body text: `HStack(alignment: .firstTextBaseline)` with `day.title` (`subheadSemiBold`, `lineLimit 1`) + `Spacer` + "X entries" (`caption2SemiBold`, accent). Doc describes the body display but entirely omits this header row. — `Sources/Design/AgentProDreamingDestination.swift:305-326`.

**major** — `dreamDiaryCard` outer structure is a `VStack(alignment: .leading, spacing: 8)` wrapping `ProSectionHeader` + `ProCard(padding: 0)`, not just a `ProCard`. The inner VStack when content is found uses `padding(14)` but the `ProCard` itself has `padding: 0`. Doc does not describe this layered structure. — `Sources/Design/AgentProDreamingDestination.swift:217-271`.

**minor** — `dreamingActionsCard` subtitle text is `"Refresh reads live state. Maintenance actions update the gateway diary/artifacts."` with `lineLimit 2`. Doc mentions the card has a header with subtitle but does not document the subtitle string. — `Sources/Design/AgentProDreamingDestination.swift:172-179`.

**minor** — `dreamingActionsCard` action status text is `foregroundStyle(.secondary)`. Doc describes `OpenClawType.caption2 .secondary` correctly but omits `lineLimit: 3`. — `Sources/Design/AgentProDreamingDestination.swift:206-211`.

**minor** — `dreamDiaryDayMenu` label uses `HStack(spacing: 6)` with calendar Image + Text capped at `minimumScaleFactor 0.75`, height 34, Capsule background `Color.primary.opacity(0.055)`. Doc states height 34 and opacity 0.055 but omits `minimumScaleFactor 0.75` and the HStack spacing. — `Sources/Design/AgentProDreamingDestination.swift:286-301`.

**minor** — `dreamingEntriesList` empty state icon is `doc.text.magnifyingglass`. Doc does not specify this icon for the entries list empty state. — `Sources/Design/AgentProDreamingDestination.swift:348-351`.

**minor** — `IPadWorkboardScreen` `compactQueueControls` outer VStack uses `spacing: 9`, not 12. Doc does not document this value, which affects compact layout appearance. — `Sources/Design/IPadWorkboardScreen.swift:188-189`.

**major** — `IPadWorkboardScreen` wide `controlsCard` `boardScopeMenu` uses a labeled HStack (`"Board"` in `captionSemiBold .secondary`) + Menu with `.bordered .small .tint(neutralControlTint)`. `compactBoardScopeMenu` is a standalone Menu with `rectangle.stack` icon, height 32, cornerRadius xs. Doc describes the compact variant but the wide `boardScopeMenu` structure is not documented. — `Sources/Design/IPadWorkboardScreen.swift:355-390`.

**major** — `IPadWorkboardQueueRow` detail text fallback chain (notes → sessionKey → agentId → "Default agent") applies identically to both `KanbanCard` and `QueueRow`. Doc does not document this shared fallback chain for either component. — `Sources/Design/IPadWorkboardScreen.swift:1099-1108`.

**minor** — `IPadWorkboardKanbanCard` labels row shows first 3 labels (`prefix(3)`) joined by `", "`, in `caption2Medium .secondary lineLimit 1`, shown only when labels non-empty. Doc says "Labels (first 3): caption2Medium, .secondary, lineLimit: 1" correctly but omits the `", "` join separator and the non-empty guard. — `Sources/Design/IPadWorkboardScreen.swift:1027-1031`.

**minor** — `agentRow` Button action is a no-op when `isActive` (`guard !isActive else return`). Doc describes the button tap setting the active agent but does not mention this guard. — `Sources/Design/AgentProTab+Overview.swift:274-276`.

**minor** — `CommandCenterTab` `gatewayFact` icon colors: Address fact uses `OpenClawBrand.accentForeground`, Agents fact uses `OpenClawBrand.accentHotForeground` for the icon tint. Doc does not specify that the icon itself takes these colors. — `Sources/Design/CommandCenterTab.swift:178-188`.

**minor** — `CommandCenterTab` `cardHeader` helper: `Text(title)` is `subheadSemiBold .secondary` in an `HStack(spacing: 8)` with `Spacer`. This helper wraps both the "Agent session" and "Recent sessions" panel headers. Doc describes only the gateway panel header and does not document the shared helper pattern. — `Sources/Design/CommandCenterTab.swift:290-297`.

**major** — `CommandSessionsScreen` header is a custom HStack with optional `OpenClawSidebarHeaderLeadingSlot` + VStack (`OpenClawType.title2` title, `captionMedium .secondary` subtitle), NOT an `OpenClawAdaptiveHeaderRow`. Doc does not describe this screen's header layout at all. — `Sources/Design/CommandCenterTab.swift:782-797`.

**minor** — `CommandSessionsScreen` `sessionsPanel` panel header row uses `subheadBold` (not `subheadSemiBold`) for the recent/archived toggle label text. Doc does not describe the panel internal header layout. — `Sources/Design/CommandCenterTab.swift:803-806`.

**minor** — `CommandSessionsScreen` `sectionHeader` only shows contextMenu (Rename/New Group/Delete) for custom category sections, never for Pinned/Ungrouped built-in sections. Doc mentions contextMenu for section headers but does not document this built-in section guard. — `Sources/Design/CommandCenterTab.swift:908-921`.

**minor** — `CommandSessionsScreen` scrollView VStack uses `spacing: 10` and `.padding(.top, 16)` / `.padding(.bottom, 18)`. Doc states the padding values correctly but does not document `spacing: 10`. — `Sources/Design/CommandCenterTab.swift:728-737`.

## Verdict

NEEDS-REPAIR — 14 blocking defects (2 critical + 12 major).
