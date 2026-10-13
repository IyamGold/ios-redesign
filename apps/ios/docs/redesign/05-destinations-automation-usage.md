# Drawer Destinations — Cron, Dreaming, Usage, Instances

This section specifies the four drawer destination screens that surface automation and usage data — Cron Jobs, Dreaming (memory entries), Usage (token/cost history), and Instances (connected presence) — covering every header, layout, card, row, badge, chip, color value, interaction, and data-loading detail needed to rebuild them pixel- and behavior-accurately without reference to the source code.

---

## Shared Design Language

All four destinations share the same header/close treatment and glass chrome button style. Differences are noted per-screen.

### Canvas Background Colors

| Screen | Light | Dark |
|---|---|---|
| Cron Jobs | `rgb(245, 244, 250)` — `#F5F4FA` | `rgb(23, 23, 23)` — `#171717` |
| Usage | `rgb(245, 244, 250)` — `#F5F4FA` | `rgb(23, 23, 23)` — `#171717` |
| Instances | `rgb(245, 244, 250)` — `#F5F4FA` | `rgb(23, 23, 23)` — `#171717` |
| Dreaming | `rgb(245, 244, 250)` — `#F5F4FA` | pure `Color.black` |

The Dreaming screen intentionally uses pure black (not `#171717`) in dark mode — a deliberate palette inversion to reinforce the "memory/subconscious" theme. (`DreamingScreen.swift:92–96`)

### Card Fill Colors

| Screen | Light card | Dark card |
|---|---|---|
| Cron Jobs | `Color.white` | `Color.black` |
| Usage | `Color.white` | `Color.black` |
| Instances | `Color.white` | `Color.black` |
| Dreaming tiles | `Color.white` | `rgb(23, 23, 23)` — `#171717` |

### Glass Chrome Button (`glassChrome` / `chromePillLabel`)

Every destination uses an identical 40 × 40 circular button for both the back/close glyph and the filter glyph. (`CronJobsScreen.swift:117–133`, `DreamingScreen.swift:156–173`, `UsageScreen.swift:165–182`, `InstancesScreen.swift:123–140`)

| Property | Value |
|---|---|
| Hit target frame | 40 × 40 pt |
| Glyph frame | 22 × 22 pt |
| Glyph rendering | `.template` (adapts to `Color.primary`) |
| Background shape | `Circle()` |
| Background style | `ChatGlassBackground(shape: Circle(), fill: …)` |
| Fill (dark) | `Color(red: 30/255, green: 30/255, blue: 30/255).opacity(0.2)` — `rgba(30,30,30,0.2)` |
| Fill (light) | `Color(red: 245/255, green: 244/255, blue: 250/255).opacity(0.2)` — `rgba(245,244,250,0.2)` |
| Shadow | `.black.opacity(0.15)`, radius 25, x 0, y 0 |

`ChatGlassBackground` renders as `glassEffect(.regular, in: shape)` on iOS 26+, falling back to `.regularMaterial` + color overlay below iOS 26. (`ChatRootSurface.swift:2814–2831`)

### Header (safeAreaInset, top edge)

All four screens suppress the navigation bar (`.toolbar(.hidden, for: .navigationBar)`) and render their own header via `.safeAreaInset(edge: .top, spacing: 0)`.

**Header composition:** `ZStack` containing a centered `Text` title and a leading-trailing `HStack` with buttons, both laid over the same space. The `ZStack` sits inside the safe-area inset.

| Property | Cron Jobs | Dreaming | Usage | Instances |
|---|---|---|---|---|
| Title text | "Cron Jobs" | "Dreaming" | "Usage" | "Instances" |
| Title font | `.system(size: 20, weight: .medium)` | `.system(size: 20, weight: .medium)` | `.system(size: 20, weight: .medium)` | `.system(size: 20, weight: .medium)` |
| Title color | `Color.primary` | `Color.primary` | `Color.primary` | `Color.primary` |
| Inset padding top | 8 pt | 8 pt | 8 pt | 8 pt |
| Inset padding bottom | 35 pt | 27 pt | 27 pt | 35 pt |
| Left button glyph | `ChatBackGlyph` | `ChatBackGlyph` | `ChatBackGlyph` | `ChatBackGlyph` |
| Right button glyph | `UsageFilterGlyph` | `UsageFilterGlyph` | `UsageFilterGlyph` | none |
| HStack horizontal padding | 24 pt | 24 pt | 24 pt | 24 pt |

The right button opens a `Menu` on Cron, Dreaming, and Usage. Instances has no right button — only a back button on the leading side.

### `OpenClawRowDivider`

Used inside grouped-list cards in Usage and Instances as the row separator. (`OpenClawProComponents.swift`)

- Shape: full-width `Rectangle`
- Height: `OpenClawSectionStyle.dividerHeight` = 2 pt
- Fill (light): `rgb(245, 244, 250)` — `#F5F4FA` (canvas color)
- Fill (dark): `rgb(23, 23, 23)` — `#171717` (canvas color)

The divider is drawn in the canvas color, not a translucent line, so consecutive rows visually read as separated by a gap of page background. This differs from Dreaming and Cron's hairline dividers.

