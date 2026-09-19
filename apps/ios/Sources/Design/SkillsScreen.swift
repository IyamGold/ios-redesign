import SwiftUI

struct SkillListItem: Identifiable, Equatable {
    let id: String
    let name: String
    let descriptionText: String
    let emoji: String?
    let enabled: Bool
}

struct SkillsScreen: View {
    let skills: [SkillListItem]
    let hasAdminScope: Bool
    let onClose: () -> Void
    let onToggle: (SkillListItem, Bool) -> Void
    let onOpenSkill: (SkillListItem) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var query = ""

    var body: some View {
        ZStack(alignment: .top) {
            (self.colorScheme == .dark
                ? Color(red: 23 / 255, green: 23 / 255, blue: 23 / 255)
                : Color(red: 245 / 255, green: 244 / 255, blue: 250 / 255))
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 45) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 17))
                            .foregroundStyle(Color.primary.opacity(0.7))
                        TextField("Search skills", text: self.$query)
                            .font(.system(size: 17))
                            .autocorrectionDisabled()
                    }
                    .padding(.leading, 21)
                    .frame(height: 50)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        Capsule(style: .continuous)
                            .fill(self.colorScheme == .dark ? Color.black : .white)
                    }

                    VStack(spacing: 34) {
                        ForEach(self.filteredSkills) { skill in
                            self.skillRow(skill)
                        }
                        if self.filteredSkills.isEmpty {
                            Text(self.query.isEmpty ? "No skills installed yet." : "No matches.")
                                .font(.system(size: 16))
                                .foregroundStyle(Color.primary.opacity(0.6))
                                .frame(maxWidth: .infinity)
                                .padding(.top, 24)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            ZStack {
                Text("Skills")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.primary)
                HStack {
                    Button(action: self.onClose) {
                        Image("ChatCloseGlyph")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                            .foregroundStyle(Color.primary)
                            .frame(width: 40, height: 40)
                            // Frosted glass chrome, matching the Usage/Instances close buttons.
                            .background {
                                ChatGlassBackground(
                                    shape: Circle(),
                                    fill: self.colorScheme == .dark
                                        ? Color(red: 30 / 255, green: 30 / 255, blue: 30 / 255).opacity(0.2)
                                        : Color(red: 245 / 255, green: 244 / 255, blue: 250 / 255).opacity(0.2))
                            }
                            .shadow(color: .black.opacity(0.15), radius: 25, x: 0, y: 0)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
            }
            .padding(.top, 8)
            .padding(.bottom, 27)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var filteredSkills: [SkillListItem] {
        let trimmed = self.query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return self.skills }
        return self.skills.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.descriptionText.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private func skillRow(_ skill: SkillListItem) -> some View {
        HStack(spacing: 14) {
            Button {
                self.onOpenSkill(skill)
            } label: {
                HStack(spacing: 14) {
                    self.iconTile(skill)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 2) {
                            Text(skill.name)
                                .font(.system(size: 17))
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                            Image("SettingsChevronRightGlyph")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 16, height: 16)
                                .foregroundStyle(Color.primary.opacity(0.6))
                        }
                        Text(skill.descriptionText)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.primary.opacity(0.6))
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            if self.hasAdminScope {
                Toggle("", isOn: Binding(
                    get: { skill.enabled },
                    set: { self.onToggle(skill, $0) }))
                    .labelsHidden()
                    .tint(Color(red: 52 / 255, green: 199 / 255, blue: 89 / 255))
            }
        }
    }

    private func iconTile(_ skill: SkillListItem) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(self.colorScheme == .dark ? Color.black : .white)
            if let emoji = skill.emoji, !emoji.isEmpty {
                Text(emoji)
                    .font(.system(size: 24))
            } else {
                Image("SkillScrollGlyph")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 35, height: 35)
                    .foregroundStyle(Color.primary)
            }
        }
        .frame(width: 45, height: 45)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5)
        }
    }
}

/// Loads the active agent's skill roster for the drawer's Skills page and feeds `SkillsScreen`.
/// Mirrors `UsageScreenHost`/`InstancesScreenHost`: a targeted `skills.status` fetch (rather than the
/// heavier shared overview load) mapped to lightweight row models. Toggles are gated on real admin
/// scope, and each enable/disable routes to `skills.update`, reloading to reconcile with server truth.
struct SkillsScreenHost: View {
    let onClose: () -> Void

    @Environment(NodeAppModel.self) private var appModel
    /// The decoded server roster is the source of truth; the list/detail models derive from it so a
    /// single reload keeps both the grid and an open panel in sync.
    @State private var entries: [SkillStatusEntryLite] = []
    /// Optimistic enable/disable flips, keyed by skill; cleared on each reload once the server confirms.
    @State private var enabledOverrides: [String: Bool] = [:]
    @State private var selectedSkillKey: String?
    @State private var installingKey: String?
    @State private var installError: String?

    private var hasAdminScope: Bool {
        self.appModel.hasOperatorAdminScope
    }

