import OpenClawChatUI
import OpenClawKit
import OpenClawProtocol
import SwiftUI
import UIKit

struct RootTabs: View {
    @Environment(NodeAppModel.self) private var appModel
    @Environment(VoiceWakeManager.self) private var voiceWake
    @Environment(GatewayConnectionController.self) private var gatewayController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.rootTabsUserInterfaceIdiomOverride) private var userInterfaceIdiomOverride
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("screen.preventSleep") private var preventSleep: Bool = true
    @AppStorage("onboarding.requestID") private var onboardingRequestID: Int = 0
    @AppStorage("gateway.onboardingComplete") private var onboardingComplete: Bool = false
    @AppStorage("gateway.hasConnectedOnce") private var hasConnectedOnce: Bool = false
    @AppStorage("gateway.preferredStableID") private var preferredGatewayStableID: String = ""
    @AppStorage("gateway.manual.enabled") private var manualGatewayEnabled: Bool = false
    @AppStorage("gateway.manual.host") private var manualGatewayHost: String = ""
    @AppStorage("onboarding.quickSetupDismissed") private var quickSetupDismissed: Bool = false
    @AppStorage("canvas.debugStatusEnabled") private var canvasDebugStatusEnabled: Bool = false
    @State private var selectedTab: AppTab = Self.initialTab
    @State private var selectedSidebarDestination: SidebarDestination = Self.initialSidebarDestination
    @State private var selectedSettingsRoute: SettingsRoute? = Self.initialSidebarDestination.settingsRoute
    @State private var selectedSettingsRouteRequestID: Int = 0
    @State private var phoneControlNavigationRequest: PhoneControlNavigationRequest?
    @State private var phoneChatReturn: PhoneChatReturn?
    @State private var phoneChatSettingsResetRequestID: Int = 0
    @State private var showConnectionSheet = false
    @State private var pendingSettingsRoute: SettingsRoute?
    // Chat drawer (WhatsApp-style side panel) — phone only.
    @State private var isChatDrawerOpen = false
    @State private var activeDrawerDestination: ChatDrawerDestination?
    @State private var drawerSessions: [ChatDrawerSession] = []
    /// True while a Settings route is pushed over the phone chat; disables the drawer's drag-to-open.
    @State private var isPhoneSettingsPresented = false
    /// The canvas embed currently open in the viewer panel (opened from the archive page).
    @State private var selectedCanvasEmbed: CanvasEmbed?
    // Embedded Settings rows push onto the sidebar stack; clear it before
    // changing sidebar roots so stale settings detail screens cannot survive.
    @State private var sidebarNavigationPath: [SettingsRoute] = []
    @State private var isSidebarVisible: Bool = Self.initialSidebarVisibility ?? false
    @State private var sidebarVisibilityUserOverridden: Bool = Self.initialSidebarVisibility != nil
    @State private var isSidebarDrawerLayout: Bool = false
    @State private var didResolveSidebarLayout: Bool = false
    @State private var voiceWakeToastText: String?
    @State private var toastDismissTask: Task<Void, Never>?
    @State private var presentedSheet: PresentedSheet?
    @State private var showGatewayProblemDetails: Bool = false
    @State private var gatewayToastDragOffset: CGFloat = 0
    // Swipe-up hides the toast only until the next problem report; every report
    // (even an equal problem) must re-surface it or shake the visible toast.
    @State private var isGatewayToastSwipeDismissed: Bool = false
    @State private var gatewayToastShake: CGFloat = 0
    // Mirror of the problem at the last handled report, used to tell a first
    // appearance (animate in) from a re-report while visible (shake).
    @State private var lastReportedGatewayProblem: GatewayConnectionProblem?
    @State private var showOnboarding: Bool = false
    @State private var onboardingAllowSkip: Bool = true
    /// Set when onboarding is opened specifically to scan a full-access QR (from the Connection sheet), so
    /// the wizard jumps straight to the scanner. Reset whenever onboarding closes.
    @State private var onboardingAutoScan: Bool = false
    @State private var didEvaluateOnboarding: Bool = false
    @State private var didAutoOpenSettings: Bool = false
    @State private var didApplyInitialChatSession: Bool = false
    @State private var gatewaySetupRequest: GatewaySetupRequest?
    @State private var suppressedExecApprovalPromptIDForNotificationSettings: String?

    private static var initialTab: AppTab {
        Self.initialTab(arguments: ProcessInfo.processInfo.arguments)
    }

    static func initialTab(arguments: [String]) -> AppTab {
        guard let flagIndex = arguments.firstIndex(of: "--openclaw-initial-tab") else {
            return self.fallbackInitialTab(arguments: arguments)
        }
        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else {
            return Self.fallbackInitialTab(arguments: arguments)
        }

        switch arguments[valueIndex].lowercased() {
        case "control", "overview":
            return .control
        case "chat":
            return .chat
        case "talk", "voice":
            return .talk
        case "agent", "agents":
            return .agent
        case "settings":
            return .settings
        default:
            return Self.fallbackInitialTab(arguments: arguments)
        }
    }

    private static func fallbackInitialTab(arguments: [String]) -> AppTab {
        self.requestedInitialSidebarDestination(arguments: arguments)?.appTab ?? .chat
    }

    private static var initialSidebarDestination: SidebarDestination {
        if let requested = requestedInitialSidebarDestination {
            return requested
        }
        return Self.defaultSidebarDestination(for: initialTab)
    }

    private static var requestedInitialSidebarDestination: SidebarDestination? {
        Self.requestedInitialSidebarDestination(arguments: ProcessInfo.processInfo.arguments)
    }

    static func requestedInitialSidebarDestination(arguments: [String]) -> SidebarDestination? {
        guard let flagIndex = arguments.firstIndex(of: "--openclaw-initial-destination") else {
            return nil
        }
        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else { return nil }
        let requested = arguments[valueIndex].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return SidebarDestination.allCases.first { $0.rawValue.lowercased() == requested }
    }

    private static var initialSidebarVisibility: Bool? {
        requestedInitialSidebarVisibility(arguments: ProcessInfo.processInfo.arguments)
    }

    private static var initialChatSessionKey: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "--openclaw-chat-session") else {
            return nil
        }
        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else { return nil }
        let trimmed = arguments[valueIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private enum PresentedSheet: Identifiable {
        case quickSetup

        var id: Int {
            switch self {
            case .quickSetup: 0
            }
        }
    }

    static func shouldUseSidebarTabs(
        idiom: UIUserInterfaceIdiom,
        horizontalSizeClass _: UserInterfaceSizeClass?) -> Bool
    {
        idiom == .pad
    }

    var body: some View {
        self.rootPresentation(
            self.rootLifecycle(
                self.rootOverlays(
                    self.tabContent
                        .tint(OpenClawBrand.accent))))
    }

    @ViewBuilder
    private var tabContent: some View {
        if self.usesSidebarTabs {
            self.sidebarSplitContent
        } else {
            self.phoneTabContent
        }
    }

    private var phoneTabContent: some View {
        ChatDrawerHost(
            isOpen: self.$isChatDrawerOpen,
            sessions: self.drawerSessions,
            // The drawer is a chat-surface control; disable drag-to-open while Settings covers the chat.
            allowsOpen: !self.isPhoneSettingsPresented,
            onSelectDestination: { self.activeDrawerDestination = $0 },
            // Selecting a session/new chat also clears any active drawer destination so the chat (not a
            // lingering destination) is what the closing drawer reveals.
            onSelectSession: {
                self.activeDrawerDestination = nil
                self.appModel.openChat(sessionKey: $0)
            },
            // New chat: mint a fresh key and switch to it. The gateway materializes the room lazily on the
            // first message, so an abandoned empty chat costs nothing (no eager sessions.create needed).
            onNewSession: {
                self.activeDrawerDestination = nil
                let key = "mobile-\(UUID().uuidString.prefix(8).lowercased())"
                self.appModel.openChat(sessionKey: key)
            },
            // Rename via the gateway (sessions.patch { label }), then refetch so the new title shows.
            onRenameSession: { key, label in
                Task {
                    await self.appModel.renameChatSession(key: key, label: label)
                    await self.loadDrawerSessions()
                }
            },
            activeSessionID: self.resolvedActiveSessionID,
            activeDestination: self.activeDrawerDestination,
            mainSessionID: self.resolvedMainSessionID)
        {
            // The chat and each drawer destination are peer "tabs" sharing one panel — exactly one shows at
            // a time (like switching chat sessions), never layered. They are ZStack SIBLINGS, not an overlay
            // of a destination on top of the chat: layering was what let the chat bleed through a
            // destination. The chat stays MOUNTED but hidden while a destination is active, so its view
            // model / gateway connection isn't torn down and rebuilt on every tab switch. Both live inside
            // the drawer host's panel, so they inherit the same left-to-right slide-to-open, drop shadow,
            // and open haptic; each destination's leading chevron opens the drawer too. You switch tabs
            // (chat included) through the drawer — no modal, no dedicated back-to-chat.
            ZStack {
                PhoneTabSettingsHost(
                    resetRequestID: self.phoneChatSettingsResetRequestID,
                    onOpenConnection: { self.showConnectionSheet = true },
                    pendingRoute: self.$pendingSettingsRoute,
                    isPresentingSettings: self.$isPhoneSettingsPresented)
                { openSettingsRoute in
                    ChatProTab(
                        headerLeadingAction: self.phoneChatReturnAction,
                        ownsNavigationStack: false,
                        openSettings: { openSettingsRoute(.home) },
                        onOpenDrawer: {
                            withAnimation(.spring(duration: 0.35)) { self.isChatDrawerOpen = true }
                        })
                }
                .opacity(self.activeDrawerDestination == nil ? 1 : 0)
                .allowsHitTesting(self.activeDrawerDestination == nil)

                if let destination = self.activeDrawerDestination {
                    self.drawerDestinationScreen(destination)
                }
            }
        }
        .task(id: self.isChatDrawerOpen) {
            if self.isChatDrawerOpen {
                await self.loadDrawerSessions()
            }
        }
    }

    /// The home session's key AS IT APPEARS in the cached list. `appModel.mainSessionKey` is the normalized
    /// base (`main`), but the gateway usually keys the same session by its agent alias
    /// (`agent:<defaultAgent>:main`). Preferring the cached key lets the drawer's "Main" section dedupe
    /// cleanly against the recents and open the real history. Falls back to the base when nothing is cached.
    private var resolvedMainSessionID: String {
        self.drawerSessions.first(where: { self.isMainSessionAlias($0.id) })?.id
            ?? self.appModel.mainSessionKey
    }

    /// True when `key` is the home session under either spelling (base `main` or `agent:<defaultAgent>:main`),
    /// mirroring the chat view model's main-session alias contract.
    private func isMainSessionAlias(_ key: String) -> Bool {
        let candidate = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = self.appModel.mainSessionKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if candidate == base {
            return true
        }
        let agent = (self.appModel.gatewayDefaultAgentId ?? self.appModel.selectedAgentId ?? "main")
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let room = base.isEmpty ? "main" : base
        return candidate == "agent:\(agent.isEmpty ? "main" : agent):\(room)"
    }

    /// The active session resolved to the key AS IT APPEARS in the drawer list, so the active row highlights
    /// automatically — not only after a manual tap. The live active key (`chatSessionKey`) is often an alias
    /// of the listed key: cold start uses the base `main` while the list has `agent:main:main`, and a chat
    /// created via "+" is focused as `mobile-…` while the gateway lists it as `agent:<agent>:mobile-…`.
    /// Falls back to the raw active key when nothing in the list matches.
    private var resolvedActiveSessionID: String {
        self.drawerSessions.first(where: { self.isActiveSessionAlias($0.id) })?.id
            ?? self.appModel.chatSessionKey
    }

    /// True when `key` is the currently-open session under either spelling — exact, or the gateway's
    /// agent-scoped form (`agent:<defaultAgent>:<room>`) of the bare/base active key.
    private func isActiveSessionAlias(_ key: String) -> Bool {
        let entry = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let active = self.appModel.chatSessionKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if entry == active {
            return true
        }
        let agent = (self.appModel.gatewayDefaultAgentId ?? self.appModel.selectedAgentId ?? "main")
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let prefix = "agent:\(agent.isEmpty ? "main" : agent):"
        if entry.hasPrefix(prefix), String(entry.dropFirst(prefix.count)) == active {
            return true
        }
        if active.hasPrefix(prefix), String(active.dropFirst(prefix.count)) == entry {
            return true
        }
        return false
    }

    /// Loads the app-cached recent chat sessions for the drawer, mapping to display rows. Cron/automation
    /// sessions (isolated scheduled agent turns, not conversations) are dropped — see `isAutomationSession`.
    private func loadDrawerSessions() async {
        let entries = await self.appModel.fetchDrawerSessions()
        self.drawerSessions = entries
            .filter { !Self.isAutomationSession($0) }
            .sorted { ($0.updatedAt ?? $0.lastActivityAt ?? 0) > ($1.updatedAt ?? $1.lastActivityAt ?? 0) }
            .map { entry in
                ChatDrawerSession(id: entry.key, title: self.drawerSessionTitle(entry))
            }
    }

    /// Cron/automation sessions (e.g. the managed "Memory Dreaming Promotion" job) run as isolated agent
    /// turns keyed `agent:<id>:cron:<job>` — they have no conversation and don't belong in the recents.
    /// The `:cron:` key segment is the gateway's canonical structure for these (`cron/isolated-agent`); a
    /// real chat key can't contain it. The kind/category/surface markers are a defensive backstop.
    private static func isAutomationSession(_ entry: OpenClawChatSessionEntry) -> Bool {
        let key = entry.key.lowercased()
        if key.hasPrefix("cron:") || key.contains(":cron:") {
            return true
        }
        let markers: Set = ["cron", "automation", "schedule", "scheduled"]
        return [entry.kind, entry.category, entry.surface]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .contains { markers.contains($0) }
    }

    /// A human display title — never the raw key. Prefers the gateway's own title (displayName / label /
    /// subject); the home session reads as "Main"; anything still untitled falls back to a dated "Chat ·
    /// <date>" (or "New chat" when there's no timestamp) so a key like `agent:main:mobile-…` never shows.
    private func drawerSessionTitle(_ entry: OpenClawChatSessionEntry) -> String {
        // An explicit user rename (label) always wins — even for the home session.
        if let label = entry.label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
            return label
        }
        // The home session reads as "Main" unless it was renamed above.
        if self.isMainSessionAlias(entry.key) {
            return "Main"
        }
        // Otherwise use the gateway's ChatGPT/Claude-style title (`derivedTitle`: displayName / subject, else
        // the first user message truncated). Fall back to a dated placeholder, then a generic — never a key.
        for candidate in [entry.derivedTitle, entry.displayName, entry.subject] {
            if let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
                return trimmed
            }
        }
        if let millis = entry.updatedAt ?? entry.lastActivityAt {
            let date = Date(timeIntervalSince1970: millis / 1000)
            return "Chat · " + Self.drawerSessionDateFormatter.string(from: date)
        }
        return "New chat"
    }

    private static let drawerSessionDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    /// Drawer items point to their existing destinations. Agent surfaces reuse `AgentProTab`
    /// (which owns its own overview-loading duty); Canvas hosts the shared screen controller.
    private func drawerDestinationScreen(_ destination: ChatDrawerDestination) -> some View {
        // Every destination is a peer "tab": its leading chevron opens the drawer (the tab switcher),
        // matching the chat's leading button + the left-to-right slide. There is no dedicated
        // back-to-chat — you switch tabs (chat included) through the drawer.
        let openDrawer = { withAnimation(.spring(duration: 0.35)) { self.isChatDrawerOpen = true } }
        return Group {
            switch destination {
            case .canvas:
                CanvasArchiveScreen(
                    onClose: openDrawer,
                    onOpenEmbed: { self.selectedCanvasEmbed = $0 })
            case .dreaming:
                DreamingScreenHost(onClose: openDrawer)
            case .usage:
                UsageScreenHost(onClose: openDrawer)
            case .instances:
                InstancesScreenHost(onClose: openDrawer)
            case .cron:
                CronJobsScreenHost(onClose: openDrawer)
            case .files:
                FilesWorkspaceScreenHost(onClose: openDrawer)
            case .skills:
                SkillsScreenHost(onClose: openDrawer)
            }
        }
        // Consistent redesigned "cancel" X across all drawer destinations (matches the Connection sheet),
        // in place of each screen's own back chevron. A top safe-area inset (not an overlay) reserves
        // its space so the button never sits on top of the screen's content. Canvas, Usage, Instances,
        // Cron, Skills, and Files draw their own header + close, so they opt out of the shared button.
        .safeAreaInset(edge: .top, alignment: .leading, spacing: 0) {
            if destination != .canvas, destination != .usage,
               destination != .instances, destination != .cron, destination != .skills,
               destination != .files, destination != .dreaming
            {
                DrawerCloseButton(onClose: { self.activeDrawerDestination = nil })
            }
        }
        // The canvas viewer panel, opened from the archive page's rows.
        .sheet(item: self.$selectedCanvasEmbed) { embed in
            CanvasEmbedPanel(
                embed: embed,
                canvasHostProvider: {
                    if let refreshed = await self.appModel.refreshCanvasHostURL() {
                        return refreshed
                    }
                    return await self.appModel.canvasHostURL()
                },
                onClose: { self.selectedCanvasEmbed = nil })
                .presentationCornerRadius(47)
        }
        .environment(self.appModel)
        .environment(self.gatewayController)
    }

    private var sidebarSplitContent: some View {
        GeometryReader { proxy in
            let isDrawerLayout = self.shouldUseSidebarDrawer(containerSize: proxy.size)
            let sidebarWidth = self.sidebarWidth(containerWidth: proxy.size.width, isDrawerLayout: isDrawerLayout)
            Group {
                if isDrawerLayout {
                    self.sidebarDrawerContent(sidebarWidth: sidebarWidth)
                } else {
                    self.sidebarNavigationSplitContent(sidebarWidth: sidebarWidth)
                }
            }
            .animation(.easeInOut(duration: 0.22), value: self.isSidebarVisible)
            .onAppear {
                self.updateSidebarLayout(containerSize: proxy.size, force: false)
            }
            .onChange(of: proxy.size) { _, size in
                self.updateSidebarLayout(containerSize: size, force: false)
            }
        }
    }

    private func sidebarNavigationSplitContent(sidebarWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            if self.isSidebarVisible {
                self.sidebarColumn
                    .frame(width: sidebarWidth, alignment: .topLeading)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    .overlay(alignment: .trailing) {
                        self.sidebarVerticalSeparator
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            self.sidebarDetailNavigationShell
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(OpenClawProBackground())
    }

    private func sidebarDrawerContent(sidebarWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            self.sidebarDetailNavigationShell
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if self.isSidebarVisible {
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: sidebarWidth)
                        .allowsHitTesting(false)
                    Color.black.opacity(0.28)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            self.hideSidebar()
                        }
                }
                .ignoresSafeArea()
                .transition(.opacity)
                .zIndex(0)

                self.sidebarColumn
                    .frame(width: sidebarWidth, alignment: .topLeading)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    .overlay(alignment: .trailing) {
                        self.sidebarVerticalSeparator
                    }
                    .shadow(color: .black.opacity(0.26), radius: 18, x: 8, y: 0)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .zIndex(1)
            }
        }
    }

    private var sidebarDetailShell: some View {
        self.sidebarDetail
            .id(self.sidebarDetailShellID)
    }

    private var sidebarColumn: some View {
        VStack(spacing: 0) {
            self.sidebarIdentityHeader
            self.sidebarList
        }
        .safeAreaPadding(.top, 8)
        .safeAreaPadding(.bottom, 8)
        .background(Color(uiColor: .systemBackground))
    }

    private var sidebarIdentityHeader: some View {
        HStack(spacing: 10) {
            OpenClawProMark(size: 30, shadowRadius: 3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("OpenClaw")
                    .font(OpenClawType.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(self.sidebarGatewayStatusColor)
                    Text(self.sidebarGatewayStatusTitle)
                        .font(OpenClawType.captionMedium)
                        .lineLimit(1)
                }
                .font(OpenClawType.captionMedium)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if self.isSidebarDrawerLayout {
                self.sidebarHideButton
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .bottom) {
            self.sidebarHorizontalSeparator
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("OpenClaw \(self.sidebarGatewayStatusTitle)")
    }

    private var sidebarGatewayStatusTitle: String {
        switch self.gatewayStatus {
        case .connected:
            "Online"
        case .connecting:
            "Connecting"
        case .error:
            "Needs attention"
        case .disconnected:
            "Offline"
        }
    }

    private var sidebarList: some View {
        List {
            ForEach(Self.sidebarGroups) { group in
                Section(group.title.capitalized) {
                    ForEach(group.destinations) { destination in
                        self.sidebarDestinationButton(destination)
                    }
                }
                .listSectionSeparator(.hidden, edges: .all)
            }
        }
        .listStyle(.sidebar)
        .tint(OpenClawBrand.accent)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemBackground))
    }

    private var sidebarHorizontalSeparator: some View {
        Rectangle()
            .fill(Color(uiColor: .separator))
            .frame(height: 1 / UIScreen.main.scale)
    }

    private var sidebarVerticalSeparator: some View {
        Rectangle()
            .fill(Color(uiColor: .separator))
            .frame(width: 1 / UIScreen.main.scale)
    }

    private var sidebarGatewayStatusColor: Color {
        switch self.gatewayStatus {
        case .connected:
            OpenClawBrand.ok
        case .connecting:
            OpenClawBrand.accent
        case .error:
            OpenClawBrand.warn
        case .disconnected:
            .secondary
        }
    }

    private func sidebarDestinationButton(
        _ destination: SidebarDestination,
        title: String? = nil) -> some View
    {
        Button {
            self.selectSidebarDestination(destination)
        } label: {
            Label(title ?? destination.sidebarTitle, systemImage: destination.systemImage)
                .font(OpenClawType.subheadSemiBold)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .truncationMode(.tail)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .font(OpenClawType.subheadSemiBold)
        .buttonStyle(.plain)
        .foregroundStyle(destination == self.selectedSidebarDestination ? OpenClawBrand.accent : .primary)
        .listRowBackground(
            destination == self.selectedSidebarDestination
                ? OpenClawBrand.accent.opacity(0.12)
                : Color.clear)
        .listRowSeparator(.hidden, edges: .all)
    }

    @ViewBuilder
    private var sidebarDetail: some View {
        switch self.selectedSidebarDestination {
        case .chat:
            ChatProTab(
                headerLeadingAction: self.sidebarHeaderLeadingAction,
                headerTitle: "Chat",
                showsAgentBadge: false,
                ownsNavigationStack: false,
                openSettings: { self.selectSidebarDestination(.gateway) })
        case .talk:
            TalkProTab(
                headerLeadingAction: self.sidebarHeaderLeadingAction,
                ownsNavigationStack: false,
                openSettings: { self.selectSidebarDestination(.gateway) },
                openVoiceSettings: { self.selectSettingsRoute(.voice) })
        case .overview:
            CommandCenterTab(
                ownsNavigationStack: false,
                headerTitle: "Overview",
                headerLeadingAction: self.sidebarHeaderLeadingAction,
                showsHeaderMark: false,
                openChat: { self.selectSidebarDestination(.chat) },
                openSettings: { self.selectSidebarDestination(.gateway) },
                openSessions: { self.selectSidebarDestination(.sessions) })
        case .activity:
            IPadActivityScreen(
                headerLeadingAction: self.sidebarHeaderLeadingAction,
                openChat: { self.selectSidebarDestination(.chat) },
                openSettings: { self.selectSidebarDestination(.gateway) })
        case .workboard:
            IPadWorkboardScreen(
                headerLeadingAction: self.sidebarHeaderLeadingAction,
                openChat: { self.selectSidebarDestination(.chat) },
                openSettings: { self.selectSidebarDestination(.gateway) })
        case .skillWorkshop:
            IPadSkillWorkshopScreen(
                headerLeadingAction: self.sidebarHeaderLeadingAction,
                openSettings: { self.selectSidebarDestination(.gateway) })
        case .agents:
            AgentProTab(
                directRoute: .agents,
                headerLeadingAction: self.sidebarHeaderLeadingAction,
                headerTitle: "Agents",
                openSettings: { self.selectSidebarDestination(.gateway) })
                .id(self.selectedSidebarDestination.id)
        case .instances:
            AgentProTab(
                directRoute: .instances,
                headerLeadingAction: self.sidebarHeaderLeadingAction,
                headerTitle: "Instances",
                openSettings: { self.selectSidebarDestination(.gateway) })
                .id(self.selectedSidebarDestination.id)
        case .sessions:
            CommandSessionsScreen(
                headerLeadingAction: self.sidebarHeaderLeadingAction,
                openChat: { self.selectSidebarDestination(.chat) })
        case .files:
            AgentProTab(
                directRoute: .files,
                headerLeadingAction: self.sidebarHeaderLeadingAction,
                headerTitle: "Files",
                openSettings: { self.selectSidebarDestination(.gateway) })
                .id(self.selectedSidebarDestination.id)
        case .dreaming:
            AgentProTab(
                directRoute: .dreaming,
                headerLeadingAction: self.sidebarHeaderLeadingAction,
                headerTitle: "Dreaming",
                openSettings: { self.selectSidebarDestination(.gateway) })
                .id(self.selectedSidebarDestination.id)
        case .usage:
            AgentProTab(
                directRoute: .usage,
                headerLeadingAction: self.sidebarHeaderLeadingAction,
                headerTitle: "Usage",
                openSettings: { self.selectSidebarDestination(.gateway) })
                .id(self.selectedSidebarDestination.id)
        case .cron:
            AgentProTab(
                directRoute: .cron,
                headerLeadingAction: self.sidebarHeaderLeadingAction,
                headerTitle: "Cron Jobs",
                openSettings: { self.selectSidebarDestination(.gateway) })
                .id(self.selectedSidebarDestination.id)
        case .terminal:
            TerminalHubScreen(
                headerLeadingAction: self.sidebarHeaderLeadingAction,
                gatewayAction: { self.selectSidebarDestination(.gateway) })
        case .docs:
            OpenClawDocsScreen(
                headerLeadingAction: self.sidebarHeaderLeadingAction,
                gatewayAction: { self.selectSidebarDestination(.gateway) })
        case .settings:
            if let selectedSettingsRoute {
                SettingsProTab(
                    directRoute: selectedSettingsRoute,
                    headerLeadingAction: self.sidebarHeaderLeadingAction,
                    ownsNavigationStack: false,
                    navigateToRoute: pushSidebarSettingsRoute,
                    onRouteChange: handleSettingsRouteChange,
                    gatewaySetupRequest: self.gatewaySetupRequest,
                    onGatewaySetupRequestHandled: handleGatewaySetupRequest)
            } else {
                SettingsProTab(
                    headerLeadingAction: self.sidebarHeaderLeadingAction,
                    ownsNavigationStack: false,
                    navigateToRoute: pushSidebarSettingsRoute,
                    onRouteChange: handleSettingsRouteChange,
                    gatewaySetupRequest: self.gatewaySetupRequest,
                    onGatewaySetupRequestHandled: handleGatewaySetupRequest)
            }
        case .gateway:
            SettingsProTab(
                directRoute: self.selectedSettingsRoute ?? self.selectedSidebarDestination.settingsRoute ?? .gateway,
                acceptsGatewaySetupRequests: !self.showOnboarding,
                headerLeadingAction: self.sidebarHeaderLeadingAction,
                ownsNavigationStack: false,
                navigateToRoute: pushSidebarSettingsRoute,
                onRouteChange: handleSettingsRouteChange,
                gatewaySetupRequest: self.gatewaySetupRequest,
                onGatewaySetupRequestHandled: handleGatewaySetupRequest)
        }
    }

    private var sidebarDetailNavigationShell: some View {
        NavigationStack(path: self.$sidebarNavigationPath) {
            self.sidebarDetailShell
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    private var usesSidebarTabs: Bool {
        Self.shouldUseSidebarTabs(
            idiom: self.userInterfaceIdiom,
            horizontalSizeClass: self.horizontalSizeClass)
    }

    private var userInterfaceIdiom: UIUserInterfaceIdiom {
        if let userInterfaceIdiomOverride {
            return userInterfaceIdiomOverride
        }
        return UIDevice.current.userInterfaceIdiom
    }

    private var sidebarDetailShellID: String {
        let routeID = self.selectedSettingsRoute.map { "\($0)" } ?? "root"
        return "\(self.selectedSidebarDestination.id):\(routeID):\(self.selectedSettingsRouteRequestID)"
    }

    private var settingsTabViewID: String {
        let routeID = self.selectedSettingsRoute.map { "\($0)" } ?? "settings"
        return "\(routeID):\(self.selectedSettingsRouteRequestID)"
    }

    private var activeExecApprovalPromptSuppressionID: String? {
        guard self.selectedTab == .settings, self.selectedSettingsRoute == .notifications else { return nil }
        return self.suppressedExecApprovalPromptIDForNotificationSettings
    }

    private var shouldCollapseSidebarAfterSelection: Bool {
        Self.shouldCollapseSidebarAfterSelection(
            layoutMode: self.isSidebarDrawerLayout ? .drawer : .split)
    }

    private var sidebarHeaderLeadingAction: OpenClawSidebarHeaderAction? {
        guard Self.shouldShowSidebarRevealInDestinationHeader(
            isSidebarVisible: self.isSidebarVisible,
            layoutMode: self.isSidebarDrawerLayout ? .drawer : .split)
        else {
            return nil
        }
        if self.isSidebarVisible {
            return OpenClawSidebarHeaderAction(
                systemName: "sidebar.left",
                accessibilityLabel: "Hide Sidebar",
                accessibilityIdentifier: Self.sidebarHideButtonAccessibilityIdentifier,
                action: { self.hideSidebar() })
        }
        return OpenClawSidebarHeaderAction(
            systemName: "sidebar.left",
            accessibilityLabel: "Show Sidebar",
            accessibilityIdentifier: Self.sidebarShowButtonAccessibilityIdentifier,
            action: { self.showSidebar() })
    }

    private var phoneChatReturnAction: OpenClawSidebarHeaderAction? {
        guard !self.usesSidebarTabs, let phoneChatReturn else { return nil }
        return OpenClawSidebarHeaderAction(
            systemName: "chevron.left",
            accessibilityLabel: "Back to \(phoneChatReturn.destination.title)",
            accessibilityIdentifier: "OpenClawChatBackToControlDetailButton",
            action: { self.openPhoneControlDetail(phoneChatReturn.destination) })
    }

    /// TabView writes through this binding; internal routing writes selectedTab directly.
    /// That distinction keeps only a user-selected Control tab responsible for resetting its child stack.
    private var phoneTabSelection: Binding<AppTab> {
        Binding(
            get: { self.selectedTab },
            set: { self.handlePhoneTabSelection($0) })
    }

    private var sidebarHideButton: some View {
        Button {
            self.hideSidebar()
        } label: {
            Image(systemName: self.isSidebarDrawerLayout ? "xmark" : "sidebar.left")
                .font(OpenClawType.subheadSemiBold)
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .foregroundStyle(OpenClawBrand.accent)
        .accessibilityLabel("Hide Sidebar")
        .accessibilityIdentifier(Self.sidebarHideButtonAccessibilityIdentifier)
    }

    private func shouldUseSidebarDrawer(containerSize: CGSize) -> Bool {
        Self.sidebarLayoutMode(containerSize: containerSize) == .drawer
    }

    private func sidebarWidth(containerWidth: CGFloat, isDrawerLayout: Bool) -> CGFloat {
        Self.sidebarWidth(containerWidth: containerWidth, isDrawerLayout: isDrawerLayout)
    }

    private func rootOverlays(_ content: some View) -> some View {
        content
            .overlay(alignment: .top) {
                // Stable container so the toast's move/opacity transition animates
                // when the gateway problem appears or clears outside withAnimation.
                ZStack(alignment: .top) {
                    if let gatewayProblem = self.activeGatewayProblemToast {
                        self.gatewayProblemToast(gatewayProblem)
                    }
                }
                .animation(self.gatewayToastAnimation, value: self.activeGatewayProblemToast)
            }
            .overlay(alignment: .topLeading) {
                if let voiceWakeToastText, !voiceWakeToastText.isEmpty {
                    VoiceWakeToast(command: voiceWakeToastText)
                        .padding(.leading, 10)
                        .safeAreaPadding(.top, self.activeGatewayProblemToast == nil ? 58 : 132)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }

            .overlay {
                if self.appModel.cameraFlashNonce != 0 {
                    RootCameraFlashOverlay(nonce: self.appModel.cameraFlashNonce)
                }
            }
            .overlay {
                if self.appModel.screen.isCanvasPresented {
                    self.canvasPresentationOverlay
                        .transition(.opacity)
                        .zIndex(20)
                }
            }
    }

    private var activeGatewayProblemToast: GatewayConnectionProblem? {
        // Operator-scope auth/pairing failures can coexist with a connected node.
        // The problem itself, not aggregate gateway status, owns toast visibility.
        guard let problem = appModel.lastGatewayProblem,
              !self.isGatewayToastSwipeDismissed
        else { return nil }
        return problem
    }

    private var gatewayToastAnimation: Animation? {
        self.reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)
    }

    private func gatewayProblemToast(_ problem: GatewayConnectionProblem) -> some View {
        GatewayProblemBanner(
            problem: problem,
            primaryActionTitle: gatewayProblemPrimaryActionTitle(problem),
            onPrimaryAction: {
                self.handleGatewayProblemPrimaryAction(problem)
            },
            onShowDetails: {
                self.showGatewayProblemDetails = true
            })
            .padding(.horizontal, 12)
            .safeAreaPadding(.top, 10)
            .offset(y: min(self.gatewayToastDragOffset, 0))
            .modifier(GatewayToastShakeEffect(animatableData: self.gatewayToastShake))
            .gesture(self.gatewayToastSwipeGesture)
            // A drag cancelled by toast removal never fires onEnded; clear the
            // offset so the next toast doesn't render shifted up.
            .onDisappear { self.gatewayToastDragOffset = 0 }
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var gatewayToastSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                self.gatewayToastDragOffset = value.translation.height
            }
            .onEnded { value in
                let swipedUp = value.translation.height < -32 || value.predictedEndTranslation.height < -80
                withAnimation(self.gatewayToastAnimation) {
                    if swipedUp {
                        self.isGatewayToastSwipeDismissed = true
                    }
                    self.gatewayToastDragOffset = 0
                }
            }
    }

    private func handleGatewayProblemReport() {
        let toastWasVisible = self.lastReportedGatewayProblem != nil && !self.isGatewayToastSwipeDismissed
        self.lastReportedGatewayProblem = self.appModel.lastGatewayProblem
        if self.isGatewayToastSwipeDismissed {
            self.isGatewayToastSwipeDismissed = false
            return
        }
        guard toastWasVisible, self.activeGatewayProblemToast != nil else { return }
        withAnimation(self.reduceMotion ? nil : .linear(duration: 0.4)) {
            self.gatewayToastShake += 1
        }
    }

    private var canvasPresentationOverlay: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            ScreenWebView(controller: self.appModel.screen)
                .ignoresSafeArea()
            Button {
                self.appModel.screen.hideCanvas()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.32), radius: 8, y: 2)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close canvas")
            .safeAreaPadding(.top, 8)
            .padding(.trailing, 12)
        }
    }

    private func rootLifecycle(_ content: some View) -> some View {
        self.rootRequestLifecycle(
            self.rootGatewayLifecycle(
                self.rootAppearLifecycle(
                    self.rootVoiceWakeLifecycle(content))))
    }

    private func rootVoiceWakeLifecycle(_ content: some View) -> some View {
        content
            .onChange(of: self.voiceWake.lastTriggeredCommand) { _, newValue in
                guard let newValue else { return }
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }

                self.toastDismissTask?.cancel()
                withAnimation(self.reduceMotion ? .none : .spring(response: 0.25, dampingFraction: 0.85)) {
                    self.voiceWakeToastText = trimmed
                }

                self.toastDismissTask = Task {
                    try? await Task.sleep(nanoseconds: 2_300_000_000)
                    await MainActor.run {
                        withAnimation(self.reduceMotion ? .none : .easeOut(duration: 0.25)) {
                            self.voiceWakeToastText = nil
                        }
                    }
                }
            }
    }

    private func rootAppearLifecycle(_ content: some View) -> some View {
        content
            .onAppear { self.updateIdleTimer() }
            .onAppear { self.lastReportedGatewayProblem = self.appModel.lastGatewayProblem }
            .onAppear { self.updateCanvasState() }
            .onAppear { self.evaluateOnboardingPresentation(force: false) }
            .onAppear { self.maybeAutoOpenSettings() }
            .onAppear { self.maybeOpenSettingsForGatewaySetup() }
            .onAppear { self.maybeShowQuickSetup() }
            .onAppear { self.applyInitialChatSessionIfNeeded() }
            .onChange(of: self.preventSleep) { _, _ in self.updateIdleTimer() }
            .onChange(of: self.appModel.talkMode.isEnabled) { _, _ in self.updateIdleTimer() }
            .onChange(of: self.scenePhase) { _, newValue in
                self.updateIdleTimer()
                self.updateHomeCanvasState()
                guard newValue == .active else { return }
                self.maybeRequestLocalNetworkAccess(reason: "scene_active")
                Task {
                    await self.appModel.refreshGatewayOverviewIfConnected()
                    await MainActor.run {
                        self.updateHomeCanvasState()
                    }
                }
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
                self.toastDismissTask?.cancel()
                self.toastDismissTask = nil
            }
    }

    private func rootGatewayProblemLifecycle(_ content: some View) -> some View {
        content
            .onChange(of: self.appModel.lastGatewayProblem) { _, newValue in
                if newValue == nil {
                    self.isGatewayToastSwipeDismissed = false
                    self.lastReportedGatewayProblem = nil
                }
            }
            .onChange(of: self.appModel.gatewayProblemReportCount) { _, _ in
                self.handleGatewayProblemReport()
            }
    }

    private func rootGatewayLifecycle(_ content: some View) -> some View {
        self.rootGatewayProblemLifecycle(content)
            .onChange(of: self.canvasDebugStatusEnabled) { _, _ in self.updateCanvasDebugStatus() }
            .onChange(of: self.gatewayController.gateways.count) { _, _ in self.maybeShowQuickSetup() }
            .onChange(of: self.appModel.gatewayServerName) { _, newValue in
                if newValue != nil {
                    self.onboardingComplete = true
                    self.hasConnectedOnce = true
                    OnboardingStateStore.markCompleted(mode: nil)
                }
                self.maybeAutoOpenSettings()
                self.maybeShowQuickSetup()
                self.updateCanvasState()
            }
            .onChange(of: self.appModel.gatewayStatusText) { _, _ in self.updateCanvasState() }
            .onChange(of: self.appModel.gatewayRemoteAddress) { _, _ in self.updateCanvasState() }
            .onChange(of: self.appModel.gatewayDisplayStatusText) { _, _ in self.updateCanvasState() }
            .onChange(of: self.appModel.homeCanvasRevision) { _, _ in self.updateHomeCanvasState() }
            .onChange(of: self.appModel.gatewayAgents.count) { _, _ in self.updateHomeCanvasState() }
            .onChange(of: self.appModel.selectedAgentId) { _, _ in self.updateHomeCanvasState() }
            .onChange(of: self.appModel.gatewayDefaultAgentId) { _, _ in self.updateHomeCanvasState() }
            .onChange(of: self.appModel.activeAgentName) { _, _ in self.updateHomeCanvasState() }
            .onChange(of: self.appModel.connectedGatewayID) { _, _ in
                self.updateCanvasState()
            }
    }

    private func rootRequestLifecycle(_ content: some View) -> some View {
        content
            .onChange(of: self.onboardingRequestID) { _, _ in
                self.evaluateOnboardingPresentation(force: true)
            }
            .onChange(of: self.showOnboarding) { _, newValue in
                guard !newValue else { return }
                self.maybeRequestLocalNetworkAccess(reason: "onboarding_dismissed")
            }
            .onChange(of: self.appModel.openChatRequestID) { _, newValue in
                self.handleOpenChatRequest(newValue)
            }
            .onChange(of: self.appModel.gatewaySetupRequestID) { _, _ in
                self.maybeOpenSettingsForGatewaySetup()
            }
            .onChange(of: self.appModel.pendingExecApprovalPrompt?.id) { _, newValue in
                if newValue != self.suppressedExecApprovalPromptIDForNotificationSettings {
                    self.suppressedExecApprovalPromptIDForNotificationSettings = nil
                }
            }
    }

    /// The connection sheet presents with no custom presenter recede. Ground-truth experiments proved a
    /// clean whole-app recede isn't achievable in SwiftUI here: a `WindowGroup` root doesn't get the native
    /// page-sheet presenter scale-back; live-scaling the app collapses its `ignoresSafeArea` edge-bleed and
    /// snaps it back at scale==1 (the "paper cut"); and `.drawingGroup()`/snapshot flattening fails on the
    /// app's WebView/glass/Metal content. Pass-through until we choose a deliberate approach.
    private func recedingRoot(_ content: some View) -> some View {
        content
    }

    private func rootPresentation(_ content: some View) -> some View {
        self.recedingRoot(content)
            .sheet(isPresented: self.$showGatewayProblemDetails) {
                if let gatewayProblem = self.appModel.lastGatewayProblem {
                    GatewayProblemDetailsSheet(
                        problem: gatewayProblem,
                        primaryActionTitle: self.gatewayProblemPrimaryActionTitle(gatewayProblem),
                        onPrimaryAction: {
                            self.handleGatewayProblemPrimaryAction(gatewayProblem)
                        })
                }
            }
            .sheet(item: self.$presentedSheet) { sheet in
                switch sheet {
                case .quickSetup:
                    GatewayQuickSetupSheet()
                        .environment(self.appModel)
                        .environment(self.gatewayController)
                        .openClawSheetChrome()
                }
            }
            .sheet(isPresented: self.$showConnectionSheet) {
                ConnectionSheetHostView(
                    onScanFullAccess: {
                        // Upgrading to full access means scanning a new (full-access) QR — launch the
                        // onboarding pairing flow straight into the scanner, not the read-only gateway
                        // details page. Defer so the sheet finishes dismissing before the cover presents.
                        self.showConnectionSheet = false
                        self.onboardingAutoScan = true
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(400))
                            self.evaluateOnboardingPresentation(force: true)
                        }
                    },
                    onClose: { self.showConnectionSheet = false })
                    .environment(self.appModel)
                    .environment(self.gatewayController)
                    .presentationCornerRadius(47)
                    .presentationDragIndicator(.hidden)
            }
            .fullScreenCover(isPresented: self.$showOnboarding) {
                OnboardingWizardView(
                    allowSkip: self.onboardingAllowSkip,
                    autoOpenScanner: self.onboardingAutoScan,
                    onRequestLocalNetworkAccess: { reason in
                        self.requestLocalNetworkAccess(reason: reason)
                    },
                    onClose: {
                        self.showOnboarding = false
                        self.onboardingAutoScan = false
                    },
                    onComplete: {
                        self.showOnboarding = false
                        self.onboardingAutoScan = false
                        self.selectSidebarDestination(.chat)
                    })
                    .environment(self.appModel)
                    .environment(self.voiceWake)
                    .environment(self.gatewayController)
            }
            .gatewayTrustPromptAlert(isEnabled: !self.showOnboarding)
            .deepLinkAgentPromptAlert()
            .execApprovalPromptDialog(
                suppressedApprovalID: self.activeExecApprovalPromptSuppressionID)
            .notificationPermissionGuidanceDialog(openNotifications: { approvalId in
                self.suppressedExecApprovalPromptIDForNotificationSettings = approvalId
                self.selectSettingsRoute(.notifications)
            })
    }

    private var gatewayStatus: GatewayDisplayState {
        GatewayStatusBuilder.build(appModel: self.appModel)
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled =
            self.scenePhase == .active && (self.preventSleep || self.appModel.talkMode.isEnabled)
    }

    private func updateCanvasState() {
        self.updateHomeCanvasState()
        self.updateCanvasDebugStatus()
    }

    private func updateCanvasDebugStatus() {
        self.appModel.screen.setDebugStatusEnabled(self.canvasDebugStatusEnabled)
        guard self.canvasDebugStatusEnabled else { return }
        let title = self.appModel.gatewayDisplayStatusText.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = self.appModel.gatewayServerName ?? self.appModel.gatewayRemoteAddress
        self.appModel.screen.updateDebugStatus(title: title, subtitle: subtitle)
    }

    private func updateHomeCanvasState() {
        let payload = self.makeHomeCanvasPayload()
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8)
        else {
            self.appModel.screen.updateHomeCanvasState(json: nil)
            return
        }
        self.appModel.screen.updateHomeCanvasState(json: json)
    }

    private func makeHomeCanvasPayload() -> RootTabsHomeCanvasPayload {
        let gatewayName = normalized(appModel.gatewayServerName)
        let gatewayAddress = normalized(appModel.gatewayRemoteAddress)
        let gatewayLabel = gatewayName ?? gatewayAddress ?? "Gateway"
        let activeAgentID = self.resolveActiveAgentID()
        let agents = self.homeCanvasAgents(activeAgentID: activeAgentID)

        switch self.gatewayStatus {
        case .connected:
            return RootTabsHomeCanvasPayload(
                gatewayState: "connected",
                eyebrow: "\(gatewayLabel) online",
                title: "Command center",
                subtitle:
                "Use Chat for code work, Talk for realtime voice, and gateway tools for approved device actions.",
                gatewayLabel: gatewayLabel,
                activeAgentName: self.appModel.activeAgentName,
                activeAgentBadge: agents.first(where: { $0.isActive })?.badge ?? "OC",
                activeAgentCaption: "Routes chat and talk",
                agentCount: agents.count,
                agents: Array(agents.prefix(6)),
                footer: "OpenClaw only runs phone-side capabilities while the app is connected and permitted.")
        case .connecting:
            return RootTabsHomeCanvasPayload(
                gatewayState: "connecting",
                eyebrow: "Gateway handshake",
                title: "Reconnecting",
                subtitle:
                "Restoring the local node session, agent list, voice config, and device capability state.",
                gatewayLabel: gatewayLabel,
                activeAgentName: self.appModel.activeAgentName,
                activeAgentBadge: "OC",
                activeAgentCaption: "Session in progress",
                agentCount: agents.count,
                agents: Array(agents.prefix(4)),
                footer: "If the gateway is reachable, the local node should recover without re-pairing.")
        case .error, .disconnected:
            return RootTabsHomeCanvasPayload(
                gatewayState: self.gatewayStatus == .error ? "error" : "offline",
                eyebrow: self.gatewayStatus == .error ? "Gateway needs attention" : "OpenClaw iOS",
                title: "Pair a gateway",
                subtitle:
                "Connect this phone as a local node for chat, realtime voice, share intake, and approved device tools.",
                gatewayLabel: gatewayLabel,
                activeAgentName: "Main",
                activeAgentBadge: "OC",
                activeAgentCaption: "Connect to load your agents",
                agentCount: agents.count,
                agents: Array(agents.prefix(4)),
                footer:
                "Use Settings to scan a pairing QR code or paste a setup code from your OpenClaw gateway.")
        }
    }

    private func resolveActiveAgentID() -> String {
        let selected = normalized(appModel.selectedAgentId) ?? ""
        if !selected.isEmpty {
            return selected
        }
        return self.resolveDefaultAgentID()
    }

    private func resolveDefaultAgentID() -> String {
        normalized(self.appModel.gatewayDefaultAgentId) ?? ""
    }

    private func homeCanvasAgents(activeAgentID: String) -> [RootTabsHomeCanvasAgentCard] {
        let defaultAgentID = self.resolveDefaultAgentID()
        let cards = self.appModel.gatewayAgents.map { agent -> RootTabsHomeCanvasAgentCard in
            let isActive = !activeAgentID.isEmpty && agent.id == activeAgentID
            let isDefault = !defaultAgentID.isEmpty && agent.id == defaultAgentID
            return RootTabsHomeCanvasAgentCard(
                id: agent.id,
                name: self.homeCanvasName(for: agent),
                badge: self.homeCanvasBadge(for: agent),
                caption: isActive ? "Routed on this phone" : (isDefault ? "Gateway default" : "Available"),
                isActive: isActive)
        }

        return cards.sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive {
                return lhs.isActive
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func homeCanvasName(for agent: AgentSummary) -> String {
        normalized(agent.name) ?? agent.id
    }
}

extension RootTabs {
    private func selectSidebarDestination(
        _ destination: SidebarDestination,
        preservingChatReturn: Bool = false)
    {
        if destination != .chat || !preservingChatReturn {
            self.phoneChatReturn = nil
        }
        self.sidebarNavigationPath.removeAll()
        if destination.settingsRoute != .notifications {
            self.suppressedExecApprovalPromptIDForNotificationSettings = nil
        }
        self.selectedSidebarDestination = destination
        self.selectedSettingsRoute = destination.settingsRoute
        self.selectedTab = destination.appTab
        self.requestPhoneControlDestinationIfNeeded(destination)
        guard self.usesSidebarTabs, self.shouldCollapseSidebarAfterSelection else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            self.setSidebarVisible(false)
        }
    }

    private func openChatFromControlDetail(_ returnDestination: SidebarDestination) {
        // Detail screens focus a session before invoking this route callback. Remember that
        // synchronous request so its later observation cannot erase the contextual return.
        self.phoneChatReturn = PhoneChatReturn(
            destination: returnDestination,
            openChatRequestID: self.appModel.openChatRequestID)
        // Chat owns an embedded Settings stack. Pop it before routing so the requested
        // session and contextual return action cannot remain hidden behind Settings.
        self.phoneChatSettingsResetRequestID &+= 1
        self.selectSidebarDestination(.chat, preservingChatReturn: true)
    }

    private func handleOpenChatRequest(_ requestID: Int) {
        guard requestID != self.phoneChatReturn?.openChatRequestID else { return }
        self.selectSidebarDestination(.chat)
    }

    private func openPhoneControlDetail(_ destination: SidebarDestination) {
        self.selectSidebarDestination(destination)
        if destination == .overview {
            self.requestPhoneControlDestinationIfNeeded(destination, force: true)
        }
    }

    private func handlePhoneTabSelection(_ selectedTab: AppTab) {
        if selectedTab != .chat {
            self.phoneChatReturn = nil
        }
        if selectedTab == .control {
            self.requestPhoneControlNavigation(.root)
        }
        self.selectedTab = selectedTab
    }

    private func requestPhoneControlDestinationIfNeeded(
        _ destination: SidebarDestination,
        force: Bool = false)
    {
        guard !self.usesSidebarTabs else { return }
        guard destination.appTab == .control else { return }
        guard force || destination != .overview else { return }
        self.requestPhoneControlNavigation(.detail(destination))
    }

    private func requestPhoneControlNavigation(_ target: PhoneControlNavigationRequest.Target) {
        let requestID = (phoneControlNavigationRequest?.id ?? 0) &+ 1
        self.phoneControlNavigationRequest = PhoneControlNavigationRequest(id: requestID, target: target)
    }

    private func selectSettingsRoute(_ route: SettingsRoute) {
        self.phoneChatReturn = nil
        self.sidebarNavigationPath.removeAll()
        if route != .notifications {
            self.suppressedExecApprovalPromptIDForNotificationSettings = nil
        }
        self.selectedSettingsRoute = route
        self.selectedSettingsRouteRequestID &+= 1
        self.selectedSidebarDestination = .settings
        self.selectedTab = .settings
        guard self.usesSidebarTabs, self.shouldCollapseSidebarAfterSelection else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            self.setSidebarVisible(false)
        }
    }

    private func pushSidebarSettingsRoute(_ route: SettingsRoute) {
        // Push, don't replace: Back must return to the settings screen the
        // user came from (e.g. Approvals -> Notifications -> back -> Approvals).
        self.sidebarNavigationPath.append(route)
        self.handleSettingsRouteChange(route)
    }

    private func handleSettingsRouteChange(_ route: SettingsRoute?) {
        guard route != .notifications else { return }
        if route == nil {
            self.selectedSettingsRoute = nil
            if self.selectedTab == .settings {
                self.selectedSidebarDestination = .settings
            }
        }
        self.suppressedExecApprovalPromptIDForNotificationSettings = nil
    }

    private func showSidebar() {
        self.sidebarVisibilityUserOverridden = true
        withAnimation(.easeInOut(duration: 0.22)) {
            self.setSidebarVisible(true)
        }
    }

    private func hideSidebar() {
        self.sidebarVisibilityUserOverridden = true
        withAnimation(.easeInOut(duration: 0.22)) {
            self.setSidebarVisible(false)
        }
    }

    private func updateSidebarLayout(containerSize: CGSize, force: Bool) {
        let layoutMode = Self.sidebarLayoutMode(containerSize: containerSize)
        let previousLayoutMode: SidebarLayoutMode = self.isSidebarDrawerLayout ? .drawer : .split
        let didResolvePreviousLayout = self.didResolveSidebarLayout
        let layoutModeDidChange = layoutMode != previousLayoutMode
        self.didResolveSidebarLayout = true
        self.isSidebarDrawerLayout = layoutMode == .drawer
        if layoutModeDidChange && didResolvePreviousLayout {
            self.sidebarVisibilityUserOverridden = false
        }
        guard force || !self.sidebarVisibilityUserOverridden else { return }

        let preferredVisibility = Self.preferredSidebarVisibility(layoutMode: layoutMode)
        guard self.isSidebarVisible != preferredVisibility else { return }
        self.setSidebarVisible(preferredVisibility)
    }

    private func setSidebarVisible(_ isVisible: Bool) {
        self.isSidebarVisible = isVisible
    }

    private func homeCanvasBadge(for agent: AgentSummary) -> String {
        if let identity = agent.identity,
           let emoji = identity["emoji"]?.value as? String,
           let normalizedEmoji = normalized(emoji)
        {
            return normalizedEmoji
        }
        let words = self.homeCanvasName(for: agent)
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "_" })
            .prefix(2)
        let initials = words.compactMap(\.first).map(String.init).joined()
        if !initials.isEmpty {
            return initials.uppercased()
        }
        return "OC"
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func gatewayProblemPrimaryActionTitle(_ problem: GatewayConnectionProblem) -> String? {
        GatewayProblemPrimaryAction.title(
            for: problem,
            retryTitle: "Retry",
            resetTitle: "Reset onboarding",
            nonRetryableTitle: "Open Settings")
    }

    private func handleGatewayProblemPrimaryAction(_ problem: GatewayConnectionProblem) {
        if problem.suggestsOnboardingReset {
            // Reset bumps onboarding.requestID, which re-presents the wizard.
            let instanceId = UserDefaults.standard.string(forKey: "node.instanceId") ?? ""
            Task {
                await GatewayOnboardingReset.reset(appModel: self.appModel, instanceId: instanceId)
            }
        } else if problem.canTrustRotatedCertificate {
            Task { await self.gatewayController.trustRotatedGatewayCertificate(from: problem) }
        } else if GatewayProblemPrimaryAction.handleProtocolMismatchIfNeeded(problem) {
            return
        } else if problem.retryable {
            Task { await self.gatewayController.connectActiveGateway() }
        } else {
            self.selectSidebarDestination(.gateway)
        }
    }

    private func evaluateOnboardingPresentation(force: Bool) {
        if force {
            // Skippable only when a usable gateway still exists (e.g. re-opening to add or upgrade a
            // gateway). After a disconnect/reset there are no credentials, so onboarding is mandatory —
            // no close affordance — otherwise the user could dismiss it straight back into a
            // credential-less app and think nothing reset.
            self.onboardingAllowSkip = self.appModel.gatewayServerName != nil || self.hasExistingGatewayConfig()
            self.showOnboarding = true
            return
        }

        guard !self.didEvaluateOnboarding else { return }
        self.didEvaluateOnboarding = true
        let route = Self.startupPresentationRoute(
            gatewayConnected: self.appModel.gatewayServerName != nil,
            hasConnectedOnce: self.hasConnectedOnce,
            onboardingComplete: self.onboardingComplete,
            hasExistingGatewayConfig: self.hasExistingGatewayConfig(),
            shouldPresentOnLaunch: OnboardingStateStore.shouldPresentOnLaunch(appModel: self.appModel))
        switch route {
        case .none:
            self.maybeRequestLocalNetworkAccess(reason: "root_appear")
        case .onboarding:
            // First-run onboarding is mandatory: no close affordance until the
            // gateway is connected. Re-opening from settings (force) allows skip.
            self.onboardingAllowSkip = false
            self.showOnboarding = true
        case .settings:
            self.didAutoOpenSettings = true
            self.selectSidebarDestination(.gateway)
            self.maybeRequestLocalNetworkAccess(reason: "root_appear")
        }
    }

    private func hasExistingGatewayConfig() -> Bool {
        if self.appModel.activeGatewayConnectConfig != nil {
            return true
        }
        if GatewaySettingsStore.activeGatewayEntry() != nil {
            return true
        }

        let preferredStableID = self.preferredGatewayStableID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !preferredStableID.isEmpty {
            return true
        }

        let manualHost = self.manualGatewayHost.trimmingCharacters(in: .whitespacesAndNewlines)
        return self.manualGatewayEnabled && !manualHost.isEmpty
    }

    private func maybeAutoOpenSettings() {
        guard !self.didAutoOpenSettings else { return }
        guard !self.showOnboarding else { return }
        let route = Self.startupPresentationRoute(
            gatewayConnected: self.appModel.gatewayServerName != nil,
            hasConnectedOnce: self.hasConnectedOnce,
            onboardingComplete: self.onboardingComplete,
            hasExistingGatewayConfig: self.hasExistingGatewayConfig(),
            shouldPresentOnLaunch: false)
        guard route == .settings else { return }
        self.didAutoOpenSettings = true
        self.selectSidebarDestination(.gateway)
        self.maybeRequestLocalNetworkAccess(reason: "auto_open_settings")
    }

    private func maybeOpenSettingsForGatewaySetup() {
        let requestID = self.appModel.gatewaySetupRequestID
        guard requestID != 0, requestID != self.gatewaySetupRequest?.id else { return }
        // The presented onboarding flow owns setup-link staging until it dismisses.
        guard !self.showOnboarding else { return }
        guard let link = appModel.consumePendingGatewaySetupLink() else { return }
        self.showOnboarding = false
        self.presentedSheet = nil
        self.didAutoOpenSettings = true
        self.selectSidebarDestination(.gateway)
        // Root owns delivery so embedded Settings views cannot consume the one-shot link.
        self.gatewaySetupRequest = GatewaySetupRequest(id: requestID, link: link)
        self.requestLocalNetworkAccess(reason: "gateway_setup_deeplink")
    }

    private func handleGatewaySetupRequest(_ requestID: Int) {
        guard self.gatewaySetupRequest?.id == requestID else { return }
        self.gatewaySetupRequest = nil
    }

    private func maybeRequestLocalNetworkAccess(reason: String) {
        guard self.didEvaluateOnboarding else { return }
        guard self.scenePhase == .active else { return }
        guard !self.showOnboarding else { return }
        self.requestLocalNetworkAccess(reason: reason)
    }

    private func requestLocalNetworkAccess(reason: String) {
        guard !self.appModel.isAppleReviewDemoModeEnabled else { return }
        self.gatewayController.requestLocalNetworkAccess(reason: reason)
    }

    private func applyInitialChatSessionIfNeeded() {
        guard !self.didApplyInitialChatSession else { return }
        self.didApplyInitialChatSession = true
        self.appModel.focusChatSession(Self.initialChatSessionKey)
    }

    private func maybeShowQuickSetup() {
        let shouldPresent = Self.shouldPresentQuickSetup(
            quickSetupDismissed: self.quickSetupDismissed,
            showOnboarding: self.showOnboarding,
            hasPresentedSheet: self.presentedSheet != nil,
            gatewayConnected: self.appModel.gatewayServerName != nil,
            hasExistingGatewayConfig: self.hasExistingGatewayConfig(),
            discoveredGatewayCount: self.gatewayController.gateways.count)
        guard shouldPresent else { return }
        self.presentedSheet = .quickSetup
    }
}