### `OpenClawSectionStyle` Constants

| Constant | Value |
|---|---|
| `cornerRadius` | 12 pt |
| `dividerHeight` | 2 pt |

---

## Cron Jobs Screen

**Files:** `Sources/Design/CronJobsScreen.swift`

### Data Model

```swift
struct CronJobRow: Identifiable, Equatable {
    let id: String
    let title: String
    let descriptionText: String
    let isRecurring: Bool   // schedule kind != "at"
    let isCompleted: Bool   // disabled recurring, or fired one-time
    let enabled: Bool
    let createdAt: Date
}
```

### State

| Property | Type | Default | Purpose |
|---|---|---|---|
| `filter` | `CronFilter` | `.active` | Which tab is showing |

### Filter Enum (`CronFilter`)

| Case | Display title | Matches rule |
|---|---|---|
| `.active` | "Active" | `!job.isCompleted` |
| `.completed` | "Completed" | `job.isCompleted` |

**Active** = not-yet-run one-shots + still-enabled recurring jobs.
**Completed** = one-shot jobs that have fired + recurring jobs the user disabled. (`CronJobsScreen.swift:39–45`)

**Filter menu (right header button):** opens a `Menu` with one `Button` per `CronFilter.allCases` (Active, then Completed). Each button's label is a `Text(option.title)`, and when `self.filter == option` an `Image(systemName: "checkmark")` is appended inside the same label so the currently-selected filter shows a trailing checkmark in the menu. (`CronJobsScreen.swift:93–106`)

### View Hierarchy

```
ZStack(alignment: .top)
  ├── canvas background (ignoresSafeArea)
  └── ScrollView
        └── VStack(spacing: 8)
              ├── ForEach(filteredJobs) → jobCard(_:)
              └── [empty state Text if filteredJobs.isEmpty]
        .padding(.horizontal, 24)
        .padding(.top, 4)
        .padding(.bottom, 40)
.safeAreaInset(edge: .top, spacing: 0)
  └── ZStack
        ├── Text("Cron Jobs") [centered]
        └── HStack
              ├── Button → glassChrome("ChatBackGlyph") [back/close]
              └── Menu → glassChrome("UsageFilterGlyph") [filter]
        .padding(.horizontal, 24)
  .padding(.top, 8)
  .padding(.bottom, 35)
```

### Empty State

- Text: `"No active tasks yet."` (active filter) / `"No completed tasks yet."` (completed filter)
- Font: `.system(size: 16)`
- Color: `Color.primary.opacity(0.6)`
- Padding: `.top(32)`, no horizontal padding (list itself has 24 pt horizontal)

### Job Card (`jobCard(_:)`)

Cards are vertically stacked with `spacing: 8`. (`CronJobsScreen.swift:135–187`)

**Outer container:**
- `VStack(alignment: .leading, spacing: 0)`
- Padding: `.horizontal(10)`, `.vertical(13)`
- `frame(maxWidth: .infinity, alignment: .leading)`
- Background: `RoundedRectangle(cornerRadius: 12, style: .continuous)` filled `Color.black` (dark) / `.white` (light)
- Border overlay: `RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5)`
- Shadow: `.black.opacity(0.05)`, radius 20, x 0, y 4

**Content row (top section):**
```
HStack(alignment: .top, spacing: 7)
  ├── badge(for: job)  ← .padding(.top, 1)
  └── VStack(alignment: .leading, spacing: 6)
        ├── Text(job.title)          [17pt medium, Color.primary, lineLimit 1]
        └── Text(job.descriptionText) [13pt, Color.primary.opacity(0.6), lineLimit 3, fixedSize vertical]
```

The subtitle is capped at 3 lines with `.lineLimit(3).fixedSize(horizontal: false, vertical: true)`. Comment explains: "one-time prompts can be long" and overflow truncates with an ellipsis. (`CronJobsScreen.swift:148–151`)

**Action chips (recurring jobs only, when `showsActions == true`):**
```
HStack(spacing: 15)
  ├── CronActionButton(glyph: "CronJobsPlayGlyph", label: "Run")
  └── CronActionButton(
        glyph: job.enabled ? "CronJobsDisableGlyph" : "CronJobsCheckGlyph",
        label: job.enabled ? "Disable" : "Enable")
.padding(.leading, 25)
.padding(.top, 12)
```

Chips are suppressed for one-time jobs: "Run would delete a default one-shot and Enable/Disable is meaningless." (`CronJobsScreen.swift:155–156`)

### Badge (`badge(for:)`)

All badges are 18 × 18 pt. (`CronJobsScreen.swift:189–215`)

| Job state | Badge appearance |
|---|---|
| Completed (`isCompleted == true`) | Filled circle, `rgb(197, 62, 56)` — `#C53E38`; white SF Symbol "checkmark" at 10pt bold, foreground `rgb(250, 250, 250)` — `#FAFAFA` |
| Active recurring (`!isCompleted && isRecurring`) | `Image("CronJobsReloadGlyph")` templated, 16 × 16 glyph inside 18 × 18 frame, foreground `rgb(52, 199, 89)` — `#34C759` (Apple system green) |
| Active one-time (`!isCompleted && !isRecurring`) | Empty `Circle().strokeBorder(Color.primary.opacity(0.4), lineWidth: 1.35)` |

