# Chat Drawer (OneTab side-nav)

The Chat Drawer is a slide-in side-navigation panel that surfaces every major destination (Dreaming, Usage, Instances, Cron Jobs, Files, Canvas, Skills) and the full session list as first-class peer tabs alongside the chat. The drawer is the single navigation hub for the phone UI; opening it always produces one crisp haptic click, and selecting any item — destination or session — closes the drawer, making every destination feel like a tab switch on the same "OneTab" surface rather than a push or sheet.

---

## 1. Types and Data Model

### 1.1 `ChatDrawerDestination`

```swift
enum ChatDrawerDestination: Hashable, Identifiable {
    case dreaming, usage, instances, cron, files, canvas, skills
}
```

Source: `Sources/Design/ChatDrawer.swift:3-9`

Seven discrete destination cases. Each case is its own `id` (identity-by-self). Used as the key for the active-destination highlight and for the `onSelectDestination` callback.

### 1.2 `ChatDrawerSession`

```swift
struct ChatDrawerSession: Identifiable, Equatable {
    let id: String
    let title: String
}
```

Source: `Sources/Design/ChatDrawer.swift:11-14`

Minimal value type. `id` is the gateway session key string (e.g. `agent:main:main`). The server list is passed in from outside; ordering and pinning are client-side only (see `ChatSessionPrefs`).

### 1.3 `ChatSessionPrefs`

`@Observable @MainActor final class ChatSessionPrefs` — persisted in `UserDefaults` under key `"chat.sessions.pinned"`. Owns a `Set<String>` of pinned session IDs.

Source: `Sources/Design/ChatSessionPrefs.swift`

| Method | Behavior |
|---|---|
| `isPinned(_ sessionKey:)` | Returns `true` if the key is in the pinned set. |
| `togglePin(_ sessionKey:)` | Inserts or removes from the set; immediately persists the new array to `UserDefaults`. |
| `ordered(_ sessions:)` | Returns pinned rows first (in their incoming recency order), then all unpinned rows. |

A single `ChatSessionPrefs.shared` singleton is accessed via `@State private var prefs = ChatSessionPrefs.shared` inside `ChatDrawerHost`. Using `@State` on an `@Observable` object makes the host re-render on `pinned` changes without needing `@Bindable` or `@EnvironmentObject`.

---

## 2. `ChatDrawerHost` — Parameters

`ChatDrawerHost<ChatContent: View>` is a generic host that wraps arbitrary chat content and the drawer panel in a single view.

| Parameter | Type | Purpose |
|---|---|---|
| `isOpen` | `Binding<Bool>` | Two-way drawer open state. |
| `sessions` | `[ChatDrawerSession]` | Full session list from the gateway (server order). |
| `allowsOpen` | `Bool` (default `true`) | Gates drag-to-open. Set `false` when a Settings screen is pushed over the chat so the left-edge swipe does not pull the drawer out from under it. |
| `onSelectDestination` | `(ChatDrawerDestination) -> Void` | Called when a destination row is tapped. |
| `onSelectSession` | `(String) -> Void` | Called with the session key when a session row is tapped. |
| `onNewSession` | `() -> Void` | Mint and switch to a fresh session (drawer header compose button). |
| `onRenameSession` | `(String, String) -> Void` | Rename: `(sessionKey, newLabel)`. Calls gateway `sessions.patch { label }`. |
| `activeSessionID` | `String?` | Currently open session key; drives the session row highlight. |
| `activeDestination` | `ChatDrawerDestination?` | Currently shown destination (nil when chat is active); drives the destination row highlight. |
| `mainSessionID` | `String` | Gateway home session key (`agent:main:main` by default). Pinned to its own section and excluded from the recents list. |
| `chatContent` | `@ViewBuilder ChatContent` | The full chat surface injected as content. |

---

## 3. Layout Constants

All constants are `private static var` computed properties on `ChatDrawerHost`.

