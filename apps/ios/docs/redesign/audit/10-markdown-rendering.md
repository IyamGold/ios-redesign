# Audit — 10-markdown-rendering.md

## Scorecard

| metric | value |
|---|---|
| precision | 0.984 |
| recall | 0.626 |
| F | 0.765 |
| critical | 0 |
| major | 10 |
| minor | 32 |
| certified | false |
| claims | 79 |

## Defects (fix these)

### Wrong / Unsupported Claims

**major** — The spec claims the slash command panel in `ChatComposer` uses a `.task(id: scopedFetchID)` with `Task.sleep(250_000_000 ns)` debounce. In reality no such debounce exists in `ChatComposer.swift` for the slash command panel; the 250 ms `Task.sleep` at `ChatSheets.swift:252` belongs to `ChatSessionsSheet`'s session-search, not the slash panel. — `ChatComposer.swift`

---

### Omissions

**minor** — The spec (§3.1 step 5) says non-data-URL images are replaced with their label text. What is not stated: no `InlineImage` struct is ever created for plain http/https URLs — only `data:image/…;base64` sources produce an `InlineImage`. Plain-URL images are replaced inline and never appear in `InlineImageList`. — `ChatMarkdownPreprocessor.swift:82-95`

**minor** — The spec (§3.1 strip order) does not document the envelope-stripping offset detail: the match strips everything from the start up to and including the first `]`, so the resulting string begins with the raw character immediately after `]` (which may be a space or newline). A rebuilder could strip too little or too much without this. — `ChatMarkdownPreprocessor.swift:102-112`

**minor** — The spec (§3.1, Step 3) says inbound-context blocks require a ` ```json ` fence immediately following the sentinel header line, but does not state that if the next line is not exactly ` ```json ` (trimmed), the sentinel line is kept as normal output. This conditional behavior is absent from the spec. — `ChatMarkdownPreprocessor.swift:160-168`

**major** — The spec (§3.1, Step 3) says `untrustedContextHeader` strips "trailing content" with no qualification. The source only strips all remaining lines when a probe regex (`<<<EXTERNAL_UNTRUSTED_CONTENT|UNTRUSTED channel metadata \(|Source:\s+`) matches within the next 8 lines. Without this conditional probe a rebuilder would strip too aggressively. — `ChatMarkdownPreprocessor.swift:202-210`

**major** — The spec (§5.2) states the math single-line form searches for the close delimiter in a straightforward way. The source uses `.backwards` to find the LAST occurrence of the close delimiter, then verifies everything after it is whitespace. A forward search would produce wrong results for input like `$$a$$b$$`. — `ChatMarkdownBlockSegmenter.swift:295-300`

**major** — The spec (§5.2) says math scanning skips lines inside inline code. The source applies a double gate: lines must be top-level `Markdown.Paragraph` children AND not in `inlineCodeLines`. The paragraph requirement is never described; the spec only mentions "not inside inline code". — `ChatMarkdownBlockSegmenter.swift:155-178`

**minor** — The spec (§5.2 math delimiter recognition) says indent ≤ 3 spaces before the delimiter. The source counts only ASCII space characters, not tabs. Also, close-line detection trims whitespace before comparing to the close string; the spec says "close on its own line" without specifying this trim. — `ChatMarkdownBlockSegmenter.swift:303-305`

**major** — The spec (§5.2, table extraction) states "incomplete tables (trailing lines are all blank and `isComplete == false`) are skipped". The source checks `source.lines[tableRange.upperBound...]` — lines AFTER the table range, not lines within it. A rebuilder checking inside the range would implement wrong behavior. — `ChatMarkdownBlockSegmenter.swift:109-114`

**minor** — The spec (§5.3) says extractions whose `lowerBound` is "before `proseStart`" are skipped. The loop condition is `>= proseStart`, so an extraction starting AT `proseStart` is included. The spec wording is technically correct but could mislead a rebuilder to skip the equality case. — `ChatMarkdownBlockSegmenter.swift:134`

