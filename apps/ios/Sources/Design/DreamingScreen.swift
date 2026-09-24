import OpenClawKit
import SwiftUI

struct DreamEntry: Identifiable, Equatable {
    enum Category: String, CaseIterable {
        case promoted = "Promoted Entries"
        case shortTerm = "Short Term Recall"
        case signal = "Signal Entries"
    }

    let id: String
    let title: String
    let snippet: String
    let category: Category
    // FLAG: the gateway's dreaming entries carry only a relative-time string (promotedAt /
    // lastRecalledAt), never an absolute date — so this holds that string verbatim instead of a
    // formatted Date. "" when the backend reports neither.
    let dateLabel: String
}

struct DreamingScreen: View {
    let entries: [DreamEntry]
    let onClose: () -> Void
    let onOpenEntry: (DreamEntry) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var filter: DreamEntry.Category?

    var body: some View {
        ZStack(alignment: .top) {
            self.canvas.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 17) {
                    ForEach(Array(self.visibleEntries.enumerated()), id: \.element.id) { index, entry in
                        VStack(spacing: 17) {
                            // Page inset lives on the row, not the list — so the divider below can run
                            // screen edge-to-edge (touching both device edges), while rows stay inset 24.
                            self.entryRow(entry)
                                .padding(.horizontal, 24)
                            if index < self.visibleEntries.count - 1 {
                                Rectangle()
                                    .fill(Color.primary.opacity(0.15))
                                    .frame(height: 0.7)
                            }
                        }
                    }
                    if self.visibleEntries.isEmpty {
                        Text("No dreams yet.")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.primary.opacity(0.6))
                            .padding(.top, 32)
                            .padding(.horizontal, 24)
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            ZStack {
                Text("Dreaming")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.primary)
                HStack {
                    self.chromePill(asset: "ChatBackGlyph", action: self.onClose)
                    Spacer()
                    Menu {
                        Button("All") { self.filter = nil }
                        ForEach(DreamEntry.Category.allCases, id: \.self) { category in
                            Button(category.rawValue) { self.filter = category }
                        }
                    } label: {
                        self.chromePillLabel(asset: "UsageFilterGlyph")
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.top, 8)
            .padding(.bottom, 27)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var visibleEntries: [DreamEntry] {
        guard let filter else { return self.entries }
        return self.entries.filter { $0.category == filter }
    }

    // Confirmed: this screen intentionally inverts the app-wide palette — pure black canvas with
    // #171717 tiles in dark, and the standard light canvas with white tiles in light.
    private var canvas: Color {
        self.colorScheme == .dark
            ? .black
            : Color(red: 245 / 255, green: 244 / 255, blue: 250 / 255)
    }

    private var tileFill: Color {
        self.colorScheme == .dark
            ? Color(red: 23 / 255, green: 23 / 255, blue: 23 / 255)
            : .white
    }

    private func entryRow(_ entry: DreamEntry) -> some View {
        Button {
            self.onOpenEntry(entry)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(self.tileFill)
                    Image("DrawerMoonStarGlyph")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 35, height: 35)
                        .foregroundStyle(Color.primary.opacity(0.85))
                }
                .frame(width: 50.5, height: 50.5)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 0) {
                        Text(entry.title)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if !entry.dateLabel.isEmpty {
                            Text(entry.dateLabel)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.primary.opacity(0.6))
                                .lineLimit(1)
                        }
                        Image("SettingsChevronRightGlyph")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                            .foregroundStyle(Color.primary.opacity(0.6))
                    }
                    Text(entry.snippet)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.primary.opacity(0.6))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func chromePill(asset: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { self.chromePillLabel(asset: asset) }
    }

    private func chromePillLabel(asset: String) -> some View {
        Image(asset)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 22, height: 22)
            .foregroundStyle(Color.primary)
            .frame(width: 40, height: 40)
            // Frosted glass chrome, matching the Usage/Instances/Skills/Files nav buttons.
            .background {
                ChatGlassBackground(
                    shape: Circle(),
                    fill: self.colorScheme == .dark
                        ? Color(red: 30 / 255, green: 30 / 255, blue: 30 / 255).opacity(0.2)
                        : Color(red: 245 / 255, green: 244 / 255, blue: 250 / 255).opacity(0.2))
            }
            .shadow(color: .black.opacity(0.15), radius: 25, x: 0, y: 0)
    }
}

// MARK: - Drawer host

/// Loads the gateway's dreaming/memory state for the drawer's Dreaming page and feeds `DreamingScreen`.
/// `doctor.memory.status` is gateway-global (no agent scope). Entries fan out from the three category
/// arrays; tapping one opens a read-only detail sheet built from the full `DreamingEntryLite`.
struct DreamingScreenHost: View {
    let onClose: () -> Void

    @Environment(NodeAppModel.self) private var appModel
    @State private var status: DreamingStatusLite?
    @State private var selectedEntryID: String?

