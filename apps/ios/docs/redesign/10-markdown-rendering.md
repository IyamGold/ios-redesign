# Markdown & Message Rendering Pipeline

This document is a complete reconstruction specification for the shared `OpenClawChatUI` markdown and message rendering pipeline. It covers every stage from raw gateway text to rendered SwiftUI views: preprocessing (envelope/metadata stripping, image extraction, normalization), block segmentation (prose vs. fenced code, display math, GFM tables), prose rendering via `AttributedString`, inline math image rendering, syntax highlighting, the streaming word-reveal animation, the composer view hierarchy, and the chat sheets. The pipeline is shared between iOS and macOS; platform divergences are called out explicitly.

---

## 1. Source Location and Sharing Contract

All types below live in the Swift package at `apps/shared/OpenClawKit/Sources/OpenClawChatUI/`. The package is used by the iOS app target, the macOS app target, and the macOS chat window. The iOS phone chat (`ChatRootSurface`) does **not** route through `ChatMessageViews` / `ChatMarkdownRenderer` — it reimplements its own bubble views in `apps/ios/Sources/Design/ChatRootSurface.swift`. The types documented here are the **legacy/macOS** chat surface and the shared infrastructure that any caller (including `ChatRootSurface`) can consume through `OpenClawChatMarkdownText`.

---

## 2. End-to-End Pipeline Overview

```
Raw gateway text string
       │
       ▼
┌─────────────────────────────────┐
│  Stage 1: ChatMarkdownPreprocessor  │  strips envelope, message-id hints,
│                                 │  inbound-context blocks, timestamps,
│                                 │  extracts inline base64 images, normalizes
└──────────────────┬──────────────┘
                   │ → cleaned string + [InlineImage]
                   ▼
┌─────────────────────────────────────┐
│  Stage 2: AssistantTextParser       │  splits <think>…</think> / <final>…</final>
│  (assistant only, pre-block-segmentation) │  into [AssistantTextSegment]
└──────────────────┬──────────────────┘
                   │ → segments: .thinking | .response
                   ▼
┌──────────────────────────────────────────┐
│  Stage 3: ChatMarkdownBlockSegmenter     │  per segment: splits into
│                                          │  [ChatMarkdownBlock]:
│                                          │  .prose | .code | .math | .table
└──────────────────┬───────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────┐
│  Stage 4: ChatMarkdownProse              │  per .prose block: parses
│           (AttributedString pipeline)    │  AttributedString with inline
│                                          │  math substitution + soft-break fix
└──────────────────┬───────────────────────┘
                   │
                   ▼
┌───────────────────────────────────────────────────────┐
│  Stage 5: ChatMarkdownRenderer (SwiftUI View)         │
│  VStack(spacing: 10) of:                              │
│   .prose  → SwiftUI.Text (AttributedString or Images) │
│   .code   → ChatCodeBlockView                         │
│   .math   → ChatMathBlockView                         │
│   .table  → ChatMarkdownTableView                     │
│  + InlineImageList at the bottom                      │
└───────────────────────────────────────────────────────┘
```

---

## 3. Stage 1 — Preprocessing (`ChatMarkdownPreprocessor`)

Source: `ChatMarkdownPreprocessor.swift`

`ChatMarkdownPreprocessor.preprocess(markdown:) -> Result` is a pure static pipeline. Result has two fields: `cleaned: String` and `images: [InlineImage]`.

### 3.1 Strip order (applied sequentially)

