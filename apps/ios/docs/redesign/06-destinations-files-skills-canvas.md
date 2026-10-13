# Drawer Destinations — Files, Skills, Canvas

This section specifies three drawer destinations reachable from `ChatDrawerHost`: the Files workspace browser (a two-level LazyVGrid backed by `agents.workspace.list`/`agents.workspace.get`), the Skills roster (a searchable list with per-skill toggle and detail panel), and the Canvas archive (an index of `[embed …]` shortcodes from the transcript, each openable as a full-screen web view). Together these cover `FilesGridScreen`, `AgentWorkspaceFilesScreen`, `SkillsScreen`, and `CanvasArtifacts.swift`.

---

## 1. Shared Design Tokens

These values recur across all three destinations.

### 1.1 Background Color

Both light and dark share the same pair used by all redesigned drawer destinations:

| Mode | RGB values | Hex |
|------|-----------|-----|
| Dark | `23/255, 23/255, 23/255` | `#171717` |
| Light | `245/255, 244/255, 250/255` | `#F5F4FA` |

Applied with `.ignoresSafeArea()` as the bottommost layer of a `ZStack`.

### 1.2 Frosted-Glass Nav Button (Glass Chrome)

All nav and close buttons share one Chrome style:

| Property | Dark value | Light value |
|----------|-----------|-------------|
| Shape | `Circle()` | `Circle()` |
| `ChatGlassBackground` fill | `Color(red:30/255, green:30/255, blue:30/255).opacity(0.2)` | `Color(red:245/255, green:244/255, blue:250/255).opacity(0.2)` |
| Shadow | `.black.opacity(0.15)`, radius `25`, x `0`, y `0` | same |
| Hit frame | `40 × 40 pt` | same |
| Icon frame | `22 × 22 pt` inside the 40 pt frame | same |
| Icon rendering | `.template`, `.foregroundStyle(Color.primary)` | same |

### 1.3 Header Insets (safeAreaInset top)

All three screens inject their header as `.safeAreaInset(edge: .top, spacing: 0)`:

| Inset | Value |
|-------|-------|
| `padding(.top, …)` | `8 pt` |
| `padding(.bottom, …)` | `27 pt` (Files, Skills); `14 pt` (Canvas archive) |

Header title: `.system(size: 20, weight: .medium)`, `.foregroundStyle(Color.primary)`, centered in a `ZStack`.

Title width/line clamping differs by screen:

| Screen | `lineLimit` | `frame(maxWidth:)` | Cite |
|--------|-------------|--------------------|------|
| Files (`FilesGridScreen`) | `lineLimit(1)` | `200 pt` | `Sources/Design/FilesGridScreen.swift:64-65` |
| Skills (`SkillsScreen`) | none | none | `Sources/Design/SkillsScreen.swift:66-67` |
| Canvas archive / viewer (`CanvasPanelHeader`) | `lineLimit(1)` | `240 pt` | `Sources/Design/CanvasArtifacts.swift` (§5.9) |
| Skill detail (`SkillPanelSheet`) | — | `188 pt` | §4.9 |

The `frame(maxWidth: 200)` on the Files title keeps a long folder name from overlapping the leading/trailing nav buttons. The `SkillsScreen` title is the fixed string `"Skills"`, so it carries neither constraint.

### 1.4 Card Fill (tiles and info cards)

| Mode | Fill |
|------|------|
| Dark | `Color.black` |
| Light | `Color.white` |

Tile border: `.strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5)`, `RoundedRectangle(cornerRadius: 12, style: .continuous)`.

---

## 2. Files Destination

### 2.1 Entry Point and Routing

`ChatDrawerDestination.files` in `ChatDrawerHost` routes to `FilesWorkspaceScreenHost` (Sources/Design/FilesGridScreen.swift:177). The destination's leading button calls `openDrawer` — a spring animation (`duration: 0.35`) that sets `isChatDrawerOpen = true` — reopening the side-nav. There is no back-to-chat button; navigation between surfaces is always via the drawer.

`FilesWorkspaceScreenHost` wraps a `NavigationStack` whose root is `FilesWorkspaceFolderView(agentId:, path: "", title: "Files", isNested: false, onClose:)` (Sources/Design/FilesGridScreen.swift:183-190).

**Agent ID resolution** (Sources/Design/FilesGridScreen.swift:193-204): tries `appModel.selectedAgentId`, then `appModel.gatewayDefaultAgentId`, then falls back to `"main"`. Whitespace-only strings are treated as nil.

### 2.2 `FilesGridScreen` View Hierarchy