### Action Button (`CronActionButton`)

(`CronJobsScreen.swift:220–263`)

| Property | Value |
|---|---|
| Glyph frame | 13 × 13 pt |
| Glyph rendering | `.template` |
| Glyph–label spacing | 7 pt (HStack) |
| Label font | `.system(size: 13, weight: .medium)` |
| Label color | `Color.primary` |
| Chip height | 27 pt (`.frame(height: 27)`) |
| Chip horizontal padding | 10 pt |
| Chip background | `RoundedRectangle(cornerRadius: 12, style: .continuous)` filled `Color.black` (dark) / `.white` (light) |
| Chip border | `strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5)` |
| Button style | `.plain` (no dimming) |

**Loading state:** While the async action is in flight, the label switches to `"..."`. The glyph stays visible. The chip does not use `.disabled` — the `guard !isRunning` guard blocks re-entry while keeping the chip at full opacity. (`CronJobsScreen.swift:259–262`)

**Haptic:** `OpenClawHaptics.tap()` fires on every button press before the async task is launched. `tap()` uses `UIImpactFeedbackGenerator(style: .light)`. (`OpenClawHaptics.swift:27–29`)

### Glyph Asset Names

| Usage | Asset name | SVG file |
|---|---|---|
| Run action chip | `CronJobsPlayGlyph` | `Polygon 3.svg` |
| Active recurring badge | `CronJobsReloadGlyph` | `li_iteration-ccw.svg` |
| Enable action chip | `CronJobsCheckGlyph` | `li_check-circle.svg` |
| Disable action chip | `CronJobsDisableGlyph` | `li_x.svg` |
| Filter (right header) | `UsageFilterGlyph` | `li_list-filter.svg` |
| Back (left header) | `ChatBackGlyph` | (shared glyph) |

### Data Loading (`CronJobsScreenHost`)

(`CronJobsScreen.swift:271–446`)

- RPC: `cron.list` with params `{"includeDisabled":true,"limit":100,"sortBy":"updatedAtMs","sortDir":"desc"}`, timeout 12 s
- Sorted by `createdAt` descending after mapping
- `createdAt` is constructed as `Date(timeIntervalSince1970: Double(job.createdatms) / 1000)` — the gateway's `createdatms` is in milliseconds and must be divided by 1000 before building the `Date`. (`CronJobsScreen.swift:333`)
- `showsActions` = `appModel.gatewayServerName != nil` (gateway connected)
- **Run** action: `cron.run` with `{"id":…,"mode":"force"}`, timeout 20 s, then reload
- **Toggle** action: `cron.update` with `{"id":…,"patch":{"enabled":!current}}`, timeout 20 s, then reload

**Mapping rules:**

- `isRecurring`: `schedule.kind != "at"` (no kind or missing dict → recurring). (`CronJobsScreen.swift:338–347`)
- `isCompleted` for recurring: `!job.enabled`. For one-time: `!job.enabled || hasRun(job)`. (`CronJobsScreen.swift:352–358`)
- `hasRun`: checks `lastRunAtMs` top-level, `state["lastRunAtMs"]`, `lastRunStatus`, or `state["lastStatus"]`. (`CronJobsScreen.swift:361–367`)
- `title`: `job.name` trimmed; falls back to schedule label when empty. (`CronJobsScreen.swift:393–396`)
- `descriptionText`: payload `message` key, then `text` key, then schedule label. (`CronJobsScreen.swift:399–405`, `409–419`)
- Schedule label priority: `schedule.kind.capitalized` → `"Cron \(expr)"` → `"Every \(durationLabel(everyMs))"` → `"Schedule configured"`. (`CronJobsScreen.swift:371–389`)
- Duration label: milliseconds are divided by 1000 to whole seconds, then matched most-significant first — whole days → `"\(days) day\(days == 1 ? "" : "s")"`, whole hours → `"\(hours) hour..."`, whole minutes → `"\(minutes) minute..."`, else the seconds fallback `"\(seconds) second\(seconds == 1 ? "" : "s")"`. Each branch emits full singular/plural English ("1 day" vs "2 days"), not a bare "(s)" label. (`CronJobsScreen.swift:430–445`)

---

## Dreaming Screen

**Files:** `Sources/Design/DreamingScreen.swift`

### Data Model

```swift
struct DreamEntry: Identifiable, Equatable {
    enum Category: String, CaseIterable {
        case promoted = "Promoted Entries"
        case shortTerm = "Short Term Recall"
        case signal = "Signal Entries"
    }
    let id: String
    let title: String
    let snippet: String
    let category: Category
    let dateLabel: String  // relative-time string from gateway, verbatim; "" when absent
}
```

The gateway returns only relative-time strings (e.g. `"2 days ago"`), never absolute dates, so `dateLabel` is stored as a raw string rather than `Date`. (`DreamingScreen.swift:14–18`)

### State

| Property | Type | Default | Purpose |
|---|---|---|---|
| `filter` | `DreamEntry.Category?` | `nil` | `nil` = all categories shown |

### Filter Menu