| Constant | Value | Meaning |
|---|---|---|
| `openOffset` | `305` pt (capped at `proxy.size.width * 0.78`) | How far the chat panel slides right when the drawer is fully open. The actual value is `min(305, width × 0.78)` so it never exceeds 78% of the screen on very narrow devices. |
| `panelRadius` | `50` pt | Corner radius of the chat panel's mask when the drawer is open (`RoundedRectangle(cornerRadius: 50, style: .continuous)`). Animated: 0 (closed) → 50 (open). |
| `headerReserve` | `62` pt | Vertical space below the notch reserved for the drawer header (title + button). The first list row rests at `topInset + 62` pt at rest and scrolls up under the scrim. |
| `scaleBleed` | `90` pt | How far the scaled drawer page extends below the visible screen bottom. The scale (anchored `.topLeading`) lifts the bottom edge by up to ~5% of the page height (~45 pt on a 900 pt tall screen); 90 pt of off-screen extension ensures the `ScrollView`'s bottom clip always stays off-screen at every scale value and the list never shows a hard cut at the bottom. |

Source: `Sources/Design/ChatDrawer.swift:52-58, 194-204`

---

## 4. Palette

### 4.1 Drawer Canvas (backdrop color)

| Mode | Color |
|---|---|
| Dark | `Color(red: 23/255, green: 23/255, blue: 23/255)` — near-black `#171717` |
| Light | `Color(red: 245/255, green: 244/255, blue: 250/255)` — warm off-white `#F5F4FA` |

Source: `Sources/Design/ChatDrawer.swift:185-189`

This is identical to the `ChatRootSurface.canvas` color (`Sources/Design/ChatRootSurface.swift:919-922`), intentionally so — the drawer canvas and the chat canvas are the same color.

### 4.2 Active Row Pill

| Mode | Fill |
|---|---|
| Dark | `Color.black` (`#000000`) |
| Light | `Color.white` (`#FFFFFF`) |

Height: `32` pt. Corner radius: `10` pt, style `.continuous`. Opacity: `1.0` (active) / `0.0` (inactive) — always present in the view tree for identity stability; never conditionally rendered.

Source: `Sources/Design/ChatDrawer.swift:459-464`

### 4.3 Glass Button Fill (header compose + `DrawerCloseButton`)

| Mode | Fill |
|---|---|
| Dark | `Color(red: 30/255, green: 30/255, blue: 30/255).opacity(0.2)` — `#1E1E1E` @ 20% |
| Light | `Color(red: 245/255, green: 244/255, blue: 250/255).opacity(0.2)` — `#F5F4FA` @ 20% |

Source: `Sources/Design/ChatDrawer.swift:255-258, 491-494`

Both the header compose button and every `DrawerCloseButton` use `ChatGlassBackground(shape: Circle(), fill: glassFill)`.

### 4.4 `ChatGlassBackground`

Generic glass button background — reused across the entire app. On iOS 26+ it calls `.glassEffect(.regular, in: shape)`; on earlier versions it layers `.regularMaterial` with the fill color on top.

```swift
struct ChatGlassBackground<S: InsettableShape>: View {
    let shape: S            // default: Capsule(style: .continuous)
    let fill: Color
    var hairline: Bool = false   // adds .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.3)
}
```

Source: `Sources/Design/ChatRootSurface.swift:2803-2833`

---

## 5. View Hierarchy