```
ZStack(alignment: .top)
├── Background Color (#171717 / #F5F4FA) — ignoresSafeArea
└── ScrollView
    ├── LazyVGrid(columns: [2 × GridItem(.flexible(), spacing: 28)], alignment: .leading, spacing: 20)
    │   └── ForEach entries → tile(_:)
    ├── (if entries empty) Text("Nothing here yet.")
    └── safeAreaInset(.top) → header ZStack
        ├── Text(title)  ← centered
        └── HStack(leading button, trailing "i" button if root)
```

Sources/Design/FilesGridScreen.swift:34-106.

### 2.3 Grid Layout Metrics

| Property | Value |
|----------|-------|
| Number of columns | 2 |
| Inter-column spacing | `28 pt` |
| Row spacing (LazyVGrid `spacing:`) | `20 pt` |
| Horizontal padding | `24 pt` on each side |
| Top padding | `4 pt` |
| Bottom padding | `40 pt` |

Sources/Design/FilesGridScreen.swift:29-49.

### 2.4 Tile (`tile(_:)`) Anatomy

Each tile is a `Button` with `.buttonStyle(.plain)` and a `VStack(alignment: .leading, spacing: 10)`. The VStack label carries `.contentShape(Rectangle())` so the whole tile footprint — including the gap between the icon well and the label block — is tappable, not just the drawn glyph/text (Sources/Design/FilesGridScreen.swift:165).

**Icon well** (Sources/Design/FilesGridScreen.swift:131-149):

| Property | Value |
|----------|-------|
| Shape | `RoundedRectangle(cornerRadius: 12, style: .continuous)` |
| Fill | Dark: `Color.black`; Light: `Color.white` |
| Height | `108 pt` |
| Width | `.frame(maxWidth: .infinity)` |
| Border | `.strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5)` |
| Glyph — folder | Asset `"FilesFolderGlyph"` (SVG: `li_folder.svg`) |
| Glyph — file | Asset `"FilesFileGlyph"` (SVG: `li_file.svg`) |
| Glyph render mode | `.template`, `.resizable()`, `.scaledToFit()` |
| Glyph frame | `37 × 37 pt` |
| Glyph color | `Color.primary.opacity(0.75)` |
| Loading state | `ProgressView()` (replaces glyph while `loadingID == entry.id`) |

**Label block** (Sources/Design/FilesGridScreen.swift:151-163):

| Property | Value |
|----------|-------|
| Stack | `VStack(alignment: .leading, spacing: 6)` |
| Name font | `.system(size: 14)` |
| Name color | `Color.primary` |
| Name limit | `lineLimit(1)` |
| Type label font | `.system(size: 12)` |
| Type label color | `Color.primary.opacity(0.6)` |
| Type label limit | `lineLimit(1)`, `.truncationMode(.tail)` |

`typeLabel` value: folders show `"Folder"`; files show the uppercased path extension (`(name as NSString).pathExtension.uppercased()`). An unusually long extension must truncate with "…" rather than wrap, which would grow the cell and misalign the grid row (Sources/Design/FilesGridScreen.swift:159-161).

### 2.5 Header Buttons

**Root screen (`isNested == false`)**:
- Leading: `Image("ChatBackGlyph")`, glass chrome, calls `onClose`.
- Trailing: `Button` with `Text("i")`, `.system(size: 19)`, glass chrome, calls `onInfo`. Shows only at root; nested screens omit it (Sources/Design/FilesGridScreen.swift:87-98).

**Nested screen (`isNested == true`)**:
- Leading: `Image(systemName: "chevron.left")`, `.system(size: 17, weight: .semibold)`, glass chrome, calls `onClose` which resolves to `dismiss()` from `@Environment(\.dismiss)`.
- No trailing button.

### 2.6 Navigation — Folder Drill-Down

Tap a folder tile → `OpenClawHaptics.tap()` fires, then `onOpenFolder(entry)` sets `pushedFolder`. The `navigationDestination(item: $pushedFolder)` pushes a new `FilesWorkspaceFolderView` with the folder's `id` as `path`, `folder.name` as `title`, and `isNested: true` (Sources/Design/FilesGridScreen.swift:231-237). The `NavigationStack` owns the push stack; the back button on each nested level pops via `dismiss()`.

### 2.7 File Preview

Tap a file tile → `loadingID = entry.id`, then `fetchPreviewURL(entry)` is awaited. On return, `previewURL` is set, `loadingID` is cleared. The modifier `.quickLookPreview($previewURL)` presents QuickLook automatically (Sources/Design/FilesGridScreen.swift:105).

**Temp file writing** (`writeTempFile`, Sources/Design/FilesGridScreen.swift:318-332): the file is written under a UUID-named subdirectory of `FileManager.default.temporaryDirectory/OpenClawWorkspaceFiles/` so QuickLook's renderer can detect the file type from its extension. Base64-encoded files are decoded to raw bytes; UTF-8 files are written directly.