Right header button opens a `Menu` with: `Button("All")` (sets `filter = nil`) then one button per category case in `DreamEntry.Category.allCases` order: Promoted Entries, Short Term Recall, Signal Entries.

### View Hierarchy

```
ZStack(alignment: .top)
  ├── canvas (ignoresSafeArea)
  └── ScrollView
        └── VStack(spacing: 17)
              ├── ForEach(visibleEntries, enumerated)
              │     └── VStack(spacing: 17)
              │           ├── entryRow(entry).padding(.horizontal, 24)
              │           └── [hairline divider if not last row]
              └── [empty state if visibleEntries.isEmpty]
        .padding(.top, 4)
        .padding(.bottom, 40)
.safeAreaInset(edge: .top, spacing: 0)
  └── ZStack
        ├── Text("Dreaming") [centered]
        └── HStack
              ├── chromePill("ChatBackGlyph") [back]
              └── Menu → chromePillLabel("UsageFilterGlyph") [filter]
        .padding(.horizontal, 24)
  .padding(.top, 8)
  .padding(.bottom, 27)
```

**Important layout note:** Row horizontal padding (24 pt) lives on the row, not the list. This lets the hairline divider between rows run full screen-edge-to-edge, while the row content stays inset 24 pt. (`DreamingScreen.swift:39–44`)

### Hairline Divider (between rows)

- Shape: `Rectangle()`
- Fill: `Color.primary.opacity(0.15)`
- Height: 0.7 pt
- Appears between every pair of adjacent rows; absent after the last row

This differs from `OpenClawRowDivider` (which uses the canvas color at 2 pt). The Dreaming hairline is a true 0.7 pt translucent line.

### Entry Row (`entryRow(_:)`)

The entire row is a `Button` with `.plain` style and `.contentShape(Rectangle())` for full-area hit testing. (`DreamingScreen.swift:104–150`)

```
Button { onOpenEntry(entry) }
  HStack(alignment: .top, spacing: 12)
    ├── ZStack [circle icon]
    │     ├── Circle().fill(tileFill)           [50.5 × 50.5 pt]
    │     └── Image("DrawerMoonStarGlyph")      [35 × 35 pt, template, primary.opacity(0.85)]
    └── VStack(alignment: .leading, spacing: 2)
          ├── HStack(spacing: 0)
          │     ├── Text(entry.title)            [17pt medium, Color.primary, lineLimit 1]
          │     ├── Spacer(minLength: 8)
          │     ├── Text(entry.dateLabel)        [13pt, primary.opacity(0.6), lineLimit 1] (if !empty)
          │     └── Image("SettingsChevronRightGlyph") [16×16, template, primary.opacity(0.6)]
          └── Text(entry.snippet)               [13pt, primary.opacity(0.6), lineLimit 2, .multilineTextAlignment(.leading)]
```

| Element | Detail |
|---|---|
| Icon circle size | 50.5 × 50.5 pt |
| Moon-star glyph asset | `DrawerMoonStarGlyph` (SVG: `li_moon-star.svg`) |
| Moon-star glyph size | 35 × 35 pt |
| Moon-star glyph opacity | `Color.primary.opacity(0.85)` |
| Title font | `.system(size: 17, weight: .medium)` |
| Date label font | `.system(size: 13)` |
| Snippet font | `.system(size: 13)` |
| Chevron asset | `SettingsChevronRightGlyph` |
| Chevron size | 16 × 16 pt |
| Snippet line limit | 2 |
| Snippet alignment | `.multilineTextAlignment(.leading)` (explicit modifier on the snippet `Text`) (`DreamingScreen.swift:143–144`) |

### Empty State

- Text: `"No dreams yet."`
- Font: `.system(size: 16)`
- Color: `Color.primary.opacity(0.6)`
- Padding: `.top(32)`, `.horizontal(24)`

### Entry Detail Sheet (`DreamEntryDetailSheet`)

Tapping an entry sets `selectedEntryID`, which triggers a `.sheet` with `presentationCornerRadius(47)`. (`DreamingScreen.swift:194–208`)

The sheet uses the same canvas/tile palette as the list screen. (`DreamingScreen.swift:277–421`)

**Header:** (`DreamingScreen.swift:315–347`)
- `safeAreaInset(edge: .top, spacing: 0)` containing a `ZStack(alignment: .top)`.
- The close button sits inside an `HStack { Button … ; Spacer() }` — the trailing `Spacer()` pushes the button to the leading edge. The `.padding(.leading, 25).padding(.top, 22)` is applied to **that `HStack`**, not to the `Button` itself. (Applying it directly to the button yields a different layout.)
- Close button: `ChatCloseGlyph` (not `ChatBackGlyph`) at 22 × 22 inside a 40 × 40 glass chrome circle (same fill/shadow as `glassChrome`).
- Title text: `"Entry"`, 20pt medium, `Color.primary`, `lineLimit(1)`, `frame(maxWidth: 188)`, `.padding(.top, 29)`. The title is the `ZStack`'s second child, centered horizontally and pinned to the top by the `ZStack(alignment: .top)`.