```
GeometryReader (proxy)
└── ZStack(alignment: .topLeading)                          ← root layer
    ├── drawerCanvas.ignoresSafeArea()                      ← static full-bleed backdrop (NOT scaled)
    ├── ZStack(alignment: .topLeading)                      ← scaled drawer page
    │   ├── drawerCanvas.ignoresSafeArea()                  ← inner backdrop fills edges under transform
    │   └── drawerContent(topInset:, trailingInset:)        ← scrollable list + scrim + header
    │       (ZStack, alignment: .topLeading)
    │       ├── ScrollView (scrollIndicators: .hidden)
    │       │   └── VStack(alignment: .leading, spacing: 0)
    │       │       ├── VStack(spacing: 23) — destination rows × 7
    │       │       ├── VStack(spacing: 22) — "Main" section (padding .top 32)
    │       │       │   ├── Text("Main")
    │       │       │   └── sessionRow(mainSessionID, pinnable: false)
    │       │       └── VStack(spacing: 22) — "Sessions" section (padding .top 32)
    │       │           ├── Text("Sessions")
    │       │           └── ForEach(prefs.ordered(recentSessions)) → sessionRow(pinnable: true)
    │       ├── drawerTopScrim(topInset:)                   ← blurred fade band, full-width
    │       └── drawerHeader                               ← "OpenClaw" title + compose button
    │   .padding(.bottom, -scaleBleed)                     ← extends page 90 pt below screen
    │   .scaleEffect(drawerScale, anchor: .topLeading)
    └── chatContent                                         ← chat panel, offset rightward
        .blur(radius: isOpen ? 0.6 : 0)
        .allowsHitTesting(!isOpen)
        .overlay { Color.black.opacity(0.001) tap-to-close scrim, when isOpen }
        .mask { RoundedRectangle(cornerRadius: isOpen ? 50 : 0, style: .continuous).ignoresSafeArea() }
        .shadow(color: .black.opacity(0.25), radius: 15, x: -5, y: 0)
        .offset(x: currentOffset(open:))
        .simultaneousGesture(panelDrag(open:))
```

Source: `Sources/Design/ChatDrawer.swift:60-135`

---

## 6. Scale Animation (Drawer Recede)

### Formula

```
slideProgress = currentOffset / openOffset          // 0.0 (closed) → 1.0 (fully open)
drawerScale   = 0.95 + 0.05 × slideProgress        // 0.95 → 1.0
```

Source: `Sources/Design/ChatDrawer.swift:64-66`

The scale is proportional to `currentOffset` (the live panel offset including mid-drag values), not just the boolean `isOpen`. A half-open drawer produces a scale of ~0.975, so the recede tracks the finger continuously rather than snapping between 0.95 and 1.0.

### Scale Anchor

`.scaleEffect(drawerScale, anchor: .topLeading)` — top-left corner pinned. This prevents the header from "pushing down" under the transform and prevents the `ignoresSafeArea` top-bleed from collapsing into a visible trim line at the top. Only the bottom and right edges inset (both hidden by the backdrop or the chat panel).

Source: `Sources/Design/ChatDrawer.swift:89`

### `scaleBleed` Anti-Clipping Trick

`.padding(.bottom, -scaleBleed)` — adds 90 pt of off-screen extension below the view frame before scaling. Because the scale lifts the bottom edge by up to ~5% of the full page height (~45 pt on a 900 pt page), keeping 90 pt off-screen guarantees the `ScrollView`'s bottom clip never becomes visible at any scale value. The `ScrollView`'s `contentInset.bottom` matches `scaleBleed + 24` so the last row visually rests at the bottom of the screen.

Source: `Sources/Design/ChatDrawer.swift:85, 329-331`

### Static Full-Bleed Backdrop

Two `drawerCanvas.ignoresSafeArea()` rectangles — one outside the scaled `ZStack` (not transformed) and one inside it — fill the gaps that appear at the scaled view's collapsed edges. When the page scales to 0.95, its trailing and bottom edges pull away from the screen boundary; the unscaled outer backdrop fills those gaps so no trim or white flash ever shows. Without the outer backdrop, the scale exposes whatever color sits behind the `GeometryReader` (typically the system background), producing a visible "paper-cut" edge.

Source: `Sources/Design/ChatDrawer.swift:72-84` (inline comment)

---

## 7. Chat Panel Behavior When Drawer Is Open

### Blur Recede

```swift
.blur(radius: isOpen ? 0.6 : 0)
```

Source: `Sources/Design/ChatDrawer.swift:98`

The panel recedes via blur, not opacity. Reducing opacity would make the panel semi-transparent so the drawer content behind it bleeds through — especially visible on destination tabs. Blur keeps the panel fully opaque while still reading as "inactive."

