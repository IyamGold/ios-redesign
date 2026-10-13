# iPad Surfaces (sidebar/detail twins)

This section documents the iPad-only live surfaces that diverge from the phone drawer: `AgentProTab` (used as direct-route destinations in the sidebar), `AgentProNodesDestination`, `AgentProDreamingDestination`, `IPadSkillWorkshopScreen`, `IPadWorkboardScreen`, and `CommandCenterTab`. On iPad the app renders a persistent sidebar (see `RootTabs.sidebarDetail`) rather than a swipe-open drawer, so every phone-drawer destination has an iPad twin that is instantiated differently and may have distinct layout behavior. A change to a phone-drawer destination does NOT automatically update its iPad twin, and vice versa — every parity-sensitive change must touch both paths.

---

## Design token reference

All iPad surfaces share these constants sourced from `Sources/Design/OpenClawProComponents.swift`.

| Token | Value | Usage |
|---|---|---|
| `OpenClawProMetric.pagePadding` | `16` pt | Horizontal inset for every card |
| `OpenClawProMetric.cardRadius` | `16` pt | `ProCard` corner radius |
| `OpenClawProMetric.controlRadius` | `12` pt | Control corner radius |
| `OpenClawProMetric.compactControlSize` | `36` pt | Square hit-target for compact controls |
| `OpenClawProMetric.bottomScrollInset` | `96` pt | `.safeAreaPadding(.bottom, …)` on all scroll views |
| `OpenClawSpacing.space1` | `4` pt | — |
| `OpenClawSpacing.space2` | `8` pt | — |
| `OpenClawSpacing.space3` | `12` pt | Card internal padding (kanban cards) |
| `OpenClawSpacing.space4` | `16` pt | — |
| `OpenClawSpacing.space6` | `24` pt | — |
| `OpenClawRadius.xs` | `8` pt | Inline pill/chip background radius |
| `OpenClawRadius.sm` | `10` pt | `detailMetric` tile background |
| `AgentLayout.cardRadius` | `OpenClawProMetric.cardRadius` (= `16`) | `AgentProTab` cards |
| `AgentLayout.filterHeight` | `34` pt | Header icon-button frame |
| `AgentLayout.metricTileHeight` | `94` pt | Fixed height for each operations metric tile |

---

## Entry point: `RootTabs.sidebarDetail`

**File:** `Sources/RootTabs.swift:620`

When `usesSidebarTabs` is true (iPad / regular horizontal size class) the split-view detail column is driven by `sidebarDetail`. It is a `@ViewBuilder` switch on `selectedSidebarDestination`. The detail is wrapped in `sidebarDetailNavigationShell`, which wraps the content in a `NavigationStack(path: sidebarNavigationPath)` with `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).clipped()`.

The shell identity is pinned by `sidebarDetailShellID` which encodes `selectedSidebarDestination.id + selectedSettingsRoute + selectedSettingsRouteRequestID`. This forces a clean re-instantiation when the destination or settings sub-route changes.

Every destination in `sidebarDetail` receives a `headerLeadingAction` via `sidebarHeaderLeadingAction` — a sidebar-specific action that controls the leading-side drawer/back affordance. On iPad the leading action typically collapses or toggles the sidebar.

### Direct-route `AgentProTab` cases

| `selectedSidebarDestination` | `directRoute` | `headerTitle` |
|---|---|---|
| `.agents` | `.agents` | `"Agents"` |
| `.instances` | `.instances` | `"Instances"` |
| `.files` | `.files` | `"Files"` |
| `.dreaming` | `.dreaming` | `"Dreaming"` |
| `.usage` | `.usage` | `"Usage"` |
| `.cron` | `.cron` | `"Cron Jobs"` |

All six cases pass `.id(self.selectedSidebarDestination.id)` to force SwiftUI to rebuild the view when the destination changes. `openSettings` routes to `selectSidebarDestination(.gateway)`.

### Other sidebar destinations

| `selectedSidebarDestination` | Type |
|---|---|
| `.chat` | `ChatProTab` |
| `.talk` | `TalkProTab` |
| `.overview` | `CommandCenterTab` |
| `.activity` | `IPadActivityScreen` |
| `.workboard` | `IPadWorkboardScreen` |
| `.skillWorkshop` | `IPadSkillWorkshopScreen` |
| `.sessions` | `CommandSessionsScreen` |
| `.terminal` | `TerminalHubScreen` |
| `.docs` | `OpenClawDocsScreen` |
| `.settings` / `.gateway` | `SettingsProTab` |

---

## `AgentProTab` — shared structure

**File:** `Sources/Design/AgentProTab.swift`

`AgentProTab` is a single type that serves both the iPad sidebar (via `directRoute`) and the iPad overview/navigation (when `directRoute` is nil — not used in the current sidebar mapping, but the navigation-stack overview mode is used in other contexts).

### Stored state

| Property | Type | Default |
|---|---|---|
| `navigationPath` | `[AgentRoute]` | `[]` |
| `overview` | `AgentOverviewSnapshot?` | `nil` |
| `overviewErrorText` | `String?` | `nil` |
| `overviewLoading` | `Bool` | `false` |
| `agentRosterFilter` | `AgentRosterFilter` | `.all` |
| `agentSearchPresented` | `Bool` | `false` |
| `agentSearchText` | `String` | `""` |
| `skillFilter` | `String` | `""` |
| `skillStatusFilter` | `SkillStatusFilter` | `.all` |
| `skillMutationBusyKeys` | `Set<String>` | `[]` |
| `skillMutationErrorText` | `String?` | `nil` |
| `skillMutationStatusText` | `String?` | `nil` |
| `skillConfigBusyKeys` | `Set<String>` | `[]` |
| `skillConfigMessages` | `[String: SkillEditorMessage]` | `[:]` |
| `skillAPIKeyDrafts` | `[String: String]` | `[:]` |
| `skillEditorSelection` | `SkillEditorSelection?` | `nil` |
| `clawHubQuery` | `String` | `""` |
| `clawHubResults` | `[ClawHubSearchResultLite]` | `[]` |
| `clawHubLoading` | `Bool` | `false` |
| `clawHubErrorText` | `String?` | `nil` |
| `clawHubInstallSlug` | `String?` | `nil` |
| `cronActionBusyIDs` | `Set<String>` | `[]` |
| `cronActionStatusText` | `String?` | `nil` |

### `body` logic

When `directRoute` is not nil the body calls `directDestination(for:)`, which calls `destination(for:)` and hides the navigation bar unless the route is `.agents` and no leading action is set. When `directRoute` is nil (overview mode) a `NavigationStack(path: navigationPath)` renders `overviewNavigation` — this mode is not used in the current iPad sidebar mapping.

The body attaches a `.task(id: overviewTaskID)` that calls `refreshOverview(force: false)` whenever the gateway/operator connection, active agent ID, or scene phase changes. The task ID is built from:

```
[gatewayConnected ? "connected" : "offline",
 appModel.isOperatorGatewayConnected ? "operator" : "no-operator",
 activeAgentID,
 scenePhase == .active ? "active" : "inactive"]
 .joined(separator: ":")
```

A `.sheet(item: skillEditorSelection)` is always attached. When `skillEditorSelection` is set it presents either `skillEditorSheet(_:)` or `missingSkillEditorSheet`.

### `AgentRoute` enum

`.agents`, `.skills`, `.instances`, `.cron`, `.usage`, `.dreaming`, `.files`

