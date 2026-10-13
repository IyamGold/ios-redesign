# OpenClaw iOS Redesign — Replication Spec

This folder is an **English version of the iOS redesign**: a surface-by-surface specification detailed enough that a competent engineer or agent could rebuild the redesigned OpenClaw iPhone/iPad app **1:1 — pixel- and behavior-accurate — without reading the Swift source**.

It documents the work on the `ios-ui-redesign` branch (26 commits over `main`; ~+20k/−5.6k lines, 38 redesigned `Sources/Design` surfaces plus the chat plumbing in `OpenClawKit`). Each document was written by reading the actual code on the branch and recording exact values (fonts, sizes, paddings, hex colors, corner radii, gradient stops, spring/haptic params, thresholds) with `path:line` citations.

## How to use this spec

- **Rebuilding from scratch?** Read in the order of the "How to replicate" checklist below — assets and tokens first, then per-surface.
- **Changing one surface?** Jump straight to its document via the navigation table.
- **Reviewing parity?** The phone and iPad render through *different* live types — see the surface map and `13-ipad.md`.

Think of each doc as the spec for one slice of the app. They are self-contained but cross-reference each other with `[[like-this]]`-style filename mentions.

## Live-surface map (orientation)

The redesign restructured the app; several legacy/shared types still compile and look authoritative but do **not** render the live phone UI. Always trace from the entry point to the surface that actually renders.

| Layer | Who renders it | Doc |
|---|---|---|
| Entry (`@main`) | `OpenClawApp.swift` → `RootTabs.swift` (owns phone-vs-iPad split) | `01-architecture.md` |
| Phone chat | `RootTabs.phoneTabContent` → `ChatProTab` → **`ChatRootSurface`** (redesigned visuals) | `03-chat-surface.md` |
| Chat data/state/transport | shared `OpenClawKit` — `OpenClawChatViewModel` (+ extensions), `IOSGatewayChatTransport` | `09-chat-plumbing-transport.md` |
| Phone navigation | `ChatDrawerHost` → `ChatDrawer` (OneTab side-nav); destinations render as a content switch | `04-drawer.md` |
| Phone drawer destinations | `CronJobsScreen`, `DreamingScreen`, `UsageScreen`, `InstancesScreen`, `FilesGridScreen`/`AgentWorkspaceFilesScreen`, `SkillsScreen`, Canvas archive | `05-`, `06-` |
| Settings (phone) | `PhoneTabSettingsHost` → `SettingsRootScreen` / `SettingsDestinationScreens` | `07-settings.md` |
| Onboarding | `OnboardingWizardView` (NavigationStack of steps) | `08-onboarding.md` |
| iPad | `RootTabs.sidebarDetail` → `AgentProTab(directRoute:)` + `AgentProNodesDestination` / `AgentProDreamingDestination` | `13-ipad.md` |
| Markdown/message rendering | shared `OpenClawChatUI` pipeline (iOS + macOS) | `10-markdown-rendering.md` |
| Voice / Talk | `TalkProTab`, `Sources/Voice/*`, voice-note recorder | `11-voice-audio.md` |
| Connection + device services | `Sources/Gateway/*`, network/location/media/screen/push services | `12-gateway-device-services.md` |

> **Legacy caution:** the `OpenClawChatUI` package's `ChatView` / `ChatMessageViews` / `ChatComposer` / `ChatTheme` are the **legacy/macOS** chat UI. iOS phone bubbles/composer do **not** render through them.

> **Phone/iPad parity:** a phone-drawer change does **not** update the iPad twin, and vice-versa. Change both when parity matters (see `13-ipad.md`).

## Navigation