### Round-Rect Mask

```swift
.mask {
    RoundedRectangle(cornerRadius: isOpen ? 50 : 0, style: .continuous)
        .ignoresSafeArea()
}
```

Source: `Sources/Design/ChatDrawer.swift:110-115`

The mask uses `ignoresSafeArea()` so the panel's full-height content (which also ignores safe areas) is not clipped at the top or bottom when rounded. Without `ignoresSafeArea()` on the mask the top and bottom of the panel would be cut to the safe-area frame and show gaps.

### Drop Shadow

```swift
.shadow(color: .black.opacity(0.25), radius: 15, x: -5, y: 0)
```

Source: `Sources/Design/ChatDrawer.swift:119-121`

The shadow is always applied — not conditional on `isOpen`. When the drawer is closed, the panel is at `offset x = 0` and fills the screen, so the shadow is off-screen to the left. As the panel slides right, the shadow becomes visible against the drawer. Being always-on means it is present throughout the opening slide rather than fading in only after the panel settles.

### Tap-to-Close Scrim

```swift
if isOpen {
    Color.black.opacity(0.001)
        .contentShape(Rectangle())
        .onTapGesture { close() }
}
```

Source: `Sources/Design/ChatDrawer.swift:104-108`

The scrim is overlaid on the chat panel before `.offset`, so it slides with the panel and only covers the visible portion of chat. An earlier implementation placed the overlay after `.offset` which spanned the full screen width and consumed taps on the drawer buttons.

---

## 8. Gesture System

### `panelDrag(open:)` — `.simultaneousGesture`

Attached with `.simultaneousGesture` (not `.gesture`) so it coexists with the transcript's vertical `ScrollView`. The two gestures share touches; the drag interceptor only steals a touch for a rightward, horizontally-dominant swipe.

Source: `Sources/Design/ChatDrawer.swift:125-126, 149-177`

#### Direction Latch (`openSwipeEngaged`)

```swift
@State private var openSwipeEngaged: Bool?
```

- `nil` until first significant movement.
- Set to `true` if `translation.width > 0 && abs(translation.width) > abs(translation.height)` — rightward and horizontally dominant.
- Set to `false` for any other direction.
- Latched for the life of the gesture. A mid-drag direction change cannot flip the decision.
- Reset to `nil` on `.onEnded`.

Source: `Sources/Design/ChatDrawer.swift:48-50, 157-163`

#### Minimum Distance

`DragGesture(minimumDistance: 12)` — the gesture does not fire until 12 pt of movement, which filters out accidental micro-drags.

Source: `Sources/Design/ChatDrawer.swift:150`

#### `allowsOpen` Gate

When `allowsOpen == false`, `.onChanged` returns immediately in the closed state so no drag offset accumulates and the drawer cannot open. This is set by the parent when a Settings screen is pushed over the chat.

Source: `Sources/Design/ChatDrawer.swift:18-22, 156`

#### Release Decision (Projected End)

```swift
let projected = base + value.predictedEndTranslation.width
withAnimation(.spring(duration: 0.35)) {
    if engaged {
        self.isOpen = projected > open / 2
    }
    self.dragOffset = 0
}
```

The decision uses `predictedEndTranslation` — the gesture's projected resting position based on velocity — so a quick flick commits the drawer to open or close even if the finger has only moved a short distance. The threshold is `openOffset / 2` (i.e. ~152 pt).

Source: `Sources/Design/ChatDrawer.swift:165-176`

#### When Drawer Is Already Open

Any drag (any direction) accumulates into `dragOffset`; the direction latch is bypassed. The release still uses the projected end.

Source: `Sources/Design/ChatDrawer.swift:152-154`

### `currentOffset(open:)`

```swift
func currentOffset(open: CGFloat) -> CGFloat {
    let base: CGFloat = isOpen ? open : 0
    return max(0, min(open, base + dragOffset))
}
```

Clamps the offset to `[0, openOffset]`. The `dragOffset` is a live `@State` (not `@GestureState`) so the snap-back on release can be animated — a `@GestureState` reset is instantaneous and would cause a visible jump.