### `AgentRosterFilter` enum

`.all` ("All"), `.online` ("Online"), `.ready` ("Ready") — each case has a `systemImage`: `person.2`, `antenna.radiowaves.left.and.right`, `checkmark.circle`

### `SkillStatusFilter` enum

`.all`, `.enabled`, `.off`, `.setup`, `.blocked`

### `AgentRosterState` enum

`.online` — color `OpenClawBrand.ok`; `.ready` — color `OpenClawBrand.info`

---

## `AgentProTab` — overview/navigation screen

**File:** `Sources/Design/AgentProTab.swift:157`, `AgentProTab+Overview.swift`

This is the non-direct-route mode rendered on iPad when no `directRoute` is passed. The current sidebar mapping does not use this path (all iPad sidebar cases pass a `directRoute`), but it is the primary display when `AgentProTab` is used as a standalone overview tab.

### Layout

`NavigationStack` → `ZStack` (background = `OpenClawProBackground()`) → `ScrollView` → `VStack(alignment: .leading, spacing: 18)` padded `.vertical` by 18.

Top-level sections in order:

1. **`rosterHeader`** — `VStack(alignment: .leading, spacing: 10)` with `.padding(.horizontal, 16)` `.padding(.top, 6)`
2. **`agentFilters`** — `HStack(spacing: 10)` with `.padding(.horizontal, 16)`
3. **`agentsSection`** — `ProCard(padding: 0, radius: 16)` with `.padding(.horizontal, 16)`
4. **`operationsSection`** — `VStack(alignment: .leading, spacing: 8)` with metric grid at `.padding(.horizontal, 16)`
5. **`dreamingSection`** — `VStack(alignment: .leading, spacing: 8)` with `.padding(.horizontal, 16)`
6. **`cronSection`** — `VStack(alignment: .leading, spacing: 8)` with `.padding(.horizontal, 16)`

The scroll view has `.refreshable { await refreshOverview(force: true) }`.

### `rosterHeader`

Title text uses `OpenClawType.title2SemiBold`. Subtitle is `"\(sortedAgents.count) total"` using `OpenClawType.subheadMedium`. The accessory slot holds `OpenClawGlassControlGroup` wrapping an `HStack(spacing: 10)` with:
- `gatewayPillButton` — when `openSettings` is present, a `Button` wrapping `OpenClawGatewayCompactPill` with `.buttonBorderShape(.capsule)` and `.openClawGlassButton()`; otherwise a bare `OpenClawGatewayCompactPill`.
- `headerIconButton` for search — SF Symbol `"magnifyingglass"`, width and height `AgentLayout.filterHeight` (34), `.buttonBorderShape(.circle)` and `.openClawGlassButton()`. Tap animates `.snappy(duration: 0.18)` to toggle `agentSearchPresented`.

When `agentSearchPresented` is true a `TextField("Search agents", ...)` appears with `.transition(.move(edge: .top).combined(with: .opacity))`, font `OpenClawType.subhead`, `.textFieldStyle(.roundedBorder)`, `.frame(height: 38)`.

### Agent roster section

`agentsSection` is a `ProCard(padding: 0, radius: 16)`.

**Empty state:** `HStack(spacing: 12)` — `ProIconBadge(systemName: "person.2.slash", color: .secondary)` + `VStack` with title (`OpenClawType.subheadSemiBold`) and detail (`OpenClawType.caption`, `.secondary`), padded by 14.

**Agent row:** `Button` with `.buttonStyle(.plain)`. Inner content is `HStack(alignment: .center, spacing: 12)` with `.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)`:
- **Avatar** (`agentAvatar`): `ZStack(alignment: .bottomTrailing)` — outer `Circle().fill(agentTint.gradient)` 36×36 with `.overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))`. Badge text: font `OpenClawType.avatar(size: count > 2 ? 14 : 18)`, white, `minimumScaleFactor: 0.62`. Status dot: `Circle().fill(state.color)` 8×8 with `Circle().strokeBorder(Color(uiColor: .systemBackground), lineWidth: 2)`.
- **Name + detail stack**: `VStack(alignment: .leading, spacing: 3)`, `.layoutPriority(1)`. Name: `OpenClawType.subheadSemiBold`. Detail: `OpenClawType.footnote`, `.secondary`, `lineLimit: 1`.
- **Active checkmark**: `Image(systemName: "checkmark")` with `OpenClawType.subheadSemiBold`, `OpenClawBrand.accent`, frame 24×44, shown only when `isActive`.

Dividers between rows are `.padding(.leading, 76)`.

`agentTint(for:state:)`: if active → `OpenClawBrand.accent`; else → `state.color.opacity(0.62)`.

**Agent sort order:** active agent first, then alphabetical by display name (case-insensitive).

**Agent filter logic:** filter by `agentRosterFilter` (`.online` requires `agentRosterState == .online`; `.ready` requires `.ready`), then by `agentSearchText` against name + id + workspace + model label (case-insensitive contains).

### Operations section (metric tiles)

`operationsSection` = `VStack(alignment: .leading, spacing: 8)` with `ProSectionHeader(title: "Live Operations")` and a `LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10)`.

Five tiles: Skills, Instances, Cron, Usage, Files — each rendered via `metricTileContent(icon:title:value:detail:color:showsChevron:)`:

`ProCard(padding: 12, radius: 16)` → `VStack(alignment: .leading, spacing: 10)`:
- Top `HStack`: `ProIconBadge` + `Spacer()` + `ProValuePill(value:, color:)` + optional chevron `Image(systemName: "chevron.right")` (`OpenClawType.captionSemiBold`, `.secondary`).
- Bottom `VStack(alignment: .leading, spacing: 2)`: title (`OpenClawType.captionSemiBold`), detail (`OpenClawType.caption2`, `.secondary`, `lineLimit: 2`, `.multilineTextAlignment(.leading)`).
- `.frame(height: 94, alignment: .topLeading)`.

Each tile with a route is wrapped in a `NavigationLink(value: AgentRoute)`. Tapping navigates in the `NavigationStack`.

**Value strings when disconnected:** all return `"offline"`. When loading: `"..."`. Computed values:
- Skills: `"\(enabledCount)/\(totalCount)"` or `"live"`.
- Instances: `"\(presence.count)"` or `"live"`.
- Cron: `"\(cronStatus.jobs)"` if enabled, else `"off"`.
- Usage: formatted as USD `"$0.00"` or compact token notation.
- Files: `activeAgentID`.

**Tile colors:** Skills/Usage/Files/Dreaming → `gatewayConnected ? OpenClawBrand.accent : .secondary`. Instances → `presence.isEmpty == false ? OpenClawBrand.accent : .secondary`. Cron → `cronStatus.enabled == true ? OpenClawBrand.accent : .secondary`.

### `agentMenuRow` (dreaming, cron preview rows)

`HStack(spacing: 12)` → `ProIconBadge` + `VStack(alignment: .leading, spacing: 3)` (title: `OpenClawType.subheadSemiBold`, detail: `OpenClawType.caption`, `.secondary`, `lineLimit: 1`) + `Spacer(minLength: 8)` + value text (`OpenClawType.caption2SemiBold`, tinted by color, `lineLimit: 1`) + optional chevron.

### Dreaming section

`dreamingSection` wraps a `ProCard(radius: 16)` containing a `NavigationLink(value: AgentRoute.dreaming)` with `agentMenuRow(icon: "moon", title: "Dreaming", ...)`.