    var body: some View {
        DreamingScreen(
            entries: self.listEntries,
            onClose: self.onClose,
            onOpenEntry: { self.selectedEntryID = $0.id })
            .task { await self.load() }
            .sheet(isPresented: Binding(
                get: { self.selectedEntryID != nil },
                set: {
                    if !$0 {
                        self.selectedEntryID = nil
                    }
                })) {
                    if let selected = self.selectedRaw {
                        DreamEntryDetailSheet(
                            entry: selected.entry,
                            categoryLabel: selected.category.rawValue,
                            onClose: { self.selectedEntryID = nil })
                            .presentationCornerRadius(47)
                    }
            }
    }

    // MARK: - Derived models

    /// Category order matches the enum: promoted, short-term, then signal.
    private var categorized: [(category: DreamEntry.Category, entries: [DreamingEntryLite])] {
        [
            (.promoted, self.status?.promotedEntries ?? []),
            (.shortTerm, self.status?.shortTermEntries ?? []),
            (.signal, self.status?.signalEntries ?? []),
        ]
    }

    private var listEntries: [DreamEntry] {
        self.categorized.flatMap { pair in
            pair.entries.map { Self.mapEntry($0, category: pair.category) }
        }
    }

    private var selectedRaw: (entry: DreamingEntryLite, category: DreamEntry.Category)? {
        guard let id = self.selectedEntryID else { return nil }
        for pair in self.categorized {
            if let match = pair.entries.first(where: { $0.id == id }) {
                return (match, pair.category)
            }
        }
        return nil
    }

    private static func mapEntry(_ entry: DreamingEntryLite, category: DreamEntry.Category) -> DreamEntry {
        let trimmed = entry.snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        // Title = first line (a natural one-line summary); body = the remainder, falling back to the
        // whole snippet when there's only one line. Path basename backstops an empty snippet.
        let title = lines.first ?? Self.basename(entry.path)
        let body = lines.count > 1 ? lines.dropFirst().joined(separator: " ") : trimmed
        return DreamEntry(
            id: entry.id,
            title: title.isEmpty ? Self.basename(entry.path) : title,
            snippet: body,
            category: category,
            dateLabel: entry.promotedAt ?? entry.lastRecalledAt ?? "")
    }

    private static func basename(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    // MARK: - Loading

    private func load() async {
        guard
            let data = try? await self.appModel.operatorSession.request(
                method: "doctor.memory.status",
                paramsJSON: "{}",
                timeoutSeconds: 8),
            let envelope = try? JSONDecoder().decode(DreamingStatusEnvelope.self, from: data)
        else { return }
        self.status = envelope.dreaming
    }
}

// MARK: - Entry detail

/// Read-only look at a single dreaming entry: the full (untruncated) snippet plus source location and
/// signal/recall counts. Follows this screen's pure-black canvas + #171717 tile palette.
struct DreamEntryDetailSheet: View {
    let entry: DreamingEntryLite
    let categoryLabel: String
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .top) {
            self.canvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(self.title)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Color.primary)

                    Text(self.subheading)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.primary.opacity(0.6))
                        .padding(.top, 6)

                    Text(self.entry.snippet.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.system(size: 16))
                        .foregroundStyle(Color.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 20)

                    self.metaCard
                        .padding(.top, 24)

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 25)
                .padding(.top, 8)
            }
        }
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

                Text("Entry")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .frame(maxWidth: 188)
                    .padding(.top, 29)
            }
        }
    }

    private var title: String {
        let trimmed = self.entry.snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        let first = trimmed.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init)
        let name = self.entry.path.split(separator: "/").last.map(String.init) ?? self.entry.path
        return first ?? name
    }

    private var subheading: String {
        var parts = [self.categoryLabel]
        if let when = self.entry.promotedAt ?? self.entry.lastRecalledAt {
            parts.append(when)
        }
        return parts.joined(separator: " · ")
    }

    private var metaCard: some View {
        VStack(spacing: 14) {
            self.metaRow("Location", self.location)
            self.hairline
            self.metaRow("Signal", "×\(self.entry.totalSignalCount)")
            self.hairline
            self.metaRow("Recalled", "×\(self.entry.recallCount)")
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(self.tileFill)
        }
    }

    private var location: String {
        let name = self.entry.path.split(separator: "/").last.map(String.init) ?? self.entry.path
        return self.entry.endLine > self.entry.startLine
            ? "\(name):\(self.entry.startLine)-\(self.entry.endLine)"
            : "\(name):\(self.entry.startLine)"
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 16))
                .foregroundStyle(Color.primary.opacity(0.6))
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 17))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.15))
            .frame(height: 0.7)
    }

    private var canvas: Color {
        self.colorScheme == .dark
            ? .black
            : Color(red: 245 / 255, green: 244 / 255, blue: 250 / 255)
    }

    private var tileFill: Color {
        self.colorScheme == .dark
            ? Color(red: 23 / 255, green: 23 / 255, blue: 23 / 255)
            : .white
    }
}