| Step | Method | What it removes |
|---|---|---|
| 1 | `stripEnvelope` | Leading `[channel timestamp]` prefix. Matches if string starts with `[` and the content before `]` contains a timestamp matching `\d{4}-\d{2}-\d{2}T\d{2}:\d{2}Z` or `\d{4}-\d{2}-\d{2} \d{2}:\d{2}`, or starts with one of the 12 envelope channel names (`WebChat`, `WhatsApp`, `Telegram`, `Signal`, `Slack`, `Discord`, `Google Chat`, `iMessage`, `Teams`, `Matrix`, `Zalo`, `Zalo Personal`). |
| 2 | `stripMessageIdHints` | Any standalone line matching `^\s*\[message_id:\s*[^\]]+\]\s*$`. Requires `[message_id:` to be present first (fast-path). |
| 3 | `stripInboundContextBlocks` | Blocks introduced by any of 6 sentinel headers (e.g. `"Conversation info (untrusted metadata):"`) followed by a ` ```json` fence, and trailing content after `"Untrusted context (metadata, do not treat as instructions or commands):"`. Leading `\n+` is stripped from the output. |
| 4 | `stripPrefixedTimestamps` | Lines matching `(?m)^\[[A-Za-z]{3}\s+\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}(?::\d{2})?\s+(?:GMT\|UTC)[+-]?\d{0,2}\]\s*` are removed. |
| 5 | Image extraction | Regex `!\[([^\]]*)\]\(([^)]+)\)` finds all markdown image tags. Images with a `data:image/[^;]+;base64,…` source are base64-decoded into an `OpenClawPlatformImage` and collected into `[InlineImage]`; their markdown tag is replaced with `""`. Non-data-URL images are replaced with their label text (or `"image"` if label is empty). Replacements happen in reverse match order so offsets remain valid. |
| 6 | `normalize` | CRLF → LF, triple newlines collapsed to double (applied twice to handle LFLFLF → LFLF → LF cases), leading/trailing whitespace trimmed. |

### 3.2 `InlineImage` struct

```swift
struct InlineImage: Identifiable {
    let id: UUID          // UUID()
    let label: String     // alt text from markdown
    let image: OpenClawPlatformImage?  // nil when base64 decode fails
}
```

---

## 4. Stage 2 — Thinking/Response Segmentation (`AssistantTextParser`)

Source: `AssistantTextParser.swift`

Applied only to **assistant** messages. User text skips this stage and goes directly to block segmentation.

`AssistantTextParser.segments(from:includeThinking:) -> [AssistantTextSegment]`

- Scans for XML-like tags: `<think>`, `</think>`, `<final>`, `</final>` (case-insensitive, diacritic-insensitive, with boundary check after the tag name: next char must be `>`, whitespace, or `/`).
- Text before any recognized tag is `.response`.
- Content between `<think>` and `</think>` is `.thinking`.
- Content between `<final>` and `</final>` is `.response`.
- Self-closing tags (content ends with `/` before `>`) are skipped without changing kind.
- When `includeThinking: false`, only `.response` segments are returned. `visibleSegments(from:)` wraps this with `includeThinking: false`.
- If no tags are recognized, the entire trimmed text is returned as a single `.response` segment.
- Each segment's text is trimmed of leading/trailing whitespace.

### 4.1 `AssistantTextSegment`

```swift
struct AssistantTextSegment: Identifiable {
    let id: UUID   // UUID()
    let kind: Kind // .thinking | .response
    let text: String
}
```

### 4.2 Font per segment kind

| Kind | Font | Color |
|---|---|---|
| `.thinking` | `OpenClawChatTypography.callout.italic()` — 16 pt Inter Regular, italic, relativeTo `.callout` | `OpenClawChatTheme.assistantText` |
| `.response` | `OpenClawChatTypography.body` — 17 pt Inter Regular, relativeTo `.body` | `OpenClawChatTheme.assistantText` |

Inline math typography also follows segment kind: `.thinking` uses `InlineMathTypography.callout` (size 16, relativeTo `.callout`), `.response` uses `InlineMathTypography.body` (size = `OpenClawChatTypography.bodySize` = 17, relativeTo `.body`).

---

## 5. Stage 3 — Block Segmentation (`ChatMarkdownBlockSegmenter`)

Source: `ChatMarkdownBlockSegmenter.swift`

`ChatMarkdownBlockSegmenter.segments(markdown:isComplete:) -> [ChatMarkdownBlock]`

Takes one preprocessed prose segment string and splits it into a flat ordered list of `ChatMarkdownBlock` values.

### 5.1 Block types

```swift
enum ChatMarkdownBlock: Equatable {
    case prose(String)
    case code(ChatCodeBlock)
    case math(ChatMathBlock)
    case table(ChatMarkdownTable)
}
```

### 5.2 Parsing strategy

The segmenter uses `swift-markdown` (`Document(parsing:)`) for CommonMark structural parsing but extracts only **top-level** blocks (fenced code, display math, GFM tables). Nested blocks stay in surrounding prose.

A `SourceBuffer` helper splits the markdown into `lines: [String]` (CRLF normalized, split on `\n`, empty substrings preserved) for line-range arithmetic.

**Math extraction** runs first (before code/table), because math delimiters can appear inside what the CommonMark parser sees as paragraph text. Math scanning only runs if the string contains `$$` or `\[`. Protected ranges (rejected math spans) prevent code/table extraction from treating lines inside them.

**Math delimiter recognition:**
- `$$` … `$$` or `\[` … `\]` at top-level paragraph lines only (not inside inline code).
- Indent ≤ 3 spaces before the delimiter.
- Single-line form: `$$latex$$` — delimiter and content on one line, content ends before matching close.
- Multi-line form: opener alone on a line, content on subsequent lines, close on its own line.
- Incomplete during streaming: if opener has no matching close and `isComplete == false`, the span and all following lines are protected (stop scanning for more openers).
- `isComplete: Bool` on `ChatMathBlock` is true when the close delimiter was found or `isComplete == true` was passed.
- Size limit: `maxMathBytes = 5000`. Oversized math is protected (falls through as prose).

**Fenced code extraction:**
- `FenceOpener.parse` recognizes `` ` `` or `~` fences of 3+ characters with ≤ 3 leading spaces. Backtick fences cannot have a backtick in the info string.
- Language is the first whitespace-delimited token of the info string, lowercased.
- `isComplete` is true when a matching close fence (same character, ≥ same count, only whitespace after) is found on the last line of the reported range, or when `isComplete == true` is passed.
- Trailing structural newline stripped from `code.code` via `dropStructuralCodeNewline`.

**Table extraction:**
- Uses `swift-markdown`'s `Table` node. The segmenter re-parses the raw line range to find the true header start (the parser's reported range can be off by one row when the delimiter row is not on line 1 of the range).
- GFM column alignment: `left`/`nil` → `.leading`, `right` → `.trailing`, `center` → `.center`.
- Limits: `maxTableBytes = 20000`, `maxTableRows = 100`, `maxTableColumns = 12`, `maxTableCells = 600`. Tables exceeding any limit are skipped (fall through as prose).
- Incomplete tables (trailing lines are all blank and `isComplete == false`) are skipped.
- Cell parsing: pipes split with escape handling (`\|` → `|`); leading/trailing empty cells stripped for pipe-delimited rows; all cells trimmed of whitespace.

**Reference-link fallback:** If the final block list has more than one block and the source document contains any link or image whose raw text ends with `]` (indicating a reference-style link), the segmenter discards all extractions and returns `proseOnly(source.lines)`. This prevents splitting reference definitions from their link labels across blocks.

**Prose ranges:** Lines before the first extraction, between extractions, and after the last extraction are joined and returned as `.prose`. Leading and trailing blank lines are trimmed from each prose slice. Empty slices are discarded.

### 5.3 Extraction sort order

All extractions are sorted by `lowerBound` ascending; ties broken by `upperBound` descending. Extractions whose `lowerBound` is before `proseStart` (already consumed) are skipped.

---

## 6. Stage 4 — Snapshot and Prose Construction

Source: `ChatMarkdownRenderer.swift`

### 6.1 `ChatMarkdownRenderSnapshot`

Constructed on `@MainActor`. Takes `text: String`, `isComplete: Bool`, and optionally `preparesReveal: Bool` (streaming path only).

```
ChatMarkdownPreprocessor.preprocess(markdown: text)
    → processed.cleaned, processed.images
ChatMarkdownBlockSegmenter.segments(markdown: processed.cleaned, isComplete: isComplete)
    → [ChatMarkdownBlock]
Each block mapped to ChatMarkdownRenderedBlock:
    .prose(String)  → .prose(ChatMarkdownProse(…))
    .code           → .code  (pass-through)
    .math           → .math  (pass-through)
    .table          → .table (pass-through)
```

`images` stores the `[InlineImage]` from preprocessing for rendering at the bottom of the view.

### 6.2 `ChatMarkdownProse` construction

```swift
init(markdown: String, isComplete: Bool, preparesReveal: Bool)
```

**Normal (completed, non-streaming) path** (`isComplete && !preparesReveal`):

1. `makeInlineContent(markdown:)` scans for inline math spans via `ChatInlineMathScanner`.
2. If any math spans are found, the markdown is reconstructed with Private-Use-Area Unicode markers replacing each valid math span. The markers are allocated starting at U+E000, skipping values already present in the markdown string. The modified markdown is then parsed into `AttributedString`.
3. The attributed string is then split around the marker characters to produce `[InlineContent]`: alternating `.text(AttributedString)` and `.math(ChatInlineMathSpan)`.
4. Math-inside-link special case: if a math marker inherits a `link` attribute (the math was used as a link label), it is kept as a `.text(literal)` piece so the link destination remains tappable.
5. If no math spans exist, `inlineContent` is `nil` and `attributed` holds the full `AttributedString`.

**Streaming (`preparesReveal == true`) path:**