### Cron section

`cronSection`: `ProCard(padding: 0, radius: 16)`. Up to 4 recent cron jobs (`recentCronJobs`) sorted by `nextRunAtMs` ascending, then by `updatedatms` descending for jobs with no next run. Each job row (`cronJobRow`) is:
- `HStack(spacing: 12)` with `.padding(.vertical, 10)` `.padding(.horizontal, 14)`.
- Icon: `"clock.arrow.circlepath"` if `job.enabled`, else `"pause.circle"`. Color: `accent` if enabled, else `.secondary`.
- Name: `OpenClawType.subheadSemiBold`, lineLimit 1. Detail: `OpenClawType.caption`, `.secondary`, lineLimit 1 (uses `nextRunAtMs` relative time, else description, else agentId, else id).
- State text: `OpenClawType.caption2SemiBold`, `accent` if enabled else `.secondary`, lineLimit 1.
- Dividers between rows: `.padding(.leading, 60)`.

Each cron row is wrapped in a `NavigationLink(value: AgentRoute.cron)`.

### Overview data fetch

`refreshOverview(force:)` fires concurrently in `async let` for: `skills.status`, `config.get`, `system-presence`, `cron.status`, `cron.list`, `doctor.memory.status`, `doctor.memory.dreamDiary`, `usage.cost`. Default timeout is 8 s; `cron.list` and `usage.cost` use 12 s. `cron.list` params: `{"includeDisabled":true,"limit":8,"sortBy":"nextRunAtMs","sortDir":"asc"}`. `usage.cost` params: `{"days":31}`. Results are combined into `AgentOverviewSnapshot`. If `liveGatewayConnected` is false, overview is cleared.

---

## `AgentProTab.agentsDestination` — iPad agents list

**File:** `Sources/Design/AgentProTab+Destinations.swift:32`

Rendered when `directRoute == .agents`. Uses SwiftUI `.listStyle(.insetGrouped)`, `.navigationTitle(headerTitle)`, `.navigationBarTitleDisplayMode(.large)`, `.searchable(text: agentSearchText, prompt: "Search agents")`, `.refreshable`. Toolbar trailing: `agentFilterMenu` (`Menu` with `Picker` for `AgentRosterFilter`) + `gatewayToolbarButton`.

`gatewayToolbarButton`: `Button(action: openSettings)` wrapping `Image(systemName: gatewayConnected ? "antenna.radiowaves.left.and.right" : "wifi.slash")` with `.tint(gatewayConnected ? OpenClawBrand.ok : .secondary)`.

---

## `AgentProTab.skillsDestination` — iPad skills

**File:** `Sources/Design/AgentProTab+Destinations.swift:65`

`ZStack` (background) → `ScrollView` → `VStack(alignment: .leading, spacing: 16)` padded `.vertical` by 18.

Sections in order:
1. `detailSummaryCard` (icon: `"sparkles"`, title: `"Skills"`)
2. `skillsPolicyControls`
3. `skillsFilterField`
4. `clawHubSearchCard`
5. `skillsList`

`.safeAreaPadding(.bottom, 96)`. `.navigationTitle("Skills")`, `.navigationBarTitleDisplayMode(.inline)`.

### `skillsPolicyControls`

`ProCard(radius: 16)` → `VStack(alignment: .leading, spacing: 12)`:
- Header: `HStack(alignment: .firstTextBaseline)` — active agent name (`OpenClawType.headline`), skill policy summary (`OpenClawType.caption`, `.secondary`), `ProValuePill` showing `agentSkillFilter == nil ? "all" : "\(count)"` in `OpenClawBrand.accent`.
- Buttons: `HStack(spacing: 8)` — "Enable All", "Disable All" (`.destructive` role), "Reset" — all `.bordered` `.small`. "Reset" disabled when `agentSkillFilter == nil`.
- Status/error text: `OpenClawType.caption2`, status in `OpenClawBrand.accent`, error in `OpenClawBrand.warn`.

### `skillsFilterField`

`ProCard(padding: 10, radius: 16)` → `VStack(alignment: .leading, spacing: 10)`:
- Search row: `HStack(spacing: 10)` — SF Symbol `"magnifyingglass"` (`OpenClawType.captionSemiBold`, `.secondary`) + `TextField("Search skills", ...)` (`OpenClawType.subhead`) + clear button (shown when not empty).
- Status `Picker` — `.segmented`, `.controlSize(.small)`. Filters: `.all`/`.enabled`/`.off`/`.setup`/`.blocked`.

### `clawHubSearchCard`

`ProCard(radius: 16)` → `VStack(alignment: .leading, spacing: 12)`:
- Header: `HStack(spacing: 10)` — `ProIconBadge("square.and.arrow.down", color: OpenClawBrand.accent)` + `VStack` (title: `"Install Skills"` `OpenClawType.headline`, subtitle: `OpenClawType.caption`, `.secondary`) + search `Button` (`.bordered`, `.small`, disabled when `clawHubLoading || !liveGatewayConnected`).
- `TextField("Search ClawHub", ...)` — `.submitLabel(.search)`, triggers `searchClawHubSkills()` on submit.
- Loading `ProgressView` when `clawHubLoading`.
- Error text in `OpenClawBrand.warn`.
- Results list: up to 8 results, `clawHubResultRow(_:)`.

`clawHubResultRow`: `HStack(alignment: .top, spacing: 10)` + `ProIconBadge("sparkles")` + `VStack` (display name `OpenClawType.subheadSemiBold`, summary `OpenClawType.caption`, `.secondary`, `lineLimit: 2`) + install `Button` (icon: `"hourglass"` if installing, else `"square.and.arrow.down"`, `.bordered`, `.mini`). Rows have `.padding(.vertical, 10)`, dividers between rows at `.padding(.leading, 42)`.

### `skillsList`

`VStack(alignment: .leading, spacing: 8)` → `ProSectionHeader(title: "Installed Skills")` → `ProCard(padding: 0, radius: 16)`.

Each `skillRow`:
- `HStack(alignment: .top, spacing: 12)` with `.padding(.vertical, 10)` `.padding(.horizontal, 14)`.
- Left: `ProIconBadge(systemName: isAllowed ? "checkmark.circle" : "nosign", color: status.color)`.
- Center: `VStack(alignment: .leading, spacing: 4)` — display name (`OpenClawType.subheadSemiBold`, `lineLimit: 1`), description/source (`OpenClawType.caption`, `.secondary`, `lineLimit: 2`), missing requirements text in `OpenClawBrand.warn` (`OpenClawType.caption2`), install summary (`OpenClawType.caption2`, `.secondary`).
- Right: `VStack(alignment: .trailing, spacing: 6)` — `skillToggle` (`.toggleStyle(.switch)`, `.controlSize(.mini)`), setup button (`.bordered`, `.mini`) when `canInstallSkillRequirements`, edit button (SF Symbol `"slider.horizontal.3"`, `.bordered`, `.mini`), status label (`OpenClawType.caption2SemiBold`, tinted by status color).
- Dividers between rows at `.padding(.leading, 60)`.

**Skill status → color mapping:**

| Status | Color |
|---|---|
| `"off"` (not allowed or agent-filtered) | `.secondary` |
| `"blocked"` (allowlist) | `.secondary` |
| `"disabled"` | `.secondary` |
| `"setup"` (missing requirements) | `OpenClawBrand.warn` |
| `"enabled"` | `OpenClawBrand.accent` |