### 2.8 Data Loading (Pagination)

`FilesWorkspaceFolderView.load()` (Sources/Design/FilesGridScreen.swift:252-276):
- Calls `agents.workspace.list` with `agentid`, optional `path` (nil for root), and `offset`.
- Pages until `collected.count >= total` or `guardCount >= 50`.
- Dedupes by `path` on each page.
- Maps `AgentsWorkspaceEntry` to `WorkspaceGridEntry(id: path, name:, isFolder: kind == "directory")`.
- Timeout: `12 s`.

The `.task(id: "\(agentId)|\(path)")` re-runs whenever the agent or path changes (Sources/Design/FilesGridScreen.swift:230).

### 2.9 Info Alert

Triggered by the root "i" button. Title: `"File not loading?"`. Message: `"Update and restart the gateway, or change gateway access to \"Full Access\"."`. Button: `Text("OK").font(.system(size: 17, weight: .medium))` (Sources/Design/FilesGridScreen.swift:239-248).

### 2.10 Empty State

If `entries.isEmpty`: `Text("Nothing here yet.")`, `.system(size: 16)`, `Color.primary.opacity(0.6)`, `.padding(.top, 32)` (Sources/Design/FilesGridScreen.swift:51-57).

---

## 3. `AgentWorkspaceFilesScreen` (iPad / Legacy Surface)

This is the **iPad** sidebar variant. The phone drawer uses `FilesWorkspaceScreenHost` + `FilesGridScreen` (§2 above). `AgentWorkspaceFilesScreen` is still live for iPad — do not confuse the two.

**Structure** (Sources/Design/AgentWorkspaceFilesScreen.swift:8-38):

```
ZStack
├── OpenClawProBackground()
└── VStack(alignment: .leading, spacing: 0)
    ├── (if headerLeadingAction) OpenClawAdaptiveHeaderRow(
    │       title: "Files", subtitle: agentId,
    │       titleFont: OpenClawType.title3SemiBold,
    │       subtitleFont: OpenClawType.subheadMedium)
    │   .padding(.horizontal, OpenClawProMetric.pagePadding)
    └── AgentWorkspaceDirectoryList(agentId:, path: "")
```

`AgentWorkspaceDirectoryList` renders a `List` (`.insetGrouped`, `.scrollContentBackground(.hidden)`) with `NavigationLink` rows. Each row is an `HStack(spacing: 12)` (Sources/Design/AgentWorkspaceFilesScreen.swift:108-125):
- An `Image(systemName:)` icon: `"folder"` (`OpenClawBrand.accent`) for directories, `"doc.text"` (`Color.secondary`) for files, sized `.font(OpenClawType.subhead)` and clamped to `.frame(width: 24)` so the following `VStack` aligns regardless of glyph width.
- `Text(entry.name)` at `OpenClawType.subhead`, primary, `lineLimit(1)`.
- An optional detail line (`OpenClawType.caption`, secondary, `lineLimit(1)`) composed of formatted byte count and relative date, joined with ` • `.

Pull-to-refresh calls `reload()`; the "Load More" row appears when `entries.count < totalEntries`. It is a `Button` whose `HStack` holds `Text("Load More")` (`OpenClawType.subheadMedium`), a `Spacer`, and either a `ProgressView` while `loadingMore` is true or `Text("\(entries.count) of \(totalEntries)")` (`OpenClawType.caption`, secondary) when idle. The whole row carries `.disabled(self.loadingMore)`, which blocks a second tap while a page fetch is in flight so load calls do not stack (Sources/Design/AgentWorkspaceFilesScreen.swift:129-147).

Directory taps push another `AgentWorkspaceDirectoryList`. File taps push `AgentWorkspaceFilePreview`, which shows images (base64 + `image/*` MIME) as a zoomable `ScrollView` or text as `ChatCodeHighlightCache.highlighted(code:languageId:)` at `OpenClawType.monoSmall`. A toolbar share button writes a unique temp copy and presents `ChatTranscriptShareSheet`.

---

## 4. Skills Destination

### 4.1 Entry Point

`ChatDrawerDestination.skills` routes to `SkillsScreenHost(onClose: openDrawer)` (Sources/RootTabs.swift:379). `SkillsScreenHost` fetches `skills.status` and feeds `SkillsScreen`. The screen draws its own header, so the shared `DrawerCloseButton` overlay is suppressed (Sources/RootTabs.swift:387-388).

### 4.2 `SkillsScreen` View Hierarchy