/// Phone tabs push Settings routes (gateway, voice) onto their own stack so
/// Back returns to the tab content the user navigated from; only global flows
/// (deep links, onboarding, problem banner) jump to the canonical Settings tab.
private struct PhoneTabSettingsHost<Content: View>: View {
    @State private var settingsPath: [SettingsRoute] = []
    /// True while a left→right back-swipe is engaged. Row taps are gated on this so a swipe that passes
    /// over a grouped-list item doesn't ALSO open that item (which pushed a route while the swipe popped
    /// the stack — leaving a dangling destination whose back went straight to chat).
    @State private var swipeBackActive = false
    private let resetRequestID: Int
    private let onOpenConnection: () -> Void
    @Binding private var pendingRoute: SettingsRoute?
    /// Mirrors "a Settings route is pushed over the chat root" so the surrounding shell can disable the
    /// chat drawer's drag-to-open while Settings is visible.
    @Binding private var isPresentingSettings: Bool
    private let content: (_ openSettingsRoute: @escaping (SettingsRoute) -> Void) -> Content

    init(
        resetRequestID: Int = 0,
        onOpenConnection: @escaping () -> Void = {},
        pendingRoute: Binding<SettingsRoute?> = .constant(nil),
        isPresentingSettings: Binding<Bool> = .constant(false),
        @ViewBuilder content: @escaping (_ openSettingsRoute: @escaping (SettingsRoute) -> Void) -> Content)
    {
        self.resetRequestID = resetRequestID
        self.onOpenConnection = onOpenConnection
        self._pendingRoute = pendingRoute
        self._isPresentingSettings = isPresentingSettings
        self.content = content
    }