    var body: some View {
        SkillsScreen(
            skills: self.listItems,
            hasAdminScope: self.hasAdminScope,
            onClose: self.onClose,
            onToggle: { item, enabled in
                Task { await self.toggle(key: item.id, enabled: enabled) }
            },
            onOpenSkill: { item in
                self.installError = nil
                self.selectedSkillKey = item.id
            })
            .task { await self.load() }
            .sheet(isPresented: Binding(
                get: { self.selectedSkillKey != nil },
                set: { presented in
                    if !presented {
                        self.selectedSkillKey = nil
                        self.installError = nil
                    }
                })) {
                    if let detail = self.selectedDetail {
                        SkillPanelSheet(
                            skill: detail,
                            hasAdminScope: self.hasAdminScope,
                            isInstalling: self.installingKey == detail.key,
                            installError: self.installError,
                            onToggleEnabled: { enabled in
                                Task { await self.toggle(key: detail.key, enabled: enabled) }
                            },
                            onInstall: { Task { await self.install(key: detail.key) } },
                            onClose: {
                                self.selectedSkillKey = nil
                                self.installError = nil
                            })
                            .presentationCornerRadius(47)
                    }
            }
    }

    // MARK: - Derived models

    private var listItems: [SkillListItem] {
        self.entries.map { entry in
            SkillListItem(
                id: entry.effectiveSkillKey,
                name: entry.name,
                descriptionText: entry.description ?? "",
                emoji: entry.emoji,
                enabled: self.isEnabled(entry))
        }
    }

    private var selectedDetail: SkillDetail? {
        guard let key = self.selectedSkillKey,
              let entry = self.entries.first(where: { $0.effectiveSkillKey == key })
        else { return nil }
        return SkillDetail(
            key: entry.effectiveSkillKey,
            name: entry.name,
            descriptionText: entry.description ?? "",
            emoji: entry.emoji,
            source: Self.normalized(entry.source) ?? "—",
            enabledGlobally: self.isEnabled(entry),
            installLabel: entry.installSummary)
    }

    /// The toggle drives the global enable/disable flag, so reflect that (not the allowlist/agent-filter
    /// blocked view), preferring any in-flight optimistic override.
    private func isEnabled(_ entry: SkillStatusEntryLite) -> Bool {
        self.enabledOverrides[entry.effectiveSkillKey] ?? entry.isGloballyEnabled
    }

    // MARK: - Loading + mutations

    /// Skill status is agent-scoped; fall back through the same chain the Agent tab uses.
    private var activeAgentID: String {
        Self.normalized(self.appModel.selectedAgentId)
            ?? Self.normalized(self.appModel.gatewayDefaultAgentId)
            ?? "main"
    }

    private var skillsParams: String {
        guard let data = try? JSONEncoder().encode(["agentId": self.activeAgentID]),
              let json = String(data: data, encoding: .utf8)
        else { return "{}" }
        return json
    }

    private func load() async {
        guard
            let data = try? await self.appModel.operatorSession.request(
                method: "skills.status",
                paramsJSON: self.skillsParams,
                timeoutSeconds: 15),
            let report = try? JSONDecoder().decode(SkillStatusReportLite.self, from: data)
        else { return }
        self.entries = report.skills
        self.enabledOverrides = [:]
    }

    private func toggle(key: String, enabled: Bool) async {
        guard self.hasAdminScope else { return }
        // Optimistic flip so the switch animates immediately; the reload below reconciles truth.
        self.enabledOverrides[key] = enabled
        let params = SkillUpdateParams(skillKey: key, enabled: enabled)
        guard let data = try? JSONEncoder().encode(params),
              let json = String(data: data, encoding: .utf8)
        else { return }
        _ = try? await self.appModel.operatorSession.request(
            method: "skills.update",
            paramsJSON: json,
            timeoutSeconds: 20)
        await self.load()
    }