```
ZStack(alignment: .top)
├── Background (#171717 / #F5F4FA) — ignoresSafeArea
└── ScrollView
    └── VStack(alignment: .leading, spacing: 45)
        ├── Search bar (HStack in Capsule)
        └── VStack(spacing: 34)
            └── ForEach filteredSkills → skillRow(_:)
    .padding(.horizontal, 24)
    .padding(.top, 4)
    .padding(.bottom, 40)
safeAreaInset(.top) → header ZStack
    ├── Text("Skills") ← centered
    └── HStack(leading ChatBackGlyph button)
```

Sources/Design/SkillsScreen.swift:21-96.

### 4.3 Search Bar

| Property | Value |
|----------|-------|
| Outer frame | `height: 50 pt`, `maxWidth: .infinity`, `alignment: .leading` |
| Leading padding | `21 pt` |
| Background | `Capsule(style: .continuous)`, fill: Dark `Color.black` / Light `Color.white` |
| Icon | `Image(systemName: "magnifyingglass")`, `.system(size: 17)`, `Color.primary.opacity(0.7)` |
| `TextField` placeholder | `"Search skills"` |
| `TextField` font | `.system(size: 17)` |
| Autocorrection | Disabled |
| Spacing (icon to field) | `8 pt` |

Sources/Design/SkillsScreen.swift:30-44.

### 4.4 Skill Row (`skillRow(_:)`)

Each row is a horizontal `HStack(spacing: 14)` (Sources/Design/SkillsScreen.swift:107-147):

**Left: tappable area** (opens detail sheet):
- `HStack(spacing: 14)`: icon tile + label block.
- Wrapped in a `Button` with `.buttonStyle(.plain)`. The button label carries `.contentShape(Rectangle())` so empty space between the icon tile and the label block (and the trailing padding before the toggle) still fires the open action (Sources/Design/SkillsScreen.swift:133).

**Label block** (`VStack(alignment: .leading, spacing: 2)`):
- Name: `HStack(spacing: 2)` — `Text(name)` at `.system(size: 17)`, `Color.primary`, `lineLimit(1)` + `Image("SettingsChevronRightGlyph")` at `16 × 16 pt`, `Color.primary.opacity(0.6)`.
- Description: `.system(size: 13)`, `Color.primary.opacity(0.6)`, `lineLimit(1)`.

**Spacer**: a `Spacer(minLength: 0)` sits between the tappable button and the toggle, pushing the toggle to the trailing edge of the row (Sources/Design/SkillsScreen.swift:137).

**Right: toggle** (only when `hasAdminScope == true`):
- `Toggle("", isOn: …)`, `.labelsHidden()`, `.tint(Color(red: 52/255, green: 199/255, blue: 89/255))`.

Row vertical spacing between rows: `34 pt` (`VStack(spacing: 34)`).

### 4.5 Icon Tile (`iconTile(_:)`)

| Property | Value |
|----------|-------|
| Frame | `45 × 45 pt` |
| Shape | `RoundedRectangle(cornerRadius: 12, style: .continuous)` |
| Fill | Dark `Color.black` / Light `Color.white` |
| Border | `.strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5)` |
| With emoji | `Text(emoji)`, `.system(size: 24)` |
| Without emoji | `Image("SkillScrollGlyph")` (SVG: `li_scroll.svg`), `35 × 35 pt`, `.template`, `Color.primary` |

Sources/Design/SkillsScreen.swift:149-170.

### 4.6 Search Filtering

`filteredSkills` (Sources/Design/SkillsScreen.swift:98-105): trims whitespace; if empty returns all skills; otherwise filters on `name.localizedCaseInsensitiveContains` OR `descriptionText.localizedCaseInsensitiveContains`.

Empty state: `Text("No skills installed yet.")` (no query) or `Text("No matches.")` (with query); `.system(size: 16)`, `Color.primary.opacity(0.6)`, centered, `.padding(.top, 24)`.

### 4.7 Header

Back glyph: `Image("ChatBackGlyph")`, glass chrome, calls `onClose`. No trailing button. Title: `"Skills"`.

### 4.8 Data Loading (`SkillsScreenHost`)

Sources/Design/SkillsScreen.swift:177-338.

- Fetches `skills.status` with `{ agentId: activeAgentID }`, timeout `15 s`.
- Decodes into `SkillStatusReportLite`; populates `entries: [SkillStatusEntryLite]`.
- `enabledOverrides: [String: Bool]` holds in-flight optimistic flips keyed by `effectiveSkillKey`; cleared on reload.
- Toggle → optimistic flip → `skills.update { skillKey, enabled }` → reload (timeout `20 s`).
- Open skill → sets `selectedSkillKey`; sheet presented with `presentationCornerRadius(47)`.

### 4.9 `SkillPanelSheet` (Detail Sheet)

Presented as a sheet with `presentationCornerRadius(47)`. Background same as SkillsScreen (`#171717` / `#F5F4FA`).

