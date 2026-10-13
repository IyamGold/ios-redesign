# Audit — 03-chat-surface.md

## Scorecard

| metric | value |
|---|---|
| precision | 0.988 |
| recall | 0.789 |
| F | 0.878 |
| critical | 0 |
| major | 7 |
| minor | 22 |
| certified | false |
| claims | 100 |

## Defects (fix these)

minor — spec says the mosaic overlay scrim is `black.opacity(0.5)`; code uses `Color(red: 10/255, green: 10/255, blue: 10/255).opacity(0.5)` (near-black, not pure black) — `Sources/Design/ChatImageViewer.swift:37`

minor — spec implies the save button's "saved" state icon is a 24×24 asset and that it reverts after 1.5 s with an `.easeOut` pairing; code uses `Image(systemName: "checkmark")` at `.font(.system(size: 18, weight: .semibold))` (no explicit frame), `.smooth(duration: 0.2)` only, and a `Task.sleep(.seconds(1.5))`; the close button fill is always `Color(red: 30/255, green: 30/255, blue: 30/255).opacity(0.2)` via `ChatGlassBackground` without a hairline; the spec's 24×24 icon claim is wrong for the "saved" state — `Sources/Design/ChatImageViewer.swift:149-174`

major — spec omits that the pan gesture only activates when `scale > 1` via `highPriorityGesture(self.scale > 1 ? self.pan : nil)`, and that pan offsets accumulate across gestures (`lastOffset` stored on `.onEnded`); neither behavior is documented — `Sources/Design/ChatImageViewer.swift:207-246`

minor — spec says dismiss activates when drag height > 120 pt and height > width, but omits the guard that requires `value.translation.height > 0` AND the drag be more vertical than horizontal on `.onChanged`; a sideways-then-down drag will not activate dismiss — `Sources/Design/ChatImageViewer.swift:129-147`

minor — spec omits that the play button inside `StagedVoiceNoteField` uses `.font(.system(size: 16))` whereas `AudioBubbleContent` uses `.font(.system(size: 18))`; the 2 pt icon-size difference between staged field and audio bubble is undocumented — `Sources/Design/ChatAudioComponents.swift:96-100`

major — spec documents `ChatFileThumbnail` as 75×75 pt but omits its internal structure: a `RoundedRectangle(cornerRadius: 5)` background at `Color.white.opacity(0.15)`, a fallback label at `.font(.system(size: 13, weight: .semibold))` with `.foregroundStyle(.white.opacity(0.7))`, and thumbnail generation via `QLThumbnailGenerator` at 75×75 pt at scale 3 — `Sources/Design/ChatAudioComponents.swift:124-174`

major — spec says "Play/pause button (see section 15/25)" but does not document that the play state renders `Image(systemName: "play.fill")` at `.font(.system(size: 18))`, nor that the button is disabled when `self.data == nil` — `Sources/Design/ChatRootSurface.swift:2057-2062`

minor — spec documents 36 bars for audio bubbles but omits that waveform levels are loaded via `.task(id: self.data)`, meaning levels reload whenever the data reference changes — `Sources/Design/ChatRootSurface.swift:2086-2089`

minor — spec omits the `.padding(5)` wrapping the `VStack` inside `composerFieldContent` when non-empty attachments are present, before the `ChatGlassPanel` — `Sources/Design/ChatRootSurface.swift:1140-1146`

minor — spec says the pending attachment dismiss button uses `.padding(4)` but does not distinguish the inner `.padding(2)` around the X icon from the outer `.padding(4)` on the button frame — `Sources/Design/ChatRootSurface.swift:1473-1484`

minor — spec documents filename padding (`.horizontal 8`, `.bottom 11`) correctly but omits the `frame(maxWidth: .infinity)` + `frame(maxHeight: .infinity, alignment: .bottom)` layout trick used to pin the filename, and that `deletingPathExtension` is applied to the filename before display — `Sources/Design/ChatRootSurface.swift:1488-1508`

major — spec section 14 omits that the audio stack in `ChatUserBubble` is `VStack(alignment: .trailing, spacing: 5)` (audio bubble then optional text bubble) and the file stack is likewise `VStack(alignment: .trailing, spacing: 5)` (file cards then optional text bubble); the 5 pt spacing and stacking order are undocumented — `Sources/Design/ChatRootSurface.swift:1873-1892`

minor — spec says "With caption: caption text `.system(size: 16)`, trailing meta row below it" but omits that the caption block is `VStack(alignment: .trailing, spacing: 2)` with `.padding(.horizontal, 8)` and `.padding(.bottom, 7)` — `Sources/Design/ChatRootSurface.swift:1963-1972`

minor — spec omits that assistant messages render `ChatImageMosaic` (when `!row.images.isEmpty`) placed above the text in the `VStack(alignment: .leading, spacing: 10)` — `Sources/Design/ChatRootSurface.swift:2315-2336`

major — spec omits the `.ignoresSafeArea()` modifier on the `GeometryReader` overlay in `ChatStepsOverlay` and the `.allowsHitTesting(self.payload != nil)` guard; without these a rebuilder will produce incorrect hit-testing and layout — `Sources/Design/ChatRootSurface.swift:2191-2218`

minor — spec says the steps sheet X button fill uses a shared `glassFill` variable; code computes the values inline (dark: `rgb(30,30,30).opacity(0.2)`, light: `rgb(245,244,250).opacity(0.2)`); the spec does not document the actual channel values needed for a rebuild — `Sources/Design/ChatRootSurface.swift:2274-2282`

minor — spec says `ChatShimmerLabel` has `.contentTransition(.opacity)` and `.easeInOut(duration: 0.3)` on `text`, but omits that a second `.contentTransition(.opacity)` is applied to the mask's inner `Text` (identical text used as the mask shape); without this, the shimmer mask will render differently — `Sources/Design/ChatRootSurface.swift:2699-2705`

minor — spec omits that the `ChatThinkingNode` button label uses `.frame(maxWidth: .infinity, alignment: .leading)` and `.contentShape(Rectangle())`, making the invisible area tappable — `Sources/Design/ChatRootSurface.swift:2137-2142`

minor — spec documents `.frame(maxWidth: .infinity, alignment: .leading)` on the outer `StreamingReplyBubble` but omits the inner `.frame(maxWidth: .infinity, alignment: .leading)` applied to the `Text(revealed)` inside the `HStack` — `Sources/Design/StreamingReplyBubble.swift:34-36`

minor — spec documents the 20 pt width overshoot in `ChatRevealWipe` but omits that `fraction` is clamped to `0–1` via `let clamped = CGFloat(max(0, min(1, self.fraction)))` before path computation — `Sources/Design/ChatRootSurface.swift:2916-2920`

major — spec omits the iOS 26 layering order in `ChatGlassBackground`: on iOS 26 the implementation applies `.glassEffect(.regular, in: self.shape)` then `.fill(self.fill)` on top (fill over glass); on older OS it uses `.fill(.regularMaterial)` with an overlay fill; a rebuilder using the wrong order will produce incorrect visuals — `Sources/Design/ChatRootSurface.swift:2816-2833`

minor — spec references `ChatGlassPanel` in sections 20 and 21 but never documents what it is; the component's constructor, corner-radius parameter, glass material, fill, and hairline behavior are entirely absent from the spec — `Sources/Design/ChatRootSurface.swift` (ChatGlassPanel definition)

## Verdict

NEEDS-REPAIR — 7 blocking major defects