**Body:**
```
ScrollView
  VStack(alignment: .leading, spacing: 0)
    ├── Text(title)         [24pt medium, Color.primary]
    ├── Text(subheading)    [13pt, primary.opacity(0.6), .top(6)]
    ├── Text(snippet)       [16pt, Color.primary, textSelection(.enabled), .frame(maxWidth: .infinity, alignment: .leading), .top(20)]
    ├── metaCard            [.top(24)]
    └── Spacer(minLength: 40)
  .padding(.horizontal, 25)
  .padding(.top, 8)
```

- `title`: first line of snippet; falls back to path basename
- `subheading`: built by joining `parts` with `" · "`, where `parts` starts as `[categoryLabel]` and appends `when` (= `promotedAt ?? lastRecalledAt`) only when that value is non-nil. So when both `promotedAt` and `lastRecalledAt` are nil the subheading is `categoryLabel` **alone** (no trailing `" · "`); otherwise it is `categoryLabel + " · " + when`. (`DreamingScreen.swift:357–362`)

**Meta card:**
```
VStack(spacing: 14)
  ├── metaRow("Location", filename:lines)
  ├── hairline (primary.opacity(0.15), 0.7 pt)
  ├── metaRow("Signal", "×N")
  ├── hairline
  └── metaRow("Recalled", "×N")
.padding(.horizontal, 15)
.padding(.vertical, 15)
.frame(maxWidth: .infinity)
.background(RoundedRectangle(cornerRadius: 12, .continuous).fill(tileFill))
```

The meta card's `VStack` uses `spacing: 14` between its rows and hairlines, `.padding(.horizontal, 15)`, `.padding(.vertical, 15)`, and `.frame(maxWidth: .infinity)`. (`DreamingScreen.swift:365–366`)

**Meta row layout:**
```
HStack
  ├── Text(label)   [16pt, primary.opacity(0.6)]
  ├── Spacer(minLength: 8)
  └── Text(value)   [17pt, Color.primary, lineLimit 1, truncationMode .middle, textSelection .enabled]
```

Location value format: `"filename:startLine-endLine"` when `endLine > startLine`, else `"filename:startLine"`.

### Data Loading (`DreamingScreenHost`)

- RPC: `doctor.memory.status` with params `{}`, timeout 8 s
- Response decoded as `DreamingStatusEnvelope`, accessing `.dreaming`
- Category order: promoted → short-term → signal (matches enum order)

**Entry mapping:**
- Snippet is trimmed; split by newlines
- `title` = first line; falls back to path basename when snippet is empty
- `snippet` = lines 2+ joined by a space; falls back to the full `trimmed` snippet when there is only one line. Because `title` is also the first (only) line in that case, a single-line entry ends up with **identical text in both `title` and `snippet`**. (`DreamingScreen.swift:245–246`)
- `dateLabel` = `entry.promotedAt ?? entry.lastRecalledAt ?? ""`

---

## Usage Screen

**Files:** `Sources/Design/UsageScreen.swift`

### Data Model

```swift
struct UsageDayEntry: Identifiable, Equatable {
    let date: Date
    let tokens: Int
    let cost: Double?
    var id: Date { self.date }
}
```

### Props

| Prop | Type | Source |
|---|---|---|
| `entries` | `[UsageDayEntry]` | One entry per day |
| `totalTokens` | `Int` | Gateway summary or sum of entries |
| `totalCost` | `Double?` | Gateway summary |
| `onClose` | `() -> Void` | Back navigation |

### State

| Property | Type | Default | Purpose |
|---|---|---|---|
| `selectedMonth` | `DateComponents?` | `nil` | `nil` = all months shown |

### Filter Menu

Right header button opens a `Menu` with: `Button("All")` (sets `selectedMonth = nil`) then one button per available month, labeled as `"\(Month name) \(year)"` (e.g. "September 2026"), sorted newest-first. Months are derived from entries; only months with data appear.

### View Hierarchy

```
ZStack(alignment: .top)
  ├── canvas background (ignoresSafeArea)
  └── ScrollView
        └── VStack(alignment: .leading, spacing: 34)
              ├── summaryCard
              └── ForEach(visibleMonths)
                    └── VStack(alignment: .leading, spacing: 6)
                          ├── Text(monthLabel)   [17pt medium, primary.opacity(0.5), .leading(15)]
                          └── card { usageRows + dividers }
              [empty state if entries.isEmpty]
        .padding(.horizontal, 24)
        .padding(.top, 4)
        .padding(.bottom, 40)
.safeAreaInset(edge: .top, spacing: 0)
  └── ZStack
        ├── Text("Usage") [centered]
        └── HStack
              ├── chromePill("ChatBackGlyph")
              └── Menu → chromePillLabel("UsageFilterGlyph")
        .padding(.horizontal, 24)
  .padding(.top, 8)
  .padding(.bottom, 27)
```

### Summary Card

A `card {}` at the top of the scroll content, always present regardless of month filter. Contains two rows:

1. `usageRow(label: "Total usage", value: "\(tokenLabel(totalTokens)) tokens")`
2. `OpenClawRowDivider()`
3. `usageRow(label: "Total cost", value: costLabel(totalCost))`

### Month Section