    var body: some View {
        NavigationStack(path: self.$settingsPath) {
            self.content { route in
                self.settingsPath.append(route)
            }
            .navigationDestination(for: SettingsRoute.self) { route in
                // The Settings entry (.home) opens the redesigned root menu, which pushes its rows'
                // routes onto this same stack; redesigned destinations render here, others fall back
                // to the existing SettingsProTab screen. Every destination gets a left→right
                // swipe-to-go-back (mirrors the chat drawer gesture) that pops this stack from anywhere.
                Group {
                    switch route {
                    case .home:
                        SettingsRootContainer(
                            onBack: { self.settingsPath.removeLast() },
                            onOpenRoute: {
                                if !self.swipeBackActive {
                                    self.settingsPath.append($0)
                                }
                            },
                            onOpenConnection: self.onOpenConnection)
                            .toolbar(.hidden, for: .navigationBar)
                    case .approvals:
                        ApprovalsScreen(onBack: { self.settingsPath.removeLast() })
                    case .permissions:
                        PermissionsScreen(onBack: { self.settingsPath.removeLast() })
                    case .notifications:
                        NotificationsScreen(onBack: { self.settingsPath.removeLast() })
                    case .channels:
                        ChannelsScreenHost(onBack: { self.settingsPath.removeLast() })
                    case .voice:
                        VoiceSettingsScreenHost(
                            onBack: { self.settingsPath.removeLast() },
                            onOpenWakeWords: {
                                if !self.swipeBackActive {
                                    self.settingsPath.append(.wakeWords)
                                }
                            })
                    case .wakeWords:
                        WakeWordsScreenHost(onBack: { self.settingsPath.removeLast() })
                    case .licenses:
                        LicensesScreen(onBack: { self.settingsPath.removeLast() })
                    default:
                        SettingsProTab(directRoute: route)
                    }
                }
                .modifier(SwipeToGoBack(isActive: self.$swipeBackActive) {
                    if !self.settingsPath.isEmpty {
                        self.settingsPath.removeLast()
                    }
                })
            }
        }
        .onChange(of: self.settingsPath.isEmpty) { _, isEmpty in
            self.isPresentingSettings = !isEmpty
        }
        .onChange(of: self.resetRequestID) { _, _ in
            self.settingsPath.removeAll()
        }
        // A root-presented sheet (Connection) requests a settings route on dismiss; push it here.
        .onChange(of: self.pendingRoute) { _, route in
            guard let route else { return }
            self.settingsPath.append(route)
            self.pendingRoute = nil
        }
    }
}

