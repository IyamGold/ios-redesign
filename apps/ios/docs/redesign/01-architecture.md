# App Architecture & Navigation

This document is the orientation map for the OpenClaw iOS redesign. It covers every layer from the `@main` entry point down to individual surface types, the phone-vs-iPad split, the chat drawer navigation model, session key semantics, and the startup/lifecycle machinery. A competent engineer should be able to reconstruct the entire navigation skeleton from this document without consulting the source.

---

## 1. Entry Point — `OpenClawApp`

**File:** `Sources/OpenClawApp.swift:666`

`OpenClawApp` is the `@main` struct conforming to `App`. It owns three top-level `@State` objects that are injected into the environment for the entire view tree:

| State property | Type | Purpose |
|---|---|---|
| `appearanceModel` | `AppAppearanceModel` | Color scheme preference; drives `.preferredColorScheme` |
| `appModel` | `NodeAppModel` | Central gateway/chat/agent model; the single source of truth for all data |
| `gatewayController` | `GatewayConnectionController` | Gateway discovery, connection, and reconnection |

### Init sequence (`OpenClawApp.init`)

1. `Self.installUncaughtExceptionLogger()` — registers an `NSSetUncaughtExceptionHandler` that logs NSExceptions (SwiftUI/WebKit can throw these without a Swift backtrace). `Sources/OpenClawApp.swift:673`
2. `GatewaySettingsStore.bootstrapPersistence()` — bootstraps persistent gateway config storage before any view renders.
3. `OpenClawType.installUIKitAppearance()` — installs branded UIKit font appearance globally (affects `UILabel`, `UIButton`, etc. outside SwiftUI).
4. `NodeAppModel()` — constructs the central model.
5. `OpenClawAppModelRegistry.appModel = appModel` — stores a weak-accessible registry copy for the app delegate (which may receive APNs events before the scene has installed the model ref).
6. `GatewayConnectionController(appModel:startDiscovery:deferDiscoveryUntilLocalNetworkRequest:)` — `startDiscovery` is `!Self.screenshotModeEnabled`; `deferDiscoveryUntilLocalNetworkRequest` is always `true`. `Sources/OpenClawApp.swift:699`

### `body` — `WindowGroup` environment chain

```
WindowGroup {
    RootTabs()
        .tint(OpenClawBrand.accent)
        .font(OpenClawType.body)
        .environment(appearanceModel)
        .preferredColorScheme(appearanceModel.preference.colorScheme)
        .environment(appModel)
        .environment(appModel.voiceWake)
        .environment(gatewayController)
}
```

`Sources/OpenClawApp.swift:706`

Every downstream view reads `NodeAppModel`, `VoiceWakeManager`, `GatewayConnectionController`, and `AppAppearanceModel` from the environment. The `.tint` and `.font` modifiers set the app-wide accent color (`OpenClawBrand.accent`) and base body font (`OpenClawType.body`).

### Window tint

`applyWindowTint()` calls `window.tintColor = OpenClawBrand.uiAccent` on every connected `UIWindowScene` window. It runs on `.task` (initial layout) and on every `scenePhase` change. `Sources/OpenClawApp.swift:757`

### Scene phase bridging

`onChange(of: scenePhase)` propagates the new phase to:
- `appModel.setScenePhase(_:)`
- `gatewayController.setScenePhase(_:)`
- `appDelegate.scenePhaseChanged(_:)` — which schedules a `BGAppRefreshTask` when entering background.

### Debug / screenshot modes

| Launch argument | Effect |
|---|---|
| `--openclaw-reset-onboarding` | Calls `GatewayOnboardingReset.resetBeforeStartup` before the model is registered |
| `--openclaw-screenshot-mode` | Disables animations, pre-seeds `UserDefaults` onboarding flags, calls `appModel.enterScreenshotFixtureMode()` |
| `--openclaw-screenshot-notification-guidance` | Additionally calls `appModel._debug_presentNotificationPermissionGuidancePromptForScreenshot()` |

---

## 2. App Delegate — `OpenClawAppDelegate`

**File:** `Sources/OpenClawApp.swift:25`

`OpenClawAppDelegate` is a `UIApplicationDelegate` + `UNUserNotificationCenterDelegate` wired via `@UIApplicationDelegateAdaptor`. It holds a `weak var appModel: NodeAppModel?` and a fallback to `OpenClawAppModelRegistry.appModel` so it can handle events that arrive before or after the SwiftUI scene installs the model.

### Pending-event queues

When `appModel` is `nil` at event time, the delegate queues events in these arrays and drains them as soon as `appModel` is assigned (via the `didSet` observer):

| Queue | Type | Drains to |
|---|---|---|
| `pendingAPNsDeviceToken` | `Data?` | `appModel.updateAPNsDeviceToken(_:)` |
| `pendingWatchPromptActions` | `[PendingWatchPromptAction]` | `appModel.handleMirroredWatchPromptAction(...)` |
| `pendingExecApprovalPrompts` | `[PendingExecApprovalPrompt]` | `appModel.presentExecApprovalNotificationPrompt(_:)` |
| `pendingExecApprovalRequestedPushes` | `[ExecApprovalNotificationPrompt]` | `appModel.handleExecApprovalRequestedRemotePush(_:)` |
| `pendingExecApprovalResolvedPushes` | `[ExecApprovalNotificationPrompt]` | `appModel.handleExecApprovalResolvedRemotePush(_:)` |
| `pendingOpenURLs` | `[URL]` | `handleOpenURL(_:model:)` |

### Background wake

- **Registration:** `BGAppRefreshTask` registered with identifier `<bundleId>.bgrefresh` in `registerBackgroundWakeRefreshTask()`.
- **Scheduling:** On scene background, schedules with `earliestBeginDate = Date() + max(60, 120)` seconds. On task expiry, reschedules at `max(60, 15 * 60)` seconds.
- **Handler:** `appModel.handleBackgroundRefreshWake(trigger:)`.