For each visible month:
- Section header: `Text(monthLabel(month))` — 17pt medium, `Color.primary.opacity(0.5)`, `.padding(.leading, 15)`
- `card {}` containing day rows separated by `OpenClawRowDivider()`

Days within a month are sorted newest-first. (`UsageScreen.swift:114–119`)

### Card (`card {}`)

(`UsageScreen.swift:133–144`)

- `VStack(alignment: .leading, spacing: 14)` containing row content
- `.padding(.vertical, 15)`
- `frame(maxWidth: .infinity, alignment: .leading)`
- Background: `RoundedRectangle(cornerRadius: 12, style: .continuous)` filled `Color.black` (dark) / `.white` (light)
- Horizontal inset lives on the **rows** (`usageRow` has `.padding(.horizontal, 15)`) so `OpenClawRowDivider` can span the full card width.

### Usage Row (`usageRow`)

(`UsageScreen.swift:146–157`)

```
HStack
  ├── Text(label)   [17pt, Color.primary]
  ├── Spacer(minLength: 0)
  └── Text(value)   [16pt, primary.opacity(0.6)]
.padding(.horizontal, 15)
```

### Empty State

- Text: `"No usage recorded yet."`
- Font: `.system(size: 16)`
- Color: `Color.primary.opacity(0.6)`
- Frame: `maxWidth: .infinity`
- Padding: `.top(24)` (no horizontal; list already has 24 pt)

### Formatting Rules

| Formatter | Logic |
|---|---|
| `tokenLabel(_:)` | ≥1 000 000: `"NM"` or `"N.1fM"` / ≥1 000: rounded `"NK"` / else: `"\(n)"` |
| `costLabel(_:)` | guard is `cost > 0`: any cost ≤ 0 (nil, `0`, **or negative**) → `"0$"`; else `"%.2f$"` (`UsageScreen.swift:199–201`) |
| `dayLabel(_:)` | `"\(Month name) \(ordinal day)"` e.g. `"September 18th"` using `NumberFormatter(.ordinal)` |
| `monthLabel(_:)` | Current year: `"\(Month name)"` only; other years: `"\(Month name) \(year)"` |
| `monthMenuLabel(_:)` | Always `"\(Month name) \(year)"` (for the filter menu) |

### Data Loading (`UsageScreenHost`)

- RPC: `usage.cost` with params `{"days":365}`, timeout 15 s
- Decodes `CostUsageSummaryLite`; maps `daily` array to `UsageDayEntry` using `DateFormatter(dateFormat: "yyyy-MM-dd", locale: en_US_POSIX, timeZone: .current)`
- `totalTokens` = `summary.totalTokens ?? sum of entry tokens`
- `totalCost` = `summary.totalCost`

---

## Instances Screen

**Files:** `Sources/Design/InstancesScreen.swift`

### Data Model

```swift
struct InstanceRowModel: Identifiable, Equatable {
    let id: String           // presenceKey (instanceId ?? deviceId ?? host ?? ip ?? "\(ts)")
    let name: String         // host ?? devicefamily ?? platform ?? mode ?? "Instance"
    let detail: String       // "ip • platform • version" joined by " • "
    let statusLabel: String  // "Self" | PresenceFormatting.state(entry)
}
```

### Props

| Prop | Type |
|---|---|
| `gatewayOnline` | `Bool` |
| `instances` | `[InstanceRowModel]` |
| `onClose` | `() -> Void` |
| `detail` | `@ViewBuilder (InstanceRowModel) -> Detail` |

No filter button — Instances is the only destination with only a back button in the header.

### View Hierarchy

```
ZStack(alignment: .top)
  ├── canvas background (ignoresSafeArea)
  └── ScrollView
        └── VStack(alignment: .leading, spacing: 36)
              ├── VStack(alignment: .leading, spacing: 7)   [gateway section]
              │     ├── HStack [gateway card]
              │     └── Text [instance count caption]
              └── VStack(alignment: .leading, spacing: 7)   [instances section]
                    ├── Text("Connected Instances") [section header]
                    └── VStack(spacing: 14)          [instance rows]
                          └── ForEach(instances, enumerated)
                                ├── NavigationLink → detail(instance)
                                │     └── HStack [row content]
                                └── OpenClawRowDivider (if not last)
        .padding(.horizontal, 24)
        .padding(.top, 4)
.safeAreaInset(edge: .top, spacing: 0)
  └── ZStack
        ├── Text("Instances") [centered]
        └── HStack
              └── Button → ChatBackGlyph [back only, leading]
        .padding(.horizontal, 24)
  .padding(.top, 8)
  .padding(.bottom, 35)
```

### Gateway Card

(`InstancesScreen.swift:35–61`)

```
HStack
  ├── Text("Gateway")     [17pt, Color.primary]
  ├── Spacer(minLength: 0)
  └── Text("Online"|"Offline")  [16pt, green|red]
.padding(.horizontal, 15)
.frame(height: 55)
.background(RoundedRectangle(cornerRadius: 12, .continuous).fill(cardFill))
```

| State | Color |
|---|---|
| Online | `rgb(52, 199, 89)` — `#34C759` |
| Offline | `rgb(211, 21, 21)` — `#D31515` |

