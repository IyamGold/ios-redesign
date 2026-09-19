import OpenClawKit
import OpenClawProtocol
import SwiftUI

struct InstanceRowModel: Identifiable, Equatable {
    let id: String
    let name: String
    let detail: String // "147.79.100.136 · linux…" / "iOS 26.5.2"
    let statusLabel: String // "Self" | "Connected" | presence state
}

struct InstancesScreen<Detail: View>: View {
    let gatewayOnline: Bool
    let instances: [InstanceRowModel]
    let onClose: () -> Void
    @ViewBuilder let detail: (InstanceRowModel) -> Detail

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    private static var learnMoreURL: URL {
        URL(string: "https://docs.openclaw.ai")!
    }

    var body: some View {
        ZStack(alignment: .top) {
            (self.colorScheme == .dark
                ? Color(red: 23 / 255, green: 23 / 255, blue: 23 / 255)
                : Color(red: 245 / 255, green: 244 / 255, blue: 250 / 255))
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    // Gateway card + caption
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text("Gateway")
                                .font(.system(size: 17))
                                .foregroundStyle(Color.primary)
                            Spacer(minLength: 0)
                            Text(self.gatewayOnline ? "Online" : "Offline")
                                .font(.system(size: 16))
                                .foregroundStyle(self.gatewayOnline
                                    ? Color(red: 52 / 255, green: 199 / 255, blue: 89 / 255)
                                    : Color(red: 211 / 255, green: 21 / 255, blue: 21 / 255))
                        }
                        .padding(.horizontal, 15)
                        .frame(height: 55)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(self.cardFill)
                        }