/// Left→right swipe-to-go-back, mirroring the chat drawer's open gesture: a full-width
/// `.simultaneousGesture` that shares touches with the screen's vertical scroll. It latches on the first
/// significant movement and only fires `action` when the swipe is clearly rightward and horizontally
/// dominant (and travels/flicks far enough), so vertical scrolling and taps pass through untouched.
private struct SwipeToGoBack: ViewModifier {
    @Binding var isActive: Bool
    let action: () -> Void
    @State private var engaged: Bool?

    init(isActive: Binding<Bool>, _ action: @escaping () -> Void) {
        self._isActive = isActive
        self.action = action
    }

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    if self.engaged == nil {
                        self.engaged = value.translation.width > 0
                            && abs(value.translation.width) > abs(value.translation.height)
                    }
                    // Flag the instant the swipe is a rightward drag, so a row it passes over is suppressed
                    // for this gesture (row taps fire on touch-up, alongside `onEnded`).
                    if self.engaged == true, !self.isActive {
                        self.isActive = true
                    }
                }
                .onEnded { value in
                    let committed = self.engaged == true
                        && (value.translation.width > 80 || value.predictedEndTranslation.width > 200)
                    self.engaged = nil
                    if committed {
                        self.action()
                    }
                    // Clear on the next runloop so a same-touch row tap still sees the flag set.
                    DispatchQueue.main.async { self.isActive = false }
                })
    }
}