**Sort order:** allowed skills before disallowed, then alphabetical case-insensitive.

### Skill editor sheet

Presented over the current view via `.sheet(item: skillEditorSelection)`.

`skillEditorSheet` is a `NavigationStack` → `ZStack` (background) → `ScrollView` → `VStack(alignment: .leading, spacing: 16)` padded `.vertical: 18`. Sections: header card, controls card, setup card, metadata card. `.navigationTitle(skill.displayName)` `.navigationBarTitleDisplayMode(.inline)`. Cancel toolbar button: `Text("Close")` `OpenClawType.subheadSemiBold`, `.cancellationAction`.

`skillEditorToggleRow`: Due to a known iOS 26 bug where native Toggle rows can ignore visible-row taps inside sheets, the toggle is implemented as a `Button` calling `onToggle(!isOn)` with a label showing `OpenClawToggleIndicator(isOn:)`. The `Button` is `.plain` style, `.accessibilityLabel(title)`, `.accessibilityValue(isOn ? "On" : "Off")`. Do not simplify this to a native Toggle without verifying the bug is fixed.

`skillSecureField`: A `ZStack(alignment: .leading)` with a `SecureField("", text: binding)` plus an overlay `Text(placeholder)` (`.tertiary`, `.allowsHitTesting(false)`, `.accessibilityHidden(true)`) when the field is empty. The actual `SecureField` has `.accessibilityLabel(placeholder)`.

---

## `AgentProNodesDestination` — iPad instances

**File:** `Sources/Design/AgentProNodesDestination.swift`

Instantiated from `AgentProTab.instancesDestination` with props forwarded from the parent tab.

### Props

| Prop | Type | Description |
|---|---|---|
| `headerLeadingAction` | `OpenClawSidebarHeaderAction?` | Present when in direct-route mode |
| `overview` | `AgentOverviewSnapshot?` | Snapshot from parent |
| `gatewayConnected` | `Bool` | Drives empty states |
| `agentCount` | `Int` | `appModel.gatewayAgents.count` |
| `instancesValue` | `String` | Formatted presence count or status |
| `instancesDetail` | `String` | Up to 2 presence labels joined by `", "` |
| `instancesColor` | `Color` | `accent` if presence > 0, else `.secondary` |
| `refresh` | `async () -> Void` | Calls `refreshOverview(force: true)` |

### Layout

`ZStack` (background) → `ScrollView` → `VStack(alignment: .leading, spacing: 16)` with `.padding(.vertical, 18)` and `.font(OpenClawType.body)`. `.refreshable`. `.safeAreaPadding(.bottom, 96)`. `.navigationTitle("Instances")` `.navigationBarTitleDisplayMode(.inline)`.

Sections in order:
1. **`header`** — conditional on `headerLeadingAction`: `OpenClawAdaptiveHeaderRow(title: "Instances", subtitle: instancesDetail, titleFont: OpenClawType.title3SemiBold, subtitleFont: OpenClawType.subheadMedium)` with `OpenClawSidebarHeaderLeadingSlot(action:)`. `.padding(.horizontal, 16)`.
2. **`summaryCard`** — `ProCard` with `HStack(spacing: 12)`: `ProIconBadge("display", color: instancesColor)` + `VStack` (title `OpenClawType.headline`, detail `OpenClawType.caption`, `.secondary`) + `Spacer(minLength: 8)` + `ProValuePill`. `.padding(.horizontal, 16)`.
3. **`totalsCard`** — `ProCard` with `VStack(alignment: .leading, spacing: 12)`: "Presence" label (`OpenClawType.headline`) + `ProValuePill` in header, then `HStack(spacing: 10)` with three `detailMetric` tiles: Connected, Agents, Gateway.
4. **`nodesList`** — `VStack(alignment: .leading, spacing: 8)` → `ProSectionHeader("Connected Instances")` → `ProCard(padding: 0)`.

### `detailMetric` helper

`VStack(alignment: .leading, spacing: 3)` — label: `OpenClawType.caption2Medium`, `.secondary`; value: `OpenClawType.subheadSemiBold`, `lineLimit: 1`, `minimumScaleFactor: 0.8`. Background: `Color.primary.opacity(0.055)` in `RoundedRectangle(cornerRadius: 10, style: .continuous)`. `.frame(maxWidth: .infinity, alignment: .leading)` `.padding(10)`.

### Node presence rows

`nodePresenceRow`: `HStack(alignment: .top, spacing: 12)` with `.padding(.vertical, 10)` `.padding(.horizontal, 14)`. Fields: `ProIconBadge` (icon/color from `PresenceFormatting`) + `VStack` (label `OpenClawType.subheadSemiBold`, detail `OpenClawType.caption` `.secondary` `lineLimit: 2`, meta `OpenClawType.caption2` `.secondary` `lineLimit: 1`) + `Spacer(minLength: 8)` + state label (`OpenClawType.caption2SemiBold`, `PresenceFormatting.color`) + optional chevron (`OpenClawType.caption2Bold`, `.secondary`, `.padding(.top, 2)`).

Meta string = `"instance \(instanceid)"` + first 2 tags + scopes count + roles count, joined by `" • "`.

Each row is wrapped in a `NavigationLink { NodeDetailScreen(entry: entry) }`. Dividers: `.padding(.leading, 60)`. Sort: by `ts` descending; ties broken by label ascending.

---

## `AgentProDreamingDestination` — iPad dreaming

**File:** `Sources/Design/AgentProDreamingDestination.swift`

### Props

| Prop | Type |
|---|---|
| `headerLeadingAction` | `OpenClawSidebarHeaderAction?` |
| `overview` | `AgentOverviewSnapshot?` |
| `gatewayConnected` | `Bool` |
| `overviewLoading` | `Bool` |
| `dreamingValue` | `String` |
| `dreamingDetail` | `String` |
| `dreamingColor` | `Color` |
| `refresh` | `async () -> Void` |

### Local state

| Property | Type | Default |
|---|---|---|
| `selectedDreamDiaryDayID` | `String?` | `nil` |
| `dreamActionBusy` | `DreamAction?` | `nil` |
| `dreamActionStatusText` | `String?` | `nil` |

### Layout

`ZStack` → `ScrollView` → `VStack(alignment: .leading, spacing: 16)` padded `.vertical: 18` with `.font(OpenClawType.body)`. `.refreshable`. `.safeAreaPadding(.bottom, 96)`. `.navigationTitle("Dreaming")` `.navigationBarTitleDisplayMode(.inline)`.

Sections in order:
1. **`header`** (conditional on `headerLeadingAction`) — `OpenClawAdaptiveHeaderRow(title: "Dreaming", subtitle: dreamingDetail, titleFont: OpenClawType.title3SemiBold, subtitleFont: OpenClawType.subheadMedium)`. `.padding(.horizontal, 16)`.
2. **`detailSummaryCard`** (icon: `"moon"`, title: `"Dreaming"`).
3. **`dreamingTotalsCard`** — "Memory State" with `HStack(spacing: 10)` of three `detailMetric` tiles: Short-term, Signals, Promoted. Shows `storeError` in `OpenClawBrand.warn` `OpenClawType.caption2` when present.
4. **`dreamingActionsCard`** — "Maintenance" with refresh button + three `DreamAction` buttons.
5. **`dreamDiaryCard`** — "Dream Diary" section with file path, update timestamp, day-selector menu, and day body.
6. Three `dreamingEntriesList` sections: "Promoted Entries", "Signal Entries", "Short-Term Recall".
7. **`dreamingPhasesCard`** — "Phases" with `.light`, `.deep`, `.rem` phase rows.

