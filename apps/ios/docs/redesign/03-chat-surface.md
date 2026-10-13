# Chat Root Surface (bubbles, composer, scroll)

`ChatRootSurface` is the live phone chat UI rendered by `ChatProTab` → `RootTabs.phoneTabContent`. It is a pure-presentation layer over `OpenClawChatViewModel`; the shared `OpenClawChatUI` package (`ChatView`, `ChatMessageViews`, `ChatComposer`) is the legacy/macOS chat UI and is not involved in iPhone rendering. Everything described in this document is sourced from `Sources/Design/ChatRootSurface.swift`, `Sources/Design/StreamingReplyBubble.swift`, `Sources/Design/ChatImageViewer.swift`, `Sources/Design/ChatAudioComponents.swift`, and `Sources/Design/ChatAudioLevels.swift`.

---

## 1. Top-level Layout

```
ZStack {
  canvas (Color, ignoresSafeArea)
  transcript (ScrollViewReader > ScrollView > LazyVStack)
}
.overlay(top)   { topScrim }
.overlay(top)   { topBar }
.overlay        { attachmentTray-backdrop (conditional) }
.safeAreaInset(bottom) { composer }
.overlay        { ChatStepsOverlay (always-mounted, nil = hidden) }
.sheet(item: openEmbed) { CanvasEmbedPanel }
.fullScreenCover { ChatCameraPicker }
.photosPicker   { image / GIF pickers }
.fileImporter   { document picker }
```

The `ZStack` is the root; `canvas` fills behind the scroll list. The top scrim and top bar sit as named overlays above the scroll content. The composer is injected into the bottom safe-area inset so the keyboard and the scroll list push together. The steps overlay is **always mounted** (a `GeometryReader/ZStack` wrapper), so its `card (.move)` and `scrim (.opacity)` transitions run as independent children rather than a single `.opacity` on the whole subtree (`ChatRootSurface.swift:275`).

### Canvas (background)

| Mode | Color |
|---|---|
| Dark | `rgb(23, 23, 23)` — `#171717` |
| Light | `rgb(245, 244, 250)` — `#F5F4FA` |

---

## 2. Top Bar

The top bar is an `HStack` rendered as an `.overlay(alignment: .top)` with padding `.horizontal 14`, `.top 8`. It has a single `.shadow(color: .black.opacity(0.15), radius: 25, x: 0, y: 0)` (`ChatRootSurface.swift:987`).

### Leading: avatar + name button

A `Button` with `.plain` style wrapping an `HStack(spacing: 0)`:

| Element | Spec |
|---|---|
| Avatar image | Asset `ChatAvatarImage`, 34×34 pt, `.scaledToFill`, `.clipShape(Circle())`, wrapped in `.padding(3)` |
| Presence dot | 11×11 pt `Circle`, fill `onlineGreen` (`rgb(52, 199, 89)`), `strokeBorder` ring 2 pt width in `onlineRing` color, offset `(x: 1, y: 1)`, aligned `.bottomTrailing` of the avatar |
| Presence dot ring | Dark: `rgb(23, 23, 23)` / Light: `rgb(245, 244, 250)` — matches canvas so it reads as a cutout |
| Dot visibility | Only shown when `viewModel.healthOK == true` |
| Dot transition | `.scale.combined(with: .opacity)` |
| Dot animation | `.smooth(duration: 0.25)` driven by `viewModel.healthOK` |
| "OpenClaw" label | `.system(size: 16, weight: .semibold)`, `.foregroundStyle(Color.primary)`, `.padding(.trailing, 14)` |
| Button background | `glassCapsule` (see Glass Surfaces section) |
| Button disabled | When `onOpenDrawer == nil` |
| Button action | Calls `onOpenDrawer?()` |

### Trailing: settings button

A `Button` wrapping:

| Element | Spec |
|---|---|
| Icon | Asset `ChatSettingsGlyph`, `.template`, 24×24 pt, `.foregroundStyle(Color.primary)` |
| Hit area | 40×40 pt frame |
| Background | `glassCapsule` |
| Action | Calls `onOpenSettings()` |

---

## 3. Top Scrim

A `Rectangle` with `.ultraThinMaterial` fill, masked by a vertical gradient, height 110 pt, full width, anchored at the top and ignoring the top safe-area edge (`ChatRootSurface.swift:996–1018`). It is non-interactive (`.allowsHitTesting(false)`).

### Dark-mode tint overlay

On top of the `.ultraThinMaterial`, a second layer of `canvas` color at opacity `0.72` is applied in dark mode only (none in light mode). This pulls the frosted band toward the near-black canvas, preventing the blur from reading as light/frosted.

### Gradient mask

```
LinearGradient(
  stops: [
    .init(color: .black.opacity(0.6), location: 0),
    .init(color: .black.opacity(0.6), location: 0.55),
    .init(color: .clear,              location: 1),
  ],
  startPoint: .top, endPoint: .bottom)
```

Effect: the material is applied at ~60% opacity from the top down to 55% of the 110 pt band, then fades to clear — a subtler scrim than a full-opacity material.

---

## 4. Transcript

### ScrollView structure

```
ScrollViewReader { proxy in
  ScrollView {
    LazyVStack(spacing: 0) {
      ForEach(rows) { row in
        messageView(for: row)
          .padding(.top, row.progressLines.isEmpty ? 0 : 10)
          .padding(.bottom, rowBottomSpacing(row))
          .background(pinnedQuestionProbe(for: row))
          .transition(row.isUser
            ? .move(edge: .bottom).combined(with: .opacity)
            : .opacity)
      }
      trailingIndicator
        .animation(.easeInOut(duration: 0.25), value: turnPhase)
        .animation(.easeInOut(duration: 0.25), value: streamingReplyText != nil)
        .animation(.easeInOut(duration: 0.25), value: nodeReady)
      Color.clear.frame(height: 0)          // contentTailBottom probe
      Color.clear.frame(height: bottomSpacerHeight)   // dynamic spacer
      Color.clear.frame(height: 1).id("chat-bottom-anchor")
    }
    .padding(.horizontal, 14)
    .padding(.top, 108)
    .coordinateSpace(.named("chatContentSpace"))
  }
  .id(rows.isEmpty)                          // recreate once on first load
  .defaultScrollAnchor(.bottom)
  .defaultScrollAnchor(.top, for: .sizeChanges)
  .scrollDismissesKeyboard(.interactively)
  ...
}
```

### Row bottom spacing

| Row type | Bottom padding |
|---|---|
| User bubble | 21 pt |
| "Worked through N steps" trail | 15 pt |
| All other assistant rows | 25 pt |

### Row top spacing

Tool-use steps trail rows get `.padding(.top, 10)` above them (all others 0) so they read as detached from the preceding user bubble but grouped with the answer below (`ChatRootSurface.swift:334`).

### Day separator rows

A centered, non-interactive `Text` row inserted between consecutive transcript rows whose calendar day changes:

| Property | Value |
|---|---|
| Font | `.system(size: 12, weight: .medium)` |
| Color | Dark: `white.opacity(0.45)` / Light: `black.opacity(0.45)` |
| Alignment | `.center`, full width |
| Vertical padding | `.padding(.vertical, 4)` |
| Label format | "Today" / "Yesterday" / weekday name (within last 7 days) / "MMM d" (same year) / "MMM d, yyyy" |

---

## 5. Scroll Behavior and Correctness Fixes

### `.id(rows.isEmpty)` — ScrollView recreation

When `rows` transitions from empty → non-empty (history load or session start), the entire `ScrollView` is recreated via `.id(rows.isEmpty)`. Without this, a bulk size-change from an empty-then-populated `LazyVStack` under `.defaultScrollAnchor(.top, for: .sizeChanges)` puts the scroll state into a limbo where cells won't paint until a manual scroll. Rebuilt with rows already present, `.defaultScrollAnchor(.bottom)` positions and paints the latest turns immediately. (`ChatRootSurface.swift:379`)

