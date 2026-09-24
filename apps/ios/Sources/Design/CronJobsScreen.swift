import OpenClawKit
import OpenClawProtocol
import SwiftUI

struct CronJobRow: Identifiable, Equatable {
    let id: String
    let title: String // OpenClaw's own job name (what it reports when asked)
    let descriptionText: String
    /// Recurring = a repeating schedule (`every`/`cron`); one-time = a single `at` fire. Drives both the
    /// badge (green reload vs circle) and whether the Run / Enable chips appear.
    let isRecurring: Bool
    /// One-time job that has run, or a recurring job the user disabled. Drives the Active/Completed
    /// filter and the completed one-time badge.
    let isCompleted: Bool
    let enabled: Bool
    let createdAt: Date
}

struct CronJobsScreen: View {
    let jobs: [CronJobRow]
    /// Whether the Run / Enable action chips are shown (gated on gateway connection, matching the prior
    /// cron screen; the server still enforces authorization on the mutation).
    let showsActions: Bool
    let onClose: () -> Void
    let onRun: (CronJobRow) async -> Void
    let onToggleEnabled: (CronJobRow) async -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var filter: CronFilter = .active

    enum CronFilter: CaseIterable {
        case active, completed

        var title: String {
            self == .active ? "Active" : "Completed"
        }

        /// Completed = one-shot jobs that have run + recurring jobs the user disabled; everything else
        /// (not-yet-run one-shots, still-enabled recurring) is Active.
        func matches(_ job: CronJobRow) -> Bool {
            switch self {
            case .active: !job.isCompleted
            case .completed: job.isCompleted
            }
        }
    }

    private var filteredJobs: [CronJobRow] {
        self.jobs.filter { self.filter.matches($0) }
    }