private struct RootTabsHomeCanvasPayload: Codable {
    var gatewayState: String
    var eyebrow: String
    var title: String
    var subtitle: String
    var gatewayLabel: String
    var activeAgentName: String
    var activeAgentBadge: String
    var activeAgentCaption: String
    var agentCount: Int
    var agents: [RootTabsHomeCanvasAgentCard]
    var footer: String
}

private struct RootTabsHomeCanvasAgentCard: Codable {
    var id: String
    var name: String
    var badge: String
    var caption: String
    var isActive: Bool
}

/// Horizontal shake for re-reported gateway problems: three oscillations that
/// settle back to identity at integer trigger values.
private struct GatewayToastShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size _: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 7 * sin(self.animatableData * 6 * .pi), y: 0))
    }
}

private struct RootCameraFlashOverlay: View {
    var nonce: Int

    @State private var opacity: CGFloat = 0
    @State private var task: Task<Void, Never>?

    var body: some View {
        Color.white
            .opacity(self.opacity)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .onChange(of: self.nonce) { _, _ in
                self.task?.cancel()
                self.task = Task { @MainActor in
                    withAnimation(.easeOut(duration: 0.08)) {
                        self.opacity = 0.85
                    }
                    try? await Task.sleep(nanoseconds: 110_000_000)
                    withAnimation(.easeOut(duration: 0.32)) {
                        self.opacity = 0
                    }
                }
            }
            .onDisappear {
                self.task?.cancel()
                self.task = nil
            }
    }
}

