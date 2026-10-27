import OpenClawKit
import SwiftUI

struct DreamEntry: Identifiable, Equatable {
    enum Category: String, CaseIterable {
        case promoted = "Promoted Entries"
        case shortTerm = "Short Term Recall"
        case signal = "Signal Entries"

        /// Singular label shown as the row header (the list groups by which store an entry came from).
        var rowLabel: String {
            switch self {
            case .promoted: "Promoted Entry"
            case .shortTerm: "Short term entry"
            case .signal: "Signal Entry"
            }
        }
    }

    let id: String
    let category: Category
    /// Leading timestamp/id token split off the stored snippet, shown dimmed before the body. Nil unless the
    /// snippet GENUINELY begins with one — never fabricated.
    let rawPrefix: String?
    /// Entry body (the snippet with any leading timestamp token removed).
    let text: String
    /// Compact age ("3mins" / "2hrs" / "5d") parsed from the snippet's leading timestamp, else the backend's
    /// relative-time string, else "".
    let ageLabel: String

    // MARK: - Snippet parsing (shared by the list + detail; never fabricates a timestamp)

    /// Splits a leading ISO-ish timestamp token off the snippet. Returns `(nil, trimmed)` when the snippet
    /// doesn't genuinely start with one.
    static func splitTimestamp(_ raw: String) -> (prefix: String?, body: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let breakIndex = trimmed.firstIndex(where: { $0 == " " || $0 == "\n" || $0 == "\t" }) else {
            return (nil, trimmed)
        }
        let token = String(trimmed[trimmed.startIndex..<breakIndex])
        guard self.looksLikeTimestamp(token) else { return (nil, trimmed) }
        let rest = String(trimmed[trimmed.index(after: breakIndex)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (token, rest)
    }

    /// A leading `YYYY-MM-DD` date with a `t` time separator (any case), e.g. `2026-10-20t03:00:00.368z`.
    static func looksLikeTimestamp(_ token: String) -> Bool {
        let lower = token.lowercased()
        let chars = Array(lower)
        guard chars.count >= 11 else { return false }
        let datePunctuation = chars[4] == "-" && chars[7] == "-"
        let dateDigits = chars[0..<4].allSatisfy(\.isNumber)
            && chars[5..<7].allSatisfy(\.isNumber)
            && chars[8..<10].allSatisfy(\.isNumber)
        return datePunctuation && dateDigits && chars[10] == "t"
    }

    /// Compact "time since" the ISO token, or nil when it can't be parsed as a date.
    static func compactAge(fromISO token: String) -> String? {
        let normalized = token.uppercased()
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        guard let date = withFraction.date(from: normalized) ?? plain.date(from: normalized) else { return nil }
        let seconds = max(0, Date().timeIntervalSince(date))
        let minutes = Int(seconds / 60)
        if minutes < 60 {
            return "\(max(minutes, 1))mins"
        }
        let hours = Int(seconds / 3600)
        if hours < 24 {
            return "\(hours)hrs"
        }
        return "\(Int(seconds / 86400))d"
    }
}

struct DreamingScreen: View {
    let entries: [DreamEntry]
    let onClose: () -> Void
    let onOpenEntry: (DreamEntry) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var filter: DreamEntry.Category?

    /// The entry list renders 20% larger than the base frame spec. One factor so tile, type, spacing, corner,
    /// and padding all scale together proportionally — bump this to resize the whole list. The nav chrome and
    /// the detail destination are intentionally unscaled.
    private let scale: CGFloat = 1.2

    var body: some View {
        ZStack(alignment: .top) {
            self.canvas.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 2 * self.scale) {
                    let visible = self.visibleEntries
                    let corner = 12 * self.scale
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, entry in
                        self.entryRow(entry)
                            .clipShape(UnevenRoundedRectangle(
                                topLeadingRadius: index == 0 ? corner : 0,
                                bottomLeadingRadius: index == visible.count - 1 ? corner : 0,
                                bottomTrailingRadius: index == visible.count - 1 ? corner : 0,
                                topTrailingRadius: index == 0 ? corner : 0,
                                style: .continuous))
                    }
                    if visible.isEmpty {
                        Text("No dreams yet.")
                            .font(.system(size: 16 * self.scale))
                            .foregroundStyle(Color.primary.opacity(0.6))
                            .padding(.top, 32)
                    }
                }
                .padding(.horizontal, 24)
                // Match the Usage/Files/Skills destinations: the 27pt header inset + 4pt here = the same
                // chrome-to-first-item gap, instead of the oversized 48pt the spec had.
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

    // MARK: Row

    private func entryRow(_ entry: DreamEntry) -> some View {
        Button {
            OpenClawHaptics.tap()
            self.onOpenEntry(entry)
        } label: {
            HStack(alignment: .top, spacing: 11 * self.scale) {
                self.moonTile
                VStack(alignment: .leading, spacing: 5 * self.scale) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(entry.category.rowLabel)
                            .font(.system(size: 12.7 * self.scale, weight: .medium))
                            .foregroundStyle(Color.primary)
                        Spacer(minLength: 8 * self.scale)
                        if !entry.ageLabel.isEmpty {
                            Text(entry.ageLabel)
                                .font(.system(size: 9 * self.scale))
                                .foregroundStyle(Color.primary.opacity(0.4))
                                .lineLimit(1)
                        }
                    }
                    self.bodyText(entry)
                        .font(.system(size: 12.7 * self.scale))
                        .lineSpacing(5 * self.scale)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 15 * self.scale)
            .padding(.vertical, 11 * self.scale)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(self.rowFill)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Two-tone body: the raw timestamp token dimmed (40% reduced fill), the entry text brighter.
    private func bodyText(_ entry: DreamEntry) -> Text {
        if let prefix = entry.rawPrefix {
            return Text(prefix).foregroundColor(Color.primary.opacity(0.6))
                + Text(" " + entry.text).foregroundColor(Color.primary.opacity(0.9))
        }
        return Text(entry.text).foregroundColor(Color.primary.opacity(0.9))
    }

    /// A 30pt rounded tile cropping an oversized 35pt moon-star offset (+7,+7) — the partial-moon crop is
    /// deliberate per the frame; do not "fix" it.
    private var moonTile: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5 * self.scale, style: .continuous)
                .fill(self.tileFill)
            Image("DrawerMoonStarGlyph")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 35 * self.scale, height: 35 * self.scale)
                .offset(x: 7 * self.scale, y: 7 * self.scale)
                .foregroundStyle(Color.primary)
        }
        .frame(width: 30 * self.scale, height: 30 * self.scale)
        .clipShape(RoundedRectangle(cornerRadius: 5 * self.scale, style: .continuous))
    }

    // MARK: Chrome + palette

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

    // Confirmed: this screen intentionally inverts the app-wide palette — pure black canvas in dark (not the
    // #171717 used elsewhere) with #171717 rows and slightly lighter #262628 moon tiles.
    private var canvas: Color {
        self.colorScheme == .dark
            ? .black
            : Color(red: 245 / 255, green: 244 / 255, blue: 250 / 255)
    }

    private var rowFill: Color {
        self.colorScheme == .dark
            ? Color(red: 23 / 255, green: 23 / 255, blue: 23 / 255)
            : .white
    }

    private var tileFill: Color {
        self.colorScheme == .dark
            ? Color(red: 38 / 255, green: 38 / 255, blue: 40 / 255)
            : Color(red: 236 / 255, green: 236 / 255, blue: 240 / 255)
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
        let (prefix, body) = DreamEntry.splitTimestamp(entry.snippet)
        let age = prefix.flatMap(DreamEntry.compactAge(fromISO:))
            ?? entry.promotedAt ?? entry.lastRecalledAt ?? ""
        return DreamEntry(
            id: entry.id,
            category: category,
            rawPrefix: prefix,
            text: body.isEmpty ? Self.basename(entry.path) : body,
            ageLabel: age)
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

/// Read-only look at a single dreaming entry: the full snippet as the hero, its category + timestamp chips,
/// and a source-location / signal / recall meta card. Follows this screen's pure-black canvas palette.
struct DreamEntryDetailSheet: View {
    let entry: DreamingEntryLite
    let categoryLabel: String
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .top) {
            self.canvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(self.heroText)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Color.primary)
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 5) {
                        self.chip(self.categoryLabel)
                        if let iso = self.isoToken {
                            self.chip(iso)
                        }
                    }

                    VStack(spacing: 2) {
                        let rows = self.metaRows
                        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                            HStack {
                                Text(row.0)
                                    .font(.system(size: 16))
                                    .foregroundStyle(Color.primary.opacity(0.6))
                                Spacer(minLength: 8)
                                Text(row.1)
                                    .font(.system(size: 17))
                                    .foregroundStyle(Color.primary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                            }
                            .padding(.horizontal, 15)
                            .frame(height: 50)
                            .frame(maxWidth: .infinity)
                            .background(self.rowFill)
                            .clipShape(UnevenRoundedRectangle(
                                topLeadingRadius: index == 0 ? 12 : 0,
                                bottomLeadingRadius: index == rows.count - 1 ? 12 : 0,
                                bottomTrailingRadius: index == rows.count - 1 ? 12 : 0,
                                topTrailingRadius: index == 0 ? 12 : 0,
                                style: .continuous))
                        }
                    }
                }
                .padding(.horizontal, 25)
                .padding(.top, 79) // clears the overlaid chrome
                .padding(.bottom, 40)
            }
        }
        .overlay(alignment: .topLeading) {
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
            .padding(.leading, 25)
            .padding(.top, 22)
        }
        .overlay(alignment: .top) {
            Text(self.headerTitle)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 220)
                .padding(.top, 29)
        }
    }

    // MARK: Derived

    /// The memory key heads the panel (e.g. a topic). Falls back to the source file name when empty.
    private var headerTitle: String {
        let key = self.entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? self.basename : key
    }

    private var split: (prefix: String?, body: String) {
        DreamEntry.splitTimestamp(self.entry.snippet)
    }

    private var heroText: String {
        let body = self.split.body
        return body.isEmpty ? self.basename : body
    }

    /// The raw timestamp token from the snippet (chip). Nil when the snippet carries none.
    private var isoToken: String? {
        self.split.prefix
    }

    private var basename: String {
        self.entry.path.split(separator: "/").last.map(String.init) ?? self.entry.path
    }

    private var metaRows: [(String, String)] {
        [
            ("Location", self.location),
            ("Signal", "x\(self.entry.totalSignalCount)"),
            ("Recalled", "x\(self.entry.recallCount)"),
        ]
    }

    private var location: String {
        self.entry.endLine > self.entry.startLine
            ? "\(self.basename):\(self.entry.startLine)-\(self.entry.endLine)"
            : "\(self.basename):\(self.entry.startLine)"
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(Color.primary.opacity(0.8))
            .lineLimit(1)
            .padding(.horizontal, 5)
            .frame(height: 18)
            .background {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(self.colorScheme == .dark
                        ? Color(red: 38 / 255, green: 38 / 255, blue: 40 / 255)
                        : Color(red: 236 / 255, green: 236 / 255, blue: 240 / 255))
            }
    }

    // MARK: Palette

    private var canvas: Color {
        self.colorScheme == .dark
            ? .black
            : Color(red: 245 / 255, green: 244 / 255, blue: 250 / 255)
    }

    private var rowFill: Color {
        self.colorScheme == .dark
            ? Color(red: 23 / 255, green: 23 / 255, blue: 23 / 255)
            : .white
    }
}
