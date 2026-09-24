import SwiftUI

struct UsageDayEntry: Identifiable, Equatable {
    let date: Date
    let tokens: Int
    let cost: Double?

    var id: Date {
        self.date
    }
}

struct UsageScreen: View {
    let entries: [UsageDayEntry]
    let totalTokens: Int
    let totalCost: Double?
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedMonth: DateComponents? // nil = all

    var body: some View {
        ZStack(alignment: .top) {
            (self.colorScheme == .dark
                ? Color(red: 23 / 255, green: 23 / 255, blue: 23 / 255)
                : Color(red: 245 / 255, green: 244 / 255, blue: 250 / 255))
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    self.summaryCard

                    ForEach(self.visibleMonths, id: \.self) { month in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(Self.monthLabel(month))
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(Color.primary.opacity(0.5))
                                .padding(.leading, 15)
                            self.card {
                                let days = self.entries(in: month)
                                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                                    self.usageRow(
                                        label: Self.dayLabel(day.date),
                                        value: "\(Self.tokenLabel(day.tokens)) tokens")
                                    if index < days.count - 1 {
                                        OpenClawRowDivider()
                                    }
                                }
                            }
                        }
                    }

                    if self.entries.isEmpty {
                        Text("No usage recorded yet.")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.primary.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            ZStack {
                Text("Usage")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.primary)
                HStack {
                    self.chromePill(asset: "ChatBackGlyph", action: self.onClose)
                    Spacer()
                    Menu {
                        Button("All") { self.selectedMonth = nil }
                        ForEach(self.availableMonths, id: \.self) { month in
                            Button(Self.monthMenuLabel(month)) {
                                self.selectedMonth = month
                            }
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

    // MARK: - Data shaping

    private var availableMonths: [DateComponents] {
        var seen: [DateComponents] = []
        for entry in self.entries.sorted(by: { $0.date > $1.date }) {
            let month = Calendar.current.dateComponents([.year, .month], from: entry.date)
            if !seen.contains(month) {
                seen.append(month)
            }
        }
        return seen
    }

    private var visibleMonths: [DateComponents] {
        if let selectedMonth {
            return [selectedMonth]
        }
        return self.availableMonths
    }

    private func entries(in month: DateComponents) -> [UsageDayEntry] {
        self.entries
            .filter {
                Calendar.current.dateComponents([.year, .month], from: $0.date) == month
            }
            .sorted { $0.date > $1.date }
    }

    // MARK: - Pieces

    private var summaryCard: some View {
        self.card {
            self.usageRow(
                label: "Total usage",
                value: "\(Self.tokenLabel(self.totalTokens)) tokens")
            OpenClawRowDivider()
            self.usageRow(label: "Total cost", value: Self.costLabel(self.totalCost))
        }
    }

    private func card(@ViewBuilder content: () -> some View) -> some View {
        // Horizontal inset lives on the ROWS (`usageRow`) so `OpenClawRowDivider` spans the card edges.
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

    private func usageRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 17))
                .foregroundStyle(Color.primary)
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 16))
                .foregroundStyle(Color.primary.opacity(0.6))
        }
        .padding(.horizontal, 15)
    }

    private func chromePill(asset: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            self.chromePillLabel(asset: asset)
        }
    }

    private func chromePillLabel(asset: String) -> some View {
        Image(asset)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 22, height: 22)
            .foregroundStyle(Color.primary)
            .frame(width: 40, height: 40)
            // Glass chrome buttons, matching the drawer's cancel-X (DrawerCloseButton).
            .background {
                ChatGlassBackground(
                    shape: Circle(),
                    fill: self.colorScheme == .dark
                        ? Color(red: 30 / 255, green: 30 / 255, blue: 30 / 255).opacity(0.2)
                        : Color(red: 245 / 255, green: 244 / 255, blue: 250 / 255).opacity(0.2))
            }
            .shadow(color: .black.opacity(0.15), radius: 25, x: 0, y: 0)
    }

    // MARK: - Formatting

    static func tokenLabel(_ tokens: Int) -> String {
        switch tokens {
        case 1_000_000...:
            let value = Double(tokens) / 1_000_000
            return value.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(value))M" : String(format: "%.1fM", value)
        case 1000...:
            return "\(Int((Double(tokens) / 1000).rounded()))K"
        default:
            return "\(tokens)"
        }
    }

    static func costLabel(_ cost: Double?) -> String {
        guard let cost, cost > 0 else { return "0$" }
        return String(format: "%.2f$", cost)
    }

    static func dayLabel(_ date: Date) -> String {
        let month = date.formatted(.dateTime.month(.wide))
        let day = Calendar.current.component(.day, from: date)
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        let ordinal = formatter.string(from: NSNumber(value: day)) ?? "\(day)"
        return "\(month) \(ordinal)"
    }

    static func monthLabel(_ month: DateComponents) -> String {
        guard let date = Calendar.current.date(from: month) else { return "" }
        let currentYear = Calendar.current.component(.year, from: Date())
        let name = date.formatted(.dateTime.month(.wide))
        if month.year == currentYear {
            return name
        }
        return "\(name) \(month.year ?? 0)"
    }

    static func monthMenuLabel(_ month: DateComponents) -> String {
        guard let date = Calendar.current.date(from: month) else { return "" }
        return "\(date.formatted(.dateTime.month(.wide))) \(month.year ?? 0)"
    }
}

/// Loads a wide (~1 year) usage window for the drawer's Usage page and feeds `UsageScreen`. It runs its
/// own targeted `usage.cost` fetch rather than widening the shared overview load (which pulls many other
/// panels on a shorter window). Falls back gracefully to whatever the gateway retains.
struct UsageScreenHost: View {
    let onClose: () -> Void

    @Environment(NodeAppModel.self) private var appModel
    @State private var entries: [UsageDayEntry] = []
    @State private var totalTokens = 0
    @State private var totalCost: Double?

    /// The gateway reports daily usage keyed by an ISO `yyyy-MM-dd` day string.
    private static let dayParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()

    var body: some View {
        UsageScreen(
            entries: self.entries,
            totalTokens: self.totalTokens,
            totalCost: self.totalCost,
            onClose: self.onClose)
            .task { await self.load() }
    }

    private func load() async {
        guard
            let data = try? await self.appModel.operatorSession.request(
                method: "usage.cost",
                paramsJSON: "{\"days\":365}",
                timeoutSeconds: 15),
            let summary = try? JSONDecoder().decode(CostUsageSummaryLite.self, from: data)
        else { return }
        let mapped = (summary.daily ?? []).compactMap { day -> UsageDayEntry? in
            guard let date = Self.dayParser.date(from: day.date) else { return nil }
            return UsageDayEntry(date: date, tokens: day.totalTokens ?? 0, cost: day.totalCost)
        }
        self.entries = mapped
        self.totalTokens = summary.totalTokens ?? mapped.reduce(0) { $0 + $1.tokens }
        self.totalCost = summary.totalCost
    }
}
