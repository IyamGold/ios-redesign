# Audit — 06-destinations-files-skills-canvas.md

## Scorecard

| metric | value |
|---|---|
| precision | 0.992 |
| recall | 0.846 |
| F | 0.913 |
| critical | 0 |
| major | 6 |
| minor | 4 |
| certified | false |
| claims | 63 |

## Defects (fix these)

**major** — Doc §1.3 mentions `lineLimit(1)` on the centered header title but omits the `frame(maxWidth: 200)` constraint entirely. Without it the title can overlap the leading/trailing nav buttons on long folder names. — `Sources/Design/FilesGridScreen.swift:65`

**major** — Doc §2.4 describes the tile anatomy but omits `.contentShape(Rectangle())` wrapping the tile button's VStack label. Without it the empty-padding area of each tile is a dead zone for taps. — `Sources/Design/FilesGridScreen.swift:165`

**major** — Doc §4.4 describes the skill row label block and button but omits `.contentShape(Rectangle())` on the open-skill button label. Without it tapping empty space inside the row HStack does not fire. — `Sources/Design/SkillsScreen.swift:133`

**major** — Doc §3 describes the `ProgressView`/count display in `AgentWorkspaceDirectoryList`'s load-more row but omits `.disabled(self.loadingMore)` on that row, which prevents duplicate load calls while a fetch is in flight. — `Sources/Design/AgentWorkspaceFilesScreen.swift:146`

**major** — Doc §5.7 describes the archive row structure but omits `.contentShape(Rectangle())` on the row button label in `CanvasArchiveScreen`. Without it tapping empty space inside the row does not fire. — `Sources/Design/CanvasArtifacts.swift:332`

**major** — Doc §5.7 describes the live-filter behavior of `CanvasArchiveScreen` but never explains that `CanvasEmbedIndex.shared` is held via `@State private var index = CanvasEmbedIndex.shared`. That `@State` wrapping is what wires `@Observable` reactivity so the archive re-renders when embeds change; omitting this makes the mechanism unexplained and non-reproducible. — `Sources/Design/CanvasArtifacts.swift:266`

**minor** — Doc §1.3 claims all screens apply `lineLimit(1)` to the centered header title, but `SkillsScreen`'s `Text("Skills")` header has neither `lineLimit(1)` nor `frame(maxWidth:)`. — `Sources/Design/SkillsScreen.swift:66-67`

**minor** — Doc §3 describes the icon and label in `AgentWorkspaceDirectoryList` rows but omits the `frame(width: 24)` constraint on the row icon and the HStack spacing of 12 pt. — `Sources/Design/AgentWorkspaceFilesScreen.swift:108-112`

**minor** — Doc §4.4 says the enable/disable toggle is on the right of the skill row but does not mention the `Spacer(minLength: 0)` between the tappable left area and the toggle that pushes it to the trailing edge. — `Sources/Design/SkillsScreen.swift:137`

**minor** — Doc nowhere mentions `Spacer(minLength: 40)` appended after the install-button block in `SkillPanelSheet`'s scroll content. Without it the last card can be obscured by the sheet's home indicator. — `Sources/Design/SkillsScreen.swift:407`

## Verdict

NEEDS-REPAIR — 6 blocking major defects.