    private func install(key: String) async {
        guard self.hasAdminScope,
              let entry = self.entries.first(where: { $0.effectiveSkillKey == key }),
              let installId = Self.normalized(entry.install?.first?.id)
        else { return }
        self.installError = nil
        self.installingKey = key
        defer { self.installingKey = nil }
        let params = SkillInstallParams(name: entry.name, installId: installId, timeoutMs: 120_000)
        do {
            let data = try JSONEncoder().encode(params)
            guard let json = String(data: data, encoding: .utf8) else { return }
            _ = try await self.appModel.operatorSession.request(
                method: "skills.install",
                paramsJSON: json,
                timeoutSeconds: 125)
            // Success: reload drops the satisfied requirement, so installLabel recomputes to nil and
            // the panel's install block disappears.
            await self.load()
        } catch {
            self.installError = AgentProTab.skillMutationMessage(error)
        }
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Skill detail panel

struct SkillDetail: Equatable {
    let key: String
    let name: String
    let descriptionText: String
    let emoji: String?
    let source: String // e.g. "openclaw-bundled"
    let enabledGlobally: Bool
    let installLabel: String? // e.g. "Install 1password CLI (brew)"; nil = nothing to install
}

struct SkillPanelSheet: View {
    let skill: SkillDetail
    let hasAdminScope: Bool
    let isInstalling: Bool
    let installError: String?
    let onToggleEnabled: (Bool) -> Void
    let onInstall: () -> Void
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private static let actionRed = Color(red: 195 / 255, green: 63 / 255, blue: 51 / 255)
    private static let errorRed = Color(red: 211 / 255, green: 21 / 255, blue: 21 / 255)

    var body: some View {
        ZStack(alignment: .top) {
            (self.colorScheme == .dark
                ? Color(red: 23 / 255, green: 23 / 255, blue: 23 / 255)
                : Color(red: 245 / 255, green: 244 / 255, blue: 250 / 255))
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    self.iconTile

                    Text(self.skill.name)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Color.primary)
                        .padding(.top, 32)

                    Text(self.skill.descriptionText)
                        .font(.system(size: 16))
                        .foregroundStyle(Color.primary.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)

                    self.enabledCard
                        .padding(.top, 32)

                    self.metaCard
                        .padding(.top, 16)

                    if let installLabel = self.skill.installLabel, self.hasAdminScope {
                        self.installButton(installLabel)
                            .padding(.top, 16)

                        if let installError, !self.isInstalling {
                            Text(installError)
                                .font(.system(size: 14))
                                .foregroundStyle(Self.errorRed)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 10)
                        }
                    }

                    Spacer(minLength: 40)
                }
                // Spec: content column inset 24pt; icon tile sits 87pt from the sheet top, i.e. 25pt
                // below the 62pt-tall header reserved by the top inset below.
                .padding(.horizontal, 24)
                .padding(.top, 25)
            }
        }
        // A top inset (not an overlay) so the header reserves its own height and the scroll content
        // starts below it. Header geometry matches the spec: 40pt glass close at (25, 22), centered
        // 20pt title at y 29 — the inset's intrinsic height (22 + 40) is the 62pt used above.
        .safeAreaInset(edge: .top, spacing: 0) {
            ZStack(alignment: .top) {
                HStack {
                    Button(action: self.onClose) {
                        Image("ChatCloseGlyph")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                            .foregroundStyle(Color.primary)
                            .frame(width: 40, height: 40)
                            // Frosted glass chrome, matching the Usage/Instances/Skills close buttons.
                            .background {
                                ChatGlassBackground(
                                    shape: Circle(),
                                    fill: self.colorScheme == .dark
                                        ? Color(red: 30 / 255, green: 30 / 255, blue: 30 / 255).opacity(0.2)
                                        : Color(red: 245 / 255, green: 244 / 255, blue: 250 / 255).opacity(0.2))
                            }
                            .shadow(color: .black.opacity(0.15), radius: 25, x: 0, y: 0)
                    }
                    Spacer()
                }
                .padding(.leading, 25)
                .padding(.top, 22)

                Text(self.skill.name)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .frame(maxWidth: 188)
                    .padding(.top, 29)
            }
        }
    }

    // MARK: - Pieces

    private var iconTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(self.cardFill)
            if let emoji = self.skill.emoji, !emoji.isEmpty {
                Text(emoji).font(.system(size: 32))
            } else {
                Image("DrawerScrollGlyph")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                    .foregroundStyle(Color.primary)
            }
        }
        .frame(width: 60, height: 60)
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.7)
        }
    }

    private var enabledCard: some View {
        HStack {
            Text("Enabled Globally")
                .font(.system(size: 17))
                .foregroundStyle(Color.primary)
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(
                get: { self.skill.enabledGlobally },
                set: { self.onToggleEnabled($0) }))
                .labelsHidden()
                .tint(Color(red: 52 / 255, green: 199 / 255, blue: 89 / 255))
                .disabled(!self.hasAdminScope)
        }
        .padding(.horizontal, 17)
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(self.cardFill)
        }
    }

    private var metaCard: some View {
        // Horizontal inset lives on the ROWS (`metaRow`) so `OpenClawRowDivider` spans the card edges.
        VStack(spacing: 14) {
            self.metaRow("Key", self.skill.key)
            OpenClawRowDivider()
            self.metaRow("Source", self.skill.source)
        }
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(self.cardFill)
        }
    }

    private func installButton(_ label: String) -> some View {
        Button(action: self.onInstall) {
            Group {
                if self.isInstalling {
                    ProgressView()
                        .tint(Self.actionRed)
                } else {
                    Text(label)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Self.actionRed)
                }
            }
            .frame(height: 50)
            .frame(maxWidth: .infinity)
            .background {
                Capsule(style: .continuous)
                    .fill(Self.actionRed.opacity(0.38))
            }
        }
        .disabled(self.isInstalling)
    }

    private var cardFill: Color {
        self.colorScheme == .dark ? .black : .white
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 16))
                .foregroundStyle(Color.primary.opacity(0.6))
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 17))
                .foregroundStyle(Color.primary)
        }
        .padding(.horizontal, 15)
    }
}