### URL handling

`application(_:open:options:)` and `onOpenURL` both funnel into `handleOpenURL(_:model:)`, which calls `DeepLinkParser.parse(_:)` and routes:
- `.agent` / `.dashboard` → `appModel.handleDeepLink(url:)`
- `.gateway` → `appModel.stageGatewaySetupLink(_:)`

`Sources/OpenClawApp.swift:160`

---

## 3. Root Layout — `RootTabs`

**File:** `Sources/RootTabs.swift:7`

`RootTabs` is the single view rendered in the `WindowGroup`. It owns the phone-vs-iPad split, all top-level state, and all global overlays.

### Idiom detection

```swift
static func shouldUseSidebarTabs(
    idiom: UIUserInterfaceIdiom,
    horizontalSizeClass _: UserInterfaceSizeClass?) -> Bool
{
    idiom == .pad
}
```

`Sources/RootTabs.swift:150` — iPad uses the sidebar/split layout; every other idiom (phone, Mac Catalyst, etc.) uses the phone drawer layout. The idiom is read from `UIDevice.current.userInterfaceIdiom` but can be overridden via the `\.rootTabsUserInterfaceIdiomOverride` environment key (used in Previews). `Sources/RootTabs.swift:758`

### Body composition

```
body
  └─ rootPresentation(
       rootLifecycle(
         rootOverlays(
           tabContent
             .tint(OpenClawBrand.accent))))
```

`tabContent` switches between `phoneTabContent` (phone) and `sidebarSplitContent` (iPad). `Sources/RootTabs.swift:157`

---

## 4. Phone Layout — `phoneTabContent`

**File:** `Sources/RootTabs.swift:174`

The phone layout is a single-panel surface. There are no bottom tabs and no separate tab bar. Navigation happens through a side drawer.

### View hierarchy

```
ChatDrawerHost(isOpen:, sessions:, allowsOpen:, onSelectDestination:,
               onSelectSession:, onNewSession:, onRenameSession:,
               activeSessionID:, activeDestination:, mainSessionID:)
  └─ chatContent (trailing closure = the "panel" content):
       ZStack {
         PhoneTabSettingsHost(resetRequestID:, onOpenConnection:,
                              pendingRoute:, isPresentingSettings:) {
           ChatProTab(headerLeadingAction:, ownsNavigationStack: false,
                      openSettings:, onOpenDrawer:)
         }
         .opacity(activeDrawerDestination == nil ? 1 : 0)
         .allowsHitTesting(activeDrawerDestination == nil)

         if let destination = activeDrawerDestination {
           drawerDestinationScreen(destination)
         }
       }
```

`Sources/RootTabs.swift:175`

#### Critical layout invariant: peer tabs, not overlays

The chat and every drawer destination are **ZStack siblings**, not overlays on top of the chat. The chat stays mounted but hidden (`opacity: 0`, `allowsHitTesting: false`) while a destination is active. This prevents the chat from bleeding through a destination, and avoids tearing down the chat view model / gateway connection on every tab switch. `Sources/RootTabs.swift:207`

#### Settings embedding

`PhoneTabSettingsHost` wraps `ChatProTab` in a `NavigationStack` so Settings screens push onto the same stack as the chat, with a swipe-to-go-back gesture that matches the drawer's direction. While any settings route is pushed, `isPhoneSettingsPresented` is `true` and `ChatDrawerHost.allowsOpen` is `false` — the drawer cannot be dragged open while Settings is on top. `Sources/RootTabs.swift:178`

#### Drawer open animation

```swift
withAnimation(.spring(duration: 0.35)) { self.isChatDrawerOpen = true }
```

`Sources/RootTabs.swift:225`

#### New chat key format

```swift
let key = "mobile-\(UUID().uuidString.prefix(8).lowercased())"
```

`Sources/RootTabs.swift:191` — The gateway materializes the room lazily on the first message; an abandoned empty chat costs nothing.

---

## 5. Chat Drawer — `ChatDrawerHost`

**File:** `Sources/Design/ChatDrawer.swift:16`

The chat drawer is the sole navigation mechanism on phone. It slides the chat panel right to reveal a list of destinations and sessions, then slides back on selection.

### Geometry constants

| Constant | Value | Notes |
|---|---|---|
| `openOffset` | `305 pt` (capped at `proxy.size.width * 0.78`) | How far right the panel slides when open |
| `panelRadius` | `50 pt` | Chat panel corner radius when open |
| `headerReserve` | `62 pt` | Space below notch reserved for the "OpenClaw" header |
| `scaleBleed` | `90 pt` | Extension below screen bottom to keep ScrollView clip off-screen at max scale |

`Sources/Design/ChatDrawer.swift:52`

### Scale animation

The drawer panel (the chat) **recedes as the drawer opens**, not by opacity but by scale:

- Scale = `0.95 + 0.05 * slideProgress`
- Anchored `topLeading` so the header never moves; only the bottom/right edges inset.
- A **static full-bleed backdrop** (same color as the drawer canvas) sits behind the scaled panel and fills any collapsed edge-bleed that `ignoresSafeArea` children produce under a scale transform.

`Sources/Design/ChatDrawer.swift:62`

### Drawer canvas color

| Scheme | Color |
|---|---|
| Dark | `rgb(23, 23, 23)` — `Color(red: 23/255, green: 23/255, blue: 23/255)` |
| Light | `rgb(245, 244, 250)` — `Color(red: 245/255, green: 244/255, blue: 250/255)` |

`Sources/Design/ChatDrawer.swift:185`

### Chat panel presentation