extension EnvironmentValues {
    @Entry var rootTabsUserInterfaceIdiomOverride: UIUserInterfaceIdiom?
}

#if DEBUG
#Preview(
    "Shell iPhone portrait",
    traits: .fixedLayout(width: 393, height: 852),
    .portrait)
{
    RootTabsPreviewHost(idiom: .phone)
}

#Preview(
    "Shell iPhone connected",
    traits: .fixedLayout(width: 393, height: 852),
    .portrait)
{
    RootTabsPreviewHost(idiom: .phone, gatewayState: .connected)
}

#Preview(
    "Shell iPhone gateway error",
    traits: .fixedLayout(width: 393, height: 852),
    .portrait)
{
    RootTabsPreviewHost(idiom: .phone, gatewayState: .error)
}

#Preview(
    "Shell iPhone landscape",
    traits: .fixedLayout(width: 852, height: 393),
    .landscapeLeft)
{
    RootTabsPreviewHost(idiom: .phone)
        .environment(\.horizontalSizeClass, .regular)
        .environment(\.verticalSizeClass, .compact)
}

#Preview(
    "Shell iPad portrait drawer",
    traits: .fixedLayout(width: 1024, height: 1366),
    .portrait)
{
    RootTabsPreviewHost(idiom: .pad)
}