**major** — The spec (§6.2) describes the streaming path but omits that `plainText` is only populated when `preparesReveal == true`. In the non-streaming, non-`preparesReveal` path, `plainText` is set to `""`, not the attributed string characters. A rebuilder expecting `plainText` to always hold visible text would be wrong. — `ChatMarkdownRenderer.swift:207-208`

**minor** — The spec (§6.2) correctly describes the `makeInlineContent` / `attributed` paths but omits the guarantee that `attributed` is always set in the initializer, and that `renderedText` guards on `inlineContent` before returning `SwiftUI.Text(self.attributed)`. This flow is implicitly correct but could confuse a rebuilder. — `ChatMarkdownRenderer.swift:200-205`

**minor** — The spec (§6.3) describes `ChatMarkdownDisplayPreprocessor` but omits the fast-path early return in `codeLineIndices`: if the markdown contains none of ` ``` `, `~~~`, a leading four-space indent, or `\n    `, it returns `Set<Int>()` without parsing. This is a correctness boundary for content that happens to contain those patterns. — `ChatMarkdownRenderer.swift:485-491`

**minor** — The spec (§7.2) says the prose block receives `.modifier(ChatInlineMathAccessibilityModifier)`. The actual source passes `prose.inlineAccessibilityText` to the modifier. Additionally, the spec says the label is "markdown text portions joined with LaTeX source", but the implementation joins plain-text attributed-string characters for prose portions — not raw markdown. — `ChatMarkdownRenderer.swift:237-247`

**major** — The spec (§9.1) does not document the full-editor inner field `VStack`. The `fullEditor` wraps the editor overlay, a divider, and an `HStack` (talk/connection/send) in a `VStack(spacing: 8)` with its own `RoundedRectangle(cornerRadius: 14)` background, separate from the outer composer container. The spec (§16.2) describes the top-level `VStack` but not this inner container or its padding (horizontal 10, vertical 8). — `ChatComposer.swift:503-532`

**major** — The spec (§16.3) states `cleanEditor` outer `HStack` padding is `padding(.vertical, cleanEditorTextPadding = 10)` on the editor surface. The actual clean-editor `HStack` carries `.padding(.horizontal, 14).padding(.vertical, 4)` at the `VStack` level; the 10 pt `cleanEditorTextPadding` is applied on the `editorOverlay` inside the pill surface. The spec conflates these two padding layers. — `ChatComposer.swift:534-570`

**minor** — The spec (§16.3) states `cleanEditorMinHeight = max(44, textMinHeight + 10 * 2)` and mentions `cleanEditorCornerRadius = cleanEditorMinHeight / 2`. The formula is correct, but the spec does not note that because `textMinHeight` can vary with Dynamic Type, `cleanEditorCornerRadius` also changes dynamically. — `ChatComposer.swift:1104-1110`

**minor** — The spec (§16.5) says the clean trailing control shows `compactTalkButton` under certain conditions. The spec does not note that the `.frame(width: cleanControlHeight, height: cleanControlHeight)` modifier is applied only on the `sendButton` path, not on the `compactTalkButton` path. — `ChatComposer.swift:575-582`

**minor** — The spec (§16.6) says iOS `TextField` has `.padding(.horizontal, 0)` (`cleanFieldTextInset = 0`). The actual vertical padding is conditional: 0 for `.clean` chrome, 6 for full chrome. The spec documents only the clean-path value and does not mention the full-chrome difference. — `ChatComposer.swift:743-744`

**minor** — The spec (§16.8, Send button) says the stop button fill uses `OpenClawChatTheme.danger (system red)`. The source constructs the visual button differently from the spec description. The stop-button fill color derivation does not simply reference a static `danger` token. — `ChatComposer.swift` (stop-button section)

## Verdict

NEEDS-REPAIR — 10 blocking major defects.