### `DreamAction` enum

| Case | Title | Icon | Gateway method |
|---|---|---|---|
| `.backfill` | `"Backfill"` | `"book.pages"` | `"doctor.memory.backfillDreamDiary"` |
| `.repair` | `"Repair"` | `"wrench.and.screwdriver"` | `"doctor.memory.repairDreamingArtifacts"` |
| `.dedupe` | `"Dedupe"` | `"square.stack.3d.down.right"` | `"doctor.memory.dedupeDreamDiary"` |

Actions are disabled when `!gatewayConnected || dreamActionBusy != nil`. Active action shows `"hourglass"` icon. Timeout: 30 s.

### `dreamingActionsCard`

`ProCard` → `VStack(alignment: .leading, spacing: 12)`. Header: `HStack` with title/subtitle plus refresh `Button` (`.bordered`, `.small`) using `"hourglass"` or `"arrow.clockwise"` icon. Actions: `HStack(spacing: 8)` of `ForEach(DreamAction.allCases)` buttons. Status text: `OpenClawType.caption2`, `.secondary`, `lineLimit: 3`.

### `dreamDiaryCard`

Attempts to extract `overview.dreamDiary`. If found with content, parses markdown into `[DreamDiaryDay]` using `dreamDiaryDays(from:)`:
- Strips HTML comment markers `<!-- openclaw:dreaming:diary:start -->` / `<!-- openclaw:dreaming:diary:end -->` if present.
- Splits on `\n---` or `\r\n---`; falls back to splitting by date lines (`*Month DD, YYYY*` or `*YYYY-MM-DD*` patterns with `unwrappedEmphasis`).
- Merges blocks with the same day title, appending bodies with `"\n\n---\n\n"`.
- `hasDatedEntry` must be true; undated blocks are filtered out.

**Day selector menu:** `Menu` with reversed day order (newest last → menu shows newest at top), calendar icon, styled as capsule with `Color.primary.opacity(0.055)` background, height 34.

**Day body display:** `Text(day.body)` with `OpenClawType.monoSmall`, `.lineLimit(120)`, `.textSelection(.enabled)`. Background: `Color.primary.opacity(0.045)` in `RoundedRectangle(cornerRadius: 10, style: .continuous)`. `.padding(10)`.

Default selected day: last day in list (chronologically latest).

### Dreaming entry rows

`HStack(alignment: .top, spacing: 12)` with `.padding(.vertical, 10)` `.padding(.horizontal, 14)`. Icon: `"text.page"` in `OpenClawBrand.accent`. Title = last path component + `":\(startLine)"`. Snippet: `OpenClawType.caption`, `.secondary`, `lineLimit: 4`, `.textSelection(.enabled)`. Detail: promoted/recalled timestamps + recall count + grounded count, joined by `" • "`. Trailing: `totalSignalCount` as `OpenClawType.caption2SemiBold` in `OpenClawBrand.accent`. Dividers: `.padding(.leading, 60)`.

### Phase rows

Phase order: `["light", "deep", "rem"]`. Each `dreamingPhaseRow`: icon `"pause.circle"` (`.secondary`) if `enabled == false`, else `"moon.stars"` (`OpenClawBrand.accent`). Title: capitalized phase name. Detail: next run relative time if `nextRunAtMs` present; else "Managed cron is installed." or "Managed cron is not installed.". State: `"off"` / `"scheduled"` / `"setup"`. State label color: `accent` if `managedCronPresent == true`, else `.secondary`. Cron expression shown as `OpenClawType.caption2`, `.secondary`, `lineLimit: 1` when present.

---

## `IPadSidebarScreenChrome` — shared container

**File:** `Sources/Design/IPadSidebarScreenChrome.swift`

Used by `IPadWorkboardScreen` and `IPadSkillWorkshopScreen` (and `IPadActivityScreen`). Wraps content in:

`ZStack` (background = `OpenClawProBackground()`) → `ScrollView` → `VStack(alignment: .leading, spacing: isCompactHeight ? 10 : 16)` padded `.vertical: isCompactHeight ? 10 : 18`.

When `!usesNativeNavigationChrome`, renders `OpenClawAdaptiveHeaderRow(title:, subtitle:, titleFont: isCompactHeight ? OpenClawType.headline : OpenClawType.title2SemiBold)` at the top with accessory `gatewayPill` (tappable if `gatewayAction` provided). `.padding(.horizontal, 16)`.

`.safeAreaPadding(.bottom, isCompactHeight ? 150 : 96)` (150 for compact height to clear system bars in landscape).

`.navigationTitle(title)` `.navigationBarTitleDisplayMode(.inline)`. When `usesNativeNavigationChrome`, shows toolbar with gateway `Button` at `.topBarTrailing`.

`isCompactHeight` = `verticalSizeClass == .compact`.

---

## `IPadSkillWorkshopScreen` — Skill Workshop

**File:** `Sources/Design/IPadSkillWorkshopScreen.swift`

### Props

| Prop | Default |
|---|---|
| `headerLeadingAction` | `nil` |
| `usesNativeNavigationChrome` | `false` |
| `openSettings` | `{}` |

### Local state

| Property | Type | Default |
|---|---|---|
| `proposals` | `[IPadSkillProposal]` | `[]` |
| `selectedProposalID` | `String?` | `nil` |
| `selectedAgentScopeID` | `String` | `""` |
| `statusFilter` | `String` | `"pending"` |
| `query` | `String` | `""` |
| `isLoading` | `Bool` | `false` |
| `inspectingProposalID` | `String?` | `nil` |
| `busyAction` | `IPadSkillProposalAction?` | `nil` |
| `errorText` | `String?` | `nil` |
| `noticeText` | `String?` | `nil` |
| `presentedProposalRoute` | `IPadSkillProposalSheetRoute?` | `nil` |

### Layout via `IPadSidebarScreenChrome`

Title: `"Skill Workshop"`. Subtitle: `"Review and apply proposed skills."`.

**Wide layout** (`!isCompactWidth`):
1. `ProMetricGrid(metrics: metrics)` — 3 metrics: Pending (`warn`), Applied (`ok`), Held (`.secondary`).
2. `filtersCard` — agent scope menu + search field + segmented status picker + refresh button.
3. `proposalBoard` — horizontal `ScrollView` of `IPadSkillProposalKanbanColumn` cards, each `frame(width: 282)`.

**Compact layout** (`isCompactWidth`):
1. `compactFiltersCard` — count/label header + agent scope menu + segmented picker + search field + refresh button.
2. `proposalList` — vertical list with `ProPanelHeader`.

`isCompactWidth` = `horizontalSizeClass == .compact || verticalSizeClass == .compact`.

### Status filters

`proposalStatusFilters = ["pending", "held", "applied", "rejected", "all"]`

The `Picker` uses `.segmented` style, `.controlSize(.small)`, `.tint(OpenClawBrand.accent)`.

`"held"` maps to `status == "quarantined" || status == "stale"`.

### Kanban board

`ScrollView(.horizontal)` → `HStack(alignment: .top, spacing: 12)`. `scrollIndicators(.visible)`. `.padding(.horizontal, 16)`.

`visibleProposalLaneStatuses` is computed from `proposalStatusBoardLanes(filter:proposalStatuses:)`. Default lanes: `["pending", "quarantined", "stale", "applied", "rejected"]`. "all" filter adds custom statuses. "held" filter reduces to `["quarantined", "stale"]`.