Sources/Design/SkillsScreen.swift:352-553.

**Header geometry** (safeAreaInset top):
- Close button (`Image("ChatCloseGlyph")`, glass chrome): leading `25 pt`, top `22 pt`.
- Title `Text(skill.name)`, `.system(size: 20, weight: .medium)`, top `29 pt`, `maxWidth: 188`.
- Combined inset height: `22 + 40 = 62 pt` (per code comment at line 417).

**Content column** (Sources/Design/SkillsScreen.swift:374-413):
- `padding(.horizontal, 24)`, `padding(.top, 25)` — content starts `87 pt` from sheet top.
- `VStack(alignment: .leading, spacing: 0)`.

**Icon tile** (large variant):

| Property | Value |
|----------|-------|
| Frame | `60 × 60 pt` |
| Shape | `RoundedRectangle(cornerRadius: 16, style: .continuous)` |
| Fill | Dark `Color.black` / Light `Color.white` |
| Border | `.strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.7)` |
| With emoji | `Text(emoji)`, `.system(size: 32)` |
| Without emoji | `Image("DrawerScrollGlyph")`, `44 × 44 pt`, `.template`, `Color.primary` |

**Name**: `.system(size: 24, weight: .medium)`, `padding(.top, 32)`.
**Description**: `.system(size: 16)`, `Color.primary.opacity(0.6)`, `fixedSize(horizontal: false, vertical: true)`, `padding(.top, 8)`.

**"Enabled Globally" card** (`enabledCard`):

| Property | Value |
|----------|-------|
| Frame | `height: 50 pt`, `maxWidth: .infinity` |
| Padding | `.horizontal, 17 pt` |
| Background | `RoundedRectangle(cornerRadius: 12)`, Dark/Light fill |
| Toggle tint | `Color(red: 52/255, green: 199/255, blue: 89/255)` |
| Disabled when | `!hasAdminScope` |

Spacing above: `padding(.top, 32)`.

**Meta card** (`metaCard`):
- `VStack(spacing: 14)`, `padding(.vertical, 15)`, background rounded rect.
- Two rows: `"Key"` and `"Source"`.
- Each row: label `.system(size: 16)`, `Color.primary.opacity(0.6)`; value `.system(size: 17)`, `Color.primary`; padding `.horizontal, 15 pt`.
- `OpenClawRowDivider()` between rows (spans full card width — horizontal inset lives on the rows only).

Spacing above: `padding(.top, 16)`.

**Install button** (only when `installLabel != nil` and `hasAdminScope`):

| Property | Value |
|----------|-------|
| Height | `50 pt`, `maxWidth: .infinity` |
| Background | `Capsule(style: .continuous)`, `actionRed.opacity(0.38)` where `actionRed = Color(red: 195/255, green: 63/255, blue: 51/255)` |
| Label font | `.system(size: 17, weight: .medium)`, `actionRed` |
| Loading | `ProgressView().tint(actionRed)` |

Error text (if `installError != nil` and not installing): `.system(size: 14)`, `Color(red: 211/255, green: 21/255, blue: 21/255)`, centered, `padding(.top, 10)`.

Install RPC: `skills.install { name, installId, timeoutMs: 120_000 }`, timeout `125 s`. On success, reloads; on failure, sets `installError` via `AgentProTab.skillMutationMessage(error)`.

**Trailing spacer**: the scroll content column ends with `Spacer(minLength: 40)` after the install-button / error block, so the last card is not obscured by the sheet's home indicator (Sources/Design/SkillsScreen.swift:407).

---

## 5. Canvas Destination

### 5.1 Model — `CanvasEmbed`

Sources/Design/CanvasArtifacts.swift:13-17.

```swift
struct CanvasEmbed: Identifiable, Equatable {
    let id: String      // "embed-<messageID>-<index>"
    let title: String   // from [embed title="…"] or "Canvas" fallback
    let entryURL: String // e.g. "/__openclaw__/canvas/documents/<id>/index.html"
}
```

### 5.2 Parsing — `CanvasEmbedParser`

Sources/Design/CanvasArtifacts.swift:44-111.

Two regex passes (block form first, then self-closing):
- Block: `\[embed\s+([^\]]*?)\][\s\S]*?\[/embed\]` (case-insensitive)
- Self-closing: `\[embed\s+([^\]]*?)/\]` (case-insensitive)

Attribute regex: `([A-Za-z_][A-Za-z0-9_-]*)\s*=\s*(?:"([^"]*)"|'([^']*)')`

