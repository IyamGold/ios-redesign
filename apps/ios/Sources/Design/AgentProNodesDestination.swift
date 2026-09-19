import OpenClawProtocol
import SwiftUI

struct AgentProNodesDestination: View {
    let headerLeadingAction: OpenClawSidebarHeaderAction?
    let overview: AgentOverviewSnapshot?
    let gatewayConnected: Bool
    let agentCount: Int
    let instancesValue: String
    let instancesDetail: String
    let instancesColor: Color
    let refresh: () async -> Void

    var body: some View {
        ZStack {
            OpenClawProBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    self.header
                    self.summaryCard
                    self.totalsCard
                    self.nodesList
                }
                .padding(.vertical, 18)
                .font(OpenClawType.body)
            }
            .refreshable {
                await self.refresh()
            }
            .safeAreaPadding(.bottom, OpenClawProMetric.bottomScrollInset)
        }
        .navigationTitle("Instances")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var header: some View {
        if let headerLeadingAction {
            OpenClawAdaptiveHeaderRow(
                title: "Instances",
                subtitle: self.instancesDetail,
                titleFont: OpenClawType.title3SemiBold,
                subtitleFont: OpenClawType.subheadMedium)
            {
                OpenClawSidebarHeaderLeadingSlot(action: headerLeadingAction)
            } accessory: {
                EmptyView()
            }
            .padding(.horizontal, OpenClawProMetric.pagePadding)
        }
    }

    private var summaryCard: some View {
        ProCard {
            HStack(spacing: 12) {
                ProIconBadge(systemName: "display", color: self.instancesColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Instances")
                        .font(OpenClawType.headline)
                    Text(self.instancesDetail)
                        .font(OpenClawType.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                ProValuePill(value: self.instancesValue, color: self.instancesColor)
            }
        }
        .padding(.horizontal, OpenClawProMetric.pagePadding)
    }

    private var totalsCard: some View {
        ProCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Presence")
                        .font(OpenClawType.headline)
                    Spacer()
                    ProValuePill(value: self.instancesValue, color: self.instancesColor)
                }
                HStack(spacing: 10) {
                    self.detailMetric(label: "Connected", value: "\(self.overview?.presence.count ?? 0)")
                    self.detailMetric(label: "Agents", value: "\(self.agentCount)")
                    self.detailMetric(label: "Gateway", value: self.gatewayConnected ? "online" : "offline")
                }
            }
        }
        .padding(.horizontal, OpenClawProMetric.pagePadding)
    }

    private var nodesList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProSectionHeader(title: "Connected Instances")
            ProCard(padding: 0) {
                let nodes = self.sortedPresenceEntries
                if nodes.isEmpty {
                    self.emptyRow(
                        icon: "display",
                        title: self.gatewayConnected ? "No instances connected" : "Instances unavailable",
                        detail: self.gatewayConnected
                            ? "The gateway did not report any system presence entries."
                            : "Connect a gateway to inspect connected instances.")
                        .padding(14)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(nodes.enumerated()), id: \.element.presenceKey) { index, entry in
                            NavigationLink {
                                NodeDetailScreen(entry: entry)
                            } label: {
                                self.nodePresenceRow(entry, showsChevron: true)
                            }
                            .buttonStyle(.plain)
                            if index < nodes.count - 1 {
                                Divider().padding(.leading, 60)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, OpenClawProMetric.pagePadding)
        }
    }

    private var sortedPresenceEntries: [PresenceEntry] {
        (self.overview?.presence ?? [])
            .sorted { lhs, rhs in
                if lhs.ts != rhs.ts {
                    return lhs.ts > rhs.ts
                }
                let lhsName = PresenceFormatting.label(lhs) ?? lhs.presenceKey
                let rhsName = PresenceFormatting.label(rhs) ?? rhs.presenceKey
                return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
            }
    }

    private func nodePresenceRow(_ entry: PresenceEntry, showsChevron: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ProIconBadge(systemName: PresenceFormatting.icon(entry), color: PresenceFormatting.color(entry))
            VStack(alignment: .leading, spacing: 4) {
                Text(PresenceFormatting.label(entry) ?? "Instance")
                    .font(OpenClawType.subheadSemiBold)
                    .lineLimit(1)
                Text(PresenceFormatting.detail(entry))
                    .font(OpenClawType.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let meta = Self.presenceMeta(entry) {
                    Text(meta)
                        .font(OpenClawType.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(PresenceFormatting.state(entry))
                .font(OpenClawType.caption2SemiBold)
                .foregroundStyle(PresenceFormatting.color(entry))
                .lineLimit(1)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(OpenClawType.caption2Bold)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }

    private func detailMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(OpenClawType.caption2Medium)
                .foregroundStyle(.secondary)
            Text(value)
                .font(OpenClawType.subheadSemiBold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            Color.primary.opacity(0.055),
            in: RoundedRectangle(cornerRadius: OpenClawRadius.sm, style: .continuous))
    }

    private func emptyRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            ProIconBadge(systemName: icon, color: .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(OpenClawType.subheadSemiBold)
                Text(detail)
                    .font(OpenClawType.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
        }
    }

    private static func presenceMeta(_ entry: PresenceEntry) -> String? {
        let tags = (entry.tags ?? []).prefix(2).joined(separator: ", ")
        let scopesCount = entry.scopes?.count ?? 0
        let rolesCount = entry.roles?.count ?? 0
        let labels = [
            PresenceFormatting.normalized(entry.instanceid).map { "instance \($0)" },
            tags.isEmpty ? nil : tags,
            scopesCount > 0 ? "\(scopesCount) scopes" : nil,
            rolesCount > 0 ? "\(rolesCount) roles" : nil,
        ].compactMap(\.self)
        return labels.isEmpty ? nil : labels.joined(separator: " • ")
    }
}