                        (Text("\(Self.countPhrase(self.instances.count)) connected to this gateway. ")
                            .foregroundColor(Color.primary.opacity(0.6))
                            + Text("Learn more.")
                            .foregroundColor(Color(red: 37 / 255, green: 99 / 255, blue: 235 / 255)))
                            .font(.system(size: 15))
                            .padding(.leading, 6)
                            .onTapGesture { self.openURL(Self.learnMoreURL) }
                    }

                    // Connected instances
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Connected Instances")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(0.5))
                            .padding(.leading, 15)
                        VStack(spacing: 14) {
                            ForEach(Array(self.instances.enumerated()), id: \.element.id) { index, instance in
                                NavigationLink {
                                    self.detail(instance)
                                } label: {
                                    HStack(spacing: 7) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(instance.name)
                                                .font(.system(size: 17))
                                                .foregroundStyle(Color.primary)
                                                .lineLimit(1)
                                            Text(instance.detail)
                                                .font(.system(size: 14))
                                                .foregroundStyle(Color.primary.opacity(0.4))
                                                .lineLimit(1)
                                        }
                                        Spacer(minLength: 0)
                                        Text(instance.statusLabel)
                                            .font(.system(size: 16))
                                            .foregroundStyle(Color.primary.opacity(0.6))
                                        Image("SettingsChevronRightGlyph")
                                            .renderingMode(.template)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 20, height: 20)
                                            .foregroundStyle(Color.primary.opacity(0.6))
                                    }
                                    // Row-level inset so the divider spans the card edges.
                                    .padding(.horizontal, 14)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if index < self.instances.count - 1 {
                                    OpenClawRowDivider()
                                }
                            }
                        }
                        .padding(.vertical, 15)
                        .background {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(self.cardFill)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            ZStack {
                Text("Instances")
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
            .padding(.bottom, 35)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var cardFill: Color {
        self.colorScheme == .dark ? .black : .white
    }

    private static func countPhrase(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        let word = (formatter.string(from: NSNumber(value: count)) ?? "\(count)").capitalized
        return count == 1
            ? "\(word) instance in total is"
            : "\(word) instances in total are"
    }
}

// MARK: - Presence formatting (shared by the drawer Instances screen and the iPad nodes destination)

enum PresenceFormatting {
    static func label(_ entry: PresenceEntry) -> String? {
        self.normalized(entry.host)
            ?? self.normalized(entry.devicefamily)
            ?? self.normalized(entry.platform)
            ?? self.normalized(entry.mode)
    }

    static func detail(_ entry: PresenceEntry) -> String {
        let parts = [
            self.normalized(entry.ip),
            self.normalized(entry.platform),
            self.normalized(entry.version),
        ].compactMap(\.self)
        if !parts.isEmpty {
            return parts.joined(separator: " • ")
        }
        return self.normalized(entry.text) ?? "Presence beacon received."
    }

    static func state(_ entry: PresenceEntry) -> String {
        if let reason = self.normalized(entry.reason) {
            return reason
        }
        if let mode = self.normalized(entry.mode) {
            return mode
        }
        return self.relativeTime(fromMilliseconds: entry.ts)
    }

    static func icon(_ entry: PresenceEntry) -> String {
        let family = self.normalized(entry.devicefamily)?.lowercased()
        if family?.contains("phone") == true {
            return "iphone"
        }
        if family?.contains("tablet") == true || family?.contains("pad") == true {
            return "ipad"
        }
        if family?.contains("desktop") == true || family?.contains("mac") == true {
            return "desktopcomputer"
        }
        return "display"
    }

    static func color(_ entry: PresenceEntry) -> Color {
        self.normalized(entry.reason) == nil ? OpenClawBrand.accent : OpenClawBrand.warn
    }

    static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    static func relativeTime(fromMilliseconds milliseconds: Int) -> String {
        let date = Date(timeIntervalSince1970: Double(milliseconds) / 1000)
        return date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }
}

extension PresenceEntry {
    /// Stable identity for a presence entry across refreshes.
    var presenceKey: String {
        self.instanceid
            ?? self.deviceid
            ?? self.host
            ?? self.ip
            ?? "\(self.ts)"
    }
}

// MARK: - Per-node detail (extracted from AgentProNodesDestination; shared by both surfaces)

struct NodeDetailScreen: View {
    let entry: PresenceEntry

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SettingsDestinationChrome(
            title: PresenceFormatting.label(self.entry) ?? "Instance",
            onBack: { self.dismiss() })
        {
            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    // Identity + technical details
                    self.card {
                        self.statusRow
                        OpenClawRowDivider()
                        self.detailRow("Instance", value: self.entry.instanceid)
                        OpenClawRowDivider()
                        self.detailRow("Device", value: self.entry.deviceid)
                        OpenClawRowDivider()
                        self.detailRow("Host", value: self.entry.host)
                        OpenClawRowDivider()
                        self.detailRow("IP", value: self.entry.ip)
                        OpenClawRowDivider()
                        self.detailRow("Platform", value: self.entry.platform)
                        OpenClawRowDivider()
                        self.detailRow("Version", value: self.entry.version)
                        OpenClawRowDivider()
                        self.detailRow("Mode", value: self.entry.mode)
                    }

                    self.listSection(title: "Scopes", values: self.entry.scopes ?? [])
                    self.listSection(title: "Roles", values: self.entry.roles ?? [])
                    self.listSection(title: "Tags", values: self.entry.tags ?? [])
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Pieces (mirrors the drawer Usage screen's grouped-list treatment)

    private func card(@ViewBuilder content: () -> some View) -> some View {
        // Horizontal inset lives on the ROWS (`rowInset`) so `OpenClawRowDivider` spans the card edges.
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(self.colorScheme == .dark ? Color.black : .white)
        }
    }

    /// Row-level horizontal inset (card no longer pads) so `OpenClawRowDivider` reaches the card edges.
    private func rowInset(_ view: some View) -> some View {
        view.padding(.horizontal, 15)
    }

    private var statusRow: some View {
        self.rowInset(HStack {
            Text("Status")
                .font(.system(size: 17))
                .foregroundStyle(Color.primary)
            Spacer(minLength: 0)
            Text(PresenceFormatting.state(self.entry))
                .font(.system(size: 16))
                .foregroundStyle(PresenceFormatting.color(self.entry))
        })
    }

    private func detailRow(_ title: String, value: String?) -> some View {
        self.rowInset(HStack {
            Text(title)
                .font(.system(size: 17))
                .foregroundStyle(Color.primary)
            Spacer(minLength: 0)
            Text(PresenceFormatting.normalized(value) ?? "n/a")
                .font(.system(size: 16))
                .foregroundStyle(Color.primary.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        })
    }

    private func listSection(title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.5))
                .padding(.leading, 15)
            self.card {
                if values.isEmpty {
                    self.rowInset(Text("None reported.")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.primary.opacity(0.6))
                        .frame(maxWidth: .infinity, alignment: .leading))
                } else {
                    ForEach(Array(values.enumerated()), id: \.element) { index, value in
                        self.rowInset(Text(value)
                            .font(.system(size: 16))
                            .foregroundStyle(Color.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled))
                        if index < values.count - 1 {
                            OpenClawRowDivider()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Drawer host

/// Loads system presence for the drawer's Instances page and feeds `InstancesScreen`, mapping each
/// presence entry to a row (marking this device as "Self") and providing `NodeDetailScreen` per row.
struct InstancesScreenHost: View {
    let onClose: () -> Void

    @Environment(NodeAppModel.self) private var appModel
    @State private var entries: [PresenceEntry] = []

    var body: some View {
        // The drawer presents this in a fullScreenCover with no navigation container, so provide one —
        // otherwise the row NavigationLinks (→ NodeDetailScreen) have nowhere to push.
        NavigationStack {
            InstancesScreen(
                gatewayOnline: self.appModel.gatewayServerName != nil,
                instances: self.rows,
                onClose: self.onClose)
            { row in
                if let entry = self.entries.first(where: { $0.presenceKey == row.id }) {
                    NodeDetailScreen(entry: entry)
                }
            }
            .task { await self.load() }
        }
    }

    private var rows: [InstanceRowModel] {
        let selfDeviceID = DeviceIdentityStore.loadOrCreate().deviceId
        return self.sortedEntries.map { entry in
            InstanceRowModel(
                id: entry.presenceKey,
                name: PresenceFormatting.label(entry) ?? "Instance",
                detail: PresenceFormatting.detail(entry),
                statusLabel: entry.deviceid == selfDeviceID ? "Self" : PresenceFormatting.state(entry))
        }
    }

    private var sortedEntries: [PresenceEntry] {
        self.entries.sorted { lhs, rhs in
            if lhs.ts != rhs.ts {
                return lhs.ts > rhs.ts
            }
            return (PresenceFormatting.label(lhs) ?? lhs.presenceKey)
                .localizedCaseInsensitiveCompare(PresenceFormatting.label(rhs) ?? rhs.presenceKey)
                == .orderedAscending
        }
    }

    private func load() async {
        guard
            let data = try? await self.appModel.operatorSession.request(
                method: "system-presence",
                paramsJSON: "{}",
                timeoutSeconds: 8),
            let decoded = try? JSONDecoder().decode([PresenceEntry].self, from: data)
        else { return }
        self.entries = decoded
    }
}