### `.defaultScrollAnchor(.bottom)` + `.defaultScrollAnchor(.top, for: .sizeChanges)`

- `.bottom` — the initial anchor: the newest message is visible at rest.
- `.top, for: .sizeChanges` — finalized answer rows inserting at full height do not instantly yank the transcript upward (the "snap"). New messages/answers still reach the bottom via explicit animated `scrollToBottom` calls, so the only visible motion is the smooth scroll while the answer reveals. (`ChatRootSurface.swift:398`)

### Bottom-inset re-pin

When the composer or keyboard grows the bottom content inset, `scrollToBottom` is called immediately (non-animated) so the last message stays above the keyboard without relying on the now-`.top` size-change anchor. (`ChatRootSurface.swift:401–405`)

### Initial rows scroll

On first appearance (`.onChange(of: rows.isEmpty, initial: true)`), if rows are already present (cold start / session switch with a cached history) and no pin is active, `scrollToBottom` is called after a one-runloop deferral via `Task { @MainActor in … }` so cells are laid out before the scroll fires. (`ChatRootSurface.swift:431–436`)

### Scene-phase foreground re-assert

A long background suspense causes `LazyVStack` to stop rendering; on foreground the cells appear blank until a manual scroll re-materializes them. On `.active`, `viewModel.resumeFromForeground()` is called and then `scrollToBottom` (non-animated). (`ChatRootSurface.swift:441–445`)

### `scrollToBottom` implementation

```swift
func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool, reason: String) {
    guard animated else {
        proxy.scrollTo("chat-bottom-anchor", anchor: .bottom)
        return
    }
    withAnimation(.easeOut(duration: 0.2)) {
        proxy.scrollTo("chat-bottom-anchor", anchor: .bottom)
    }
}
```

Animated path uses `.easeOut(duration: 0.2)`.

---

## 6. Pin-to-Top Scroll Behavior (Send Flow)

When the user sends a message, the newly-appearing user bubble springs up to rest near the top of the viewport so the space below it fills with the assistant reply. This uses a multi-part coordinate system.

### Named coordinate space

`"chatContentSpace"` — set on the `LazyVStack`; all content-relative measurements read from this space.

### Pin lifecycle

1. **On send (`armAndSend`):** `pinScrollPending = true`, `pinnedQuestionTop = nil` reset.
2. **On first `rows.count` change after send:** the last user row's id is captured as `pinTurnID`; `pinScrollPending = false`. A spring scroll runs: `.spring(response: 0.42, dampingFraction: 0.82)` to `proxy.scrollTo(userRow.id, anchor: pinAnchor)`. (`ChatRootSurface.swift:420`)
3. **While pinned:** reply rows fill in below. The `.top` size-change anchor holds the pinned question in place — no scroll on token arrival. `scrollToBottom` is only called when no pin is active. (`ChatRootSurface.swift:449–465`)
4. **Pin is NOT released at reply end.** Releasing would tear down the bottom spacer (~1 viewport) and force a scroll-to-bottom, which snapped the transcript upward. The finished turn stays put — question near the top, reply below. The pin advances to the next question on the next send. (`ChatRootSurface.swift:756–760`)
5. **On session switch (`.task(id: ObjectIdentifier(viewModel))`):** `pinTurnID = nil`, `pinScrollPending = false`, `pinnedQuestionTop = nil`.

### `pinAnchor`

A `UnitPoint` computed from the viewport height:

```swift
guard viewportHeight > 200 else { return .top }
return UnitPoint(x: 0.5, y: min(0.4, 120 / viewportHeight))
```

Result: the pinned question's top edge rests approximately 120 pt below the viewport top (clearing the top bar/scrim), capped at 40% of the viewport height.

### Dynamic bottom spacer (`bottomSpacerHeight`)

Reserves exactly enough room below the newest turn to keep the pinned question at the scroll ceiling as the reply grows:

```swift
guard pinTurnID != nil, viewportHeight > 0 else { return 10 }  // bottomContentPadding
let pinOffset = pinAnchor.y * viewportHeight
return max(10, viewportHeight - pinOffset - pinnedTurnHeight)
```

`pinnedTurnHeight = contentTailBottom - pinnedQuestionTop` (measured via preference keys). As the reply grows, `pinnedTurnHeight` grows 1:1 and the spacer shrinks — no net reflow, no reply-end snap, no over-scroll into dead space. (`ChatRootSurface.swift:191–195`)

### Preference key probes

| Key | Measures | Strategy |
|---|---|---|
| `PinnedQuestionTopKey` | The pinned row's `minY` in content coords | Only the pinned row emits; `reduce` takes `value ?? nextValue()` (first non-nil wins). Once a long reply scrolls the pinned row off the top, `LazyVStack` stops rendering it (probe → nil), so the last non-nil value is retained and never overwritten with nil. Reset on send/session switch. |
| `ContentTailBottomKey` | The `minY` of a `Color.clear` frame placed after all real rows | `reduce` takes `max(value, nextValue())`. Placed before the dynamic spacer so it represents the bottom of real content. |

---

## 7. Row Animations

Live turns animate row insertions; history loads and session switches do not:

```swift
let liveTurn = pinScrollPending || pinTurnID != nil || awaitingReplyReveal
if liveTurn, nextRows.count != rows.count {
    withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
        self.rows = nextRows
    }
}
```

Per-row transitions:
- **User rows:** `.move(edge: .bottom).combined(with: .opacity)` — springs up from below.
- **Assistant rows:** `.opacity` — fades in, so the finalized answer row replacing the streaming bubble is a crossfade, not a pop.

### `nodeReady` delay