    private var emptyMessage: String {
        switch self.filter {
        case .active: "No active tasks yet."
        case .completed: "No completed tasks yet."
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            (self.colorScheme == .dark
                ? Color(red: 23 / 255, green: 23 / 255, blue: 23 / 255)
                : Color(red: 245 / 255, green: 244 / 255, blue: 250 / 255))
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(self.filteredJobs) { job in
                        self.jobCard(job)
                    }
                    if self.filteredJobs.isEmpty {
                        Text(self.emptyMessage)
                            .font(.system(size: 16))
                            .foregroundStyle(Color.primary.opacity(0.6))
                            .padding(.top, 32)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            ZStack {
                Text("Cron Jobs")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.primary)
                HStack {
                    Button(action: self.onClose) {
                        self.glassChrome("ChatBackGlyph")
                    }
                    Spacer()
                    Menu {
                        ForEach(CronFilter.allCases, id: \.self) { option in
                            Button {
                                self.filter = option
                            } label: {
                                Text(option.title)
                                if self.filter == option {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    } label: {
                        self.glassChrome("UsageFilterGlyph")
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.top, 8)
            .padding(.bottom, 35)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    /// Glass circular chrome button (close + filter), matching the drawer's floating buttons.
    private func glassChrome(_ asset: String) -> some View {
        Image(asset)
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

    private func jobCard(_ job: CronJobRow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 7) {
                self.badge(for: job)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 6) {
                    Text(job.title)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    Text(job.descriptionText)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.primary.opacity(0.6))
                        // One-time jobs show their full prompt (wraps + grows the card); recurring jobs
                        // keep a single-line subtitle so their chips stay the focus.
                        .lineLimit(job.isRecurring ? 1 : nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Chips only on recurring jobs. One-time jobs fire once on their schedule; "Run" would
            // delete a default one-shot and "Enable/Disable" is meaningless, so they show no controls.
            if self.showsActions, job.isRecurring {
                HStack(spacing: 15) {
                    CronActionButton(glyph: "CronJobsPlayGlyph", label: "Run") {
                        await self.onRun(job)
                    }
                    CronActionButton(
                        glyph: job.enabled ? "CronJobsDisableGlyph" : "CronJobsCheckGlyph",
                        label: job.enabled ? "Disable" : "Enable")
                    {
                        await self.onToggleEnabled(job)
                    }
                }
                .padding(.leading, 25)
                .padding(.top, 12)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(self.colorScheme == .dark ? Color.black : .white)
        }
        // Hairline border + soft shadow per the card spec. Adaptive border (primary@0.2) so it reads on
        // the black dark-mode card, where a literal #00000033 would be invisible.
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.05), radius: 20, x: 0, y: 4)
    }

    @ViewBuilder
    private func badge(for job: CronJobRow) -> some View {
        if job.isCompleted {
            ZStack {
                // Completed job (one-time that ran, or recurring the user disabled). Paper C6-0:
                // #C53E38 circle, #FAFAFA check.
                Circle().fill(Color(red: 197 / 255, green: 62 / 255, blue: 56 / 255))
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(red: 250 / 255, green: 250 / 255, blue: 250 / 255))
            }
            .frame(width: 18, height: 18)
        } else if job.isRecurring {
            // Active recurring job: green reload glyph (Paper DS-0).
            Image("CronJobsReloadGlyph")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(Color(red: 52 / 255, green: 199 / 255, blue: 89 / 255))
                .frame(width: 18, height: 18)
        } else {
            // Not-yet-run one-time job. Paper spec EB-0: empty circle, stroke @0.4.
            Circle()
                .strokeBorder(Color.primary.opacity(0.4), lineWidth: 1.35)
                .frame(width: 18, height: 18)
        }
    }

    /// Run / Enable chip. Swaps its label to "..." while the async work runs so the user gets feedback
    /// until the gateway mutation and the follow-up reload complete, then reverts.
    private struct CronActionButton: View {
        let glyph: String
        let label: String
        let action: () async -> Void

        @Environment(\.colorScheme) private var colorScheme
        @State private var isRunning = false

        var body: some View {
            Button {
                guard !self.isRunning else { return }
                OpenClawHaptics.tap()
                Task {
                    self.isRunning = true
                    await self.action()
                    self.isRunning = false
                }
            } label: {
                HStack(spacing: 7) {
                    Image(self.glyph)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 13, height: 13)
                    Text(self.isRunning ? "..." : self.label)
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 10)
                .frame(height: 27)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(self.colorScheme == .dark ? Color.black : .white)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5)
                }
            }
            // No `.disabled` while running: it would dim the chip. The `guard !isRunning` above already
            // blocks re-entry, so the chip stays at full opacity through the "..." state.
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Drawer host

/// Loads cron jobs for the drawer's Cron Jobs page, maps each `CronJob` to a `CronJobRow`, and runs the
/// same RPCs (`cron.run`, `cron.update`) the iPad screen uses. Run/enable buttons show when the gateway
/// is connected; the server still enforces authorization on the mutation.
struct CronJobsScreenHost: View {
    let onClose: () -> Void

    @Environment(NodeAppModel.self) private var appModel
    @State private var jobs: [CronJob] = []

    var body: some View {
        CronJobsScreen(
            jobs: self.jobs.map(Self.row(from:)).sorted { $0.createdAt > $1.createdAt },
            showsActions: self.appModel.gatewayServerName != nil,
            onClose: self.onClose,
            onRun: { row in await self.run(row) },
            onToggleEnabled: { row in await self.toggle(row) })
            .task { await self.load() }
    }

    private func load() async {
        guard
            let data = try? await self.appModel.operatorSession.request(
                method: "cron.list",
                paramsJSON: "{\"includeDisabled\":true,\"limit\":100,\"sortBy\":\"updatedAtMs\",\"sortDir\":\"desc\"}",
                timeoutSeconds: 12),
            let list = try? JSONDecoder().decode(CronJobsListLite.self, from: data)
        else { return }
        self.jobs = list.jobs
    }

    private func run(_ row: CronJobRow) async {
        guard let job = self.jobs.first(where: { $0.id == row.id }),
              let json = Self.encode(CronRunParams(id: job.id, mode: "force"))
        else { return }
        _ = try? await self.appModel.operatorSession.request(
            method: "cron.run", paramsJSON: json, timeoutSeconds: 20)
        await self.load()
    }

    private func toggle(_ row: CronJobRow) async {
        guard let job = self.jobs.first(where: { $0.id == row.id }),
              let json = Self.encode(
                  CronUpdateParams(id: job.id, patch: CronUpdatePatch(enabled: !job.enabled)))
        else { return }
        _ = try? await self.appModel.operatorSession.request(
            method: "cron.update", paramsJSON: json, timeoutSeconds: 20)
        await self.load()
    }

    private static func encode(_ value: some Encodable) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Mapping

    private static func row(from job: CronJob) -> CronJobRow {
        let recurring = self.isRecurring(job)
        return CronJobRow(
            id: job.id,
            title: self.title(job),
            descriptionText: self.description(job),
            isRecurring: recurring,
            isCompleted: self.isCompleted(job, isRecurring: recurring),
            enabled: job.enabled,
            createdAt: Date(timeIntervalSince1970: Double(job.createdatms) / 1000))
    }

    /// Recurring = any repeating schedule; a one-time job is a single `at` fire. The gateway schedule
    /// `kind` is the source of truth here (`deleteAfterRun` is a separate, defaultable flag).
    private static func isRecurring(_ job: CronJob) -> Bool {
        guard let schedule = job.schedule.value as? [String: AnyCodable] else {
            return true
        }
        // No `at` kind (or no kind at all) → a repeating schedule.
        let kind = (schedule["kind"]?.value as? String)?
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        return kind != "at"
    }

    /// A recurring job is only "done" once the user disables it. A one-time job is done once it has
    /// fired: the gateway disables a one-shot after its run (even on error), and records the run in
    /// `state` — the top-level `lastRunAtMs` is not populated by all gateway builds — so treat either
    /// signal as completion.
    private static func isCompleted(_ job: CronJob, isRecurring: Bool) -> Bool {
        if isRecurring {
            return !job.enabled
        }
        return !job.enabled || self.hasRun(job)
    }

    /// Whether a one-time job has attempted a run, tolerant of where the gateway records it.
    private static func hasRun(_ job: CronJob) -> Bool {
        if job.lastrunatms != nil || self.intValue(job.state["lastRunAtMs"]) != nil {
            return true
        }
        let status = (job.lastrunstatus?.value as? String) ?? (job.state["lastStatus"]?.value as? String)
        return status?.isEmpty == false
    }

    /// Human schedule label from the job's schedule dict (mirrors the iPad `cronScheduleSummary`):
    /// a `kind` preset ("Weekly"), else a cron `expr`, else an `everyMs` interval.
    private static func scheduleTitle(_ job: CronJob) -> String {
        guard let schedule = job.schedule.value as? [String: AnyCodable] else {
            return "Schedule configured"
        }
        if let kind = (schedule["kind"]?.value as? String)?.trimmingCharacters(in: .whitespaces),
           !kind.isEmpty
        {
            return kind.capitalized
        }
        if let expr = (schedule["expr"]?.value as? String)?.trimmingCharacters(in: .whitespaces),
           !expr.isEmpty
        {
            return "Cron \(expr)"
        }
        if let everyMs = self.intValue(schedule["everyMs"]) {
            return "Every \(self.durationLabel(everyMs))"
        }
        return "Schedule configured"
    }

    /// OpenClaw's own job name; falls back to the schedule label when a job has no name so the card
    /// still shows something meaningful.
    private static func title(_ job: CronJob) -> String {
        let name = job.name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? self.scheduleTitle(job) : name
    }

    /// The prompt/event text OpenClaw stored in the job payload; falls back to the schedule label when a
    /// payload carries no text (e.g. a command job) so the subtitle is never empty.
    private static func description(_ job: CronJob) -> String {
        if let text = self.payloadText(job) {
            return text
        }
        return self.scheduleTitle(job)
    }

    /// Cron payloads are a `{ kind, message?, text? }` object: `message` holds an agentTurn prompt,
    /// `text` a systemEvent string. Return whichever is present.
    private static func payloadText(_ job: CronJob) -> String? {
        guard let payload = job.payload.value as? [String: AnyCodable] else { return nil }
        for key in ["message", "text"] {
            let value = (payload[key]?.value as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let value, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func intValue(_ value: AnyCodable?) -> Int? {
        switch value?.value {
        case let intValue as Int: intValue
        case let doubleValue as Double: Int(doubleValue)
        case let stringValue as String: Int(stringValue)
        default: nil
        }
    }

    private static func durationLabel(_ milliseconds: Int) -> String {
        let seconds = milliseconds / 1000
        if seconds % 86400 == 0 {
            let days = seconds / 86400
            return "\(days) day\(days == 1 ? "" : "s")"
        }
        if seconds % 3600 == 0 {
            let hours = seconds / 3600
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        }
        if seconds % 60 == 0 {
            let minutes = seconds / 60
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        }
        return "\(seconds) second\(seconds == 1 ? "" : "s")"
    }
}