URL resolution (Sources/Design/CanvasArtifacts.swift:92-109):
- If `url=` attribute present: use verbatim.
- If `ref=` attribute: URL-path-encode, prepend `/__openclaw__/canvas/documents/<ref>/index.html`.
- Guard: entry path must start with `/__openclaw__/canvas` or `/__openclaw__/a2ui`; any other embed is silently ignored (desktop parity).
- Default title: `"Canvas"` when `title` attribute is absent or empty.

Tags are stripped back-to-front from the visible text (so earlier range indices stay valid) and the remainder is trimmed of whitespace.

### 5.3 Shared Index — `CanvasEmbedIndex`

Sources/Design/CanvasArtifacts.swift:24-40.

`@MainActor @Observable final class` with `static let shared`. Holds `embeds: [CanvasEmbed]` (newest-first, deduped by `entryURL`).

`update(fromTranscriptOrder:)` reverses and deduplicates by `entryURL` (Set-insertion order), then compares IDs before updating to avoid spurious publishes.

`ChatRootSurface` populates the index as it projects rows; the Canvas archive reads it. This decoupling means the archive always reflects the live transcript state even though it doesn't own the message list.

### 5.4 URL Resolution — `CanvasURLResolver`

Sources/Design/CanvasArtifacts.swift:113-136.

Splices the canvas entry path under the capability-scoped host prefix (`/__openclaw__/cap/<token>`) so the `oc_cap` token rides in the URL path and the document's sub-resources inherit it. Returns nil when the host URL is absent or doesn't start with `/__openclaw__/cap`.

### 5.5 Chat Card — `CanvasEmbedCard`

Rendered inline in the conversation as a `ChatDisplayRow` with `canvasEmbed != nil` (Sources/Design/ChatRootSurface.swift:560-561).

Sources/Design/CanvasArtifacts.swift:212-258.

**Structure**:
```
Button(.plain)
└── HStack(spacing: 17)
    ├── CanvasThumbnailTile(width: 64, height: 47, fill: background, showsShadow: false)
    ├── VStack(alignment: .leading, spacing: 6)
    │   ├── Text(embed.title) — .system(size: 14), Color.primary, lineLimit(1)
    │   └── Text("Canvas") — .system(size: 12), Color.primary.opacity(0.6)
    ├── Spacer(minLength: 0)
    └── Image("SettingsChevronRightGlyph") — 24×24 pt, Color.primary.opacity(0.4)
    .padding(.horizontal, 14)
    .frame(height: 70)
```

**Card container**:
- `RoundedRectangle(cornerRadius: 12, style: .continuous)`
- Fill: Dark `Color.black` / Light `Color.white.opacity(0.7)`
- Border: `.strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5)`
- Shadow: `.black.opacity(0.07)`, radius `4`, x `0`, y `2`

**Thumbnail fill** in card context: Dark `Color(red:23/255, green:23/255, blue:23/255)` (`#171717`) / Light `Color(red:245/255, green:244/255, blue:250/255)` (`#F5F4FA`). No shadow on the thumbnail tile (`showsShadow: false`).

Tap action: calls `onOpen` → sets `openEmbed` on `ChatRootSurface`, triggering `CanvasEmbedPanel` as a sheet (Sources/Design/ChatRootSurface.swift:253-269).

### 5.6 Thumbnail Tile — `CanvasThumbnailTile`

Private shared component used by both the chat card and the archive list. Sources/Design/CanvasArtifacts.swift:140-164.

```
ZStack
├── RoundedRectangle(cornerRadius: 5, style: .continuous) — caller-supplied fill
└── Image("CanvasFileGlyph") — li_file-terminal.svg — 33×33 pt
    .template, Color.primary.opacity(dark ? 0.35 : 0.20)
.frame(width: callerWidth, height: callerHeight)
.shadow(color: showsShadow ? .white.opacity(0.15) : .clear, radius: 1)
```

The archive page passes `showsShadow: true`; the in-chat card tile passes `showsShadow: false`. The two surfaces are explicitly styled independently (Sources/Design/CanvasArtifacts.swift:146-147).

### 5.7 Canvas Archive Screen — `CanvasArchiveScreen`

The drawer's Canvas tab. Sources/Design/CanvasArtifacts.swift:262-357.

**Entry point**: `ChatDrawerDestination.canvas` routes here via `drawerDestinationScreen` in `RootTabs`. The `onClose` callback re-opens the drawer with a spring animation (`duration: 0.35`). The screen draws its own header (the shared `DrawerCloseButton` overlay is suppressed).

**Observation wiring**: the screen holds the shared index as `@State private var index = CanvasEmbedIndex.shared` (Sources/Design/CanvasArtifacts.swift:266). Wrapping the `@Observable` singleton in `@State` is what registers this view as an observer; when `ChatRootSurface` mutates `CanvasEmbedIndex.shared.embeds`, the `results` computed property re-reads `self.index.embeds` and the archive re-renders live. Reading `CanvasEmbedIndex.shared.embeds` directly (without the `@State` wrapper) would not establish the dependency.