- **Blur when open:** `.blur(radius: isOpen ? 0.6 : 0)` — keeps the panel opaque (nothing behind it shows through) while reading as inactive. Opacity was not used because it made destinations bleed through.
- **Interaction gate:** `.allowsHitTesting(!isOpen)` — prevents taps on the chat while the drawer is open.
- **Tap-to-close scrim:** `Color.black.opacity(0.001)` with `.contentShape(Rectangle()).onTapGesture { close() }` — invisible but hittable; tapping the receded chat panel closes the drawer.
- **Drop shadow:** `shadow(color: .black.opacity(0.25), radius: 15, x: -5, y: 0)` — always on, even when the drawer is closed, so the shadow appears throughout the slide rather than fading in at rest. `Sources/Design/ChatDrawer.swift:118`
- **Mask:** `RoundedRectangle(cornerRadius: isOpen ? 50 : 0, style: .continuous).ignoresSafeArea()` — clips the panel to the full screen when closed, rounded when open. `Sources/Design/ChatDrawer.swift:111`

### Drag gesture

`panelDrag` is a `.simultaneousGesture(DragGesture(minimumDistance: 12))` so it coexists with the transcript's vertical scroll. `Sources/Design/ChatDrawer.swift:150`

- **Closed state:** on first movement, latches `openSwipeEngaged` as `true` only if `translation.width > 0 && abs(width) > abs(height)` (rightward and horizontally dominant). If latched `true`, tracks `dragOffset = max(0, translation.width)`.
- **Open state:** tracks `dragOffset = translation.width` directly (closes on a leftward drag).
- **Release:** computes `projected = base + predictedEndTranslation.width`; commits open/close based on `projected > open / 2`. Animates with `.spring(duration: 0.35)`.
- **Gate:** `allowsOpen` must be `true` (set `false` when Settings is presented) for the closed-state open path.

### Haptic on open/close

```swift
.onChange(of: self.isOpen) { _, _ in OpenClawHaptics.click() }
```

`Sources/Design/ChatDrawer.swift:132` — A "crisp minimal click" fires on every open and close, including tab switches (because selecting a destination closes the drawer).

### Drawer header

- Title: `Text("OpenClaw")` with `.system(size: 25.6, weight: .semibold)`, `foregroundStyle(.primary)`.
- New-chat button: image asset `ChatPlusGlyph`, 20×20 pt, inside a 34×34 pt hit target with `ChatGlassBackground(shape: Circle())`.
  - Dark glass fill: `Color(red: 30/255, green: 30/255, blue: 30/255).opacity(0.2)`
  - Light glass fill: `Color(red: 245/255, green: 244/255, blue: 250/255).opacity(0.2)`
  - Shadow: `color: .black.opacity(0.15), radius: 25, x: 0, y: 0`
- Header padding: `.leading(14)`, `.trailing(8)`, `.top(topInset + 8)`. `Sources/Design/ChatDrawer.swift:233`

### Top scrim

A frosted blur band (`.ultraThinMaterial`) at the top of the drawer content list. Height = `topInset + headerReserve`. In dark mode, overlaid with `drawerCanvas.opacity(0.72)` to tint toward the near-black canvas. Masked by a `LinearGradient` with stops:
- `0.0` → `black.opacity(0.6)`
- `0.55` → `black.opacity(0.6)`
- `1.0` → `.clear`

`Sources/Design/ChatDrawer.swift:210`

### Drawer destination rows

Each destination row is a `Button` with:
- Icon: custom image asset (22×22 pt), `renderingMode(.template)`, opacity `0.9`.
- Label: `.system(size: 17.13)`, `foregroundStyle(.primary)`.
- Leading padding: `14 pt` (so the active pill fills from the ScrollView edge).
- Active highlight: `RoundedRectangle(cornerRadius: 10, style: .continuous)`, height `32 pt`, fill `Color.black` (dark) or `Color.white` (light), `opacity(isActive ? 1 : 0)`.

`Sources/Design/ChatDrawer.swift:426`

### Drawer destination list (order)

```
Dreaming        ("DrawerMoonStarGlyph")
Usage           ("DrawerPieChartGlyph")
Instances       ("DrawerServerGlyph")
Cron Jobs       ("DrawerClockGlyph")
Files           ("DrawerFilesGlyph")
Canvas          ("DrawerPaletteGlyph")
Skills          ("DrawerScrollGlyph")
```

`Sources/Design/ChatDrawer.swift:274` — Row-to-row spacing within each `VStack`: `23 pt` for destinations, `22 pt` for session rows.

### Session sections

1. **"Main" section** — `padding(.top, 32)` from the destination list. Header label: `Text("Main")`, `.system(size: 15)`, `foregroundStyle(.primary.opacity(0.6))`, `padding(.leading, 14)`. One row for `mainSessionID`. Not pinnable.
2. **"Sessions" section** — `padding(.top, 32)` from the Main section. Header label: `Text("Sessions")`, same style. Lists `recentSessions` (all sessions except the main session), ordered by `ChatSessionPrefs.shared.ordered(_:)` (pinned items float to top).

`Sources/Design/ChatDrawer.swift:299`

### Session rows

Same structure as destination rows. Tapping selects the session and closes the drawer. Context menu:
- "Rename" — opens a system `alert` with a `TextField` pre-filled with the current title.
- "Pin" / "Unpin" (if `pinnable`) — toggles `prefs.togglePin(id)`.

The active row highlights only when no destination is active (`activeDestination == nil && id == activeSessionID`). `Sources/Design/ChatDrawer.swift:405`

### `ChatDrawerDestination` enum

`Sources/Design/ChatDrawer.swift:3`

```swift
enum ChatDrawerDestination: Hashable, Identifiable {
    case dreaming, usage, instances, cron, files, canvas, skills
}
```

### `ChatDrawerSession` struct

```swift
struct ChatDrawerSession: Identifiable, Equatable {
    let id: String    // session key as it appears in the gateway list
    let title: String // human display title (never a raw key)
}
```

`Sources/Design/ChatDrawer.swift:11`

---

## 6. Drawer Destination Routing — `drawerDestinationScreen`

**File:** `Sources/RootTabs.swift:357`

When `activeDrawerDestination` is set, `RootTabs.drawerDestinationScreen(_:)` instantiates the matching screen:

| `ChatDrawerDestination` | Screen type | Owns its own header/close? |
|---|---|---|
| `.canvas` | `CanvasArchiveScreen(onClose:, onOpenEmbed:)` | Yes — excluded from shared `DrawerCloseButton` |
| `.dreaming` | `DreamingScreenHost(onClose:)` | Yes |
| `.usage` | `UsageScreenHost(onClose:)` | Yes |
| `.instances` | `InstancesScreenHost(onClose:)` | Yes |
| `.cron` | `CronJobsScreenHost(onClose:)` | Yes |
| `.files` | `FilesWorkspaceScreenHost(onClose:)` | Yes |
| `.skills` | `SkillsScreenHost(onClose:)` | Yes |

All `onClose` callbacks call `withAnimation(.spring(duration: 0.35)) { self.isChatDrawerOpen = true }` to reopen the drawer (acting as the "back to drawer" affordance). `Sources/RootTabs.swift:361`

#### Shared `DrawerCloseButton`

For destinations that do NOT own their own header, a `DrawerCloseButton` is injected via `.safeAreaInset(edge: .top, alignment: .leading, spacing: 0)`. In the current list, every destination owns its own header/close, so the shared button is inactive for all cases. `Sources/RootTabs.swift:386`

`DrawerCloseButton` spec (`Sources/Design/ChatDrawer.swift:469`):
- Icon: `ChatCloseGlyph` asset, 22×22 pt, inside 40×40 pt hit target with `ChatGlassBackground(shape: Circle())`.
- Glass fill: same dark/light values as the new-chat button.
- Shadow: `color: .black.opacity(0.15), radius: 25, x: 0, y: 0`.
- Position: `.padding(.leading, 25)`, `.padding(.top, 22)`.

#### Canvas embed sheet

When a canvas row is tapped in `CanvasArchiveScreen`, it sets `selectedCanvasEmbed` and the sheet presents:

```swift
.sheet(item: $selectedCanvasEmbed) { embed in
    CanvasEmbedPanel(embed:, canvasHostProvider:, onClose:)
        .presentationCornerRadius(47)
}
```

`Sources/RootTabs.swift:395`

---

## 7. Phone Settings Stack — `PhoneTabSettingsHost`

**File:** `Sources/RootTabs.swift:1603`

`PhoneTabSettingsHost` wraps the chat content in a `NavigationStack(path: $settingsPath)`. Settings screens push onto this stack so "Back" returns to the chat (not a separate tab). `Sources/RootTabs.swift:1632`

### Route → screen mapping

| `SettingsRoute` | Screen |
|---|---|
| `.home` | `SettingsRootContainer(onBack:, onOpenRoute:, onOpenConnection:)` — toolbar hidden |
| `.approvals` | `ApprovalsScreen(onBack:)` |
| `.permissions` | `PermissionsScreen(onBack:)` |
| `.notifications` | `NotificationsScreen(onBack:)` |
| `.channels` | `ChannelsScreenHost(onBack:)` |
| `.voice` | `VoiceSettingsScreenHost(onBack:, onOpenWakeWords:)` |
| `.wakeWords` | `WakeWordsScreenHost(onBack:)` |
| `.licenses` | `LicensesScreen(onBack:)` |
| all others | `SettingsProTab(directRoute: route)` — fallback |

`Sources/RootTabs.swift:1641`

### `SwipeToGoBack` modifier

Applied to every pushed settings destination. `Sources/RootTabs.swift:1677`

