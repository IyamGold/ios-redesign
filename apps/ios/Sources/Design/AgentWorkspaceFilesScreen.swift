import OpenClawChatUI
import OpenClawKit
import OpenClawProtocol
import SwiftUI

/// Read-only browser for the selected agent's workspace, backed by the
/// `agents.workspace.list` / `agents.workspace.get` gateway RPCs.
struct AgentWorkspaceFilesScreen: View {
    let agentId: String
    let headerLeadingAction: OpenClawSidebarHeaderAction?

    var body: some View {
        ZStack {
            OpenClawProBackground()
            VStack(alignment: .leading, spacing: 0) {
                if let headerLeadingAction {
                    OpenClawAdaptiveHeaderRow(
                        title: "Files",
                        subtitle: self.agentId,
                        titleFont: OpenClawType.title3SemiBold,
                        subtitleFont: OpenClawType.subheadMedium)
                    {
                        OpenClawSidebarHeaderLeadingSlot(action: headerLeadingAction)
                    } accessory: {
                        EmptyView()
                    }
                    .padding(.horizontal, OpenClawProMetric.pagePadding)
                }
                AgentWorkspaceDirectoryList(agentId: self.agentId, path: "")
            }
        }
        .navigationTitle("Files")
        .navigationBarTitleDisplayMode(.inline)
    }

    static func displayName(forPath path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
}

struct AgentWorkspaceDirectoryList: View {
    @Environment(NodeAppModel.self) var appModel
    let agentId: String
    let path: String

    @State private var entries: [AgentsWorkspaceEntry] = []
    @State private var totalEntries = 0
    @State private var loading = false
    @State private var loadingMore = false
    @State private var errorText: String?