**Caption below gateway card:**
- Attributed text: `"\(countPhrase(instances.count)) connected to this gateway. "` (secondary color) + `"Learn more."` (blue link)
- Font: `.system(size: 15)`
- Padding: `.leading(6)`
- Tap on full text: `openURL(URL("https://docs.openclaw.ai")!)`
- Count phrase: spells out count ("One instance in total is" / "Two instances in total are")
- Link color: `rgb(37, 99, 235)` — `#2563EB`

### Connected Instances Section Header

- Text: `"Connected Instances"`
- Font: `.system(size: 17, weight: .medium)`
- Color: `Color.primary.opacity(0.5)`
- Padding: `.leading(15)`

### Instance List Card

(`InstancesScreen.swift:69–110`)

- Outer `VStack(spacing: 14)` containing rows + `OpenClawRowDivider` separators (divider rendered only between rows, `index < instances.count - 1`).
- `.padding(.vertical, 15)` around the VStack.
- Background: `RoundedRectangle(cornerRadius: 12, .continuous)` filled `cardFill` (black/white).
- Unlike the Usage `card {}` and `NodeDetailScreen` card, this instance-list `VStack` has **no** `.frame(maxWidth: .infinity, ...)` modifier; it takes its width from the enclosing leading-aligned `VStack` and the 24 pt page inset.

The main scroll `VStack` applies only `.padding(.top, 4)` and `.padding(.horizontal, 24)` — there is **no** `.padding(.bottom, 40)` here, unlike the Cron/Dreaming/Usage screens which explicitly add a 40 pt bottom inset. (`InstancesScreen.swift:112–115`)

### Instance Row

(`InstancesScreen.swift:70–102`)

Each row is a `NavigationLink` with `.plain` button style and `.contentShape(Rectangle())`.

```
HStack(spacing: 7)
  ├── VStack(alignment: .leading, spacing: 3)
  │     ├── Text(instance.name)   [17pt, Color.primary, lineLimit 1]
  │     └── Text(instance.detail) [14pt, primary.opacity(0.4), lineLimit 1]
  ├── Spacer(minLength: 0)
  ├── Text(instance.statusLabel)  [16pt, primary.opacity(0.6)]
  └── Image("SettingsChevronRightGlyph") [20×20, template, primary.opacity(0.6)]
.padding(.horizontal, 14)
.contentShape(Rectangle())
```

| Element | Size / style |
|---|---|
| Name | 17pt, `Color.primary` |
| Detail subtitle | 14pt, `Color.primary.opacity(0.4)` |
| Status label | 16pt, `Color.primary.opacity(0.6)` |
| Chevron | `SettingsChevronRightGlyph`, 20 × 20 pt |

### Spacing Between Cards

- Between gateway section and instances section: part of outer `VStack(spacing: 36)`
- Between gateway card and caption: `VStack(spacing: 7)`
- Between instances section header and card: `VStack(spacing: 7)`
- Between instance rows (inside card): 14 pt (VStack spacing), visually separated by `OpenClawRowDivider`

### Navigation Container

`InstancesScreenHost` wraps `InstancesScreen` in a `NavigationStack` because the drawer presents via `fullScreenCover` which provides no navigation container, and the row `NavigationLink`s (leading to `NodeDetailScreen`) need somewhere to push. (`InstancesScreen.swift:369–370`)

### Node Detail Screen (`NodeDetailScreen`)

Tapping a row pushes `NodeDetailScreen` inside the `NavigationStack`. It uses `SettingsDestinationChrome` (the standard Settings-tab destination chrome) for its header. The chrome `title` is `PresenceFormatting.label(entry)` and falls back to the string literal `"Instance"` when `label` returns nil. (`InstancesScreen.swift:238–355`, fallback at `246`)

**Card layout** (mirrors Usage card structure, `InstancesScreen.swift:283–294`):
- `VStack(alignment: .leading, spacing: 14)`, `.padding(.vertical, 15)`, plus `.frame(maxWidth: .infinity, alignment: .leading)` on the `VStack` (paralleling the Usage card).
- Horizontal inset on rows (`rowInset` = `.padding(.horizontal, 15)`) so `OpenClawRowDivider` spans card.

**Detail card rows:**

| Row | Label | Value |
|---|---|---|
| Status | "Status" | `PresenceFormatting.state(entry)` colored `PresenceFormatting.color(entry)` — `OpenClawBrand.accent` (no reason) or `OpenClawBrand.warn` (has reason) |
| Instance | "Instance" | `entry.instanceid ?? "n/a"` |
| Device | "Device" | `entry.deviceid ?? "n/a"` |
| Host | "Host" | `entry.host ?? "n/a"` |
| IP | "IP" | `entry.ip ?? "n/a"` |
| Platform | "Platform" | `entry.platform ?? "n/a"` |
| Version | "Version" | `entry.version ?? "n/a"` |
| Mode | "Mode" | `entry.mode ?? "n/a"` |

**`detailRow` values** (Instance, Device, Host, IP, Platform, Version, Mode): 16pt, `Color.primary.opacity(0.6)`, `lineLimit(1)`, `truncationMode(.middle)`, `textSelection(.enabled)`. Value = `PresenceFormatting.normalized(value) ?? "n/a"`. (`InstancesScreen.swift:313–326`)
Label text (all rows): 17pt, `Color.primary`.