### `IPadSkillProposalKanbanColumn`

`ProCard(padding: 0, radius: OpenClawProMetric.cardRadius)` → `VStack(spacing: 0)`. Header: `ProPanelHeader(title: laneLabel, value: "\(count)")`. Empty state: `ProStatusRow`. Proposals: `IPadSkillProposalKanbanCard` with `Divider().padding(.leading, 12)` between rows.

### `IPadSkillProposalKanbanCard`

`VStack(alignment: .leading, spacing: 10)` → `.padding(OpenClawSpacing.space3)` (12). Selected background: `OpenClawBrand.accent.opacity(0.08)` in `RoundedRectangle(cornerRadius: 8, style: .continuous)`. `.contentShape(Rectangle())`.

Content:
- `Button` (`.plain`) with icon (`"hourglass"` when inspecting, else `"hammer"`) + title (`OpenClawType.subheadSemiBold`, tinted `OpenClawBrand.accent` when selected, else `.primary`, `lineLimit: 2`) + description (`OpenClawType.caption`, `.secondary`, `lineLimit: 3`).
- `HStack(spacing: 8)` with `ProValuePill` + age label (`OpenClawType.caption2SemiBold`, `.secondary`).
- Action buttons row (pending only): Apply (`"checkmark.circle"`), Reject (`"xmark.circle"`, `.destructive`), Inspect (`"doc.text.magnifyingglass"`) — all `.bordered`, `.mini`.
- `.contextMenu` with Inspect + (for pending) Apply/Reject.

### `IPadSkillProposalRow` (list mode)

`HStack(alignment: .top, spacing: 12)` with `.padding(.horizontal, 14)` `.padding(.vertical, 10)`. Selected background: `OpenClawBrand.danger.opacity(0.08)` (note: uses `danger` not `accent`) in `RoundedRectangle(cornerRadius: 8)`. Icon `"hourglass"` when `isBusy`, else `"hammer"`. Title: `subheadSemiBold`, `accent` if selected else `.primary`, `lineLimit: 1`. Description: `caption`, `.secondary`, `lineLimit: 2`. Age: `caption2SemiBold`, `.secondary`.

Swipe actions: trailing (no full swipe) — Apply (`ok` tint), Reject (`.destructive`); leading (full swipe) — Inspect (`accent` tint).
Context menu: Inspect + (pending only) Apply/Reject.

### `IPadSkillProposal` model

`statusColor` mapping:

| Status | Color |
|---|---|
| `"pending"` | `OpenClawBrand.warn` |
| `"applied"` | `OpenClawBrand.ok` |
| `"rejected"` | `.secondary` |
| `"quarantined"`, `"stale"` | `OpenClawBrand.warn` |
| default | `OpenClawBrand.accent` |

`ageLabel`: `"now"` < 1 min; `"\(min)m"` < 1 h; `"\(h)h"` < 24 h; else `"\(d)d"`.

Content is fetched lazily via `skills.proposals.inspect` (timeout 20 s). Previous content is preserved when `updatedAtMs` matches. YAML frontmatter (`^---\n...\n---\n`) is stripped.

### Proposal detail sheet

`.sheet(item: presentedProposalRoute)` wrapping a `NavigationStack` → `ScrollView` → `proposalDetailCard` in `.padding(.horizontal, pagePadding)` `.padding(.vertical, OpenClawSpacing.space4)`. `.navigationBarTitleDisplayMode(.inline)`. Confirm toolbar button: `Text("Done")`.

Detail card actions layout: compact → `VStack(spacing: 8)`, wide → `HStack(spacing: 8)`. Content body: `OpenClawType.monoSmall`, `.secondary`, `lineLimit: 16`, `.textSelection(.enabled)`. Support files: monospace `OpenClawType.monoCaption2`, `.secondary`, `lineLimit: 1`.

### Gateway data flow

Load: `skills.proposals.list` (timeout 20 s) with `IPadSkillProposalListParams(agentId: selectedAgentParam)`. Response decoded as `IPadSkillProposalManifest`. Previous proposals' content/supportFiles are preserved when `updatedAtMs` matches. After load, auto-inspects `selectedProposalID` if set.

Write: `skills.proposals.apply` / `skills.proposals.reject` (timeout 30 s). Requires `canWrite && hasOperatorAdminScope`. After mutation: reloads full list.

Admin-scope guard: when `!canApplyProposalMutations`, shows `HStack` with `"lock.shield"` (`OpenClawBrand.warn`) + `"Admin scope required."` (`OpenClawType.captionSemiBold`, `.secondary`).

---

## `IPadWorkboardScreen` — Workboard

**File:** `Sources/Design/IPadWorkboardScreen.swift`

### Props

| Prop | Default |
|---|---|
| `headerLeadingAction` | `nil` |
| `usesNativeNavigationChrome` | `false` |
| `openChat` | required |
| `openSettings` | `{}` |

### Local state

| Property | Type | Default |
|---|---|---|
| `cards` | `[IPadWorkboardCard]` | `[]` |
| `statuses` | `[String]` | `IPadWorkboardDefaults.statuses` |
| `selectedStatus` | `String` | `"active"` |
| `selectedBoardID` | `String` | `""` |
| `knownBoardIDs` | `[String]` | `[]` |
| `query` | `String` | `""` |
| `isLoading` | `Bool` | `false` |
| `errorText` | `String?` | `nil` |
| `draftTitle` | `String` | `""` |
| `draftNotes` | `String` | `""` |
| `isCreatingCard` | `Bool` | `false` |
| `busyCardID` | `String?` | `nil` |
| `dispatchSummaryText` | `String?` | `nil` |
| `presentedSheet` | `IPadWorkboardSheet?` | `nil` |

`IPadWorkboardDefaults.statuses = ["todo", "scheduled", "ready", "running", "review", "blocked", "done"]`

### Layout via `IPadSidebarScreenChrome`

Title: `"Workboard"`. Subtitle: `workboardSubtitle` = `"\(boardScopeLabel) / \(IPadWorkboardDefaults.label(for: selectedStatus))"`.

**Wide layout** (`!isCompactWidth`):
1. `ProMetricGrid(metrics: metrics)` — 3 metrics: Cards (`accent`), Running (`ok`), Blocked (`warn`).
2. `controlsCard` — board scope menu + search field + segmented status picker + New Card/Dispatch/Refresh buttons.
3. `kanbanBoard` — horizontal scroll of `IPadWorkboardKanbanColumn`, each `frame(width: 282)`.

**Compact layout**:
1. `compactQueueControls` — card count + board scope menu + status chip scroll + New Card/Dispatch buttons.
2. `compactCardsPanel` — `ProPanelHeader` + `IPadWorkboardQueueRow` list.

`isCompactWidth` = `horizontalSizeClass == .compact || verticalSizeClass == .compact`.

### Segmented picker (wide)

Includes `"Active"` tab + all statuses. `"Active"` = all non-done, non-archived cards. `.pickerStyle(.segmented)`, `.controlSize(.small)`, `.tint(OpenClawBrand.accent)`.

### Compact status chips