**Header** (`CanvasPanelHeader`): title `"Canvas"`, `leadingGlyph: "ChatBackGlyph"`. Padding: `padding(.top, 8)`, `padding(.bottom, 14)` on the outer safeAreaInset.

**Search bar** (identical pattern to SkillsScreen):

| Property | Value |
|----------|-------|
| Height | `50 pt` |
| Leading padding | `21 pt` |
| Background | `Capsule`, Dark `Color.black` / Light `Color.white` |
| Light-mode border | `.strokeBorder(Color.black.opacity(0.2), lineWidth: 0.5)` |
| Dark-mode border | `none` (`.clear`) |
| Placeholder | `"Search"` |
| Autocorrection | Disabled |
| Spacing (icon + field) | `8 pt` |

Sources/Design/CanvasArtifacts.swift:286-307.

**Archive row list** (`VStack(spacing: 12)` containing per-row `VStack(spacing: 12)`):

Each row (Sources/Design/CanvasArtifacts.swift:310-343):

```
Button(.plain)
└── HStack(spacing: 13)
    ├── CanvasThumbnailTile(width: 49, height: 54, fill: dark?.black/.white, showsShadow: true)
    └── VStack(alignment: .leading, spacing: 2)
        ├── Text(embed.title) — .system(size: 17, weight: .medium), Color.primary, lineLimit(1)
        └── Text("Canvas") — .system(size: 13), Color.primary.opacity(0.6)
    Spacer(minLength: 0)
    .contentShape(Rectangle())   ← on the HStack label; makes the full row width tappable
```

The button label carries `.contentShape(Rectangle())`, so tapping the empty trailing area of the row (past the title block, where the `Spacer` lives) still fires `onOpenEmbed` (Sources/Design/CanvasArtifacts.swift:332).

**Inter-row divider**: a `Rectangle()` with `Color.primary.opacity(0.1)`, height `0.5 pt`, `padding(.leading, 63)`. Shown only between rows (never after the last row): guarded by `if index < rows.count - 1` (Sources/Design/CanvasArtifacts.swift:336-340).

**Outer VStack spacing** (search bar to row list): `VStack(spacing: 31)`.

**Horizontal padding**: `24 pt` each side. **Top padding**: `4 pt`. No explicit bottom padding (the `ScrollView` ends naturally).

**Live filter**: `results` recomputes from `CanvasEmbedIndex.shared.embeds` — a case-insensitive `title.localizedCaseInsensitiveContains` match; empty query returns all.

Tap a row → `onOpenEmbed(embed)` → `RootTabs.selectedCanvasEmbed = embed` → `CanvasEmbedPanel` presented as a `.sheet` (Sources/RootTabs.swift:395-404).

### 5.8 Canvas Viewer Panel — `CanvasEmbedPanel`

Sources/Design/CanvasArtifacts.swift:364-423.

Presented as a `sheet` from either `ChatRootSurface` (inline card tap) or `CanvasArchiveScreen` (archive row tap).

**State machine** (`LoadState`):
- `.resolving` — initial; `EmptyView` shown.
- `.ready` — `ScreenWebView(controller: replayController)` shown, `.ignoresSafeArea(edges: .bottom)`.
- `.failed` — `Image("CanvasFileGlyph")`, `64 × 64 pt`, `Color.primary.opacity(0.15)`.

**Background**: same `#171717` / `#F5F4FA` palette (Sources/Design/CanvasArtifacts.swift:380-384).

**Header** (`CanvasPanelHeader`): title is `embed.title`, `leadingGlyph: "ChatCloseGlyph"` (default). Padding via safeAreaInset: `padding(.top, 14)`, `padding(.bottom, 10)` (inside `CanvasPanelHeader` itself, Sources/Design/CanvasArtifacts.swift:204-206).

**Load sequence** (Sources/Design/CanvasArtifacts.swift:409-422): in `.task`:
1. Await `canvasHostProvider()` (a fresh `canvasHostURL()` refresh).
2. Call `CanvasURLResolver.absoluteURL(entryURL:canvasHostURL:)`.
3. If nil → `.failed`.
4. Call `replayController.present(urlString:)` to set the target URL on the controller **before** the web view mounts.
5. Set `loadState = .ready` — the web view is now conditionally inserted into the hierarchy.

Why pre-set the URL: mounting the `ScreenWebView` with an already-set URL means the controller loads the real document on first attach, avoiding a flash of the default scaffold page (Sources/Design/CanvasArtifacts.swift:416-419).