Source: `Sources/Design/ChatDrawer.swift:43-45, 139-142`

### Animation

```swift
withAnimation(.spring(duration: 0.35)) { ... }
```

Used for both open and close snaps. No custom spring damping or response specified — uses SwiftUI's default spring damping for the given duration.

Source: `Sources/Design/ChatDrawer.swift:169, 181`

---

## 9. Haptic Feedback

Every `isOpen` state change triggers `OpenClawHaptics.click()`.

```swift
.onChange(of: isOpen) { _, _ in
    OpenClawHaptics.click()
}
```

Source: `Sources/Design/ChatDrawer.swift:132-134`

`OpenClawHaptics.click()` plays the `secured1` Core Haptics pattern: one crisp transient event at `t=0`, intensity `1.0`, sharpness `0.9`. This pattern is described as "minimalist — one crisp click."

Source: `Sources/Onboarding/OpenClawHaptics.swift:39-42, 144-145`

Because the haptic fires on every `isOpen` toggle (not only open), both opening and closing the drawer — and selecting a destination or session (which calls `close()`) — produce the same click. This reinforces the "tab switch" feel: every drawer action sounds like the drawer moving.

---

## 10. Top Scrim

The `drawerTopScrim(topInset:)` creates a blurred fade band at the top of the drawer so rows dissolve as they scroll under the header rather than hitting a hard clip.

### Structure

```
Rectangle()
  .fill(.ultraThinMaterial)
  .overlay { drawerCanvas.opacity(colorScheme == .dark ? 0.72 : 0) }
  .mask {
      LinearGradient(
          stops: [
              (.black.opacity(0.6), location: 0),
              (.black.opacity(0.6), location: 0.55),
              (.clear,              location: 1),
          ],
          startPoint: .top,
          endPoint: .bottom)
  }
  .frame(height: topInset + headerReserve)   // dynamic: safe-area top + 62 pt
  .frame(maxWidth: .infinity)
  .ignoresSafeArea(edges: .top)
  .allowsHitTesting(false)
```

Source: `Sources/Design/ChatDrawer.swift:210-231`

### Gradient Stops

| Stop | Color | Location |
|---|---|---|
| 0 | `.black.opacity(0.6)` | `0.0` (top) |
| 1 | `.black.opacity(0.6)` | `0.55` |
| 2 | `.clear` | `1.0` (bottom) |

The mask holds a constant 0.6 opacity from the top down to 55% of the scrim's height, then fades to clear. This means the material is applied at ~60% strength in the opaque zone and graduates to zero right where the first row rests. This produces a subtler blur than a full-opacity material band.

### Dark Mode Tint Overlay

In dark mode, `drawerCanvas.opacity(0.72)` (i.e. `#171717` @ 72%) is overlaid on the frosted `.ultraThinMaterial`. This darkens the frost toward the near-black canvas color, keeping the header band dark and independent of whatever content is scrolling beneath. In light mode the overlay is `opacity(0)` (no-op) because the frosted white material already matches the canvas.

### Exact 1:1 Match with Chat Top Scrim

The gradient stops (0.6 cap, 0.55 plateau, clear at 1.0), the `.ultraThinMaterial` base, and the dark mode `0.72` canvas overlay are identical between `drawerTopScrim` and `ChatRootSurface.topScrim`. The only difference is the frame height: the chat scrim is a fixed `110` pt; the drawer scrim is `topInset + headerReserve` (dynamic, matching the notch depth).

Source: `Sources/Design/ChatRootSurface.swift:996-1018`

### Placement

The scrim is placed as a full-width overlay inside `drawerContent`'s `ZStack`, above the `ScrollView` and below the `drawerHeader`. Its `ignoresSafeArea(edges: .top)` causes its top edge to land under the notch (the physical screen top), not as a visible band starting below the status bar. This eliminates any visible mid-screen seam.

---

## 11. Drawer Header