`ScrollView(.horizontal)` → `HStack(spacing: 8)` → capsule buttons. Selected chip: `OpenClawBrand.accent.opacity(0.12)` background, `OpenClawBrand.accent.opacity(0.42)` border, `accent` text. Unselected: `Color.primary.opacity(0.06)` background, `Color.primary.opacity(0.08)` border. Height 30, horizontal padding 10, font `OpenClawType.caption2SemiBold`. Gradient fade at trailing edge: `LinearGradient([.clear, Color(uiColor: .secondarySystemGroupedBackground)])` width 24, `.allowsHitTesting(false)`.

### Kanban board

`ScrollView(.horizontal)` → `HStack(alignment: .top, spacing: 12)` → columns. `.scrollIndicators(.visible)`. `.padding(.horizontal, 16)` `.padding(.bottom, 12)`.

Visible kanban statuses: if `selectedStatus == "active"` → all statuses except `"done"`; else single-status lane.

### `IPadWorkboardKanbanColumn`

`ProCard(padding: 0, radius: OpenClawProMetric.cardRadius)` → `ProPanelHeader` + empty `ProStatusRow` or `IPadWorkboardKanbanCard` rows with `Divider().padding(.leading, 12)`.

### `IPadWorkboardKanbanCard`

`VStack(alignment: .leading, spacing: 10)` → `.padding(OpenClawSpacing.space3)` (12). `.contentShape(Rectangle())`.

- `Button(action: inspect)` (`.plain`) → `VStack(alignment: .leading, spacing: 7)`:
  - `HStack(alignment: .top, spacing: 10)`: `ProIconBadge` + `VStack` (title `subheadSemiBold` `lineLimit: 2`, detail `caption` `.secondary` `lineLimit: 3`).
  - Labels (first 3): `OpenClawType.caption2Medium`, `.secondary`, `lineLimit: 1`.
- Action `HStack(spacing: 8)`: session open button (if `sessionKey` non-empty), actions `Menu` (ellipsis icon, `.bordered`, `.mini`), `Spacer`, `ProValuePill`.

**Card icon/color mapping:**

| Status | Icon | Color |
|---|---|---|
| `"running"` | `"figure.run"` | `OpenClawBrand.ok` |
| `"review"` | `"checklist"` | `OpenClawBrand.accentForeground` |
| `"blocked"` | `"exclamationmark.triangle"` | `OpenClawBrand.warn` |
| `"done"` | `"checkmark.circle"` | `.secondary` |
| default | `"tray"` | `OpenClawBrand.accentHotForeground` |

### `IPadWorkboardQueueRow`

`HStack(alignment: .top, spacing: 10)` with `.padding(.horizontal, 14)` `.padding(.vertical, 10)`. Inspect button (`.plain`) with full-width content + actions `Menu` (`"ellipsis.circle"` size 19 semibold, 36×36, `OpenClawBrand.accent`). `.contextMenu { actionMenuItems }`.

Swipe leading (full swipe): Inspect (`accent`), Open Session (`ok`) if session present.
Swipe trailing (no full swipe): next-status button (`OpenClawBrand.accentHot`), Archive (`.secondary`). Next status = element immediately after current in `statuses` array.

### New card sheet

`Form` with section header `"Card"` containing title `TextField` (`.sentences` autocap) and notes `TextField(axis: .vertical, lineLimit: 3...6)`. Error section if `errorText` present. `.navigationTitle("New Card")` `.navigationBarTitleDisplayMode(.inline)`. Cancel + Create toolbar buttons.

### Card detail sheet (`IPadWorkboardCardDetailSheet`)

`NavigationStack` → `Form` with two sections. Section "Card": `LabeledContent` rows for Title and Status, notes text if non-empty. Section "Actions": Open Session button (if `sessionKey`), Move `Menu`, Archive/Unarchive button. Done toolbar button.

### `open(card:)` behavior

Dismisses the current sheet first (`presentedSheet = nil`), then calls `appModel.openChat(sessionKey: sessionKey)` + `openChat()` to navigate to Chat. This prevents the old card detail sheet obscuring the target chat session.

### Gateway data flow

Load cards: `workboard.cards.list` (20 s). Loads boards: `workboard.boards.list` (20 s). Create: `workboard.cards.create` (20 s). Move: `workboard.cards.move` (20 s). Archive: `workboard.cards.archive` (20 s). Dispatch: `workboard.cards.dispatch` (45 s) with `IPadWorkboardDispatchSummary` decoded.

Card position ordering: next position = `maxPosition + 1000` among cards with same status.

`applyCardsResponse` normalizes statuses (falls back to `IPadWorkboardDefaults.statuses` if empty) and sorts cards by position.

---

## `CommandCenterTab` — Overview tab

**File:** `Sources/Design/CommandCenterTab.swift`

Serves as the `.overview` sidebar destination on iPad. Also used as a standalone phone tab (not documented here).

### Props

| Prop | Default |
|---|---|
| `ownsNavigationStack` | `true` |
| `usesNativeNavigationChrome` | `false` |
| `headerTitle` | `"OpenClaw"` |
| `headerLeadingAction` | `nil` |
| `showsHeaderMark` | `true` |
| `openChat` | required |
| `openSettings` | required |
| `openSessions` | `nil` |