The `replayController` is a fresh `ScreenController()` per panel instance, so it never disturbs the live canvas in `DrawerCanvasScreen` (Sources/Design/CanvasArtifacts.swift:371).

### 5.9 `CanvasPanelHeader` (Shared)

Sources/Design/CanvasArtifacts.swift:167-207.

```
ZStack
├── Text(title) — .system(size:20, weight:.medium), lineLimit(1), maxWidth:240
└── HStack
    └── Button → Image(leadingGlyph) 22×22 pt, glass chrome 40×40 pt
    .padding(.leading, 25)
.padding(.top, 14)
.padding(.bottom, 10)
```

`leadingGlyph` parameter defaults to `"ChatCloseGlyph"` (viewer panels); archive screen passes `"ChatBackGlyph"`. This is the only structural difference between the archive header and the viewer header.

---

## 6. Glyph Asset Reference

| Asset name | SVG filename | Used in |
|-----------|-------------|---------|
| `FilesFileGlyph` | `li_file.svg` | Files grid — file tile icon |
| `FilesFolderGlyph` | `li_folder.svg` | Files grid — folder tile icon |
| `SkillScrollGlyph` | `li_scroll.svg` | Skills list — fallback icon tile |
| `DrawerScrollGlyph` | (same SVG reused via separate asset) | Skills detail panel — fallback icon tile |
| `CanvasFileGlyph` | `li_file-terminal.svg` | Canvas thumbnail tile + failed-load state |
| `DrawerFilesGlyph` | `li_folder-closed.svg` | Drawer nav row — Files |
| `DrawerPaletteGlyph` | (existing asset) | Drawer nav row — Canvas |
| `ChatBackGlyph` | (existing asset) | Leading close button on Files/Skills/Canvas archive screens |
| `ChatCloseGlyph` | (existing asset) | Leading close button on Skills detail panel + Canvas viewer panel |
| `SettingsChevronRightGlyph` | (existing asset) | Skill row disclosure chevron + canvas card chevron |

All new glyphs are rendered with `.renderingMode(.template)` and a `foregroundStyle` modifier so they adapt to dark/light mode via `Color.primary`.

---

## 7. Behavioral Notes

### 7.1 Files Grid — Why the Type Label is Truncated

An unusually long file extension would grow the cell height and misalign the grid row pair. `.lineLimit(1).truncationMode(.tail)` enforces single-line truncation. This is an explicit design constraint, not just an overflow guard (Sources/Design/FilesGridScreen.swift:159-161).

### 7.2 Files Loading — Guard Count

The pagination loop caps at `guardCount < 50` to prevent an infinite loop if the server always returns the same entries or if `totalentries` is corrupt. Deduplication by path provides a second guard: if a page returns no new entries the loop also breaks (Sources/Design/FilesGridScreen.swift:258-269).

### 7.3 Skills — Optimistic Toggle

The enabled state is flipped immediately in `enabledOverrides` before the RPC completes, so the toggle animates without a round-trip delay. The dict is cleared after `reload()` confirms the server truth, reconciling any discrepancy (Sources/Design/SkillsScreen.swift:297-308).

### 7.4 Canvas Index — No-Op Guard

`CanvasEmbedIndex.update(fromTranscriptOrder:)` compares the resulting `id` arrays before assigning to `embeds`. This prevents `ChatRootSurface`'s row projection (which runs on every scroll-position change) from triggering spurious `@Observable` updates and unnecessary archive-screen re-renders (Sources/Design/CanvasArtifacts.swift:36-39).

### 7.5 Canvas Viewer — No Scaffold Flash

The `ScreenWebView` is only inserted into the view hierarchy once `loadState == .ready`, which is set only after `replayController.present(urlString:)` has already been called. This ordering ensures the web view's first `attach` + `reload` loads the real document URL, not the controller's default blank/scaffold page (Sources/Design/CanvasArtifacts.swift:413-421).

### 7.6 Canvas Viewer — Fresh Controller Per Panel

`CanvasEmbedPanel` instantiates its own `ScreenController` (`@State private var replayController = ScreenController()`). This isolation means opening a canvas in the viewer never mutates the shared `appModel.screen` controller used by `DrawerCanvasScreen`, preserving whatever the live canvas is showing (Sources/Design/CanvasArtifacts.swift:371).

### 7.7 Temp File Uniqueness for QuickLook / Share

Both the Files grid preview and the `AgentWorkspaceFilePreview` share write path places each export under a `UUID().uuidString` subdirectory of `OpenClawWorkspaceFiles/` in the system temp directory. This prevents a later same-basename export from replacing bytes already handed to an active QuickLook controller or system share extension (Sources/Design/FilesGridScreen.swift:320-321; Sources/Design/AgentWorkspaceFilesScreen.swift:438-441).