```
HStack
├── Text("OpenClaw")
│     .font(.system(size: 25.6, weight: .semibold))
│     .foregroundStyle(Color.primary)
├── Spacer(minLength: 0)
└── Button (compose / new session)
      label:
        Image("ChatPlusGlyph") — template, 20×20 pt
          .foregroundStyle(Color.primary)
          .frame(40×40)
          .background { ChatGlassBackground(shape: Circle(), fill: glassFill) }
          .shadow(color: .black.opacity(0.15), radius: 25, x: 0, y: 0)
```

Source: `Sources/Design/ChatDrawer.swift:233-264`

| Property | Value |
|---|---|
| Title font | `.system(size: 25.6, weight: .semibold)` |
| Title color | `Color.primary` |
| Compose glyph | `"ChatPlusGlyph"` (template image), 20×20 pt |
| Compose button hit area | `frame(width: 40, height: 40)` |
| Compose button background | `ChatGlassBackground(shape: Circle(), fill: glassFill)` |
| Compose button shadow | `.black.opacity(0.15)`, radius `25`, x `0`, y `0` |
| Header leading padding | `8` pt (`.padding(.leading, 8)` on the whole `drawerHeader`, applied in `drawerContent`) |
| Header trailing padding | `trailingInset` (= `proxy.size.width - openOffset + 16`) |
| Header top padding | `topInset + 8` |

Tapping the compose button calls `onNewSession()` then `close()`, switching to a fresh session and closing the drawer simultaneously.

---

## 12. Destination Rows

### `drawerRow(_:_:destination:action:)`

```
Button(action: action)
  HStack(spacing: 12)
    Image(icon)
      .renderingMode(.template)
      .resizable()
      .scaledToFit()
      .frame(22×22)
      .opacity(0.9)
    Text(label)
      .font(.system(size: 17.13))
    Spacer(minLength: 0)
  .foregroundStyle(Color.primary)
  .padding(.leading, 14)
  .contentShape(Rectangle())
.buttonStyle(.plain)
.background { activeRowHighlight(destination == activeDestination) }
```

Source: `Sources/Design/ChatDrawer.swift:426-452`

| Property | Value |
|---|---|
| Row spacing (icon-to-label) | `12` pt |
| Icon size | `22×22` pt |
| Icon opacity | `0.9` |
| Label font | `.system(size: 17.13)` |
| Leading content inset | `14` pt |
| Row spacing (between rows) | `23` pt (outer `VStack(spacing: 23)`) |

### Destination Row Inventory

| Icon name | Label | Destination case |
|---|---|---|
| `DrawerMoonStarGlyph` | `"Dreaming"` | `.dreaming` |
| `DrawerPieChartGlyph` | `"Usage"` | `.usage` |
| `DrawerServerGlyph` | `"Instances"` | `.instances` |
| `DrawerClockGlyph` | `"Cron Jobs"` | `.cron` |
| `DrawerFilesGlyph` | `"Files"` | `.files` |
| `DrawerPaletteGlyph` | `"Canvas"` | `.canvas` |
| `DrawerScrollGlyph` | `"Skills"` | `.skills` |

Source: `Sources/Design/ChatDrawer.swift:275-296`

---

## 13. Session Rows

### Section Structure

Two VStacks below the destination rows, each with `.padding(.top, 32)`:

1. **Main section** — `VStack(alignment: .leading, spacing: 22)`:
   - `Text("Main")` — `.system(size: 15)`, `Color.primary.opacity(0.6)`, `.padding(.leading, 14)`
   - `sessionRow(id: mainSessionID, title: mainSessionTitle, pinnable: false)`

2. **Sessions section** — `VStack(alignment: .leading, spacing: 22)`:
   - `Text("Sessions")` — `.system(size: 15)`, `Color.primary.opacity(0.6)`, `.padding(.leading, 14)`
   - `ForEach(prefs.ordered(recentSessions)) { session in sessionRow(..., pinnable: true) }`

`recentSessions` filters out `mainSessionID` so the home session never appears in both sections.

