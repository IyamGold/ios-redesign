# Audit — 04-drawer.md

## Scorecard

| metric | value |
|---|---|
| precision | 0.973 |
| recall | 0.825 |
| F | 0.893 |
| critical | 1 |
| major | 6 |
| minor | 4 |
| certified | false |
| claims | 50 |

## Defects (fix these)

**Wrong/Unsupported Claims**

- major — Doc section 11 states compose button hit area is `frame(width: 40, height: 40)` — actual frame is `.frame(width: 34, height: 34)` (line 249), not 40×40 — `Sources/Design/ChatDrawer.swift:233-264`

**Omissions**

- critical — Doc section 11 states compose button hit area `frame(width: 40, height: 40)`; actual code line 249 is `.frame(width: 34, height: 34)`. The value is materially wrong by 6 pt on each axis — `Sources/Design/ChatDrawer.swift:249`

- major — `drawerHeader` applies `.padding(.leading, 14)` and `.padding(.trailing, 8)` (lines 262-263) before the container in `drawerContent` adds another `.padding(.leading, 8)` and `.padding(.trailing, trailingInset)` (lines 340-341). The effective leading inset of the header HStack content from the ScrollView edge is 8+14=22 pt. Doc section 11 states "Header leading padding: 8 pt" without accounting for the header's own 14 pt internal leading padding — `Sources/Design/ChatDrawer.swift:262-263`

- major — The header's own `.padding(.trailing, 8)` (line 263) is not mentioned anywhere in the doc. This gives the compose button a fixed 8 pt trailing gap from the header's right boundary, separate from the container's `trailingInset` padding — `Sources/Design/ChatDrawer.swift:263`

- major — The compose `Button` inside `drawerHeader` applies `.buttonStyle(.plain)` (line 259). Doc section 11 omits this; a rebuilder's version would show the default system button press highlight — `Sources/Design/ChatDrawer.swift:259`

- major — In the closed state when `openSwipeEngaged == true`, `dragOffset` is clamped to `max(0, value.translation.width)` (line 162). Doc section 8 describes only that "Any drag accumulates into dragOffset" for the open state and omits the `max(0,…)` floor clamp for the closed state, which prevents the chat from sliding left past x=0 — `Sources/Design/ChatDrawer.swift:162`

- major — `drawerContent` applies `.frame(maxHeight: .infinity, alignment: .top)` (line 344) and `.ignoresSafeArea(edges: .top)` (line 345) on the outer ZStack. Both modifiers are absent from the doc's layout description; they are required for content to fill the full height and extend under the notch — `Sources/Design/ChatDrawer.swift:344-345`

- minor — The content VStack inside the ScrollView has `.frame(maxWidth: .infinity, alignment: .leading)` (line 322). The doc does not mention this modifier, which is needed for the VStack to fill horizontal space and left-align within the scroll container — `Sources/Design/ChatDrawer.swift:322`

- minor — The outer `HStack` of `drawerHeader` has no explicit `spacing:` parameter (line 234), relying on SwiftUI's default spacing. Doc section 11 does not call this out; a rebuilder who sets a specific spacing value would get a different layout between the title and compose button — `Sources/Design/ChatDrawer.swift:234`

- minor — The rename alert uses a computed `Binding<Bool>` (lines 346-351) derived from `renameTargetID != nil`, not a simple `@State Bool`. Doc section 15 describes the logical flow but does not note this implementation detail; a rebuilder would naturally reach for a plain `@State` flag and get different behavior — `Sources/Design/ChatDrawer.swift:346-351`

- minor — The Main session's `sessionRow` is called with `pinnable: false`, which suppresses both the pin indicator and the pin/unpin context-menu item, but the Rename context-menu item is always present outside the `if pinnable` block. Doc section 15 correctly states rename stays available for Main but does not explicitly say Main still shows a Rename option in its context menu; a rebuilder skimming the section might drop the context menu from Main entirely — `Sources/Design/ChatDrawer.swift:407-413`

## Verdict

NEEDS-REPAIR — 7 blocking defects (1 critical + 6 major).