| # | Document | What it covers |
|---|---|---|
| 01 | [`01-architecture.md`](01-architecture.md) | Entry point → `RootTabs` phone/iPad split, drawer navigation model, session-key semantics, startup/lifecycle. The orientation map. |
| 02 | [`02-design-system.md`](02-design-system.md) | Branded typography (`OpenClawType`), color tokens, glass/material backgrounds, scrim gradients, spacing/radii constants, haptic vocabulary (`OpenClawHaptics`). |
| 03 | [`03-chat-surface.md`](03-chat-surface.md) | `ChatRootSurface`: bubble-less replies, composer, scroll/pin/streaming, tool-use collapse, image viewer, audio, render-correctness fixes. |
| 04 | [`04-drawer.md`](04-drawer.md) | The OneTab side-nav: swipe-to-open, distance-based scale, scrim, Main/Sessions, active pill, rename, cron filtering. |
| 05 | [`05-destinations-automation-usage.md`](05-destinations-automation-usage.md) | Cron Jobs, Dreaming, Usage, Instances destination screens. |
| 06 | [`06-destinations-files-skills-canvas.md`](06-destinations-files-skills-canvas.md) | Files workspace browser, Skills roster, Canvas archive. |
| 07 | [`07-settings.md`](07-settings.md) | Settings root + all destinations (Approvals, Permissions, Notifications, Channels, Voice, Wake Words, Licenses), Connection sheet. |
| 08 | [`08-onboarding.md`](08-onboarding.md) | Welcome → QR/manual setup → feedback/connection state machine → success. |
| 09 | [`09-chat-plumbing-transport.md`](09-chat-plumbing-transport.md) | Gateway RPCs, `OpenClawChatViewModel` lifecycle, history reconciliation, dedupe/seq ordering, derived titles, thinking-level rule. |
| 10 | [`10-markdown-rendering.md`](10-markdown-rendering.md) | Shared markdown pipeline: preprocess → segment → render, code highlighting, inline math, streaming reveal, composer, sheets. |
| 11 | [`11-voice-audio.md`](11-voice-audio.md) | Talk mode (WebRTC + relay), permission prompt, wake words, voice-note recorder/waveform, on-device transcription. |
| 12 | [`12-gateway-device-services.md`](12-gateway-device-services.md) | Discovery, trust/auth, WebSocket connect, health, Keychain, TCP/TLS probes, device-capability services. |
| 13 | [`13-ipad.md`](13-ipad.md) | iPad sidebar/detail twins and the phone-parity map. |
| 14 | [`14-assets-glyphs.md`](14-assets-glyphs.md) | Every imageset → source artwork filename → consuming Swift surface. |

## How to replicate (recommended order)

1. **Assets & fonts first.** Source every glyph in `14-assets-glyphs.md` (most are Lucide, `li_` prefix) and register each under the same asset-catalog name. Bundle the branded fonts (see `02-design-system.md` and `apps/ios/THIRD_PARTY_FONTS.md`).
2. **Design tokens.** Build the `OpenClawType` typography scale, color tokens, glass backgrounds, scrims, radii, and the `OpenClawHaptics` vocabulary from `02-design-system.md`. Everything downstream depends on these.
3. **App shell & navigation.** Stand up `OpenClawApp` → `RootTabs` with the phone/iPad split and the drawer host (`01-architecture.md`, `04-drawer.md`).
4. **Chat surface + plumbing.** Build `ChatRootSurface` (`03-`) over the `OpenClawChatViewModel`/transport layer (`09-`) and the markdown pipeline (`10-`).
5. **Destinations & settings.** Implement the drawer destinations (`05-`, `06-`) and Settings (`07-`).
6. **Onboarding, voice, services.** `08-`, `11-`, `12-`.
7. **iPad twins.** `13-` — mirror each phone destination into its sidebar/detail form.

## Asset & protocol regeneration (do not hand-author)