    var body: some View {
        List {
            if let errorText {
                Section {
                    Text(errorText)
                        .font(OpenClawType.footnote)
                        .foregroundStyle(OpenClawBrand.warn)
                }
            } else if self.entries.isEmpty, !self.loading {
                Section {
                    Text("This folder is empty.")
                        .font(OpenClawType.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                ForEach(self.entries, id: \.path) { entry in
                    self.entryRow(entry)
                }
                if self.entries.count < self.totalEntries {
                    self.loadMoreRow
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .font(OpenClawType.body)
        .overlay {
            if self.loading, self.entries.isEmpty {
                ProgressView()
            }
        }
        .refreshable {
            await self.reload()
        }
        .task(id: "\(self.agentId)|\(self.path)") {
            await self.reload()
        }
    }

    private func entryRow(_ entry: AgentsWorkspaceEntry) -> some View {
        let isDirectory = self.isDirectory(entry)
        return NavigationLink {
            if isDirectory {
                ZStack {
                    OpenClawProBackground()
                    AgentWorkspaceDirectoryList(agentId: self.agentId, path: entry.path)
                }
                .navigationTitle(AgentWorkspaceFilesScreen.displayName(forPath: entry.path))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .navigationBar)
            } else {
                AgentWorkspaceFilePreview(agentId: self.agentId, path: entry.path)
                    .toolbar(.visible, for: .navigationBar)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isDirectory ? "folder" : "doc.text")
                    .font(OpenClawType.subhead)
                    .foregroundStyle(isDirectory ? OpenClawBrand.accent : Color.secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(OpenClawType.subhead)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let detail = self.entryDetail(entry) {
                        Text(detail)
                            .font(OpenClawType.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private var loadMoreRow: some View {
        Button {
            Task { await self.loadMore() }
        } label: {
            HStack {
                Text("Load More")
                    .font(OpenClawType.subheadMedium)
                Spacer()
                if self.loadingMore {
                    ProgressView()
                } else {
                    Text("\(self.entries.count) of \(self.totalEntries)")
                        .font(OpenClawType.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(self.loadingMore)
    }

    private func isDirectory(_ entry: AgentsWorkspaceEntry) -> Bool {
        (entry.kind.value as? String) == "directory"
    }

    private func entryDetail(_ entry: AgentsWorkspaceEntry) -> String? {
        var parts: [String] = []
        if let size = entry.size {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
        }
        if let updatedAtMs = entry.updatedatms {
            let date = Date(timeIntervalSince1970: Double(updatedAtMs) / 1000)
            parts.append(date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    @MainActor
    private func reload() async {
        self.loading = true
        self.errorText = nil
        defer { self.loading = false }
        if let result = await self.fetchPage(offset: 0) {
            self.entries = result.entries
            self.totalEntries = result.totalentries
        }
    }

    @MainActor
    private func loadMore() async {
        guard !self.loadingMore else { return }
        self.loadingMore = true
        defer { self.loadingMore = false }
        if let result = await self.fetchPage(offset: self.entries.count) {
            let known = Set(self.entries.map(\.path))
            self.entries.append(contentsOf: result.entries.filter { !known.contains($0.path) })
            self.totalEntries = result.totalentries
        }
    }

    @MainActor
    private func fetchPage(offset: Int) async -> AgentsWorkspaceListResult? {
        let method = "agents.workspace.list"
        let params = AgentsWorkspaceListParams(
            agentid: self.agentId,
            path: self.path.isEmpty ? nil : self.path,
            offset: offset == 0 ? nil : offset,
            limit: nil)
        let paramsJSON = (try? Self.encodeParams(params)) ?? "<encode failed>"
        do {
            let data = try await self.appModel.operatorSession.request(
                method: method,
                paramsJSON: paramsJSON,
                timeoutSeconds: 12)
            do {
                return try JSONDecoder().decode(AgentsWorkspaceListResult.self, from: data)
            } catch {
                let raw = String(data: data, encoding: .utf8) ?? "<\(data.count) non-utf8 bytes>"
                self.reportFailure(
                    error, stage: "decode", method: method, paramsJSON: paramsJSON, rawResponse: raw)
                return nil
            }
        } catch {
            self.reportFailure(
                error, stage: "request", method: method, paramsJSON: paramsJSON, rawResponse: nil)
            return nil
        }
    }

    /// Diagnostics: surface the real cause (gateway rejection / transport / decode) instead of a
    /// generic string, both on-screen and in the console, with the exact request context.
    @MainActor
    private func reportFailure(
        _ error: Error,
        stage: String,
        method: String,
        paramsJSON: String,
        rawResponse: String?)
    {
        var lines: [String] = []
        lines.append("method: \(method)")
        lines.append("agentId: \"\(self.agentId)\"")
        lines.append("path: \"\(self.path)\"\(self.path.isEmpty ? " (root)" : "")")
        lines.append("params: \(paramsJSON)")
        lines.append("")
        lines.append(Self.describeError(error))
        if let rawResponse {
            lines.append("")
            lines.append("raw response (first 500): \(String(rawResponse.prefix(500)))")
        }
        let diagnostic = lines.joined(separator: "\n")
        print("🗂️ [Files] \(stage) failed\n\(diagnostic)")
        self.errorText = "Could not load this folder.\n\n\(diagnostic)"
    }

    static func describeError(_ error: Error) -> String {
        if let gatewayError = error as? GatewayResponseError {
            var text = "Gateway rejected [\(gatewayError.code)]: \(gatewayError.message)"
            if let reason = gatewayError.detailsReason {
                text += "\nreason: \(reason)"
            }
            if !gatewayError.details.isEmpty {
                text += "\ndetail keys: \(gatewayError.details.keys.sorted().joined(separator: ", "))"
            }
            return text
        }
        if let decodingError = error as? DecodingError {
            return "Decode failed: \(Self.describeDecoding(decodingError))"
        }
        let nsError = error as NSError
        return "Transport error (\(nsError.domain) #\(nsError.code)): \(nsError.localizedDescription)"
    }

    static func describeDecoding(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            let keys = context.codingPath.map(\.stringValue)
            return keys.isEmpty ? "<root>" : keys.joined(separator: ".")
        }
        switch error {
        case let .keyNotFound(key, context):
            return "missing key \"\(key.stringValue)\" at \(path(context))"
        case let .typeMismatch(type, context):
            return "type mismatch (\(type)) at \(path(context)) — \(context.debugDescription)"
        case let .valueNotFound(type, context):
            return "null value (\(type)) at \(path(context))"
        case let .dataCorrupted(context):
            return "data corrupted at \(path(context)) — \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }

    static func encodeParams(_ params: some Encodable) throws -> String {
        let data = try JSONEncoder().encode(params)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

struct AgentWorkspaceFilePreview: View {
    @Environment(NodeAppModel.self) var appModel
    let agentId: String
    let path: String

    private struct ShareItem: Identifiable {
        let id = UUID()
        let fileURL: URL
    }

    @State private var file: AgentsWorkspaceFile?
    @State private var loading = false
    @State private var errorText: String?
    @State private var shareItem: ShareItem?
    @State private var showsShareError = false

    var body: some View {
        ZStack {
            OpenClawProBackground()
            self.content
        }
        .navigationTitle(AgentWorkspaceFilesScreen.displayName(forPath: self.path))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    self.share()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share file")
                .disabled(self.file == nil)
            }
        }
        .sheet(item: self.$shareItem) { item in
            ChatTranscriptShareSheet(fileURL: item.fileURL)
        }
        .alert("Could not share this file.", isPresented: self.$showsShareError) {
            Button {
                self.showsShareError = false
            } label: {
                Text("OK")
                    .font(OpenClawType.subheadMedium)
            }
        }
        .task(id: "\(self.agentId)|\(self.path)") {
            await self.load()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let file {
            self.preview(for: file)
        } else if self.loading {
            ProgressView()
        } else if let errorText {
            VStack(spacing: 8) {
                Image(systemName: "doc.questionmark")
                    .font(OpenClawType.title3SemiBold)
                    .foregroundStyle(.secondary)
                Text(errorText)
                    .font(OpenClawType.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(OpenClawProMetric.pagePadding)
        }
    }

    @ViewBuilder
    private func preview(for file: AgentsWorkspaceFile) -> some View {
        if self.isImage(file), let image = self.decodedImage(file) {
            ScrollView([.horizontal, .vertical]) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .padding(OpenClawProMetric.pagePadding)
            }
        } else {
            ScrollView([.horizontal, .vertical]) {
                Text(ChatCodeHighlightCache.highlighted(
                    code: file.content,
                    languageId: self.languageId))
                    .font(OpenClawType.monoSmall)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(OpenClawProMetric.pagePadding)
            }
        }
    }

    private var fileExtension: String {
        (self.path as NSString).pathExtension.lowercased()
    }

    /// The highlighter's language ids line up with common file extensions;
    /// unknown ids fall back to plain text rendering.
    private var languageId: String? {
        self.fileExtension.isEmpty ? nil : self.fileExtension
    }

    private func isImage(_ file: AgentsWorkspaceFile) -> Bool {
        (file.encoding.value as? String) == "base64" && file.mimetype.hasPrefix("image/")
    }

    private func decodedImage(_ file: AgentsWorkspaceFile) -> UIImage? {
        guard let data = Data(base64Encoded: file.content) else { return nil }
        return UIImage(data: data)
    }

    @MainActor
    private func load() async {
        self.loading = true
        self.file = nil
        self.errorText = nil
        defer { self.loading = false }
        let method = "agents.workspace.get"
        let params = AgentsWorkspaceGetParams(agentid: self.agentId, path: self.path)
        let paramsJSON = (try? AgentWorkspaceDirectoryList.encodeParams(params)) ?? "<encode failed>"
        do {
            let data = try await self.appModel.operatorSession.request(
                method: method,
                paramsJSON: paramsJSON,
                timeoutSeconds: 20)
            self.file = try JSONDecoder().decode(AgentsWorkspaceGetResult.self, from: data).file
        } catch {
            let diagnostic = """
            method: \(method)
            agentId: "\(self.agentId)"
            path: "\(self.path)"
            params: \(paramsJSON)

            \(AgentWorkspaceDirectoryList.describeError(error))
            """
            print("🗂️ [Files] preview failed\n\(diagnostic)")
            self.errorText = "This file cannot be previewed. It may be binary or too large.\n\n\(diagnostic)"
        }
    }

    /// Mirrors the chat transcript export flow: write a temp copy, then hand
    /// it to the system share sheet.
    private func share() {
        guard let file else { return }
        let safeName = (file.name as NSString).lastPathComponent
        guard !safeName.isEmpty, safeName != ".", safeName != ".." else {
            self.showsShareError = true
            return
        }
        // Each share gets stable bytes at a unique URL; a later same-basename
        // export must not replace the item already handed to an extension.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenClawWorkspaceFiles", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent(safeName, isDirectory: false)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if self.isImage(file) {
                guard let data = Data(base64Encoded: file.content) else {
                    self.showsShareError = true
                    return
                }
                try data.write(to: fileURL, options: .atomic)
            } else {
                try file.content.write(to: fileURL, atomically: true, encoding: .utf8)
            }
            self.shareItem = ShareItem(fileURL: fileURL)
        } catch {
            self.showsShareError = true
        }
    }
}