**`statusRow` is NOT a `detailRow`** and differs in two ways (`InstancesScreen.swift:301–311`):
- Its value foreground is `PresenceFormatting.color(entry)` (brand `accent` when no reason, `warn` when reason non-empty) — **not** `Color.primary.opacity(0.6)`.
- It applies **none** of `lineLimit(1)`, `truncationMode(.middle)`, or `textSelection(.enabled)`. Those modifiers belong only to `detailRow`.
- Value text is 16pt; value = `PresenceFormatting.state(entry)`.

**`OpenClawBrand` colors used in status:**
- `accent` light: `rgb(183, 56, 51)` / dark: `rgb(198, 62, 56)`
- `warn` light: `rgb(154, 87, 0)` / dark: `rgb(255, 214, 10)`

**List sections** (Scopes, Roles, Tags): (`InstancesScreen.swift:328–354`)
- Each section is a `VStack(alignment: .leading, spacing: 6)` — the inner 6 pt spacing sits between the section header and its card (distinct from the outer scroll `VStack(spacing: 34)`).
- Section header: 17pt medium, `primary.opacity(0.5)`, `.leading(15)` padding.
- Card with same styling as the detail card above.
- Empty state: `"None reported."` at 16pt, `primary.opacity(0.6)`, with `.frame(maxWidth: .infinity, alignment: .leading)`, row-inset 15 pt.
- Values: 16pt, `Color.primary`, each with `.frame(maxWidth: .infinity, alignment: .leading)` and `.textSelection(.enabled)`, row-inset 15 pt, separated by `OpenClawRowDivider` (divider only between values, not after the last).

Outer scroll: `VStack(alignment: .leading, spacing: 34)`, `.padding(.horizontal, 24)`, `.padding(.top, 4)`, `.padding(.bottom, 40)`.

### `PresenceFormatting` Rules

(`InstancesScreen.swift:167–222`)

| Helper | Resolution order |
|---|---|
| `label(_:)` | `host ?? devicefamily ?? platform ?? mode` (first non-empty) |
| `detail(_:)` | `[ip, platform, version].compactMap.joined(separator: " • ")` or `text` or `"Presence beacon received."` |
| `state(_:)` | `reason` if non-empty, else `mode` if non-empty, else `relativeTime(fromMilliseconds: ts)` |
| `icon(_:)` | SF Symbol: `devicefamily` contains "phone" → `"iphone"`, "tablet"/"pad" → `"ipad"`, "desktop"/"mac" → `"desktopcomputer"`, else `"display"` |
| `color(_:)` | `normalized(entry.reason) == nil` → `OpenClawBrand.accent`, else `OpenClawBrand.warn`. `normalized` trims whitespace and maps empty to nil, so a blank/whitespace-only `reason` counts as nil → accent (not warn). (`InstancesScreen.swift:210–211`) |

`relativeTime` uses `.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))`.

**Row sort order:** newest `ts` first; ties broken by `PresenceFormatting.label` ascending, case-insensitive. (`InstancesScreen.swift:395–403`)

**"Self" detection:** `entry.deviceid == DeviceIdentityStore.loadOrCreate().deviceId` → `statusLabel = "Self"`. (`InstancesScreen.swift:389–391`)

### Data Loading (`InstancesScreenHost`)

- RPC: `system-presence` with params `{}`, timeout 8 s
- Decodes `[PresenceEntry]`
- Presence key (stable identity): `instanceid ?? deviceid ?? host ?? ip ?? "\(ts)"` (`InstancesScreen.swift:228–233`)

---

## Cross-Screen Summary Table

| Attribute | Cron Jobs | Dreaming | Usage | Instances |
|---|---|---|---|---|
| Canvas dark | `#171717` | `Color.black` | `#171717` | `#171717` |
| Canvas light | `#F5F4FA` | `#F5F4FA` | `#F5F4FA` | `#F5F4FA` |
| Card dark | `Color.black` | `#171717` | `Color.black` | `Color.black` |
| Card light | `Color.white` | `Color.white` | `Color.white` | `Color.white` |
| Header bottom padding | 35 pt | 27 pt | 27 pt | 35 pt |
| Right header control | Filter menu | Filter menu | Filter menu | None |
| Filter menu glyph | `UsageFilterGlyph` | `UsageFilterGlyph` | `UsageFilterGlyph` | — |
| Card corner radius | 12 pt | 12 pt (detail) | 12 pt | 12 pt |
| Row divider type | None (8 pt gap between cards) | 0.7 pt hairline `primary@0.15` | `OpenClawRowDivider` (2 pt canvas color) | `OpenClawRowDivider` (2 pt canvas color) |
| Scroll bottom padding | 40 pt | 40 pt | 40 pt | none explicit |
| Scroll top padding | 4 pt | 4 pt | 4 pt | 4 pt |
| Horizontal page padding | 24 pt | 24 pt (on rows) | 24 pt | 24 pt |
| Navigation style | None (flat) | None + sheet for detail | None (flat) | `NavigationStack` for push |
| Haptics | `.tap()` on action chips | None | None | None |