- **Glyphs/assets** live in `apps/ios/Sources/Assets.xcassets/*.imageset/`. See `14-assets-glyphs.md` for the full inventory and source filenames.
- **Protocol models** (`apps/shared/OpenClawKit/Sources/OpenClawProtocol/GatewayModels.swift`) are **generated** via `pnpm protocol:gen:swift` (drift-guarded by `pnpm protocol:check`). Never hand-edit them.
- **Licenses** are discovered at runtime from `apps/ios/Resources/Licenses/` (UTF-8 `.txt` only) by `LicenseDocumentLoader`; rows are not hardcoded. See `07-settings.md`.
- **Fonts** bundled under `apps/ios/Sources/Fonts/` must be recorded with upstream source + SHA-256 in `apps/ios/THIRD_PARTY_FONTS.md`.

## Commit ledger (`main..ios-ui-redesign`, newest first)

### Chat surface & plumbing
| SHA | Delivered |
|---|---|
| `a2463ed718` | Render chat history on cold start/foreground; cap cron subtitles at 3 lines |
| `3559f616f6` | Dedupe consecutive chat replies; order by gateway seq |
| `5c8b059489` | Taller composer; block drawer drag from Settings |
| `a4cff546df` | Keep composer talk/waveform button always visible |
| `7b33d14826` | Online presence dot on chat avatar |
| `810d7ab3c8` | Rich audio/file rendering, image viewer, on-device voice transcription |
| `ffbb300a56` | Fix chat reply glitches and scroll churn |
| `693dbba781` | Two-phase reply haptics; composer remove-button fixes |
| `bf9ab66cb9` | Chat root surface — attachments, code blocks, bubble-less replies |

### Drawer & destinations
| SHA | Delivered |
|---|---|
| `6c66f36363` | Scrollable drawer with live sessions, titles, rename, open animation |
| `b7aae00d34` | Drawer items as opaque peer tabs (chevron + open haptic) |
| `70891d75d3` | Full-width swipe to open chat drawer; swipe-back in settings |
| `915aa94d18` | Drawer destination screens; chat markdown/scroll/settings polish |
| `0a729874ec` | Render canvas as reopenable chat cards + Canvas archive |
| `9544b116c5` | Chat drawer (side-nav) with Files/Canvas/agent destinations |

### Settings
| SHA | Delivered |
|---|---|
| `81ed0efed1` | Voice, Wake Words, and Licenses settings destinations |
| `156a4daac9` | Redesign Approvals, Permissions, Notifications, Channels |
| `1374f578c7` | Connection sheet + Settings root polish |
| `0d4f4db948` | Redesign Settings root screen |

### Onboarding & foundation
| SHA | Delivered |
|---|---|
| `d164fba98f` | Dedicated Permissions camera/mic glyphs |
| `701e1c115a` | Drop removed `statusLine` arg from onboarding welcome smoke test |
| `752fb43200` | Haptics helper with core-haptics patterns; wire into onboarding |
| `7551412f19` | Feedback state glyphs |
| `0d586fd3c1` | Merge connect/auth into feedback step with state machine; new success screen |
| `4290439d05` | Onboarding welcome step |
| `79cd41709b` | SwiftFormat + SwiftLint; split `ChatViewModel` pending-run timeout |

## Known gaps / caveats

Prose can describe structure, tokens, and behavior exactly, but a few things are inherently out of reach and must be sourced from the repo itself:

- **Binary assets** — the SVG/PNG glyphs and bundled fonts are inventoried (name, source filename, usage) in `14-assets-glyphs.md`, not reproduced. Source equivalents from Lucide / the noted originals.
- **Generated protocol models** — see the regeneration note above; describe the contract, don't transcribe the generated Swift.
- **Figma pixel nuance** — where a value is in code it's recorded verbatim; any purely visual nuance not expressed as a constant (e.g. hand-tuned asset interiors) lives in the artwork.
- **Verification pass pending** — the automated cross-check-against-code audit did not complete in the generation run. These docs are faithful transcriptions by surface readers but have not yet been adversarially verified line-by-line against the source. A sharded audit (one agent per doc) can be run to flag any missing exact values or drift before this is treated as authoritative.