After a send, `nodeReady = false` immediately. A `Task.sleep(for: .seconds(0.42))` (matching the spring's `response`) then sets it to `true`. This prevents the "Thinking" node from riding the user-bubble spring and popping in before the bubble settles. The node fades in via `.easeInOut(duration: 0.25)` on `nodeReady`. (`ChatRootSurface.swift:315–319`, `1315–1319`)

---

## 8. Turn Phase Machine

A forward-only state machine drives all working-state UI. Prevents mid-turn oscillation caused by `pendingRuns` clearing and re-adopting between tool calls.

```swift
enum TurnPhase: Int { case idle, thinking, tooling, answering }
```

| Phase | Meaning | UI shown |
|---|---|---|
| `.idle` | Nothing in flight | No node, no streaming bubble |
| `.thinking` | Run started, no tool step yet | `ChatThinkingNode` (shimmer) or streaming bubble (tool-free reply) |
| `.tooling` | ≥1 tool preamble surfaced | `ChatThinkingNode` (shimmer) with live preamble text |
| `.answering` | Final answer streaming after tools | Footprints collapsed to in-transcript "steps" row; streaming bubble shows answer |

Transitions are forward-only: `guard next == .idle || next.rawValue > turnPhase.rawValue else { return }`. Only `.idle` can revert the phase. (`ChatRootSurface.swift:160–165`)

### Promotion to `.answering`

When in `.tooling` and `pendingToolCalls` is empty and `streamingAssistantText.count >= 160` (the `answeringPromoteThreshold`), the phase promotes to `.answering` and `rebuildRows()` flushes footprints into the in-transcript row. (`ChatRootSurface.swift:457–462`)

### `turnJustCompleted` guard

Set to `true` when the answer row lands while `turnPhase != .idle`, then phase is set to `.idle`. This blocks a trailing `pendingRuns` re-adopt from restarting a phantom `.thinking` phase. Reset to `false` on the next send. (`ChatRootSurface.swift:752–758`)

---

## 9. Trailing Indicator (below the last row)

The `trailingIndicator` view sits directly after the `ForEach` in the `LazyVStack`, before the probes and spacer. All three state transitions are animated with `.easeInOut(duration: 0.25)` on `turnPhase`, `streamingReplyText != nil`, and `nodeReady`.

### Streaming bubble branch

Shown when `streamingReplyText != nil` (phase is `.thinking` or `.answering`, no pending tool calls, text is non-empty after trimming):

```
StreamingReplyBubble(fullText: streamText, textColor: dark ? .white : .black)
  .frame(maxWidth: .infinity, alignment: .leading)
  .padding(.bottom, 25)
  .transition(.opacity)
```

### Thinking node branch

Shown when `streamingReplyText == nil`, `turnPhase != .idle`, and `nodeReady == true`:

```
ChatThinkingNode(
  label: activityLatestLine,
  steps: liveActivitySteps,
  shimmer: true,
  colorScheme: colorScheme)
  .frame(maxWidth: .infinity, alignment: .leading)
  .padding(.bottom, 25)
  .transition(.opacity)
```

`activityLatestLine` is the live streaming text during `.tooling` (trimmed, non-empty), else the last finalized step, else `"Thinking"`.

---

## 10. `StreamingReplyBubble`

A pacing buffer decouples what the user sees from bursty network arrivals.

| Property | Value |
|---|---|
| Tick interval | 14 ms |
| Catch-up divisor | 8 — `step = max(1, behind / 8)` |
| Font | `.system(size: 16)` |
| Text color | Passed in (`dark ? .white : .black`) |
| Text animation | `.easeOut(duration: 0.12)` on `revealedCount` |
| Alignment | `HStack(alignment: .bottom, spacing: 3)` |
| Inner text frame | `Text(revealed)` inside the HStack carries its OWN `.frame(maxWidth: .infinity, alignment: .leading)` so the text claims the full row width and the cursor trails at the end (`StreamingReplyBubble.swift:33–36`). This is in addition to the outer `.frame(maxWidth: .infinity, alignment: .leading)` the trailing-indicator applies to the whole bubble. |
| Cursor | `StreamingCursor` (hidden via `.opacity(caughtUp ? 0 : 1)`) |

### `StreamingCursor`

A blinking caret trailing the reveal:

| Property | Value |
|---|---|
| Shape | `RoundedRectangle(cornerRadius: 1.5)` |
| Color | `textColor.opacity(0.55)` |
| Size | 7×18 pt |
| Blink animation | `.easeInOut(duration: 0.6).repeatForever(autoreverses: true)` between opacity 1.0 and 0.15 |

The `.task(id: fullText)` restarts whenever `fullText` grows (each new token chunk), resuming the drip from the current `revealedCount` rather than from zero.

---

## 11. `ChatThinkingNode` ("Worked through N steps" / live footprint)

A single persistent element that mutates through a run's lifecycle. The same `ChatThinkingNode` represents all states so crossfades happen in-place rather than insertions/removals.

### Collapsed label

- **Shimmer phase** (`shimmer: true`): `ChatShimmerLabel(text: label)` — shimmering italic SF 16pt.
- **Resting phase** (`shimmer: false`): `Text(label).font(.system(size: 16).italic()).foregroundStyle(tint).lineLimit(1).truncationMode(.tail)`.

Tint: `(dark ? Color.white : .black).opacity(0.55)`.

Label transitions via `.animation(.easeInOut(duration: 0.25), value: label)` + `.contentTransition(.opacity)`.

### Chevron

`Image(systemName: "chevron.right")` at `.system(size: 10, weight: .semibold)`, foreground `tint`, visible only when `canOpen` (not shimmer, steps non-empty, `onOpenSteps` is set).

### Tap

Button action calls `onOpenSteps?()`, which opens the steps sheet. The node is `.disabled(!canOpen)` when not openable. The label is an `HStack(spacing: 6)` (collapsed label + optional chevron) carrying `.contentShape(Rectangle())`, and the whole button then gets `.frame(maxWidth: .infinity, alignment: .leading)` (`ChatRootSurface.swift:2137–2142`). Together these make the full-width empty area to the right of the text tappable, not just the glyphs.

### `ChatShimmerLabel` shimmer sweep

Driven by `TimelineView(.animation)` (immune to parent re-renders):

| Property | Value |
|---|---|
| Sweep period | 1.6 seconds |
| Band width | 55% of the label's rendered width |
| Band gradient | `.clear → Color.primary.opacity(0.9) → .clear` |
| Base opacity | `Color.primary.opacity(0.35)` |
| Sweep range | From `x: -band` to `x: phase * (width + band)` |
| Text font | `.system(size: 16).italic()` |
| Base text | `Text(text)` at base opacity, `.contentTransition(.opacity)`, overlaid by the sweep |
| Mask text | The sweep gradient is `.mask { Text(text).font(Self.font).contentTransition(.opacity) }` — a SECOND identical `Text` with its own `.contentTransition(.opacity)` serves as the mask shape. Both the base and mask `Text` carry the transition so the glyphs crossfade in lockstep when `text` mutates; omitting it on the mask would render the shimmer differently during a label change (`ChatRootSurface.swift:2682–2705`) |
| Text change animation | `.easeInOut(duration: 0.3)` on `text` |

---

## 12. "Worked through N steps" Steps Sheet

A custom bottom-sheet overlay (not a system `.sheet`) to achieve full edge-to-edge layout on iOS 26. It is always mounted as an `.overlay` on `ChatRootSurface`; `payload == nil` renders nothing. (`ChatRootSurface.swift:269–277`)

### Stable-parent structure and overlay guards

The body is a `GeometryReader { geo in ZStack(alignment: .bottom) { … } }` where the GeometryReader/ZStack is the STABLE always-mounted parent; the scrim and card are conditionally inserted INSIDE it so each runs its own transition (`ChatRootSurface.swift:2191–2218`). Two modifiers on the GeometryReader are load-bearing for a rebuild:

- `.ignoresSafeArea()` on the `GeometryReader` — lets the scrim cover the full screen and the card sit bottom-flush under the home indicator. The inner `ZStack` is `.frame(maxWidth: .infinity, maxHeight: .infinity)`.
- `.allowsHitTesting(self.payload != nil)` — when closed, the empty overlay must NOT eat taps meant for the chat beneath it. Without this, the always-mounted overlay would swallow touches even while hidden.

### Open/close animation

```swift
private static let stepsSheetSlide: Animation = .spring(response: 0.5, dampingFraction: 0.95)
```

Driven by `withAnimation(stepsSheetSlide) { stepsSheet = ... }`. The card uses `.transition(.move(edge: .bottom))`; the scrim uses `.transition(.opacity)`. Because the overlay is always mounted, each transition runs independently.

### Card layout

| Property | Value |
|---|---|
| Card max height | `geo.size.height * 0.62 + safeAreaInsets.bottom` |
| Card background | Canvas color (`#171717` dark / `#F5F4FA` light) |
| Card shape | `.rect(topLeadingRadius: 47, topTrailingRadius: 47)` |
| Grabber | `Capsule`, `Color.primary.opacity(0.25)`, 40×5 pt, `.padding(.top, 8)` |
| Drag dismiss threshold | 120 pt downward translation |
| Snap-back animation | `.easeOut(duration: 0.2)` |
| Scrim | `Color.black.opacity(0.35)`, full coverage, tap to dismiss |

### Card header

`ZStack` layout: title centered, X button leading:

| Element | Value |
|---|---|
| Title font | `.system(size: 19, weight: .medium)` |
| Title color | `Color.primary` |
| Title text | `"Worked through N step[s]"` |
| Header padding | `.top 14`, `.bottom 16` |
| X button icon | Asset `ChatCloseGlyph`, `.template`, resizable, `.scaledToFit`, 22×22 pt, `Color.primary` |
| X button hit area | 40×40 pt |
| X button background | `ChatGlassBackground(shape: Circle(), fill: …)` with the fill computed inline per scheme — dark: `rgb(30, 30, 30).opacity(0.2)`, light: `rgb(245, 244, 250).opacity(0.2)` (`ChatRootSurface.swift:2274–2282`) |
| X button shadow | `.shadow(color: .black.opacity(0.15), radius: 25, x: 0, y: 0)` |
| X button padding | `.horizontal 24` (HStack containing the button + `Spacer`) |

### Step list

`VStack(alignment: .leading, spacing: 22)` inside a `ScrollView`:

| Element | Value |
|---|---|
| Bullet | 5×5 pt `Circle`, `(dark ? white : black).opacity(0.5)`, `.padding(.top, 8)` |
| Text font | `.system(size: 16)` |
| Text color | `Color.primary` |
| HStack spacing | 12 |
| Leading margin | 40 pt (per spec) |
| Trailing margin | 24 pt |
| Bottom inset | `safeAreaInsets.bottom + 24` |

---

## 13. `rebuildRows` — Row Projection

Rows are projected once per `viewModel.messages` change (not per render pass), keeping the expensive `AssistantTextParser` / `ChatTextBlock.parse` off the 60fps render path. (`ChatRootSurface.swift:34–36`, `607`)

### Tool-use collapse logic

As messages are processed in order:
1. If an assistant message has `stopReason` containing "tool" OR has content blocks with type containing "toolCall" → it is a tool-use preamble; its visible text is appended to `pendingProgress` instead of becoming a row.
2. Any real row (user message, non-tool assistant reply, canvas embed) flushes the accumulated `pendingProgress` as a single `ChatDisplayRow(progressLines: [...])` placed immediately before that row.

### Phase-gated footprint routing

Footprints live in the `ChatThinkingNode` during `.thinking`/`.tooling` phases, and are flushed to the in-transcript "steps" row during `.answering`/`.idle`. This prevents the node↔row oscillation the `pendingRuns` flicker used to cause. (`ChatRootSurface.swift:729–735`)

### Identical-projection skip (Fix A)

If `nextRows == self.rows` (equality via `ChatDisplayRow.==`), `self.rows` is NOT reassigned. A safety-net history refetch that changed nothing visible would otherwise re-diff the entire `LazyVStack`, causing the idle-time blank-until-touch regression. (`ChatRootSurface.swift:765–769`)

### Canvas embed ordering

`[embed]` shortcodes are parsed from assistant text and rendered as `CanvasEmbedCard` rows placed ABOVE the reply text so the cards read as part of the reply. `CanvasEmbedIndex.shared.update(fromTranscriptOrder:)` is called at every rebuild. (`ChatRootSurface.swift:705–709`)

### Attachment cache strategy

The gateway drops image bytes from the canonical user row after the optimistic echo is replaced. To preserve attachments across the provisional→canonical swap:

1. Images are cached in `imageCache[idempotencyKey]` (in-memory) and written to `Caches/ChatAttachmentImages/` as JPEG at quality 0.9 (once per session via `diskCachedKeys`).
2. Audio/file chips are cached only when they carry a non-nil payload (byte-aware caching prevents clobbering a good payload with a byte-less canonical row). Stored in `Caches/ChatAttachmentChips/` as a JSON manifest + `.bin` payload files.
3. On cold start (memory cache empty, bytes already absent from the canonical row), images and chips are rehydrated from disk on first encounter.

### `"See attached."` suppression

If the only visible text in a message is `"See attached."` and the message has images or chips, the text is set to `""` and not rendered. Audio chip messages always have their text set to `""` regardless of content. (`ChatRootSurface.swift:678–684`)

---

## 14. User Bubble (`ChatUserBubble`)

Trailing-aligned, capped at 296 pt wide (`maxBubbleWidth`), pushed trailing via `frame(maxWidth: .infinity, alignment: .trailing)`.

### Bubble fill

```swift
Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark ? .black : .white
})
```

### Text color

`colorScheme == .dark ? .white : .black`

### Bubble shape

```swift
UnevenRoundedRectangle(
    topLeadingRadius: 12,
    bottomLeadingRadius: 12,
    bottomTrailingRadius: 3,
    topTrailingRadius: 12,
    style: .continuous)
```

The `bottomTrailingRadius: 3` creates the "message tail" effect without a separate tail asset.

### Text bubble layout

`VStack(alignment: .leading, spacing: 4)`:
- `ChatFormattedText(text:, isUser: true, textColor:)` — formatted text.
- `metaRow` (time + tick) when `showsMeta` — aligned `.trailing` with `minWidth: textWidth` (measured via `GeometryReader`) so the meta row right-aligns across the bubble's content width without forcing the bubble to fill its max width.

Padding: `.horizontal 8`, `.vertical 7`.

### Meta row

`HStack(spacing: 2)`:
- Timestamp: `.system(size: 12)`, `textColor.opacity(0.6)`, format `"h:mma"` (e.g., `"9:41AM"`).
- Tick icon: Asset `ChatCheckCheckGlyph` (delivered) or `ChatCheckGlyph` (error), 18×18 pt, template, `textColor.opacity(0.6)`.

### Image bubble

`VStack(spacing: 8)` wrapping `ChatImageMosaic` (see section 18) topped by a `ZStack(alignment: .bottomTrailing)` for the overlay-meta-chip when no caption (`ChatRootSurface.swift:1953–1977`):
- Overlay chip (when `row.text.isEmpty`): `overlayMetaChip` (`RoundedRectangle(cornerRadius: 4)` fill `black.opacity(0.4)`, white time + tick icons, `.padding(.horizontal, 4)`, `.padding(.vertical, 2)`) with `.padding(4)` inside the ZStack.
- With caption (when `!row.text.isEmpty`): a `VStack(alignment: .trailing, spacing: 2)` containing the caption `Text(row.text)` at `.system(size: 16)`, `foreground` color, `.frame(maxWidth: .infinity, alignment: .leading)`, then the `metaRow`. The whole caption block gets `.padding(.horizontal, 8)` and `.padding(.bottom, 7)`.
- Image bubble width fixed at 250 pt; `.padding(3)` around the whole VStack; background is the bubble shape filled `bubbleFill`.

### Audio bubble (`AudioBubbleContent`)

Fixed width 242 pt, `HStack(spacing: 12)` inside `VStack(alignment: .trailing, spacing: 4)` (`ChatRootSurface.swift:2046–2085`):
- **Play/pause button.** When `playback.isPlaying`: `ChatPauseGlyph(color: foreground)` (see section 25). When idle: `Image(systemName: "play.fill")` at `.font(.system(size: 18))`, `.foregroundStyle(foreground)`. The button is `.disabled(self.data == nil)` so a byte-less (not-yet-rehydrated) chip is non-tappable; its `action` toggles playback only when `data != nil`.
- `ChatAmplitudeWaveform(levels:, color: foreground.opacity(0.4), activeColor: foreground, progress: playback.progress)` — 36 bars, `.frame(maxWidth: .infinity, alignment: .leading)`, `.clipped()`.
- Duration label: `.system(size: 12)`, `.monospacedDigit()`, `.lineLimit(1)`, `.fixedSize()`, `foreground` color. Shows `playback.currentTime` while playing (when `> 0`), else `durationSeconds`.
- `metaRow` below.

Padding: `.horizontal 12`, `.vertical 8`. Waveform levels load via `.task(id: self.data)` at `barCount: 36`, so they reload whenever the `data` reference changes (e.g., provisional→canonical row swap) (`ChatRootSurface.swift:2086–2089`).

### Attachment stacking (audio / file)

Audio and file attachments each render inside a `VStack(alignment: .trailing, spacing: 5)` with a fixed stacking order — the media first, then an optional caption bubble below it (`ChatRootSurface.swift:1873–1892`):

- **Audio stack (`audioStack`):** the audio bubble, then — only when `!row.text.isEmpty` — the `textBubble` below it (a typed caption becomes a separate bubble).
- **File stack (`fileStack`):** `ForEach(fileChips)` of file card bubbles, then — only when `!row.text.isEmpty` — the `textBubble` below them.

The 5 pt inter-element spacing and the media-above-caption order are load-bearing for the trailing-aligned layout.

### File card bubble (`fileCardBubble`)

Fixed 237×87 pt, `ZStack(alignment: .topLeading)` of the bubble-shaped fill behind an `HStack(spacing: 0)` (`ChatRootSurface.swift:1905–1928`):
- `ChatFileThumbnail` 75×75 pt on leading, `.padding(.leading, 7)`, `.padding(.vertical, 6)`. `fileName` = `chip.fileName ?? chip.title`; `fallbackLabel` = `chip.fileExtension?.uppercased() ?? "FILE"`.
- File title: `Text(chip.title)`, `.system(size: 16)`, `foreground` color, `lineLimit(2)`, `.multilineTextAlignment(.center)`, `.frame(maxWidth: .infinity)`, `.padding(.horizontal, 8)`.
- `metaRow` overlaid at `.bottomTrailing`, `.padding(.trailing, 10)`, `.padding(.bottom, 2)`.

#### `ChatFileThumbnail` internals

`ZStack` at a fixed 75×75 pt frame (`ChatAudioComponents.swift:124–174`):

| Element | Value |
|---|---|
| Background | `RoundedRectangle(cornerRadius: 5, style: .continuous)` filled `Color.white.opacity(0.15)` |
| Thumbnail (when generated) | `Image(uiImage:)`, resizable, `.scaledToFill`, 75×75 pt, clipped to `RoundedRectangle(cornerRadius: 5)` |
| Fallback label (no thumbnail) | `Text(fallbackLabel)` at `.font(.system(size: 13, weight: .semibold))`, `.foregroundStyle(.white.opacity(0.7))` |
| Thumbnail generation | `QLThumbnailGenerator.shared.generateBestRepresentation` for a `Request(fileAt:size: CGSize(75, 75), scale: 3, representationTypes: .thumbnail)` |
| Load trigger | `.task(id: self.fileName)` — runs once when `thumbnail == nil` and `payload != nil`; payload is written to a temp file (removed via `defer`) for QuickLook |

---

## 15. Assistant Message (`ChatAssistantMessage`)

**No bubble.** Full transcript width. `VStack(alignment: .leading, spacing: 10)` with `.frame(maxWidth: .infinity, alignment: .leading)`, children in this order (`ChatRootSurface.swift:2315–2336`):

| Order | Element | Condition |
|---|---|---|
| 1 | `ChatImageMosaic(images: row.images)` — placed ABOVE the text so assistant-delivered images read as part of the reply (same tap→viewer→zoom→save path as user images) | `!row.images.isEmpty` |
| 2 | `ChatFormattedText(text:, isUser: false, textColor:, reveal:)` | `!row.text.isEmpty` |
| 3 | Timestamp | `!row.isStreaming && row.timestamp != nil` — `.system(size: 12)`, `(dark ? white : black).opacity(0.6)` |

The `reveal` parameter is `true` only for the row whose id equals `revealReplyID` (the just-finalized live answer). This triggers the top-to-bottom wipe.

---

## 16. Top-to-Bottom Reveal Wipe (`ChatFormattedText`, `ChatRevealWipe`)

Applies only to `revealReplyID` rows (one per turn). Only armed when `awaitingReplyReveal` was set, which only happens during a live run — never on history load or session switch.

### Reveal timing

```swift
private static let perLine: Double = 0.085   // seconds per rendered line
private static let minDuration: Double = 0.55
private static let maxDuration: Double = 2.2
let revealDuration = min(maxDuration, max(minDuration, Double(lineCount) * perLine))
```

Line count is computed from parsed blocks: prose (non-empty lines), list items, code/heading blocks each count as 1.

### Wipe mechanics

```swift
content
  .mask(alignment: .top) {
    ChatRevealWipe(fraction: revealFraction, overshoot: feather * 2)
      .fill(Color.black)
      .blur(radius: feather)  // 16 pt
  }
  .onAppear {
    withAnimation(.linear(duration: revealDuration)) {
      revealFraction = 1
    }
  }
```

`ChatRevealWipe` is an animatable `Shape` (not a gradient—a `Double` feeding gradient stops does not tween; `animatableData` get/set proxies `fraction`). In `path(in:)` the fraction is first clamped to `0–1` via `let clamped = CGFloat(max(0, min(1, self.fraction)))` before any geometry is computed (`ChatRootSurface.swift:2916–2920`). The path is a rectangle from `y: -overshoot` to `y: -overshoot + clamped * (height + 2 * overshoot)`, overshooting by `feather * 2 = 32 pt` top and bottom so the blurred edge falls outside the text. Width overshoots by 20 pt on each side (`x: -20`, `width: rect.width + 40`) to prevent side clipping; height is `max(0, bottom - top)`. Animation: `.linear(duration: revealDuration)`.

A streaming reply that was visible before finalization sets `awaitingReplyReveal = false` so its finalized row does NOT play the wipe — the text was already fully revealed progressively. Only tool-run answers (footprint-only during the run) still wipe. (`ChatRootSurface.swift:468–473`)

---

## 17. `ChatFormattedText` — Markdown Block Rendering

Parses text once at `init` via `ChatTextBlock.parse()`. This is a line-oriented block parser (not a full CommonMark parser).

### Block types

| Block | Triggered by |
|---|---|
| `.prose(String)` | Default fallback; paragraphs split on blank lines |
| `.code(language, code)` | ```` ``` ```` fences |
| `.heading(level, text)` | Lines starting with `#` through `######` |
| `.list([Item])` | Lines starting with `-`/`*`/`+` (bullet) or `N.`/`N)` (ordered) |

Tables (rows containing `|` followed by a separator row) are passed through as `.prose` and rendered by the kit's inline renderer.

### VStack spacing

`VStack(alignment: .leading, spacing: 20)` between blocks. Within prose: `VStack(alignment: .leading, spacing: 20)` between paragraphs. Within lists: `VStack(alignment: .leading, spacing: 15)` between items.

### Prose line spacing

`proseLineSpacing = 8 pt`, passed as `lineSpacing` to `OpenClawChatMarkdownText`.

### Heading fonts

| Level | Font |
|---|---|
| H1 | `.system(size: 20, weight: .bold)` |
| H2 | `.system(size: 18, weight: .semibold)` |
| H3+ | `.system(size: 16, weight: .semibold)` |

### List items

`HStack(alignment: .top, spacing: 8)`:
- Marker: `.system(size: 16)`, opacity `item.ordered ? 1 : 0.7` (bullet markers are slightly dimmer).
- `minWidth` for marker: 20 pt (ordered) or 14 pt (unordered).
- Content: `OpenClawChatMarkdownText` at `.system(size: 16)`.
- Nesting indent: `CGFloat(item.depth) * 16 pt` leading padding.

### `CodeBlockView`

`VStack(alignment: .leading, spacing: 0)`:

| Property | Value |
|---|---|
| Background | `.black` (dark) / `.white` (light), `RoundedRectangle(cornerRadius: 14)` |
| Border | `Color.primary.opacity(0.08)`, lineWidth 0.5 |
| Code font | `.system(size: 13, design: .monospaced)` |
| Code padding | `.horizontal 14`, `.bottom 14` |
| Horizontal scroll | `ScrollView(.horizontal, showsIndicators: false)` |
| Text selection | `.enabled` |
| Language label | `.system(size: 12, weight: .medium)`, `Color.primary.opacity(0.5)` |
| Copy button | Asset `FeedbackCopyGlyph` 14×14 pt; transitions to `checkmark` SF symbol on copy |
| Copy label | "Copy" / "Copied", `.system(size: 12, weight: .medium)`, `Color.primary.opacity(0.6)` |
| Header padding | `.horizontal 14`, `.vertical 10` |
| Copy feedback | `.easeOut(duration: 0.15)` appear/disappear; auto-resets after 1.5 s |
| Copy haptic | `OpenClawHaptics.tap()` |

---

## 18. Image Mosaic (`ChatImageMosaic`)

Shared between user and assistant messages. Tile shape: `RoundedRectangle(cornerRadius: 9)`.

| Count | Layout |
|---|---|
| 1 | Single tile 244×244 pt |
| 2 | `HStack(spacing: 2)`: 129×244 + 113×244 |
| 3+ | `HStack(spacing: 2)`: 129×244 left + `VStack(spacing: 2)` right with 113×121 top + 113×121 bottom; if >3, the bottom-right tile overlays a `rgb(10, 10, 10).opacity(0.5)` scrim (near-black `#0A0A0A`, NOT pure `black`) and a `"+ N"` counter (`.system(size: 24)`, tracking `-2.4`, white). The scrim is `tile.fill(...)` at 113×121 pt with `.allowsHitTesting(false)` (`ChatImageViewer.swift:37`) |

Tapping any tile presents `ChatImageViewer` as a `fullScreenCover`.

---

## 19. Image Viewer (`ChatImageViewer`)

Full-screen, black background, `TabView` with `.page` style (index dots hidden):

| Property | Value |
|---|---|
| Background fade on drag | `1 - min(dragOffset.height / 400, 0.6)` |
| Scale on drag | `max(1 - dragOffset.height / 2000, 0.85)` |
| Dismiss gesture | Downward drag > 120 pt height; see dismiss-gesture guards below |
| Snap-back animation | `.spring(duration: 0.3)` |
| Double-tap zoom | Toggles between 1× and 2.5×, spring `.spring(duration: 0.3)` |
| Pinch zoom range | 1×–4× |
| Pinch snap-back | When `scale < 1.05`, animate to 1× with `.spring(duration: 0.25)` |
| Minimum drag distance | 15 pt |
| Gestures hidden during zoom | Dismiss drag disabled when `anyZoomed` |
| Status bar | Hidden |

### Dismiss-gesture guards

The dismiss `DragGesture(minimumDistance: 15)` is attached via `.simultaneousGesture`. Both the tracking (`.onChanged`) and the activation (`.onEnded`) have distinct guards (`ChatImageViewer.swift:129–147`):

- **`.onChanged`** only updates `dismissDrag` when ALL of: `!anyZoomed`, `value.translation.height > 0` (downward only), AND `abs(height) > abs(width)` (more vertical than horizontal). A sideways-then-down drag never starts tracking the dismiss, so paging between images is not hijacked.
- **`.onEnded`** closes only when `!anyZoomed` AND `value.translation.height > 120`; otherwise `dismissDrag` springs back to `.zero` via `.spring(duration: 0.3)`.

### Zoom pan (`ZoomablePagedImage`)

Each paged image owns pinch, double-tap, and a pan gesture (`ChatImageViewer.swift:199–247`):

- Pan is attached via `.highPriorityGesture(self.scale > 1 ? self.pan : nil)` — it is **only active while zoomed in** (`scale > 1`); at 1× the gesture is `nil` so the paging/dismiss gestures own the drag.
- Pan offsets **accumulate across gestures**: `.onChanged` sets `offset = lastOffset + value.translation`, and `.onEnded` commits `lastOffset = offset`, so a second drag continues from where the first ended rather than snapping back to origin.
- `resetZoom()` (double-tap to 1×, pinch-snap below 1.05×, or `.onDisappear`) zeroes `scale`, `lastScale`, `offset`, `lastOffset`, and `anyZoomed`.

### Overlay buttons

`HStack`, `.padding(.horizontal, 20)`, `.padding(.top, 8)`. Hidden when drag is non-zero (`.opacity(dismissDrag == .zero ? 1 : 0)`). Both buttons share the `glassButton` builder: icon frame 24×24 pt, outer hit frame 40×40 pt, `.foregroundStyle(.white)`, background `ChatGlassBackground(fill: rgb(30,30,30).opacity(0.2))` (default `Capsule` shape, no hairline) (`ChatImageViewer.swift:149–174`).

- **Close:** Asset `ChatCloseGlyph`, `.renderingMode(.template)`, resizable `.scaledToFit`.
- **Save:** default state asset `ChatDownloadGlyph` (`.template`, resizable, `.scaledToFit`). **Saved state** renders `Image(systemName: "checkmark")` at `.font(.system(size: 18, weight: .semibold))` — an SF symbol, NOT a 24×24 asset (it inherits the shared 24×24 outer group frame but has no explicit image frame of its own). Tapping writes the current image to the photo album, fires `OpenClawHaptics.success()`, and sets `saved = true` with `.smooth(duration: 0.2)`. A `Task.sleep(.seconds(1.5))` then reverts `saved = false`, again with `.smooth(duration: 0.2)` — there is no `.easeOut` pairing. The close button's glass fill never changes; the 24×24 asset sizing applies to the default-state icons only.

---

## 20. Composer

Inserted via `.safeAreaInset(edge: .bottom)`. Outer wrapper: `.padding(.horizontal, 14)`, `.padding(.vertical, 10)`.

### Layout

`HStack(alignment: .bottom, spacing: 10)`:
1. **Leading button** (36×36 pt) — Plus/Close/X.
2. **Composer field content** (expanding, see below).
3. **Trailing button** (36×36 pt `Circle`) — Talk/Send/Stop.

### Leading button (`plusButton`)

| State | Icon | Fill |
|---|---|---|
| Default (tray closed) | `ChatPlusGlyph` | `composerGlassFill` |
| Recording or voice note staged | `ChatCloseGlyph` | `composerGlassFill` |
| Tray open | `ChatPlusGlyph` (fades to 0 opacity) | `rgb(64,64,64).opacity(0.2)` |

The button fades out when the tray opens (`.easeOut(duration: 0.1)`) and fades back in on close (`.easeOut(duration: 0.15)`). It rises `–12 pt` (same as the tray lift) via `.offset(y: attachmentGroupLift)`.

**Close-bounce keyframe animation** triggered on `showsAttachmentTray`:
- Open: no dip (lift-only).
- Close: `SpringKeyframe(12, duration: 0.16, spring: .snappy)` then `SpringKeyframe(0, duration: 0.34, spring: .bouncy)`.

Tapping:
- Recording → cancel recording.
- Voice note staged → remove it (with `.spring(duration: 0.25)`).
- Tray open → close tray.
- Default → open tray.

### Composer field variants

| Condition | View |
|---|---|
| Recording | `recordingField` on `fieldPillBackground` |
| Voice note staged | `StagedVoiceNoteField` on `ChatGlassBackground(shape: RoundedRectangle(cornerRadius: 15), fill: composerGlassFill, hairline: true)` |
| No attachments | `inputField` with `.frame(minHeight: 36)` on `fieldPillBackground` |
| Attachments present | `VStack(alignment: .leading, spacing: 8)` with `pendingAttachmentStrip` above `inputField`, then `.padding(5)`, backed by `ChatGlassPanel(fill: composerGlassFill, cornerRadius: 15)` (`ChatRootSurface.swift:1140–1146`) |

The `.padding(5)` sits between the inner `VStack` and the `ChatGlassPanel` background, insetting the strip + field from the panel edge.

The field content is wrapped in a `GeometryReader` background measuring `proxy.size.height` → `inputHeight`. Animated with `.spring(duration: 0.3)` on `viewModel.attachments.isEmpty`.

### Field pill corner radius

```swift
composerFieldCornerRadius: CGFloat {
    inputHeight > 44 ? 15 : 48
}
```

Pill (48 pt) in single-line; 15 pt when the field wraps past one line.

### `inputField` layout

`HStack(alignment: .bottom, spacing: 8)`:
- `TextField("Chat with Molty" / "Connecting…", text: $viewModel.input, axis: .vertical)`, `.system(size: 16)`, `.lineLimit(1...8)`.
- Mic button `ChatMicGlyph` 20×20 pt, `Color.primary.opacity(0.9)` — only shown when attachments are empty.

Padding: `.horizontal 14`, `.vertical 7`.

### `recordingField` layout

`HStack(spacing: 10)`:
- Red dot: 8×8 pt `Circle`, `bubbleRed`.
- `ChatAmplitudeWaveform(levels: voiceRecorder.liveLevels, color: Color.primary.opacity(0.4))` — no `activeColor`/`progress` (recording, not playback), `maxWidth: .infinity`.
- Elapsed time: `.system(size: 16).monospacedDigit()`, `Color.primary`, `lineLimit(1)`, `fixedSize()`.

Padding: `.horizontal 14`, `.vertical 7`, `minHeight: 36`.

### Trailing button

`ZStack` containing a `Circle` fill and icon, 36×36 pt.

| Condition | Fill | Icon |
|---|---|---|
| Recording (never disabled) | `bubbleRed` (full opacity) | `stop.fill` SF symbol, `.system(size: 15, weight: .semibold)`, white |
| Has draft | `bubbleRed` (full or `.opacity(0.5)` when `sendDisabled`) | `arrow.up` SF symbol, `.system(size: 16, weight: .semibold)`, white |
| Empty / connecting | `bubbleRed` | `ChatWaveformGlyph` (4-bar static waveform) |

Shadow: `.shadow(color: .black.opacity(0.2), radius: 25, x: 0, y: 0)`.

`sendDisabled` = `hasDraft && !canSendLive` (hasDraft is true if input is non-empty OR attachments exist; canSendLive = `viewModel.healthOK`).

### `ChatWaveformGlyph`

`HStack(spacing: 2.25)` of 4 capsules (heights: 10.1, 13.5, 18, 9 pt), width 1.9 pt each, fill `rgb(217, 217, 217)`.

---

## 21. Attachment Tray

Positioned via `.overlay(alignment: .bottomLeading)` on the composer wrapper, offset `.leading 14`, `.bottom 10`, and lifted `attachmentGroupLift = –12 pt`. Transition: `.scale(scale: 0.1, anchor: .bottomLeading).combined(with: .opacity)`.

Open animation: `.spring(duration: 0.35)`. Close animation: `.spring(duration: 0.3)`.

### Tray content

`VStack(alignment: .leading, spacing: 23)`, padding 17 pt all sides, width 200 pt, background `ChatGlassPanel(cornerRadius: 20)`:

| Row | Asset | Icon size | Action |
|---|---|---|---|
| GIFs | `ChatStickerGlyph` | 22 pt | Open GIF photo picker |
| Images | `ChatImagePlusGlyph` | 22 pt | Open image photo picker |
| Camera | `ChatCameraGlyph` | 22 pt | Present camera full-screen |
| Files | `ChatFilesGlyph` | 24 pt | Open file importer |

Each row: `HStack(spacing: 12)`, icon at `.opacity(0.9)`, label `.system(size: 17)`, `Color.primary`. Tapping fires `OpenClawHaptics.tap()`, closes the tray, then performs the action.

Panel fill:
- Dark: `rgb(64, 64, 64).opacity(0.2)`.
- Light: `white.opacity(0.4)`.

Tray-backdrop (full-screen tap catcher): `Color.black.opacity(0.001)`, closes the tray on any outside tap.

---

## 22. Pending Attachment Strip

`ScrollView(.horizontal, showsIndicators: false)` > `HStack(spacing: 5)`, rendered above the `inputField` inside the glass panel when `!viewModel.attachments.isEmpty`.

### Image tile

100×100 pt, `RoundedRectangle(cornerRadius: 10)`, `scaledToFill`. Dismiss button at `.topTrailing` (`ChatRootSurface.swift:1463–1484`): `ChatCloseGlyph` (`.template`, resizable, `.scaledToFit`) at 12×12 pt, `.foregroundStyle(.black)`, with `.padding(2)` around the icon, on a white `Circle` background. The button label then gets `.frame(width: 34, height: 34, alignment: .topTrailing)` + `.contentShape(Rectangle())` (so the 34×34 hit area extends inward over the image and isn't lost to the horizontal scroll gesture), and the whole `Button` gets an outer `.padding(4)`. The inner `.padding(2)` (icon→circle gap) and outer `.padding(4)` (button→neighbors gap) are distinct. Removal animated with `.spring(duration: 0.25)` plus `OpenClawHaptics.tap()`.

### File card tile (no preview)

100×100 pt, `ZStack(alignment: .topLeading)` with a `RoundedRectangle(cornerRadius: 10)` filled `bubbleRed` (`rgb(195, 63, 51)`) behind two labels (`ChatRootSurface.swift:1488–1509`):
- Extension label (top): `fileExtensionLabel` (the filename's `pathExtension` uppercased, or `"FILE"` when empty), `.system(size: 16)`, `white.opacity(0.6)`, `.padding(.leading, 6)`, `.padding(.top, 10)`.
- File name (bottom): the filename with its extension stripped via `(fileName as NSString).deletingPathExtension` (or `"file"` when the name is empty), `.system(size: 16)`, white, `lineLimit(1)`. Pinned to the bottom via `.frame(maxWidth: .infinity)` then `.frame(maxHeight: .infinity, alignment: .bottom)`, with `.padding(.horizontal, 8)` and `.padding(.bottom, 11)`.

---

## 23. Voice Note Recording Flow

1. Tap mic button → `OpenClawHaptics.tap()`, `voiceRecorder.start()`.
2. Leading button becomes `ChatCloseGlyph`; field switches to `recordingField` (waveform + elapsed).
3. Tap trailing stop button → `OpenClawHaptics.tap()`, `voiceRecorder.finish()` → stages attachment, on-device transcription begins in background via `VoiceNoteTranscriber`.
4. Field switches to `StagedVoiceNoteField` (playback UI, 44 bars).
5. Tap leading X → remove voice note (animated `.spring(duration: 0.25)`).
6. On send: if input is empty, uses on-device transcript (cached or freshly transcribed) as the hidden message body.

Cancel recording: tap leading X → `OpenClawHaptics.tap()`, `voiceRecorder.cancel()`.

Duration label format: `"%d:%02d"` (e.g., `"0:42"`).

### `StagedVoiceNoteField`

`HStack(spacing: 12)` (`ChatAudioComponents.swift:84–122`):
- Play/pause button. When `playback.isPlaying`: `ChatPauseGlyph(color: Color.primary)`. When idle: `Image(systemName: "play.fill")` at `.font(.system(size: 16))` — note this is **16 pt**, 2 pt smaller than `AudioBubbleContent`'s 18 pt play icon (section 14). Foreground `Color.primary`.
- `ChatAmplitudeWaveform` 44 bars, `Color.primary.opacity(0.4)` inactive, `Color.primary` active, `progress: playback.progress`, `.frame(maxWidth: .infinity, alignment: .leading)`, `.clipped()`.
- Duration label: `.system(size: 12)`, `.monospacedDigit()`, `.lineLimit(1)`, `.fixedSize()`, `Color.primary`. Shows `playback.currentTime` while playing (when `> 0`), else `durationSeconds`.

Padding: `.horizontal 14`, `minHeight: 36`. Levels load via `.task(id: self.data)` at `barCount: 44`.

---

## 24. Audio Bubble Waveform (`ChatAmplitudeWaveform`)

`HStack(alignment: .center, spacing: 2.25)` of capsules:

| Property | Value |
|---|---|
| Bar width | 1.9 pt |
| Min bar height | 3 pt |
| Max bar height | 18 pt |
| Height formula | `minBarHeight + (maxBarHeight - minBarHeight) * CGFloat(level)` |
| Active vs inactive | Active color when `index / count < progress`; otherwise base color |
| Bar animation | `.linear(duration: 0.08)` on `levels` change |

`ChatAudioEnvelope.levels(from:barCount:)` computes RMS per window, normalizes to peak, 36 bars for audio bubbles, 44 for staged preview.

---

## 25. Audio Playback (`ChatAudioPlayback`)

`@MainActor @Observable`. `AVAudioPlayer` driven, polling at 100 ms intervals via an async task loop.

- `toggle(data:)` — if playing, pause; if idle, create player, set session to `.playback`, call `play()`.
- `AVAudioSession` category: `.playback`, mode: `.default`.
- Rewinding: if `currentTime >= duration`, resets to 0 before playing.
- Natural end: polling loop detects `!player.isPlaying && isPlaying` → resets `isPlaying = false`, `currentTime = 0`.

`ChatPauseGlyph`: `HStack(spacing: 2.75)` of 2 `RoundedRectangle(cornerRadius: 0.9)` bars, 5.5×16.5 pt each.

---

## 26. Glass Surface Tokens

### `ChatGlassBackground`

Generic insettable-shape background parameterized by `shape`, `fill: Color`, and `hairline: Bool`. The branch order differs by OS and is load-bearing (`ChatRootSurface.swift:2803–2833`):

- **iOS 26+:** `self.shape.fill(self.fill)` FIRST, then `.glassEffect(.regular, in: self.shape)` applied as a modifier on top. Because `.glassEffect` is a modifier over the already-filled shape, the Liquid Glass renders OVER the tint fill (the fill shows through/under the glass). (Audit framing "glass then fill on top / fill over glass" is backwards — see correction note.)
- **Pre-iOS 26:** `self.shape.fill(.regularMaterial)` with `.overlay { self.shape.fill(self.fill) }` — material first, color fill layered on top as an overlay.

After the OS branch, if `hairline == true`, a `self.shape.strokeBorder(Color.white.opacity(0.2), lineWidth: 0.3)` is overlaid.

| Property | Value |
|---|---|
| Default shape | `Capsule(style: .continuous)` |
| Hairline border | `Color.white.opacity(0.2)`, lineWidth 0.3 (optional; default `hairline: false`) |

### `ChatGlassPanel`

A rounded-rectangle sibling of `ChatGlassBackground` used for the composer attachment panel (section 20) and the attachment tray (section 21). Parameters: `fill: Color`, `cornerRadius: CGFloat` (no shape or hairline parameter). Same OS-branched layering as `ChatGlassBackground` (`ChatRootSurface.swift:2880–2898`):

- **iOS 26+:** `RoundedRectangle(cornerRadius:, style: .continuous).fill(self.fill)` then `.glassEffect(.regular, in: .rect(cornerRadius: self.cornerRadius))` on top (glass over fill).
- **Pre-iOS 26:** `RoundedRectangle(...).fill(.regularMaterial)` with `.overlay { RoundedRectangle(...).fill(self.fill) }`.

There is no hairline on `ChatGlassPanel`.

### Key colors

| Token | Dark | Light |
|---|---|---|
| `canvas` | `rgb(23, 23, 23)` | `rgb(245, 244, 250)` |
| `glassFill` (top bar) | `rgb(30, 30, 30).opacity(0.2)` | `rgb(245, 244, 250).opacity(0.2)` |
| `composerGlassFill` | `rgb(64, 64, 64).opacity(0.2)` | `rgb(245, 244, 250).opacity(0.2)` |
| `bubbleRed` | `rgb(195, 63, 51)` | same |
| `onlineGreen` | `rgb(52, 199, 89)` | same |
| `onlineRing` | `rgb(23, 23, 23)` | `rgb(245, 244, 250)` |

---

## 27. Haptics

| Event | Call |
|---|---|
| Reply intro (first assistant row after send) | `OpenClawHaptics.tap()` |
| Record start | `OpenClawHaptics.tap()` |
| Record finish | `OpenClawHaptics.tap()` |
| Record cancel | `OpenClawHaptics.tap()` |
| Tray row tap | `OpenClawHaptics.tap()` |
| Attachment remove | `OpenClawHaptics.tap()` |
| Code copy | `OpenClawHaptics.tap()` |
| Image save | `OpenClawHaptics.success()` |

Only one reply haptic fires per turn (the intro). There is no closing haptic — one-word replies land start+end together and would double-buzz. (`ChatRootSurface.swift:505–512`)

---

## 28. Photo / File Ingestion

| Source | Max items | Staging method | Note |
|---|---|---|---|
| Photo library | 10 | `addImageAttachment(data:fileName:mimeType:)` as JPEG | `photoSelection` cleared immediately so re-picking the same photo works |
| Camera | 1 | `addImageAttachment` as JPEG at quality 0.9 | `fullScreenCover` over the chat |
| GIF library | 5 | `addFileAttachment(data:fileName:mimeType:)` verbatim | Preserves original MIME type so animated GIFs keep their frames |
| File importer | Unlimited | `addFileAttachment` verbatim | Security-scoped resource accessed per URL |

---

## 29. Key State Properties Summary

| Property | Type | Purpose |
|---|---|---|
| `rows` | `[ChatDisplayRow]` | Pre-projected display rows, rebuilt once per `messages` change |
| `turnPhase` | `TurnPhase` | Forward-only phase machine driving node/bubble/footprint |
| `turnJustCompleted` | `Bool` | Prevents phantom `.thinking` restart after reply lands |
| `pinTurnID` | `String?` | Row id of the pinned user question; nil = no pin |
| `pinScrollPending` | `Bool` | One-shot: triggers spring-to-top on the first rows.count change after send |
| `pinnedQuestionTop` | `CGFloat?` | Content-space top of the pinned row; retained against nil |
| `contentTailBottom` | `CGFloat` | Content-space bottom of the last real row |
| `viewportHeight` | `CGFloat` | Scroll container height for spacer math |
| `revealReplyID` | `String?` | Id of the answer that should play the wipe reveal |
| `awaitingReplyReveal` | `Bool` | Armed on run start; disarmed when a live streaming text is shown |
| `nodeReady` | `Bool` | Delayed node visibility — prevents node riding the bubble's spring |
| `replyIntroArmed` | `Bool` | One-shot intro haptic; fires once per turn |
| `liveActivitySteps` | `[String]` | Live preamble lines shown in the footprint node |
| `stepsSheet` | `ChatStepsPayload?` | Non-nil opens the steps overlay |
| `showsAttachmentTray` | `Bool` | Attachment tray open/closed |
| `inputHeight` | `CGFloat` | Measured field height driving corner-radius transitions |
| `imageCache` | `[String: [UIImage]]` | In-memory attachment image cache keyed by idempotency key |
| `chipCache` | `[String: [ChatAttachmentChip]]` | In-memory audio/file chip cache |