- `makeInlineContent` is skipped (too expensive per-delta).
- `attributed = Self.parseMarkdown(markdown)` produces a single `AttributedString`.
- `plainText = String(attributed.characters)` is extracted.
- `wordRanges = chatStreamingWordRanges(in: plainText).suffix(24)` — at most 24 trailing words tracked.
- `tailStart` = first word range's `lowerBound`, or `plainText.count` if none.
- `prefix` = `attributed[0..<tailStart]`.
- `tail` = array of `TailPiece` (attributed slice + optional word range for opacity animation).

### 6.3 Soft-break preservation (`ChatMarkdownDisplayPreprocessor`)

Applied before `AttributedString(markdown:)` parsing, inside `parseMarkdown(_:)`.

- CRLF normalized to LF.
- For each adjacent non-empty line pair: if neither line starts a block-level element (heading, blockquote, list, thematic break, indented code), and neither already ends with `  ` or `\`, the trailing two spaces `  \n` (markdown hard break) are appended to force line preservation.
- Code block lines (determined via `swift-markdown` `CodeBlock` ranges) are excluded from soft-break injection.
- This prevents CommonMark's default behavior of collapsing consecutive non-block lines into a single paragraph.

### 6.4 `AttributedString` parsing options

```swift
AttributedString.MarkdownParsingOptions(
    interpretedSyntax: .full,
    failurePolicy: .returnPartiallyParsedIfPossible)