`mainSessionTitle` resolves to `sessions.first(where: { $0.id == mainSessionID })?.title ?? "Main"`.

Source: `Sources/Design/ChatDrawer.swift:298-320`

### `sessionRow(id:title:pinnable:)`

```
Button { onSelectSession(id); close() }
  label:
    HStack(spacing: 6)
      Text(title)
        .font(.system(size: 17.13))
        .foregroundStyle(Color.primary)
        .lineLimit(1)
      if pinnable && prefs.isPinned(id):
        Image(systemName: "pin.fill")
          .font(.system(size: 11))
          .foregroundStyle(Color.primary.opacity(0.4))
      Spacer(minLength: 0)
    .padding(.leading, 14)
    .contentShape(Rectangle())
.buttonStyle(.plain)
.background { activeRowHighlight(activeDestination == nil && id == activeSessionID) }
.contextMenu { Rename + Pin/Unpin buttons }
```

Source: `Sources/Design/ChatDrawer.swift:381-424`

| Property | Value |
|---|---|
| Title font | `.system(size: 17.13)` |
| Title color | `Color.primary` |
| Title line limit | `1` |
| Pin icon | `"pin.fill"` (SF Symbol), `.system(size: 11)`, `Color.primary.opacity(0.4)` |
| HStack spacing | `6` pt |
| Leading content inset | `14` pt |
| Row spacing (between rows) | `22` pt (outer section `VStack(spacing: 22)`) |

### Active Session Highlight Rule

The session row highlight is suppressed when `activeDestination != nil`. If a destination tab is showing, that destination row owns the highlight; the session rows are all inactive. This prevents two active rows from showing simultaneously.

Source: `Sources/Design/ChatDrawer.swift:405-406` (inline comment)

---

## 14. Active Row Highlight Pill

```swift
private func activeRowHighlight(_ isActive: Bool) -> some View {
    RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(colorScheme == .dark ? Color.black : Color.white)
        .frame(height: 32)
        .opacity(isActive ? 1 : 0)
}
```

Source: `Sources/Design/ChatDrawer.swift:459-464`

The pill always exists in the view tree (opacity-gated, not conditionally inserted). This keeps SwiftUI view identity stable across active-state changes so there is no unexpected layout recalculation or animation glitch on selection.

The `14` pt leading inset on both row types means the row's `HStack` starts 14 pt from the left of the containing `ScrollView`. The pill's `.background` fills from the `ScrollView`'s left edge (x = 0) to the full row width — its leading edge is not inset — so the pill's left rounded corner is at the drawer's left edge (8 pt from the screen edge after the outer `.padding(.leading, 8)`), not 14 pt inside it.

---

## 15. Rename and Pin Interactions

### Rename (context menu → alert)

State:
```swift
@State private var renameTargetID: String?
@State private var renameText = ""
```

Flow:
1. Long-press any session row → context menu with "Rename" (`pencil` SF Symbol).
2. Tap "Rename": sets `renameText = title`, `renameTargetID = id`.
3. Alert is presented (bound to `renameTargetID != nil`).
4. Alert has a `TextField("Name", text: $renameText)`, "Cancel" button (role `.cancel`), and "Save" button.
5. "Save": calls `onRenameSession(id, renameText)`, then clears `renameTargetID`.
6. Alert dismiss (Cancel or background tap): clears `renameTargetID`.

Source: `Sources/Design/ChatDrawer.swift:407-411, 346-361`

The alert text label is `"Rename chat"`.

### Pin / Unpin (context menu)

Only shown when `pinnable == true` (i.e. not the Main session row).

- If pinned: shows "Unpin" with `"pin.slash"` SF Symbol.
- If not pinned: shows "Pin" with `"pin"` SF Symbol.

Tapping either calls `prefs.togglePin(id)`, which immediately persists to `UserDefaults` and causes the `ForEach` to re-evaluate `prefs.ordered(recentSessions)` (pinned rows float to the top within the Sessions section).

Source: `Sources/Design/ChatDrawer.swift:414-423`