- `.simultaneousGesture(DragGesture(minimumDistance: 12))` — shares touches with vertical scroll.
- Latches `engaged` on first movement: `true` if `translation.width > 0 && abs(width) > abs(height)`.
- Sets `isActive = true` the moment engaged (suppresses row taps for this gesture's lifetime).
- Commits pop when `translation.width > 80 || predictedEndTranslation.width > 200`.
- Clears `isActive` on the next runloop after `onEnded` so a same-touch row tap still sees the flag set during its own handling.

---

## 8. `ChatProTab` — Chat Surface Host

**File:** `Sources/Design/ChatProTab.swift:5`

`ChatProTab` is the host that connects the chat data layer (`OpenClawChatViewModel`) to the redesigned chat visual (`ChatRootSurface`). It does not render any chrome of its own.

### Init parameters

| Parameter | Type | Default | Notes |
|---|---|---|---|
| `headerLeadingAction` | `OpenClawSidebarHeaderAction?` | `nil` | Passed down to `ChatRootSurface` |
| `headerTitle` | `String?` | `nil` | Overrides the default agent-name title |
| `showsAgentBadge` | `Bool` | `true` | Whether the circular agent badge appears |
| `ownsNavigationStack` | `Bool` | `true` | `false` on phone/iPad (host provides the stack) |
| `openSettings` | `(() -> Void)?` | `nil` | Called when the status pill is tapped |
| `onOpenDrawer` | `(() -> Void)?` | `nil` | Called by `ChatRootSurface` leading button |

`Sources/Design/ChatProTab.swift:35`

### NavigationStack ownership

When `ownsNavigationStack == false`, `ChatProTab` renders `content` directly without wrapping it in a `NavigationStack`, and hides the navigation bar with `.toolbar(.hidden, for: .navigationBar)`. This prevents duplicate chrome in the phone layout where `PhoneTabSettingsHost` already provides the stack. `Sources/Design/ChatProTab.swift:51`

### Talk mode full-screen cover

Tapping the talk control inside `ChatRootSurface` sets `showsTalkMode = true`, which presents:

```swift
.fullScreenCover(isPresented: $showsTalkMode) {
    ZStack(alignment: .topLeading) {
        TalkProTab(ownsNavigationStack: true, openSettings: {}, openVoiceSettings: {})
        Button { showsTalkMode = false } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.primary)
                .frame(width: 40, height: 40)
                .background { Circle().fill(.regularMaterial) }
        }
        .padding(.leading, 14)
    }
}
```

`Sources/Design/ChatProTab.swift:139`

### View model synchronization (`syncChatViewModel`)

The view model is rebuilt (not just synced) when either:
1. `chatViewModelOwnerID` changes — the gateway identity changed; the cached transcript belongs to a different gateway.
2. `transportAgentID` changes — the delivery agent changed.

It is *not* rebuilt if only the session key changes (`viewModel.syncSession(to:)` is called instead). This avoids tearing down the transport/cache while switching sessions on the same gateway.

If `viewModel.isAttachmentOwnerPinned == true` (voice recording in progress), rebuild is deferred until the pin clears. `Sources/Design/ChatProTab.swift:204`

### Haptics

The redesigned phone chat overrides `OpenClawChatHaptics` to suppress `.runCompleted` and `.runFailed` events — the visual reply feedback in `ChatRootSurface` already provides tactile context on answer arrival. `.messageSent` and `.actionConfirmed` still fire. `Sources/Design/ChatProTab.swift:269`

### Undeliverable outbox recovery

If `viewModel.errorText == OpenClawChatTransportUpgradeMessage.routingContract`, the outbox is stuck (the gateway can never replay the queued routing contract, and the FIFO queue blocks all live sends). `ChatProTab` purges the chat transcript cache for that gateway ID so the rebuilt view model starts clean. One-shot guarded by `didRecoverUndeliverableOutbox`. `Sources/Design/ChatProTab.swift:118`

### Agent badge derivation

| Source | Priority |
|---|---|
| `agent.identity["emoji"]` (trimmed, non-empty, non-`?`) | 1st |
| First 2 words' initials, uppercased | 2nd |
| `"OC"` fallback | Last |

`Sources/Design/ChatProTab.swift:514`

### Connection pill

`connectionPill` is an `HStack(spacing: 5)` of a `ProStatusDot` and a text label. Padding: `.horizontal(6)`. Tap opens settings. `Sources/Design/ChatProTab.swift:322`

| Gateway state | Label text | Color |
|---|---|---|
| `.connected` + usable | "Connected" | `OpenClawBrand.ok` |
| `.connected` + not usable | "Unavailable" | `.secondary` |
| `.connecting` | "Connecting" | `OpenClawBrand.accent` |
| `.error` | "Attention" | `OpenClawBrand.warn` |
| `.disconnected` | "Offline" | `.secondary` |

`Sources/Design/ChatProTab.swift:444`

### Composer placeholder

| State | Placeholder |
|---|---|
| Gateway connected | `"Message <agentName>..."` |
| Offline queuing supported | `"Message <agentName>; sends when connected"` |
| No connection, no queue | `"Connect to a gateway"` |

`Sources/Design/ChatProTab.swift:457`

### Starter prompts (empty state)

Three hardcoded prompts (ID, title, prompt string):
1. `"summarize-status"` — "Check OpenClaw status"
2. `"show-controls"` — "What can I control here?"
3. `"start-voice"` — "Help me start voice chat"

`Sources/Design/ChatProTab.swift:559`

---

## 9. iPad Layout — `sidebarSplitContent`

**File:** `Sources/RootTabs.swift:411`

iPad uses a `GeometryReader`-driven layout that switches between two modes:

### Layout modes

| Mode | Condition | Behavior |
|---|---|---|
| **Split** | `containerWidth >= 980 pt` AND `width > height` | Sidebar and detail render side-by-side in an `HStack(spacing: 0)` |
| **Drawer** | Otherwise (portrait or narrow width) | Sidebar overlays the detail via a `ZStack`; tap outside closes it |

`Sources/RootTabsNavigation.swift:149`

### Sidebar width calculation

```swift
static func sidebarWidth(containerWidth: CGFloat, isDrawerLayout: Bool) -> CGFloat {
    if isDrawerLayout {
        return min(340, max(280, containerWidth * 0.86))
    }
    return min(340, max(316, containerWidth * 0.25))
}
```

`Sources/RootTabsNavigation.swift:163`

Constants:
- `sidebarSplitIdealWidth = 316 pt`
- `sidebarSplitMaximumWidth = 340 pt`
- `sidebarDrawerMaximumWidth = 340 pt`
- `sidebarPersistentWidthThreshold = 980 pt`

`Sources/RootTabsNavigation.swift:25`

### Layout animation

Both split and drawer layouts animate sidebar show/hide with `.easeInOut(duration: 0.22)`. The sidebar column uses `.transition(.move(edge: .leading).combined(with: .opacity))`. `Sources/RootTabs.swift:422`

### Drawer mode overlay details

```
ZStack(alignment: .topLeading) {
    sidebarDetailNavigationShell      // full size, behind
    if isSidebarVisible:
        // Scrim (zIndex 0)
        HStack {
            Color.clear (sidebarWidth)
            Color.black.opacity(0.28)  // tap to hide
        }.ignoresSafeArea

        // Sidebar column (zIndex 1)
        sidebarColumn
            .shadow(color: .black.opacity(0.26), radius: 18, x: 8, y: 0)
}
```

`Sources/RootTabs.swift:450`

### Sidebar column

```
VStack(spacing: 0) {
    sidebarIdentityHeader    // logo + gateway status + optional hide button
    sidebarList              // List(.sidebar) with section groups
}
.safeAreaPadding(.top, 8)
.safeAreaPadding(.bottom, 8)
.background(Color(uiColor: .systemBackground))
```

`Sources/RootTabs.swift:488`

#### Identity header

- `OpenClawProMark(size: 30, shadowRadius: 3)` — branded logo mark, accessibility hidden.
- `Text("OpenClaw")` — `.headline` font, `.primary` color.
- Status subtitle: `Image(systemName: "circle.fill")` at `.system(size: 7, weight: .bold)` + `Text(sidebarGatewayStatusTitle)` at `.captionMedium` font.
- Padding: `.horizontal(18)`, `.vertical(12)`.
- Bottom separator: 1-physical-pixel `Rectangle().fill(Color(uiColor: .separator))`.

`Sources/RootTabs.swift:498`

| Gateway state | Status title | Dot color |
|---|---|---|
| `.connected` | "Online" | `OpenClawBrand.ok` |
| `.connecting` | "Connecting" | `OpenClawBrand.accent` |
| `.error` | "Needs attention" | `OpenClawBrand.warn` |
| `.disconnected` | "Offline" | `.secondary` |

`Sources/RootTabs.swift:537`

#### Sidebar list

`.listStyle(.sidebar)`, `.tint(OpenClawBrand.accent)`, `.scrollContentBackground(.hidden)`. No visible section separators (`.listSectionSeparator(.hidden, edges: .all)`).

Row: `Label(title, systemImage:)` at `.subheadSemiBold` font, `minimumScaleFactor(0.82)`, padding `.vertical(8) .horizontal(10)`. Active row: `foregroundStyle` is `OpenClawBrand.accent`; `listRowBackground` is `OpenClawBrand.accent.opacity(0.12)`. `Sources/RootTabs.swift:592`

### Sidebar groups and destinations

`Sources/RootTabsNavigation.swift:282`

| Group title | Destinations |
|---|---|
| `"CHAT"` | `.chat`, `.talk` |
| `"CONTROL"` | `.overview`, `.activity`, `.agents`, `.workboard`, `.skillWorkshop`, `.instances`, `.sessions`, `.files`, `.dreaming`, `.usage`, `.cron`, `.terminal` |
| `"SETTINGS"` | `.settings` |
| `"REFERENCE"` | `.docs` |

### Sidebar detail routing (`sidebarDetail`)

**File:** `Sources/RootTabs.swift:620`

| `SidebarDestination` | Rendered type |
|---|---|
| `.chat` | `ChatProTab(headerLeadingAction:, headerTitle: "Chat", showsAgentBadge: false, ownsNavigationStack: false, openSettings:)` |
| `.talk` | `TalkProTab(headerLeadingAction:, ownsNavigationStack: false, openSettings:, openVoiceSettings:)` |
| `.overview` | `CommandCenterTab(ownsNavigationStack: false, ...)` |
| `.activity` | `IPadActivityScreen(...)` |
| `.workboard` | `IPadWorkboardScreen(...)` |
| `.skillWorkshop` | `IPadSkillWorkshopScreen(...)` |
| `.agents` | `AgentProTab(directRoute: .agents, ...)` |
| `.instances` | `AgentProTab(directRoute: .instances, ...)` |
| `.sessions` | `CommandSessionsScreen(...)` |
| `.files` | `AgentProTab(directRoute: .files, ...)` |
| `.dreaming` | `AgentProTab(directRoute: .dreaming, ...)` |
| `.usage` | `AgentProTab(directRoute: .usage, ...)` |
| `.cron` | `AgentProTab(directRoute: .cron, ...)` |
| `.terminal` | `TerminalHubScreen(...)` |
| `.docs` | `OpenClawDocsScreen(...)` |
| `.settings` | `SettingsProTab(directRoute: selectedSettingsRoute or nil, ...)` |
| `.gateway` | `SettingsProTab(directRoute: selectedSettingsRoute ?? .gateway, ...)` |

Note: `.agents`, `.instances`, `.files`, `.dreaming`, `.usage`, `.cron` all use `AgentProTab` with different `directRoute` values and carry `.id(selectedSidebarDestination.id)` to force identity reset on each switch.

### Detail navigation shell

```swift
NavigationStack(path: $sidebarNavigationPath) {
    sidebarDetailShell
}
.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
.clipped()
```

`Sources/RootTabs.swift:744`

`sidebarNavigationPath` (a `[SettingsRoute]`) is cleared before every destination switch so stale settings detail screens cannot survive. `Sources/RootTabs.swift:1302`

### Sidebar header leading action

In **split** mode: always present (shows hide/show button). In **drawer** mode: shown only when sidebar is hidden (reveal button). The button uses `Image(systemName: "sidebar.left")` in split mode and `"xmark"` in drawer mode. `Sources/RootTabs.swift:785`

---

## 10. `SidebarDestination` and `AppTab` Enums

**File:** `Sources/RootTabsNavigation.swift:31`

### `AppTab`

```swift
enum AppTab: Hashable {
    case control, chat, talk, agent, settings
}
```

### `SidebarDestination` (all cases)

| Case | `appTab` | `settingsRoute` | Sidebar title |
|---|---|---|---|
| `.chat` | `.chat` | `nil` | "Chat" |
| `.talk` | `.talk` | `nil` | "Talk" |
| `.overview` | `.control` | `nil` | "Overview" |
| `.activity` | `.control` | `nil` | "Activity" |
| `.agents` | `.agent` | `nil` | "Agents" |
| `.workboard` | `.control` | `nil` | "Workboard" |
| `.skillWorkshop` | `.control` | `nil` | "Skill Workshop" |
| `.instances` | `.control` | `nil` | "Instances" |
| `.sessions` | `.control` | `nil` | "Sessions" |
| `.files` | `.control` | `nil` | "Files" |
| `.dreaming` | `.control` | `nil` | "Dreaming" |
| `.usage` | `.control` | `nil` | "Usage" |
| `.cron` | `.control` | `nil` | "Cron Jobs" |
| `.terminal` | `.control` | `nil` | "Terminal" |
| `.docs` | `.control` | `nil` | "Docs" |
| `.settings` | `.settings` | `nil` | "Settings" |
| `.gateway` | `.settings` | `.gateway` | "Connection" |

`Sources/RootTabsNavigation.swift:39`

---

## 11. Session Key Model — `SessionKey`

**File:** `Sources/SessionKey.swift`

Session keys identify chat rooms. The gateway has two spellings for the same room: the "base" key (e.g. `"main"`) and the agent-scoped form (e.g. `"agent:defaultAgentId:main"`).

### Static functions

#### `normalizeMainKey(_:)`

```swift
static func normalizeMainKey(_ raw: String?) -> String {
    let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "main" : trimmed
}
```

Empty or nil input → `"main"`. `Sources/SessionKey.swift:4`

#### `makeAgentSessionKey(agentId:baseKey:)`

```swift
static func makeAgentSessionKey(agentId: String, baseKey: String) -> String
```

- Empty `agentId` → returns normalized `baseKey` (or `"main"`).
- Non-empty `agentId` → `"agent:<agentId>:<normalizedBase>"`. `Sources/SessionKey.swift:9`

#### `agentId(from:)`

Parses the agent ID out of a full key. Splits on `":"`, requires `parts.count >= 3` and `parts[0].lowercased() == "agent"`. Returns `parts[1]` trimmed, or `nil` if empty. `Sources/SessionKey.swift:19`

### Alias resolution (in `RootTabs`)

The drawer must highlight the correct active session row even when the active key and the listed key differ in spelling. Two predicates handle this:

#### `isMainSessionAlias(_:)`

True when `key` equals the base `appModel.mainSessionKey` OR equals `"agent:<defaultOrSelectedAgent>:<room>"`. `Sources/RootTabs.swift:254`

#### `isActiveSessionAlias(_:)`

True when:
1. `entry == active` (exact match), OR
2. `entry = "agent:<agent>:<active>"` (listed key is the scoped form of the bare active key), OR
3. `active = "agent:<agent>:<entry>"` (active key is the scoped form of the bare listed key).

`Sources/RootTabs.swift:278`

### Session title derivation

`drawerSessionTitle(_:)` in `RootTabs` (`Sources/RootTabs.swift:326`):

1. **User label** (`entry.label`) — always wins, even for the home session.
2. **"Main"** — if the session is the main session alias and has no label.
3. **`derivedTitle`** — gateway's generated title (display name, subject, or truncated first user message).
4. **`displayName`** — fallback.
5. **`subject`** — fallback.
6. **`"Chat · <MMM d>"`** — if `updatedAt` or `lastActivityAt` is available (date format: `"MMM d"`).
7. **`"New chat"`** — final fallback.

Date formatter: `DateFormatter` with `dateFormat = "MMM d"`. `Sources/RootTabs.swift:349`

### Automation session filter

Sessions with keys matching `cron:` prefix or `:cron:` substring are excluded from the drawer. Defensive backstop also checks `kind`, `category`, `surface` fields against `{"cron", "automation", "schedule", "scheduled"}`. `Sources/RootTabs.swift:312`

### Session loading

`loadDrawerSessions()` is called whenever the drawer opens (`task(id: isChatDrawerOpen)`). It calls `appModel.fetchDrawerSessions()`, filters automation sessions, sorts by `(updatedAt ?? lastActivityAt ?? 0)` descending, and maps to `ChatDrawerSession` structs. `Sources/RootTabs.swift:298`

---

## 12. Global Overlays — `rootOverlays`

**File:** `Sources/RootTabs.swift:846`

Three overlay layers sit above the entire `tabContent`:

### Gateway problem toast (`.overlay(alignment: .top)`)

A `ZStack(alignment: .top)` containing `GatewayProblemBanner` when `activeGatewayProblemToast != nil`. Animated with `.spring(response: 0.35, dampingFraction: 0.85)` (or `nil` when `reduceMotion` is on). Transition: `.move(edge: .top).combined(with: .opacity)`. `Sources/RootTabs.swift:851`

- Padding: `.horizontal(12)`, `.safeAreaPadding(.top, 10)`.
- **Swipe-to-dismiss:** `DragGesture(minimumDistance: 12)`. Swipe-up threshold: `translation.height < -32 || predictedEndTranslation.height < -80`. Sets `isGatewayToastSwipeDismissed = true`. `Sources/RootTabs.swift:915`
- **Shake for re-reports:** `GatewayToastShakeEffect` — `GeometryEffect` using `7 * sin(animatableData * 6 * .pi)` (three oscillations). Animated with `.linear(duration: 0.4)`. `Sources/RootTabs.swift:1764`
- **Clearing:** When `lastGatewayProblem` becomes `nil`, `isGatewayToastSwipeDismissed` resets to `false`. `Sources/RootTabs.swift:1030`

### Voice wake toast (`.overlay(alignment: .topLeading)`)

`VoiceWakeToast(command:)` with `.padding(.leading, 10)` and `.safeAreaPadding(.top, activeGatewayProblemToast == nil ? 58 : 132)`. Transition: `.move(edge: .top).combined(with: .opacity)`. Auto-dismissed after `2_300_000_000` nanoseconds (2.3 seconds). `Sources/RootTabs.swift:859`

Spring animation: `.spring(response: 0.25, dampingFraction: 0.85)` on show; `.easeOut(duration: 0.25)` on hide.

### Canvas presentation overlay (`.overlay`, zIndex 20)

Full-screen `ZStack(alignment: .topTrailing)` with:
- `Color.black.ignoresSafeArea()`
- `ScreenWebView(controller: appModel.screen).ignoresSafeArea()`
- Close button: `Image(systemName: "xmark.circle.fill")`, `.system(size: 30, weight: .semibold)`, `.symbolRenderingMode(.hierarchical)`, `.white`, `shadow(color: .black.opacity(0.32), radius: 8, y: 2)`, 48×48 pt hit target, `.safeAreaPadding(.top, 8)`, `.padding(.trailing, 12)`.

Transition: `.opacity`. Shown when `appModel.screen.isCanvasPresented`. `Sources/RootTabs.swift:944`

### Camera flash overlay

`RootCameraFlashOverlay` — `Color.white.opacity(opacity).ignoresSafeArea().allowsHitTesting(false)`. On each `nonce` change: fade to `opacity: 0.85` (`.easeOut(duration: 0.08)`), wait `110_000_000` ns (0.11 s), fade to `opacity: 0` (`.easeOut(duration: 0.32)`). `Sources/RootTabs.swift:1772`

---

## 13. Root Presentation — Sheets and Covers

**File:** `Sources/RootTabs.swift:1099`

| Presentation | Trigger | Type |
|---|---|---|
| Gateway problem details | `showGatewayProblemDetails` | `.sheet` |
| Quick setup | `presentedSheet == .quickSetup` | `.sheet` — `GatewayQuickSetupSheet()` with `.openClawSheetChrome()` |
| Connection sheet | `showConnectionSheet` | `.sheet` — `ConnectionSheetHostView`, `presentationCornerRadius(47)`, `presentationDragIndicator(.hidden)` |
| Onboarding wizard | `showOnboarding` | `.fullScreenCover` — `OnboardingWizardView(allowSkip:, autoOpenScanner:, ...)` |

Connection sheet → full-access scan: dismisses the sheet, sets `onboardingAutoScan = true`, waits `400 ms`, then re-evaluates onboarding presentation. `Sources/RootTabs.swift:1123`

---

## 14. Startup Presentation Logic

**File:** `Sources/RootTabsNavigation.swift:230`

```swift
static func startupPresentationRoute(
    gatewayConnected: Bool,
    hasConnectedOnce: Bool,
    onboardingComplete: Bool,
    hasExistingGatewayConfig: Bool,
    shouldPresentOnLaunch: Bool) -> StartupPresentationRoute
```

| Condition | Route |
|---|---|
| Gateway connected | `.none` |
| Existing gateway config | `.none` |
| `shouldPresentOnLaunch || !hasConnectedOnce || !onboardingComplete` | `.onboarding` |
| Otherwise | `.settings` |

First-run onboarding (`.onboarding` from startup) sets `onboardingAllowSkip = false` (no close affordance until connected). Re-opening via settings sets `onboardingAllowSkip = true`. `Sources/RootTabs.swift:1483`

### Quick setup sheet

Shown automatically when:
- `!quickSetupDismissed`
- `!showOnboarding`
- No other sheet is presented
- Gateway not connected
- No existing config
- `gatewayController.gateways.count > 0` (gateway discovered on local network)

`Sources/RootTabsNavigation.swift:257`

---

## 15. `AppStorage` Keys Used by `RootTabs`

| Key | Type | Default | Purpose |
|---|---|---|---|
| `"screen.preventSleep"` | `Bool` | `true` | Keeps screen awake while app is active |
| `"onboarding.requestID"` | `Int` | `0` | Bumped to re-trigger onboarding |
| `"gateway.onboardingComplete"` | `Bool` | `false` | Marks onboarding flow done |
| `"gateway.hasConnectedOnce"` | `Bool` | `false` | Set on first successful connection |
| `"gateway.preferredStableID"` | `String` | `""` | Preferred gateway pairing ID |
| `"gateway.manual.enabled"` | `Bool` | `false` | Manual gateway override toggle |
| `"gateway.manual.host"` | `String` | `""` | Manual gateway host string |
| `"onboarding.quickSetupDismissed"` | `Bool` | `false` | User dismissed the quick-setup sheet |
| `"canvas.debugStatusEnabled"` | `Bool` | `false` | Shows canvas debug overlay |

`Sources/RootTabs.swift:15`

---

## 16. Launch Arguments

| Argument | Effect |
|---|---|
| `--openclaw-initial-tab <value>` | Sets initial tab: `control`/`overview`, `chat`, `talk`/`voice`, `agent`/`agents`, `settings` |
| `--openclaw-initial-destination <value>` | Sets initial `SidebarDestination` by raw value |
| `--openclaw-sidebar-visibility <value>` | Forces sidebar visible/hidden: `visible`/`show`/`shown`/`open`/`true`/`1` or `hidden`/`hide`/`closed`/`false`/`0` |
| `--openclaw-chat-session <key>` | Opens the specified session key on launch |
| `--openclaw-reset-onboarding` | Resets onboarding state before model registration (debug only) |
| `--openclaw-screenshot-mode` | Disables animations, pre-seeds onboarding flags, enters screenshot fixture mode (debug only) |
| `--openclaw-screenshot-notification-guidance` | Additionally shows notification guidance prompt in screenshot mode (debug only) |

`Sources/RootTabs.swift:75`, `Sources/RootTabsNavigation.swift:186`, `Sources/OpenClawApp.swift:679`

---

## 17. Live Surface Map Summary

| Surface | Live on phone? | Live on iPad? | File |
|---|---|---|---|
| `ChatRootSurface` | Yes (via `ChatProTab`) | Yes (via `ChatProTab` in sidebar detail) | `Sources/Design/ChatRootSurface.swift` |
| `ChatDrawerHost` | Yes | No | `Sources/Design/ChatDrawer.swift` |
| `PhoneTabSettingsHost` | Yes | No | `Sources/RootTabs.swift:1603` |
| `AgentProTab` (with `directRoute`) | No (phone has drawer screens) | Yes (sidebar detail) | Shared |
| `OpenClawChatUI.ChatView` | No (legacy/macOS) | No (legacy/macOS) | Shared package |
| `CanvasArchiveScreen` | Yes (drawer destination) | No (not in sidebar) | `Sources/Design/...` |
| `DreamingScreenHost` | Yes (drawer destination) | No (sidebar uses `AgentProTab(directRoute:.dreaming)`) | `Sources/Design/...` |
| `UsageScreenHost` | Yes (drawer destination) | No | `Sources/Design/...` |
| `InstancesScreenHost` | Yes (drawer destination) | No | `Sources/Design/...` |
| `CronJobsScreenHost` | Yes (drawer destination) | No | `Sources/Design/...` |
| `FilesWorkspaceScreenHost` | Yes (drawer destination) | No | `Sources/Design/...` |
| `SkillsScreenHost` | Yes (drawer destination) | No | `Sources/Design/...` |
| `SettingsRootContainer` | Yes (phone settings stack) | No (iPad uses `SettingsProTab`) | `Sources/Design/...` |