On iPad `ownsNavigationStack` is `false` (the sidebar's `NavigationStack` wraps it), `usesNativeNavigationChrome` is `false`, `headerTitle` is `"Overview"`, `showsHeaderMark` is `false`.

### Local state

| Property | Type |
|---|---|
| `defaultChatSessionEntry` | `OpenClawChatSessionEntry?` |
| `recentChatSessions` | `[OpenClawChatSessionEntry]` |

### Layout

`GeometryReader` → `ZStack` (background = `CommandControlBackground` = `OpenClawProBackground()`, ambient overlay, `ScrollView`).

`ScrollView` → `VStack(alignment: .leading, spacing: 14)` with `.padding(.top, 18)` `.padding(.bottom, 18)`. `.safeAreaPadding(.bottom, 96)`.

**Wide split layout** (triggered by `horizontalSizeClass == .regular && containerWidth >= 1000`):

```
HStack(alignment: .top, spacing: 12) {
    defaultChatSessionSection.frame(maxWidth: .infinity, alignment: .topLeading)
    recentSessions.frame(maxWidth: .infinity, alignment: .topLeading)
}
.padding(.horizontal, 16)
```

**Standard layout** (container < 1000 or compact):

```
defaultChatSessionSection.padding(.horizontal, 16)
recentSessions.padding(.horizontal, 16)
```

**Header** (when `!usesNativeNavigationChrome`): `OpenClawAdaptiveHeaderRow(title: headerTitle, subtitle: gatewaySubtitle, titleFont: OpenClawType.title3SemiBold, subtitleFont: OpenClawType.caption, subtitleLineLimit: 1)`. Leading slot: `OpenClawSidebarHeaderLeadingSlot(action:)` if present, else `OpenClawProMark(size: 28, shadowRadius: 5)` (shown only when `!hasLeadingAction && showsHeaderMark`). Accessory: `Button(action: openSettings) { Image("gearshape.fill") }` with `.openClawGlassButton()`, frame `36×36`.

**Ambient overlay** (light mode only): `LinearGradient([Color.white.opacity(0.05), Color.clear])` top-to-bottom, `.ignoresSafeArea()`, `.allowsHitTesting(false)`.

### `gatewayCard`

`CommandPanel(isProminent: true, padding: 12)` → `VStack(alignment: .leading, spacing: 10)`. Card header: `Text("Gateway")` `OpenClawType.subheadSemiBold`, `.secondary`.

Three `gatewayFact` tiles in `HStack(spacing: 0)` with `Divider().frame(height: 38)` between them. Connection / Address / Agents.

`gatewayFact(icon:title:value:color:)`: `VStack(alignment: .leading, spacing: 6)` → icon `Image(systemName:)` (`OpenClawType.caption2Bold`, tinted) + title `Text` (`OpenClawType.caption2Medium`, `.secondary`) in `HStack(spacing: 5)`; value `Text` (`OpenClawType.captionSemiBold`, tinted for Connection else `.primary`, `lineLimit: 1`, `minimumScaleFactor: 0.72`). `.frame(maxWidth: .infinity, alignment: .leading)` `.padding(.horizontal, 10)`.

**Gateway status → color:**

| State | Text | Color |
|---|---|---|
| `.connected` | `"Online"` | `OpenClawBrand.ok` |
| `.connecting` | `"Connecting"` | `OpenClawBrand.accent` |
| `.error` | `"Attention"` | `OpenClawBrand.warn` |
| `.disconnected` | `"Offline"` | `.secondary` |

`.padding(.vertical, 7)` on the three-fact `HStack`.

### `defaultChatSessionSection`

`CommandPanel(padding: 12)` → `VStack(spacing: 10)`. Card header `"Agent session"`. Single `Button` (`.plain`) → `CommandSessionRow(item: defaultChatWorkItem)`.

`defaultChatWorkItem`: icon `"bubble.left.and.text.bubble.right.fill"` if current, else `"bubble.left.fill"`. Color: `accent` if open, else `ok`. Title: `appModel.activeAgentName`. Detail: relative time of last activity or `"No recent activity"`. State: `"open"` or `"default"`. Trailing: `"chat"`.

### `recentSessions`

`CommandPanel(padding: 12)` → `VStack(spacing: 10)`. Card header `"Recent sessions"`. Sessions come from `recentSessionPreviewSessions` — a selection from `CommandSessionGrouping.previewSelection`.

Each session: `Button` (`.plain`) → `CommandSessionRow(item:)` with `.commandSessionActions(…)` modifier.

"View more" row shown when `hasMoreRecentSessions`. If `openSessions` is set, calls it; else pushes `CommandSessionsScreen` via `NavigationLink`.

Empty state: `CommandEmptyStateRow(icon:, title:, detail:)`.

### `CommandSessionRow`

`HStack(alignment: .center, spacing: 12)` with `.padding(.horizontal, 4)` `.padding(.vertical, 6)`:
- Icon: `Image(systemName:)` `OpenClawType.captionSemiBold`, tinted, 30×30 in `RoundedRectangle(cornerRadius: 10)` filled at `color.opacity(0.12)`.
- `VStack(alignment: .leading, spacing: 4)`:
  - Title row: optional unread dot (`Circle()` 7×7 `accent`), title `OpenClawType.subheadSemiBold` `lineLimit: 1` `minimumScaleFactor: 0.82`, spacer, optional pin icon (`caption2Medium`, `accent`), trailing label `caption2Medium`, `.secondary`.
  - Detail row: detail `OpenClawType.caption`, `.secondary`, `lineLimit: 1`; optional `ProProgressBar(width: 68)`; progress/state label `OpenClawType.captionSemiBold`, tinted, `lineLimit: 1`, `frame(width: 48, alignment: .trailing)`.

### Session title/key redaction

`redactedSessionTitle(for:)`:
- Contains `:ios-` → `"iOS chat"`
- Starts with `telegram:` → `"Telegram chat"`
- Starts with `user:+` → `"Direct chat"`
- Starts with `cron:` → humanized slug

`isRecentChatSession` excludes: the default session key, direct sessions matching the default base or "main"/"global"/`"node-*"`, `"onboarding"` sessions, and agent-device sessions (`agent:*:*:thread` pattern matching default base).

### `CommandSessionsScreen`

Full sessions browser. Accessible via sidebar `.sessions` destination or the "View more" link from `CommandCenterTab`.

`ZStack` (background) → `ScrollView` → `VStack(alignment: .leading, spacing: 10)` `.padding(.top, 16)` `.padding(.bottom, 18)`. `.safeAreaPadding(.bottom, 96)`.

Shows archived/active toggle (`.switch`, `.mini`) when `sessionControlsAvailable`. Groups sessions via `CommandSessionGrouping.sections(from:knownGroups:)`. Session rows use `CommandSessionRow` with `.commandSessionActions` modifier. Group section headers have `.contextMenu` for rename/create/delete.

Group mutations update `SessionGroupStore` and patch all members (both active and archived) via `transport.patchSession`. Limit for full-store enumeration: 10,000 rows per list call.

### `CommandSessionActionsModifier`

Context menu modifier with: Pin/Unpin, Mark as Read/Unread, Rename, Fork, Move to Group (`Menu`), Archive, Delete (with confirmation dialog). Rename and New Group use `.alert` with `TextField`. Delete uses `.confirmationDialog` (`.visible` titleVisibility). All mutations use `performSessionMutation` + refresh.

### Session load

Fetch limit: `CommandCenterTab.recentSessionsFetchLimit = 200`. Falls back to `appModel.loadCachedChatSessions()` on error. After successful load calls `appModel.reconcileChatSessionReadState` and `storeCachedChatSessions`.

---

## Parity map: phone-drawer vs iPad-sidebar changes

When any of the following phone-drawer destinations is modified, the corresponding iPad twin must be updated in the same change to maintain pixel and behavior parity.

| Phone drawer destination | iPad sidebar twin | File(s) |
|---|---|---|
| `DreamingScreenHost` (phone) | `AgentProTab(directRoute: .dreaming)` → `AgentProDreamingDestination` | `AgentProDreamingDestination.swift` |
| `UsageScreenHost` (phone) | `AgentProTab(directRoute: .usage)` → `usageDestination` | `AgentProTab+Destinations.swift`, `AgentProTab+Usage.swift` |
| `InstancesScreenHost` (phone) | `AgentProTab(directRoute: .instances)` → `AgentProNodesDestination` | `AgentProNodesDestination.swift` |
| `CronJobsScreenHost` (phone) | `AgentProTab(directRoute: .cron)` → `cronDestination` | `AgentProTab+Destinations.swift`, `AgentProTab+Cron.swift` |
| `FilesWorkspaceScreenHost` (phone) | `AgentProTab(directRoute: .files)` → `AgentWorkspaceFilesScreen` | `AgentProTab+Destinations.swift`, `AgentWorkspaceFilesScreen.swift` |
| `SkillsScreenHost` (phone) | `AgentProTab(directRoute: .skills)` → `skillsDestination` | `AgentProTab+Destinations.swift`, `AgentProTab+Skills.swift` |
| `ChatDrawer` agent selector (phone) | `AgentProTab(directRoute: .agents)` → `agentsDestination` | `AgentProTab+Destinations.swift`, `AgentProTab+Overview.swift` |
| `DreamingScreenHost` sessions — n/a | `CommandCenterTab` + `CommandSessionsScreen` | `CommandCenterTab.swift`, `CommandCenterSupport.swift` |

**Architecture note (from `CLAUDE.md`):** Phone chat visuals live in `ChatRootSurface`, NOT in `OpenClawChatUI`'s `ChatView`/`ChatMessageViews`/`ChatComposer`. iPad still uses `AgentProTab` for agents/instances/files/dreaming/usage/cron. A phone-drawer change does NOT update the iPad twin — change both explicitly when parity matters.