---

## 16. `DrawerCloseButton`

Shared dismiss control used at the top of every drawer destination screen. Matches the Connection sheet's close button exactly.

```
Button(action: onClose)
  Image("ChatCloseGlyph") — template, 22×22 pt
    .foregroundStyle(Color.primary)
    .frame(40×40)
    .background { ChatGlassBackground(shape: Circle(), fill: glassFill) }
    .shadow(color: .black.opacity(0.15), radius: 25, x: 0, y: 0)
.buttonStyle(.plain)
.padding(.leading, 25)
.padding(.top, 22)
```

Source: `Sources/Design/ChatDrawer.swift:469-496`

| Property | Value |
|---|---|
| Glyph | `"ChatCloseGlyph"` (template image), 22×22 pt |
| Hit area | `40×40` pt |
| Background | `ChatGlassBackground(shape: Circle(), fill: glassFill)` |
| Shadow | `.black.opacity(0.15)`, radius `25`, x `0`, y `0` |
| Leading padding | `25` pt |
| Top padding | `22` pt |

---

## 17. `DrawerCanvasScreen`

Minimal host for the shared canvas web view exposed as the Canvas destination.

```swift
struct DrawerCanvasScreen: View {
    @Environment(NodeAppModel.self) private var appModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScreenWebView(controller: appModel.screen)
                .ignoresSafeArea(edges: .bottom)
        }
        .onAppear { appModel.screen.showDefaultCanvas() }
    }
}
```

Source: `Sources/Design/ChatDrawer.swift:501-514`

The top safe area is NOT ignored so the `DrawerCloseButton` (overlaid by the presenting host) has reserved space above the web content. The bottom edge bleeds to fill the screen. `showDefaultCanvas()` is called on `.onAppear` to render the canvas at the correct URL.

---

## 18. Destinations as Content Switch (not Overlay)

The drawer destinations (Dreaming, Usage, Instances, Cron Jobs, Files, Canvas, Skills) are not presented as sheets or navigation pushes from the drawer. They are rendered in `RootTabs.drawerDestinationScreen` as a content switch — the destination view replaces the chat content in the same full-screen area. The drawer routes to the destination via `onSelectDestination`, which the host uses to set an `activeDestination` binding. Each destination screen owns its own header with `DrawerCloseButton`, which sets `activeDestination = nil` to return to the chat.

This is why `activeDestination` is tracked separately from `isOpen`: the drawer can be closed while a destination is showing, and the destination tab's row remains highlighted.

---

## 19. Cron Jobs Destination — Built-In Filter

`CronJobsScreen` is the destination for `.cron`. It has its own filter state (not in the drawer) presented as a `Menu` in the header. Two filter options:

| Filter case | `title` | `matches(_:)` logic |
|---|---|---|
| `.active` | `"Active"` | `!job.isCompleted` |
| `.completed` | `"Completed"` | `job.isCompleted` |

A `CronJobRow` is completed if it is a one-shot that has fired, or a recurring job the user disabled. The active pill and the filter menu button both use `ChatGlassBackground`-backed glass chrome matching the drawer's floating buttons.

Source: `Sources/Design/CronJobsScreen.swift:31-50`

---

## 20. ScrollView Insets

Inside `drawerContent`, the content `VStack` receives:

| Edge | Value | Reason |
|---|---|---|
| `.leading` | `8` pt | Active pill bleeds 14 pt left of the 22 pt label; the pill's left rounded corner sits at the ScrollView edge, which is 8 pt from the screen edge. |
| `.trailing` | `trailingInset` = `proxy.size.width - openOffset + 16` | Keeps all row content to the left of the chat panel, with a 16 pt gap. |
| `.top` | `topInset + headerReserve` = `topInset + 62` pt | First row rests just below the header. |
| `.bottom` | `scaleBleed + 24` = `90 + 24 = 114` pt | Last row rests at the visible bottom; the ScrollView's clip sits off-screen. |

Source: `Sources/Design/ChatDrawer.swift:322-332`