```

Fallback: if parsing fails entirely, `AttributedString(displayMarkdown)` (plain text).

---

## 7. Stage 5 — ChatMarkdownRenderer (SwiftUI View)

Source: `ChatMarkdownRenderer.swift`

### 7.1 Inputs

| Property | Type | Description |
|---|---|---|
| `snapshot` | `ChatMarkdownRenderSnapshot` | Pre-built block list + images |
| `context` | `.user \| .assistant` | Controls link tint color |
| `variant` | `.standard \| .compact` | Controls default line spacing |
| `font` | `Font` | Applied to all prose blocks |
| `textColor` | `Color` | Applied to all prose blocks |
| `lineSpacing` | `CGFloat?` | Override; nil → standard: 4, compact: 2 |
| `inlineMathTypography` | `InlineMathTypography` | Controls inline math font size and text style |
| `reveal` | `ChatMarkdownProseReveal?` | Streaming reveal data for the active prose block |

`@ScaledMetric` drives `inlineMathFontSize` (scaled from `inlineMathTypography.size`, relative to `inlineMathTypography.relativeTo`).

### 7.2 View hierarchy

```
VStack(alignment: .leading, spacing: 10)
├── ForEach blocks:
│   ├── .prose  → proseText() → SwiftUI.Text
│   │     .font(font)
│   │     .foregroundStyle(textColor)
│   │     .tint(linkColor)
│   │     .textSelection(.enabled)
│   │     .lineSpacing(lineSpacing ?? (compact ? 2 : 4))
│   │     .modifier(ChatInlineMathAccessibilityModifier)
│   ├── .code   → ChatCodeBlockView(block:)
│   ├── .math   → ChatMathBlockView(block:textColor:)
│   └── .table  → ChatMarkdownTableView(table:)
└── if !images.isEmpty → InlineImageList(images:)
```

### 7.3 Link tint

- User context: `linkColor = textColor` (white on user bubble)
- Assistant context: `linkColor = OpenClawChatTheme.accent` (platform red)

### 7.4 Inline math accessibility

When `inlineContent` is non-nil, an `.accessibilityLabel` is applied to the prose `Text` containing the full visible text (markdown text portions joined with LaTeX source for math spans), so VoiceOver reads the mathematical expression source.

---

## 8. Inline Math Rendering

Sources: `ChatInlineMath.swift`, `ChatMarkdownRenderer.swift`

### 8.1 Scanner (`ChatInlineMathScanner`)

Scans for `\(…\)` delimiters in markdown. Limits:
- `maxSpanCount = 16` — more than 16 spans in one block → remaining treated as `.literal`
- `maxSourceBytes = 200` — span source longer than 200 UTF-8 bytes → treated as `.literal`
- Multi-line spans → treated as `.literal`

Correctly skips content inside confirmed backtick code spans (matched by length, escape-aware) so inline code containing `\(` is not misidentified.

Returns `[Piece]`: `.markdown(String)` | `.math(latex:String, source:String)` | `.literal(String)`.

### 8.2 Parse cache (`ChatMathParseCache`)

- Capacity: 80 entries. Wholesale reset when full.
- Rejects: empty latex, non-ASCII Unicode (SwiftMath drops silently), nesting depth > 64, command count > 128, presence of `\color`, `\colorbox`, or `\textcolor` (SwiftMath 1.7.3 traps on empty color-command bodies).
- Calls `MTMathListBuilder.build(fromString:)`.

### 8.3 Image cache (`ChatInlineMathImageCache`)

Cache key: `(latex, fontSize, colorHash)`. Capacity: 80 entries. Wholesale reset when full.

Size guards: `maxRenderedPixelArea = 262144`, `maxRenderedPixelDimension = 4096`. Both width and height must be within bounds and total pixel area must not exceed the cap.

Render process:
1. Parse via `ChatMathParseCache.mathList`.
2. Create `MTMathUILabel` in `.text` mode to measure `fittingSize`/`intrinsicContentSize`.
3. Check size limits.
4. Create `MTMathImage(latex:fontSize:textColor:labelMode:.text, textAlignment:.left)` and call `asImage()`.
5. `baselineOffset = -(metricsLabel.displayList?.descent ?? 0)` — lowers the image so its typographic baseline aligns with surrounding text (SwiftUI places `Text(Image)` bottom on the baseline).

Platform color resolution: on macOS, color is resolved under the appropriate `NSAppearance` (light/dark). On iOS, `UIColor.resolvedColor(with:)` is used.

### 8.4 Display math block (`ChatMathBlockView`)

- Renders only when `block.isComplete` and `ChatMathParseCache.mathList(latex:) != nil`.
- Uses `MTMathUILabel` in `.display` mode, centered, via `ChatMathPlatformView` (`NSViewRepresentable`/`UIViewRepresentable`).
- Wrapped in `ScrollView(.horizontal, showsIndicators: false)` with `.defaultScrollAnchor(.center)`, `.frame(maxWidth: .infinity)`, `.padding(.vertical, 4)`.
- Accessibility: `accessibilityElement(children: .ignore)` + `accessibilityLabel(Text(block.latex))`.
- When incomplete or parse fails: falls back to `ChatCodeBlockView(block: ChatCodeBlock(language: nil, code: block.latex, isComplete: false))` (plain monospace, no highlighting).
- Font size: `@ScaledMetric(relativeTo: .body) = OpenClawChatTypography.bodySize` (17 pt).

---

## 9. Code Block Rendering (`ChatCodeBlockView`)

Source: `ChatMarkdownBlockViews.swift`

### 9.1 View hierarchy

```
VStack(alignment: .leading, spacing: 6)
├── if block.language != nil:
│     Text(language)
│       .font(OpenClawChatTypography.caption2)  // 11pt body, relativeTo .caption2
│       .foregroundStyle(.secondary)
└── ScrollView(.horizontal, showsIndicators: false)
      Text(attributedCode)
        .font(OpenClawChatTypography.mono(size: 13, relativeTo: .footnote))
        .foregroundStyle(OpenClawChatTheme.assistantText)
        .lineSpacing(2)
        .textSelection(.enabled)
```

Background: `RoundedRectangle(cornerRadius: 12, style: .continuous)` filled with `OpenClawChatTheme.subtleCard`, overlay stroke `Color.white.opacity(0.08)` lineWidth 1. Padding: 10pt all sides. `frame(maxWidth: .infinity, alignment: .leading)`.

### 9.2 Highlighting

Open fences (`!block.isComplete`) bypass highlighting entirely and return plain `AttributedString`. This keeps each streaming delta cheap.

Completed fences call `ChatCodeHighlightCache.highlighted(code:languageId:)`.

Cache key: `"\(languageId ?? "")\u{0}\(code)"`. Capacity: 160 entries. Wholesale reset when full.

### 9.3 Supported languages and their token kinds

| Language IDs | Keywords | Line comments | Block comments | Strings | Triple quotes |
|---|---|---|---|---|---|
| `swift` | 65 keywords | `//` | `/* */` (nested) | `"` | Yes |
| `kotlin`, `kt`, `kts` | 37 keywords | `//` | `/* */` (nested) | `"` | Yes |
| `typescript`, `ts`, `tsx`, `javascript`, `js`, `jsx`, `mjs`, `cjs` | 57 keywords | `//` | `/* */` | `"`, `'`, `` ` `` | No (backtick = multiline template) |
| `python`, `py`, `python3` | 35 keywords | `#` | None | `"`, `'` | Yes |
| `bash`, `sh`, `shell`, `zsh`, `console` | 30 keywords | `#` (boundary-only) | None | `"`, `'` | No |
| `json`, `jsonc`, `json5` | `false`, `null`, `true` | None | None | `"` | No |

All other language IDs produce unstyled plain text.

Limits: `maxHighlightedLines = 200`, `maxHighlightedBytes = 20000`. Code exceeding either limit is returned as plain `AttributedString`.

Bash line comments require a boundary: the character before `#` must be whitespace or one of `;&|()<>`, or the `#` must be at position 0. This prevents `#!` shebang lines and color codes from being highlighted as comments.

### 9.4 Token colors (`ChatCodeSyntaxPalette`)

Colors are dynamic (light/dark adaptive). On macOS, implemented via `NSColor(dynamicProvider:)` (semantic `NSColor` is unreliable in SwiftPM). On iOS, via `UIColor(dynamicProvider:)`.

| Token kind | Light (R, G, B) | Dark (R, G, B) |
|---|---|---|
| `.keyword` | (0.68, 0.24, 0.64) | (1.00, 0.48, 0.70) |
| `.string` | (0.82, 0.18, 0.11) | (1.00, 0.51, 0.44) |
| `.number` | (0.15, 0.16, 0.85) | (0.85, 0.79, 0.49) |
| `.comment` | (0.44, 0.50, 0.55) | (0.50, 0.55, 0.60) |
| `.plain` | (no color override) | (no color override) |

---

## 10. Table Rendering (`ChatMarkdownTableView`)

Source: `ChatMarkdownBlockViews.swift`

### 10.1 View hierarchy

```
ScrollView(.horizontal, showsIndicators: false)
  Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 7)
    GridRow (header)
      ForEach columns → cell(header[column], isHeader: true)
                         .gridColumnAlignment(columnAlignment(column))
    Divider()
    ForEach rows
      GridRow
        ForEach columns → cell(rows[row][column], isHeader: false)
```

Background: `RoundedRectangle(cornerRadius: 12, style: .continuous)` filled with `OpenClawChatTheme.subtleCard`, stroke `Color.white.opacity(0.08)` lineWidth 1. Padding: 10pt all sides. `frame(maxWidth: .infinity, alignment: .leading)`.

### 10.2 Cell rendering

Header cells: `OpenClawChatTypography.footnoteSemiBold` (13pt semibold, relativeTo `.footnote`).
Body cells: `OpenClawChatTypography.footnote` (13pt regular, relativeTo `.footnote`).
All cells: `foregroundStyle(OpenClawChatTheme.assistantText)`, `.textSelection(.enabled)`.

Cell content is parsed as inline-only markdown:
```swift
AttributedString.MarkdownParsingOptions(
    interpretedSyntax: .inlineOnlyPreservingWhitespace,
    failurePolicy: .returnPartiallyParsedIfPossible)
```

Column alignment maps to `HorizontalAlignment`: `.leading` → `.leading`, `.center` → `.center`, `.trailing` → `.trailing`. Columns beyond `alignments.count` default to `.leading`.

---

## 11. Inline Images (`InlineImageList`)

Source: `ChatMarkdownRenderer.swift`

Rendered as a `ForEach` at the bottom of the `ChatMarkdownRenderer` `VStack`, after all blocks.

For images with a decoded `OpenClawPlatformImage`:
```
Image(platform image)
  .resizable()
  .scaledToFit()
  .frame(maxHeight: 260)
  .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  .overlay(
    RoundedRectangle(cornerRadius: 12, style: .continuous)
      .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
```

For failed images (nil): `Text(label or "Image")` in `OpenClawChatTypography.footnote`, `.foregroundStyle(.secondary)`.

---

## 12. Streaming Word-Reveal Animation

Sources: `ChatStreamingReveal.swift`, `ChatMessageViews.swift`

### 12.1 Constants (`ChatStreamingRevealConstants`)

| Constant | Value |
|---|---|
| `wordInterval` | 0.04 s — target inter-word stagger during normal flow |
| `fadeDuration` | 0.12 s — opacity 0 → 1 duration per word |
| `maximumCatchUpDuration` | 0.4 s — total allowed animation window when catching up with a batch of new words |
| `maximumFadingWords` | 24 — tail window; words beyond 24 are revealed instantly |

### 12.2 `chatStreamingWordRanges(in:)` — `[Range<Int>]`

Simple character-index word scanner. Whitespace gaps separate words. Returns character-offset ranges (not String indices).

### 12.3 `step(state:newText:now:)` — state machine

Called each time the streamed text grows:

1. If `newText` does not have `state.text` as a prefix (rewrite): return a fresh `ChatStreamingRevealState(text: newText)` — reveals the replacement immediately.
2. If text unchanged: prune words whose `deadline ≤ now`, keep the rest.
3. Otherwise (normal append):
   - Recompute word ranges for the full new text.
   - Carry forward existing words that still have `deadline > now` and whose start position appears in the new ranges.
   - Add new words (start ≥ old character count, not already tracked) with `fadeStart = now`, `deadline = now + fadeDuration`.
   - Sort by start. Trim to `maximumFadingWords` (removing front = oldest).
   - Compute per-word stagger: if multiple words, `catchUpSpacing = (0.4 - 0.12) / (count - 1)`, then `spacing = min(0.04, catchUpSpacing)`. Single new word: spacing = 0.
   - Reschedule: each word at index `i` gets `scheduledStart = now + i * spacing`, `scheduledDeadline = scheduledStart + fadeDuration`. Existing words keep their `fadeStart` but may have `deadline` moved **earlier** (catch-up never extends an existing deadline).

### 12.4 `revealedOpacities(state:now:)` — `ChatStreamingRevealFrame`

For each word in state where `now < deadline`:
- `duration = deadline - fadeStart`
- `opacity = duration > 0 ? clamp((now - fadeStart) / duration, 0, 1) : 1`

Returns `ChatStreamingRevealFrame(fullyRevealedPrefixCharacterOffset:fading:)`. `fullyRevealedPrefixCharacterOffset` is the `lowerBound` of the first still-fading word (or `text.count` if none).

### 12.5 `ChatMarkdownProse.revealedText(frame:textColor:)`

The prose is pre-split into `prefix` (fully revealed) + `tail` pieces. The tail is an array of `TailPiece(attributed:wordRange?)`. For each piece, if `wordRange` matches a fading word in the frame, `foregroundColor` is overridden with `textColor.opacity(fading.opacity)`.

Returns `SwiftUI.Text` by concatenation: `Text(prefix) + Text(tailPiece1) + Text(tailPiece2) + …`

### 12.6 `ChatStreamingAssistantTextBody` — streaming container

Declared `@MainActor`. State:

| Property | Type | Purpose |
|---|---|---|
| `snapshot` | `Snapshot` | Holds per-segment `ChatMarkdownRenderSnapshot` built with `preparesReveal: true` |
| `revealState` | `ChatStreamingRevealState` | Current word timing for the active tail block |
| `revealLocation` | `Snapshot.ProseLocation?` | Which segment + block is currently animating |
| `pendingUntil` | `TimeInterval?` | `latestDeadline` of current reveal state; drives `.task(id:)` sleep |

Frame driver: when `pendingUntil != nil` and not in reduced motion, wraps rendering in `TimelineView(.animation(minimumInterval: 1/60))`. When `pendingUntil == nil` or reduced motion is on, renders statically (no `TimelineView`).

`.task(id: pendingUntil)` waits until `max(0, pendingUntil - now)` seconds have elapsed, then sets `pendingUntil = nil` to stop the `TimelineView`. Superseded tasks are cancelled automatically.

On `.onChange(of: text)` or `.onChange(of: includesThinking)`: rebuilds `Snapshot`, calls `step(state:newText:now:)` to advance reveal state. If `revealLocation` changes, starts a fresh `ChatStreamingRevealState`.

`.onAppear`: re-runs update if `snapshot.sourceText != text` (handles the case where the view appeared with stale data from `init`).

Reduced motion: `@Environment(\.accessibilityReduceMotion)`. When true, `pendingUntil` is always `nil`.

---

## 13. Message Bubble View Hierarchy (`ChatMessageViews.swift`)

Note: this is the **shared/macOS** chat surface. The iOS phone chat uses `ChatRootSurface` instead.

### 13.1 `ChatMessageBubble`

```swift
struct ChatMessageBubble: View {
    let message: OpenClawChatMessage
    let style: OpenClawChatView.Style      // .standard | .onboarding
    let markdownVariant: ChatMarkdownVariant
    let userAccent: Color?
    let showsAssistantTrace: Bool
    let assistantName: String?
    let assistantAvatarText: String?
    let assistantAvatarTint: Color?
    let showsAssistantAvatar: Bool
    let isClean: Bool
}
```

Layout:

- **User:** `messageBody.frame(maxWidth: 560, alignment: .trailing).frame(maxWidth: .infinity, alignment: .trailing).padding(.horizontal, 2)`
- **Assistant:** `HStack(alignment: .top, spacing: 8) { ChatAgentAvatar(...).padding(.top, 1); messageBody.frame(maxWidth: 560, alignment: .leading) }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 2)`

`bubbleMaxWidth = 560` (`ChatUIConstants.bubbleMaxWidth`).

### 13.2 `ChatMessageBody` — bubble vs. clean

`usesBubble` is true when:
- `isUser`, OR
- `style == .onboarding`, OR
- `!isClean`, OR
- `openClawAssistantBubblesInCleanChrome` environment value is `true` (iOS phone opt-in)

**Bubble mode paddings:**
- `.padding(.vertical, 10)`, `.padding(.horizontal, 12)`

**Clean mode paddings:**
- `.padding(.vertical, 5)`, `.padding(.horizontal, 4)`

### 13.3 Bubble styling

`ChatBubbleShape(cornerRadius: 18, tail: bubbleTail)` — `bubbleCorner = 18`.

Tail is only rendered in `.onboarding` style (`.right` for user, `.left` for assistant). Standard style uses `.none` (plain rounded rect).

**Tail geometry:**
- `tailWidth = 7`, `tailBaseHeight = 9`
- Base bottom Y: `bubbleMaxY - max(cornerRadius * 0.45, 6)`
- Tip position: `bubbleMaxX + tailWidth` (right) or `bubbleMinX - tailWidth` (left)
- Cubic bezier curves for organic shape

**User bubble:**
- Fill: `userAccent ?? OpenClawChatTheme.userBubble`
- Border: `Color.white.opacity(0.12)`, lineWidth 0.5
- Shadow: `.clear` (no shadow)

**Assistant bubble (onboarding):**
- Fill: `OpenClawChatTheme.onboardingAssistantBubble`
- Border: `OpenClawChatTheme.onboardingAssistantBorder` (white 0.12), lineWidth 0.8
- Shadow: `color: .black.opacity(0.28), radius: 6, y: 2`
- Tail leading padding: 8pt

**Assistant bubble (standard/clean + bubble opt-in):**
- Fill: `OpenClawChatTheme.assistantBubble`
- Border: `Color.white.opacity(0.08)`, lineWidth 1
- Shadow: `.clear`

### 13.4 `ChatAgentAvatar`

```
Circle()
  .fill(LinearGradient(
    colors: [(tint ?? accent).opacity(0.95),
             Color(red:38/255, green:40/255, blue:43/255)],
    startPoint: .topLeading,
    endPoint: .bottomTrailing))
.overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
.shadow(color: (tint ?? accent).opacity(0.18), radius: 8, y: 4)
```

Default size: 30pt (outer frame). Display text priority: `text` (up to 3 chars) → initials from `name` (up to 2 words, joined initials, uppercased) → `"OC"`.

Font: `OpenClawChatTypography.avatar(size: fontSize)` where `fontSize = size * (displayText.count > 2 ? 0.34 : 0.42)`.

### 13.5 Message content stack

```swift
VStack(alignment: .leading, spacing: 10)
```

Contents (in order):
1. If tool-result role and `showsAssistantTrace`: `ToolResultCard(title:text:isUser:toolName:)` (only if text is non-empty)
2. Else if user: `ChatMarkdownRenderer(context: .user, variant: markdownVariant, font: OpenClawChatTypography.body, textColor: OpenClawChatTheme.userText)`
3. Else (assistant): `ChatAssistantTextBody(text:markdownVariant:includesThinking:)`
4. If `showsLinkPreview` and first URL found: `ChatLinkPreview(url:)`
5. If non-empty inline attachments: `ForEach AttachmentRow`
6. If `showsAssistantTrace` and tool calls: `ForEach ToolCallCard`
7. If `showsAssistantTrace` and inline tool results: `ForEach ToolResultCard`

`.textSelection(.enabled)` and `.foregroundStyle(textColor)` on the whole stack.

`primaryText` concatenates all content items with `type == "text"` or `type == nil` (joined with `\n`), then passes through `OpenClawChatMessage.displayText(contentText:role:stopReason:errorMessage:)`.

### 13.6 `ToolCallCard`

```
VStack(alignment: .leading, spacing: 6)
  HStack(spacing: 6) { Text(toolName)  .font(footnoteSemiBold);  Spacer }
  if summary: Text(summary).font(mono 13pt footnote).foregroundStyle(.secondary).lineLimit(2)
.padding(10)
.background(subtleCard + stroke white 0.08, radius 12)
```

### 13.7 `ToolResultCard`

```
VStack(alignment: .leading, spacing: 8)
  HStack { Text(title).font(footnoteSemiBold); Spacer }
  Text(displayText).font(mono 13pt footnote).lineLimit(expanded ? nil : 8)
  if shouldShowToggle: Button("Show less"/"Show full output").font(caption).foregroundStyle(.secondary)
.padding(10)
.background(subtleCard + stroke white 0.08, radius 12)
```

Preview limit: 8 lines (`previewLineLimit = 8`). Toggle shown when `lines.count > 8`. Collapsed text appends `"\n…"`.

### 13.8 Typing indicator (`ChatTypingIndicatorBubble`)

Three `Circle()` dots (7×7pt, `Color.secondary.opacity(0.55)`):
- Scale: `animate ? 1.05 : 0.70` (reduced motion: 0.85 fixed)
- Opacity: `animate ? 0.95 : 0.30` (reduced motion: 0.55 fixed)
- Animation: `.easeInOut(duration: 0.55).repeatForever(autoreverses: true).delay(Double(idx) * 0.16)` per dot
- Animates only when `scenePhase == .active` and `!accessibilityReduceMotion`

Label `"Writing"` in `captionSemiBold`. HStack spacing: 9. Padding vertical: clean=5, standard=10, onboarding=9. Padding horizontal: clean=4, standard=12, onboarding=14.

Container style: `assistantBubbleContainerStyle(isClean:cornerRadius:15)` — adds bubble background + border only when bubbles are active, adds 8pt padding in clean+bubble mode.

### 13.9 `ChatStreamingAssistantBubble`

```
HStack(alignment: .top, spacing: 8)
  ChatAgentAvatar (if showsAssistantAvatar) .padding(.top, 1)
  VStack(alignment: .leading, spacing: 10)
    ChatAssistantTextBody(text:, isComplete: false)
  .padding(isClean ? 4 : 12)
  .assistantBubbleContainerStyle(isClean:)
.frame(maxWidth: .infinity, alignment: .leading)
```

### 13.10 Environment key `openClawAssistantBubblesInCleanChrome`

```swift
@Entry public var openClawAssistantBubblesInCleanChrome: Bool = false
```

Default: `false`. iOS phone chat sets this to `true` via `.environment(\.openClawAssistantBubblesInCleanChrome, true)` to opt into iMessage-style assistant bubbles in the clean chrome.

---

## 14. Visible-Text Extraction (`ChatMessageVisibleText`)

Source: `ChatMessageVisibleText.swift`

Public utility for transcript export and the Listen (TTS) action.

```swift
public enum ChatMessageVisibleText {
    public static func visibleText(in message: OpenClawChatMessage) -> String
    public static func hasVisibleText(in message: OpenClawChatMessage) -> Bool
}
```

- Extracts `primaryText` (same logic as `ChatMessageBody.primaryText`): joins all `content` items with `type == "text"` or empty type.
- For user role: returns `primaryText` directly.
- For assistant role: `AssistantTextParser.visibleSegments(from:)` strips thinking segments, joins `.response` segments with `"\n\n"`.

This ensures the exported and spoken text always matches exactly what appears in the bubble.

---

## 15. `OpenClawChatMarkdownText` — Public Seam

Source: `OpenClawChatMarkdownText.swift`

```swift
public struct OpenClawChatMarkdownText: View {
    public init(text: String, isUser: Bool, font: Font, textColor: Color, lineSpacing: CGFloat? = nil)
}
```

Delegates to `ChatMarkdownRenderer(text:context:variant:.standard, font:textColor:lineSpacing:)`. Always uses `.standard` variant. Intended for app-side surfaces that need the full markdown pipeline (e.g. `ChatRootSurface` card footers, Settings previews) without importing the internal types.

---

## 16. Composer (`OpenClawChatComposer`)

Source: `ChatComposer.swift`

### 16.1 Two chrome modes

| Mode | Description |
|---|---|
| `.full` | Full composer with toolbar row (model/session/thinking pickers, refresh, attachment, talk), divider, and a send/abort bar. Used by standard desktop chat. |
| `.clean` | iMessage-style: paperclip + voice-note icon left of a pill field, send/mic button on the right. Used by iOS phone chat (via `ChatRootSurface` hosting) and clean macOS embedded surfaces. |

### 16.2 Top-level `VStack(alignment: .leading, spacing: 4)` contents (in order)

1. Composer toolbar (`.full` + `.standard` style only, hidden during voice note recording)
2. Attachments strip (`.standard` style only, when non-empty)
3. Voice note recording row (when recording active) OR editor

Background (`.full` chrome only): `RoundedRectangle(cornerRadius: 18)` filled with `OpenClawChatTheme.composerBackground`, stroke `OpenClawChatTheme.composerBorder`, shadow `black 0.12, radius 12, y 6`. macOS standard style uses `UnevenRoundedRectangle` (top corners 0, bottom corners 18).

Outer padding: onboarding = 5pt, clean = 4pt, full = 6pt.

### 16.3 Clean editor layout

```
HStack(alignment: .bottom, spacing: 8)
  attachmentPicker
    .frame(width: cleanIconControlSize=32, height: cleanEditorMinHeight)
  voiceNoteButton (if not talk-active)
    .frame(width: 32, height: cleanEditorMinHeight)
  editorOverlay
    .padding(.vertical, cleanEditorTextPadding=10)
    .padding(.horizontal, 14)
    .frame(minHeight: cleanEditorMinHeight)
    .modifier(CleanChatComposerSurface(cornerRadius: cleanEditorCornerRadius))
  cleanTrailingControl
    .frame(height: cleanEditorMinHeight, alignment: .bottom)
```

`cleanEditorMinHeight = max(44, textMinHeight + 10 * 2)`.

`cleanEditorCornerRadius = cleanEditorMinHeight / 2` (pill shape).

`textMinHeight`: standard clean = 24pt, onboarding = 24pt, full = 28pt. Each is `max(base, scaledBodyLineHeight)` where `@ScaledMetric(relativeTo: .body) var scaledBodyLineHeight: CGFloat = 22`.

`textMaxHeight`: standard clean = 48pt, onboarding = 52pt, full = 64pt. Each is `max(base, scaledBodyLineHeight * 4)`.

### 16.4 Clean composer surface (`CleanChatComposerSurface`)

iOS ≥ 26: `.glassEffect(.regular, in: .rect(cornerRadius:))`.
iOS < 26: `.background(.regularMaterial, in: RoundedRectangle) + .overlay(stroke composerBorder, lineWidth: 1)`.
macOS: `.background(composerField fill) + .overlay(stroke composerBorder, lineWidth: 1)`.

### 16.5 Clean trailing control (`cleanTrailingControl`)

When draft is empty and no pending runs and `talkControl` exists: `compactTalkButton` — circle-filled mic icon (32×32pt icon inside a 44×44pt hit target).

Otherwise: `sendButton` at `cleanControlHeight = 44pt`, visual size `cleanIconControlSize = 32pt`, corner radius `32/2 = 16`.

### 16.6 iOS text field (clean mode)

```swift
TextField("", text: $viewModel.input, axis: .vertical)
    .font(OpenClawChatTypography.body)
    .textFieldStyle(.plain)
    .lineLimit(1...4)
    .fixedSize(horizontal: false, vertical: true)
    .submitLabel(.return)  // return inserts newline; send is the button
    .padding(.horizontal, 0)  // cleanFieldTextInset = 0
    .padding(.vertical, 0)    // cleanEditorTextPadding applied by parent
```

Placeholder: `Text(placeholderText)` in `OpenClawChatTypography.body`, `.foregroundStyle(.tertiary)`. Default placeholder text: `"Message…"`.

### 16.7 macOS text view (full mode)

`ChatComposerNSTextView` (subclass of `NSTextView`) wrapped in `NSScrollView`. Configuration:
- `drawsBackground = false`, `isRichText = false`
- `isAutomaticQuoteSubstitutionEnabled = false`
- `isAutomaticTextReplacementEnabled = false`
- `isAutomaticDashSubstitutionEnabled = false`
- `isAutomaticSpellingCorrectionEnabled = false`
- `font = .systemFont(ofSize: 14, weight: .regular)` (macOS only — not branded)
- `textContainerInset = NSSize(width: 2, height: 4)`
- `focusRingType = .none`
- `allowsUndo = true`
- Horizontally non-resizable, vertically resizable, width-tracking container

macOS send key: `Return` (keyCode 36) without modifiers triggers send. `Shift+Return` inserts a newline. IME-marked text (composition) is never intercepted.

Image paste: PNG, TIFF, JPEG (`public.jpeg`), GIF (`com.compuserve.gif`), HEIC (`public.heic`), HEIF (`public.heif`) data types, plus file URLs to image files. File references are loaded on `DispatchQueue.global(qos: .userInitiated)`.

### 16.8 Send/Stop button

Visual size: clean = 32×32pt, full = `sendButtonSize = 44pt`. Corner radius: clean = 16, full = 12.

**Send state:**
- Fill: `userAccent ?? OpenClawChatTheme.userBubble` (active) or `.clear` (clean disabled) or `secondary 0.32` (full disabled)
- Foreground: `.white` (active or full chrome) or `.secondary.opacity(0.55)` (clean disabled)
- Border opacity: active = 0.18, full disabled = 0.08, clean disabled = 0
- Icon: `arrow.up` at `display(size: 13, weight: .semibold, relativeTo: .caption)`

**Stop state** (pending run, no draft):
- Fill: `OpenClawChatTheme.danger` (system red)
- Icon: `stop.fill` at same font

### 16.9 Slash command panel

Shown when: input starts with `/` (not `//`), the remainder has no whitespace (or is `skill`/`skill …`), composer is enabled, and the transport supports slash command catalog.

Panel: `VStack(alignment: .leading, spacing: 0)`, height `340pt`, `.regularMaterial` background, `RoundedRectangle(cornerRadius: 16)`, stroke `secondary 0.15 lineWidth 0.5`, shadow `black 0.12 radius 12 y 4`.

Row: `HStack(alignment: .top, spacing: 0)` with `VStack(spacing: 3)` containing command invocation (`mono(size: 15, weight: .semibold, relativeTo: .subheadline)`) and description (`caption`, secondary, lineLimit 2). Padding: `.horizontal(8) .vertical(8)`. Highlighted row background: `.selection`.

Animation: `.easeInOut(duration: 0.18)` for show/hide.

macOS keyboard navigation: Up/Down arrows move highlight, Tab/Return accept, Escape dismisses. Modified keys and IME composition are passed through to the text view.

Scroll affordance (> 4 matches): gradient fade + `chevron.compact.down` at 16pt semibold.

Debounce for search updates: `.task(id: scopedFetchID)` with `Task.sleep(250_000_000 ns)`.

### 16.10 Context usage indicator

Circular ring `14×14pt`. Stroke: `muted.opacity(0.2)` background, color `warning` when `fraction >= 0.8` else `muted`. Trim: `.trim(from: 0, to: fraction)` with `.lineCap(.round)`, rotated `-90°`. Accessibility label: `"Context \(percentage)% used"`.

### 16.11 Attachments strip

Horizontal `ScrollView` of capsule-shaped chips. Each chip: `accent.opacity(0.08)` background, `Capsule()` shape. Padding: `.horizontal(8) .vertical(5)`.

Image thumbnails: 22×22pt, `cornerRadius: 6`.

### 16.12 Talk (realtime) button

Full chrome: pill with `HStack(spacing: 6)` of icon + label, height 32pt, padded `.horizontal(10)`. Fill: `userBubble` (active) or subtle card (idle) or `secondary 0.12` (disconnected). Stroke: white 0.18 (active) or `composerBorder`.

Clean chrome: circle `32×32pt` icon inside `44×44pt` hit area. Fill: `accent` (idle) or `userBubble` (active). Opacity 0.4 when disconnected and not active.

Accessibility identifier: `"chat-realtime-control"`.

---

## 17. Chat Sheets (`ChatSheets.swift`)

Source: `ChatSheets.swift`

### 17.1 `ChatSessionsSheet`

`NavigationStack` with a `List`. Scoped picker (segmented: Active / Archived) in the section header (text case nil, caption font). Search bar via `.searchable(prompt: "Search sessions")`.

Session row layout:
```
HStack(spacing: 8)
  VStack(alignment: .leading, spacing: 4)
    Text(displayName ?? key)
      .font(OpenClawChatTypography.mono(size: 17, relativeTo: .body))
      .lineLimit(1)
    if updatedAt: Text(formatted date/time abbreviated/shortened)
      .font(OpenClawChatTypography.caption)
      .foregroundStyle(.secondary)
  Spacer
  if pinned: Image("pin.fill") .font(.system(size: 12)) .foregroundStyle(.secondary)
```

Swipe actions (leading, trailing):
- Leading (non-archived): Pin/Unpin — tint `OpenClawChatTheme.accent`
- Trailing: Archive/Unarchive — tint `danger` (archive) or `accent` (unarchive)

Context menu: Rename (opens alert with `TextField`), Pin/Unpin, Archive/Unarchive.

Rename alert: `TextField("Session name", text: $renameText)` + Rename / Cancel buttons.

Archived scope fetches are separate server-side queries with a 250 ms debounce for search. Active list comes directly from `viewModel.sessions`. A 400 ms delay is used for post-mutation refreshes.

Archived session tap: calls `viewModel.restoreSession(key:)` first; only switches on success (prevents composer from pointing at still-archived session).

Toolbar: Refresh (leading) + xmark close (trailing).

---

## 18. Typography Reference

Source: `ChatTypography.swift`

| Token | Size | Weight | Font (iOS) | Font (macOS) |
|---|---|---|---|---|
| `title3` | 22pt | bold | RedHatDisplay-Regular | system |
| `title3SemiBold` | 22pt | semibold | RedHatDisplay-Regular | system |
| `headline` | 17pt | semibold | RedHatDisplay-Regular | system |
| `callout` | 16pt | regular | Inter-Regular | system |
| `body` | 17pt | regular | Inter-Regular | system |
| `footnote` | 13pt | regular | Inter-Regular | system |
| `footnoteSemiBold` | 13pt | semibold | Inter-Regular | system |
| `caption` | 12pt | regular | Inter-Regular | system |
| `captionSemiBold` | 12pt | semibold | Inter-Regular | system |
| `caption2` | 11pt | regular | Inter-Regular | system |
| `mono(size:)` | variable | regular | JetBrainsMono-Regular | system mono |
| `mono(size:weight:.semibold)` | variable | semibold | JetBrainsMono-SemiBold | system mono |
| `display(size:weight:)` | variable | variable | RedHatDisplay-Regular | system |

All fonts use `Font.custom(_:size:relativeTo:)` for Dynamic Type support. macOS uses the platform system font name via `NSFont.systemFont(ofSize:).fontName`.

---

## 19. Theme Color Reference

Source: `ChatTheme.swift`

### iOS adaptive colors (light / dark)

| Token | Light | Dark |
|---|---|---|
| canvas top | `#F6F7F9` | `#0C0D0F` |
| canvas middle | `#FAFBFC` | `#07080A` |
| canvas bottom | `#FFFFFF` | `#040506` |
| dark panel | — | `#0A0C0E` |
| dark panel raised | — | `#111215` |
| dark composer | — | `#18191C` |
| accent (light) | `#DC2626` (RGB 220,38,38) | — |
| accent (dark) | — | `#C6312A` (RGB 198,49,42) |

| Semantic token | iOS value |
|---|---|
| `userBubble` / `accent` | adaptive accent above |
| `assistantBubble` | light: `.systemGray5`; dark: `darkPanelRaised` |
| `onboardingAssistantBubble` | light: `.secondarySystemBackground`; dark: `darkPanelRaised` |
| `userText` | `.white` |
| `assistantText` | `UIColor.label` |
| `composerBackground` | light: `.secondarySystemGroupedBackground`; dark: `darkPanel` |
| `composerField` | light: `.secondarySystemBackground`; dark: `darkComposer` |
| `composerBorder` | light: `.separator`; dark: `UIColor.white.withAlpha(0.14)` |
| `subtleCard` | light: `.tertiarySystemBackground`; dark: `darkPanelRaised` |
| `divider` | `secondary.opacity(0.2)` |
| `danger` | `UIColor.systemRed` |
| `warning` | `UIColor.systemOrange` |

---

## 20. Known Gaps and Rebuild Notes

- `chatFirstPreviewURL(in:)` — link preview URL extraction function referenced in `ChatMessageBody` but not in the primary files. Its implementation is likely in `ChatLinkPreview.swift`.
- `ToolDisplayRegistry.resolve(name:args:)` and `ToolResultTextFormatter.format(text:toolName:)` — tool display name/icon resolution. Not in primary files.
- `OpenClawChatViewModel` — all composer state (sessions, model picker, attachments, slash commands, `canSend`, `send()`, `abort()`, etc.) lives in this `@Observable` class.
- `OpenClawChatMessage`, `OpenClawChatMessage.displayText(contentText:role:stopReason:errorMessage:)` — message model and display-text synthesis. Lives in `OpenClawKit` core, not `OpenClawChatUI`.
- `OpenClawVoiceNoteButton`, `OpenClawVoiceNoteRecordingRow`, `OpenClawChatVoiceNoteControl` — voice note UI components referenced in the composer but not in primary files.
- `ChatLinkPreview` — link preview card component rendered below message text.
- `AssistantBubbleContainerStyle` — adds bubble chrome to the typing indicator and streaming bubble in clean mode; its conditional logic depends on `openClawAssistantBubblesInCleanChrome`.
- Exact `OpenClawChatView.Style` and `ComposerChrome` enum cases are `standard`, `onboarding`, `clean`, and `full` based on usage, but their definitions are in `ChatView.swift` (not a primary file).
- `ChatTranscriptExporter` — also consumes `ChatMessageVisibleText` for export; not covered here.