#Preview(
    "Shell iPad landscape split",
    traits: .fixedLayout(width: 1366, height: 1024),
    .landscapeLeft)
{
    RootTabsPreviewHost(idiom: .pad, gatewayState: .connected)
}

#Preview(
    "Shell iPad connecting",
    traits: .fixedLayout(width: 1366, height: 1024),
    .landscapeLeft)
{
    RootTabsPreviewHost(idiom: .pad, gatewayState: .connecting)
}

#Preview(
    "Shell iPad gateway error",
    traits: .fixedLayout(width: 1366, height: 1024),
    .landscapeLeft)
{
    RootTabsPreviewHost(idiom: .pad, gatewayState: .error)
}

private struct RootTabsPreviewHost: View {
    @State private var appearanceModel = AppAppearanceModel()
    @State private var appModel: NodeAppModel
    @State private var gatewayController: GatewayConnectionController
    private let idiom: UIUserInterfaceIdiom

    init(idiom: UIUserInterfaceIdiom, gatewayState: RootTabsPreviewGatewayState = .offline) {
        let appModel = NodeAppModel()
        gatewayState.apply(to: appModel)
        self.idiom = idiom
        _appModel = State(initialValue: appModel)
        _gatewayController = State(
            initialValue: GatewayConnectionController(appModel: appModel, startDiscovery: false))
    }

    var body: some View {
        RootTabs()
            .environment(self.appearanceModel)
            .environment(self.appModel)
            .environment(self.appModel.voiceWake)
            .environment(self.gatewayController)
            .environment(\.rootTabsUserInterfaceIdiomOverride, self.idiom)
    }
}

private enum RootTabsPreviewGatewayState {
    case offline
    case connecting
    case connected
    case error

    @MainActor
    func apply(to appModel: NodeAppModel) {
        switch self {
        case .offline:
            break
        case .connecting:
            appModel.gatewayStatusText = "Connecting..."
        case .connected:
            appModel.enterAppleReviewDemoMode()
        case .error:
            appModel.gatewayStatusText = "Gateway error: connection refused"
        }
    }
}

#endif
