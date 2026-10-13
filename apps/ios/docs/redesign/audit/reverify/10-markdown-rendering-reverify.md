# Re-verify — 10-markdown-rendering.md

## Scorecard

| metric | value |
|---|---|
| originalDefectCount | 10 |
| resolvedCount | 10 |
| unresolved | 0 |
| newErrors | 0 |
| remainingOmissions | 2 (minor) |

---

## Unresolved Defects

None.

---

## New Errors Introduced by Repair

None found. All sampled new content was verified against source.

---

## Remaining Omissions (minor only)

**minor** — §5.2 says `inlineCodeLines` is "collected recursively from every `Markdown.InlineCode` node" but omits that `collectInlineCodeLines` is only called on direct `Markdown.Paragraph` children of the document (not on all document children). Inline code inside list items, blockquotes, etc. is never added to `inlineCodeLines`. (`ChatMarkdownBlockSegmenter.swift:165-170`)

**minor** — §16.6 says "The horizontal inset is `cleanFieldTextInset = 0`" without noting that this applies only to `.clean` chrome; the same property returns `4` for full chrome (`ChatComposer.swift:1136-1138`). The section title scopes it to clean mode but the code sample shows the conditional vertical path, so a rebuilder reading both paths could apply `0` horizontally for full chrome too.

---

## Verdict

CERTIFIED — zero critical or major defects remain across unresolved, newErrors, and remainingOmissions.
