# Audit — 01-architecture.md

## Scorecard

| metric | value |
|---|---|
| precision | 0.978 |
| recall | 0.7 |
| F | 0.816 |
| critical | 0 |
| major | 9 |
| minor | 10 |
| certified | false |
| claims | 91 |

## Defects (fix these)

### Wrong/Unsupported Claims

**major** — Doc states: sidebar header button uses `Image(systemName: "xmark")` in drawer mode when sidebar is hidden (`Sources/RootTabs.swift:785`). Code says: `sidebarHeaderLeadingAction` uses `systemName: "sidebar.left"` in ALL cases — both visible and hidden states, in both split and drawer mode. The icon never becomes `"xmark"`. The `"xmark"` icon belongs to the separate inline `sidebarHideButton`, not to the `sidebarHeaderLeadingAction` passed to detail screens. — `Sources/RootTabs.swift:785-803`

### Omissions

**major** — Doc does not document `sidebarHeaderLeadingAction` using `"sidebar.left"` for both show and hide states in drawer mode. The distinction between `sidebarHideButton` (inline, uses `"xmark"`) and `sidebarHeaderLeadingAction` (passed to detail screens, always `"sidebar.left"`) is entirely absent. — `Sources/RootTabs.swift:797-804`

**major** — `headerIdentityBadge` is entirely absent from the doc. It is a `30×30 pt Circle()` filled with `OpenClawBrand.accent`, containing the agent badge text in white at `OpenClawType.avatar(size: agentBadge.count > 2 ? 12 : 15)`, with `minimumScaleFactor(0.6)` and `lineLimit(1)`. This is a nav-bar UI element in `ChatProTab`. — `Sources/Design/ChatProTab.swift:193-202`

**major** — `chatActionsMenu` is undocumented. It is an `ellipsis.circle` `Menu` containing: a "New Chat" button (disabled when no `viewModel`/`gateway`/attachment pinned), a conditional "New Chat in Worktree" button (only when `activeAgent?.workspacegit == true`), and an "Export Transcript" button. — `Sources/Design/ChatProTab.swift:334-379`

**major** — Doc says agent badge initials come from "First 2 words" but omits that the split also treats `"-"` and `"_"` as word separators, not just whitespace. This affects badge rendering for agent names such as `"my-agent"` or `"my_agent"`. — `Sources/Design/ChatProTab.swift:531`

**major** — `syncChatViewModel` has a third code path absent from the doc: when `viewModelRoutingContract != routingContract` but `ownerID` and `transportAgentID` are unchanged, it calls `viewModel.syncSessionRoutingContract(...)` without rebuilding. The doc documents only the rebuild path and the `syncSession(to:)` path. — `Sources/Design/ChatProTab.swift:236-239`

**major** — `phoneChatReturn` / `PhoneChatReturn` contextual back-to-control feature is entirely missing. The chat header can show a "Back to <destination>" `chevron.left` action when navigated from a control destination, driven by `phoneChatReturn` state and the `openChatFromControlDetail` path. — `Sources/RootTabs.swift:806-813`

**major** — `canQueueOffline` conditional logic is absent. When `isAttachmentOwnerPinned` is true, offline queuing is gated on `viewModelHasVerifiedOfflineRoutingIdentity` rather than `appModel.hasVerifiedChatOfflineRoutingIdentity`. This affects both the `messagePlaceholder` and the composer/attachment enable state. — `Sources/Design/ChatProTab.swift:467-472`

**major** — Several `ChatProTab` `@State` properties driving UI behavior are undocumented: `viewModelRoutingContract` (gates routing contract sync), `viewModelPresentationAgentID`/`Name`/`Badge` (frozen during attachment pin, shown in header), `viewModelHasVerifiedOfflineRoutingIdentity` (gates offline queue placeholder), and `speech` (`OpenClawChatSpeechController` for TTS). — `Sources/Design/ChatProTab.swift:13-27`

**minor** — `sidebarIdentityHeader` `HStack` has `spacing: 10` and inner `VStack` has `spacing: 2`. Neither spacing value is documented. — `Sources/RootTabs.swift:499,503`

**minor** — `sidebarIdentityHeader` contains `Spacer(minLength: 8)` between the title `VStack` and the hide button. Not documented. — `Sources/RootTabs.swift:521`

**minor** — `sidebarHideButton` has `.frame(width: 44, height: 44)` hit target. Not documented. — `Sources/RootTabs.swift:830`

**minor** — `sidebarList` has `.background(Color(uiColor: .systemBackground))` in addition to the column's own background. Not documented. — `Sources/RootTabs.swift:564`

**minor** — `OpenClawApp.body` applies `.onReceive(UIContentSizeCategory.didChangeNotification)` to call `OpenClawType.refreshUIKitAppearance(in:)`, meaning dynamic type changes trigger a UIKit appearance refresh. Not documented. — `Sources/OpenClawApp.swift:721-725`

**minor** — New-chat button claim (image asset `ChatPlusGlyph`, `20×20 pt`, `34×34 pt` hit target) in the drawer header cites `ChatDrawer.swift:233`. This file is not among the owned files verified in this audit; the claim is unverifiable from owned sources. — `Sources/Design/ChatDrawer.swift:233`

**minor** — `sidebarHideButton` uses `.foregroundStyle(OpenClawBrand.accent)` for its icon color. Not documented. — `Sources/RootTabs.swift:833`

**minor** — Sidebar list row omits `.frame(maxWidth: .infinity, alignment: .leading)` and `.contentShape(Rectangle())`, which are required for the full-width tap target. Doc states padding values correctly but misses these two modifiers. — `Sources/RootTabs.swift:604-607`

**minor** — Doc does not mention that `normalizedBadgeEmoji` is a separate `nonisolated static func` reused in both `currentAgentBadge` (`ChatProTab`) and `homeCanvasBadge` (`RootTabs`), with a subtly different nil-check behavior (`nil` return vs `"OC"` fallback at different layers). — `Sources/Design/ChatProTab.swift:540-544`

**minor** — `PhoneTabSettingsHost` section does not document the `swipeBackActive` `@State` property that gates row taps during swipe-to-go-back, preventing accidental navigation pushes when a back-swipe passes over a settings row. — `Sources/RootTabs.swift:1608`

## Verdict

NEEDS-REPAIR — 9 major defects block certification.
