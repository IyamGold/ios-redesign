import SwiftUI

enum SettingsThemeChoice: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
}

struct SettingsAgentOption: Identifiable, Equatable {
    let id: String
    let name: String
}

/// The redesigned Settings root as a self-contained component with injected bindings, so the host
/// drops it in with the existing destinations behind each row (per-destination redesigns follow
/// screen by screen). Branded typography (`OpenClawType`) and colors (`OpenClawBrand`) throughout.
struct SettingsRootScreen: View {
    @Binding var theme: SettingsThemeChoice
    let defaultAgent: SettingsAgentOption?
    let agentOptions: [SettingsAgentOption]
    let hasAdminScope: Bool
    let onSelectAgent: (SettingsAgentOption) -> Void
    let onBack: () -> Void
    let onOpenConnection: () -> Void
    let onOpenApprovals: () -> Void
    let onOpenPermissions: () -> Void
    let onOpenNotifications: () -> Void
    let onOpenChannels: () -> Void
    let onOpenVoice: () -> Void
    let onOpenLicenses: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @Environment(\.displayScale) private var displayScale

    private static let docsURL = URL(string: "https://docs.openclaw.ai")!

    var body: some View {
        ZStack(alignment: .top) {
            self.canvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    self.connectionPill
                    self.section("Control") {
                        self.cardRow(icon: "SettingsShieldGlyph", title: "Approvals", action: self.onOpenApprovals)
                        self.cardDivider
                        self.cardRow(icon: "SettingsToggleGlyph", title: "Permissions", action: self.onOpenPermissions)
                        self.cardDivider
                        self.defaultAgentRow
                    }
                    self.section("App settings") {
                        self.cardRow(
                            icon: "SettingsBellGlyph",
                            title: "Notifications",
                            action: self.onOpenNotifications)
                        self.cardDivider
                        self.cardRow(
                            icon: "SettingsUnplugGlyph",
                            title: "Channels & Integrations",
                            action: self.onOpenChannels)
                        self.cardDivider
                        self.cardRow(
                            icon: "SettingsWaveformGlyph",
                            title: "Voice settings",
                            action: self.onOpenVoice)
                    }
                    self.section("Appearance") {
                        self.themeRow
                    }
                    self.section("Reference") {
                        self.linkPillRow(icon: "SettingsBookGlyph", title: "Docs", url: Self.docsURL)
                    }
                    self.section("Licenses & agreements") {
                        // Routes to the in-app bundled Licenses screen (policy: keep the Settings
                        // Licenses screen), not an external URL.
                        self.cardRow(icon: "SettingsFileWarningGlyph", title: "Licenses", action: self.onOpenLicenses)
                    }
                }
                .padding(.horizontal, 24)
                // Clear the floating header; content scrolls beneath it under the frosted band.
                .padding(.top, 72)
                .padding(.bottom, 40)
            }
        }
        // Subtle frosted band so scrolled content fades under the header (matches the chat surface).
        .overlay(alignment: .top) { self.topScrim }
        .overlay(alignment: .top) { self.header }
        .toolbar(.hidden, for: .navigationBar)
    }

    /// Frosted top band: content scrolls beneath the header and fades out, half-strength blur then clear.
    private var topScrim: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            // `.ultraThinMaterial` lightens whatever scrolls beneath, so in dark mode tint it toward the
            // near-black canvas to keep the band dark and content-independent.
            .overlay { self.canvas.opacity(self.colorScheme == .dark ? 0.72 : 0) }
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.6), location: 0),
                        .init(color: .black.opacity(0.6), location: 0.55),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom)
            }
            .frame(height: 110)
            .frame(maxWidth: .infinity)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
    }

    // MARK: - Chrome

    private var header: some View {
        ZStack {
            // Design calls for SF Pro medium here, not the branded Display face.
            Text("Settings")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.primary)
            HStack {
                Button(action: self.onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        // Neutral glyph on a Liquid Glass circle with the same soft shadow as the chat
                        // floating buttons, so the nav reads as glass instead of a flat material.
                        .foregroundStyle(Color.primary)
                        .frame(width: 40, height: 40)
                        .background { ChatGlassBackground(shape: Circle(), fill: self.glassFill) }
                        .shadow(color: .black.opacity(0.15), radius: 25, x: 0, y: 0)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .padding(.top, 8)
        .padding(.bottom, 21)
    }

    // MARK: - Sections and rows

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            // Design calls for SF Pro medium here, not the branded Display face.
            Text(title)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.5))
                .padding(.leading, 17)
            // 17pt above/below the divider → ~34pt between rows, divider centered.
            VStack(spacing: 17) {
                content()
            }
            .padding(.vertical, 12)
            .padding(.leading, 17)
            .padding(.trailing, 12)
            .background {
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .fill(self.cardFill)
            }
        }
    }

    private var connectionPill: some View {
        Button(action: self.onOpenConnection) {
            HStack(spacing: 12) {
                Image("SettingsWifiGlyph")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    // #2563EB — matches the "Connection" label.
                    .foregroundStyle(OpenClawBrand.welcomeLink)
                Text("Connection")
                    .font(OpenClawType.body)
                    .foregroundStyle(OpenClawBrand.welcomeLink)
                Spacer(minLength: 0)
            }
            .padding(.leading, 16)
            .frame(height: 50)
            .frame(maxWidth: .infinity)
            .background {
                Capsule(style: .continuous).fill(self.cardFill)
            }
        }
    }

    private func cardRow(
        icon: String? = nil,
        iconView: AnyView? = nil,
        title: String,
        action: @escaping () -> Void) -> some View
    {
        Button(action: action) {
            HStack(spacing: 12) {
                if let iconView {
                    iconView
                } else if let icon {
                    Image(icon)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .foregroundStyle(Color.primary.opacity(0.7))
                }
                Text(title)
                    .font(OpenClawType.body)
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 0)
                Image("SettingsChevronRightGlyph")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(Color.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var cardDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.3))
            // Force full-width fill (bare shapes in a flexible row can size unevenly) and snap to a
            // single device pixel so every divider is the exact same length and crispness.
            .frame(maxWidth: .infinity)
            .frame(height: 1 / self.displayScale)
            .padding(.leading, 34)
    }

    private var defaultAgentRow: some View {
        HStack(spacing: 12) {
            Image("SettingsUsersGlyph")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .foregroundStyle(Color.primary.opacity(0.7))
            Text("Default Agent")
                .font(OpenClawType.body)
                .foregroundStyle(Color.primary)
            Spacer(minLength: 0)
            if self.hasAdminScope, self.agentOptions.count > 1 {
                Menu {
                    ForEach(self.agentOptions) { option in
                        Button { self.onSelectAgent(option) } label: {
                            Text(option.name)
                                .font(OpenClawType.body)
                        }
                    }
                } label: {
                    self.pickerTrailing(self.defaultAgent?.name ?? "—")
                }
            } else {
                Text(self.defaultAgent?.name ?? "—")
                    .font(OpenClawType.callout)
                    .foregroundStyle(Color.primary.opacity(0.6))
            }
        }
    }

    private var themeRow: some View {
        HStack(spacing: 12) {
            Image("SettingsSunGlyph")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .foregroundStyle(Color.primary.opacity(0.7))
            Text("Theme")
                .font(OpenClawType.body)
                .foregroundStyle(Color.primary)
            Spacer(minLength: 0)
            Menu {
                ForEach(SettingsThemeChoice.allCases, id: \.self) { choice in
                    Button { self.theme = choice } label: {
                        Text(choice.rawValue)
                            .font(OpenClawType.body)
                    }
                }
            } label: {
                self.pickerTrailing(self.theme.rawValue)
            }
        }
        .frame(height: 26)
    }

    private func linkPillRow(icon: String, title: String, url: URL) -> some View {
        Button {
            self.openURL(url)
        } label: {
            HStack(spacing: 12) {
                Image(icon)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .foregroundStyle(Color.primary.opacity(0.7))
                Text(title)
                    .font(OpenClawType.body)
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 0)
                Image("SettingsArrowUpRightGlyph")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    // The glyph bakes its own 0.3 opacity; tint at full strength so it isn't double-dimmed.
                    .foregroundStyle(Color.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func pickerTrailing(_ value: String) -> some View {
        HStack(spacing: 7) {
            Text(value)
                .font(OpenClawType.callout)
                .foregroundStyle(Color.primary.opacity(0.6))
            Image("SettingsChevronsUpDownGlyph")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                // The glyph bakes its own opacity; tint at full strength so it isn't double-dimmed.
                .foregroundStyle(Color.primary)
        }
    }

    // MARK: - Palette

    private var canvas: Color {
        self.colorScheme == .dark
            ? Color(red: 23 / 255, green: 23 / 255, blue: 23 / 255)
            : Color(red: 245 / 255, green: 244 / 255, blue: 250 / 255)
    }

    private var cardFill: Color {
        self.colorScheme == .dark
            ? Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255)
            : .white
    }

    /// Subtle tint under the Liquid Glass nav circle (matches the chat floating buttons).
    private var glassFill: Color {
        self.colorScheme == .dark
            ? Color(red: 30 / 255, green: 30 / 255, blue: 30 / 255).opacity(0.2)
            : Color(red: 245 / 255, green: 244 / 255, blue: 250 / 255).opacity(0.2)
    }
}

/// Wires the redesigned Settings root menu to the app model and appearance store. It does NOT own a
/// navigation stack — it renders inside the host's existing stack and pushes each row's destination via
/// `onOpenRoute`, so back/gesture behavior stays native (a nested stack mis-renders and glitches back).
struct SettingsRootContainer: View {
    @Environment(NodeAppModel.self) private var appModel
    @Environment(AppAppearanceModel.self) private var appearanceModel
    let onBack: () -> Void
    let onOpenRoute: (SettingsRoute) -> Void
    /// Tapped "Connection". Presented from the window root (see phoneTabContent) so the native
    /// page-sheet card-recede animates the app behind it — presenting from here, deep in the settings
    /// nav stack, suppresses that recede.
    let onOpenConnection: () -> Void

    var body: some View {
        SettingsRootScreen(
            theme: self.themeBinding,
            defaultAgent: self.currentDefaultAgentOption,
            agentOptions: self.agentOptions,
            hasAdminScope: self.appModel.hasOperatorAdminScope,
            onSelectAgent: { self.appModel.setSelectedAgentId($0.id) },
            onBack: self.onBack,
            onOpenConnection: self.onOpenConnection,
            onOpenApprovals: { self.onOpenRoute(.approvals) },
            onOpenPermissions: { self.onOpenRoute(.permissions) },
            onOpenNotifications: { self.onOpenRoute(.notifications) },
            onOpenChannels: { self.onOpenRoute(.channels) },
            onOpenVoice: { self.onOpenRoute(.voice) },
            onOpenLicenses: { self.onOpenRoute(.licenses) })
    }

    private var themeBinding: Binding<SettingsThemeChoice> {
        Binding(
            get: { SettingsThemeChoice(appearance: self.appearanceModel.preference) },
            set: { self.appearanceModel.select($0.appearance) })
    }

    private var agentOptions: [SettingsAgentOption] {
        self.appModel.gatewayAgents.map { agent in
            let trimmed = agent.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = (trimmed?.isEmpty == false) ? trimmed! : agent.id
            return SettingsAgentOption(id: agent.id, name: name)
        }
    }

    private var currentDefaultAgentOption: SettingsAgentOption? {
        let selectedID = self.normalized(self.appModel.selectedAgentId)
            ?? self.normalized(self.appModel.gatewayDefaultAgentId)
        guard let selectedID else { return self.agentOptions.first }
        return self.agentOptions.first { $0.id == selectedID } ?? self.agentOptions.first
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Owns the gateway wiring and renders `ConnectionSheet`. Lives at the window root (presented from
/// phoneTabContent) so the native page-sheet card-recede animates the app behind it.
struct ConnectionSheetHostView: View {
    @Environment(NodeAppModel.self) private var appModel
    @Environment(GatewayConnectionController.self) private var gatewayController
    @State private var switchingGateway = false
    let onScanFullAccess: () -> Void
    let onClose: () -> Void

    var body: some View {
        ConnectionSheet(
            gateways: self.connectionGatewayRows,
            hasFullAccess: self.appModel.hasOperatorAdminScope,
            onSelectGateway: { stableID in Task { await self.switchGateway(stableID) } },
            onScanFullAccess: self.onScanFullAccess,
            onDisconnect: {
                self.onClose()
                Task { await self.disconnect() }
            },
            onClose: self.onClose)
    }

    /// Read the persisted registry fresh each render — the store can be populated a beat after the app
    /// connects, and this view re-renders on the app-model changes that accompany that, so the list
    /// self-heals rather than showing a stale (possibly empty) snapshot.
    private var connectionGatewayRows: [ConnectionGatewayRow] {
        let registry = GatewaySettingsStore.loadGatewayRegistry()
        return registry.entries.map { entry in
            ConnectionGatewayRow(
                id: entry.stableID,
                name: entry.name,
                isFocused: entry.stableID == registry.activeStableID)
        }
    }

    /// Switch + reconnect via the controller (registry write alone does not reconnect). Toggling
    /// `switchingGateway` re-renders, so the fresh read above reflects the new active gateway.
    private func switchGateway(_ stableID: String) async {
        guard !self.switchingGateway else { return }
        self.switchingGateway = true
        defer { self.switchingGateway = false }
        _ = await self.gatewayController.switchToGateway(stableID: stableID)
    }

    /// Clears all gateway credentials and reopens onboarding.
    private func disconnect() async {
        await GatewayOnboardingReset.reset(
            appModel: self.appModel,
            instanceId: GatewaySettingsStore.currentInstanceID())
    }
}

extension SettingsThemeChoice {
    init(appearance: AppAppearancePreference) {
        switch appearance {
        case .system: self = .system
        case .light: self = .light
        case .dark: self = .dark
        }
    }

    var appearance: AppAppearancePreference {
        switch self {
        case .system: .system
        case .light: .light
        case .dark: .dark
        }
    }
}
