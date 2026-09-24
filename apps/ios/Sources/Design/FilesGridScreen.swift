import OpenClawKit
import OpenClawProtocol
import QuickLook
import SwiftUI

struct WorkspaceGridEntry: Identifiable, Hashable {
    let id: String // full path
    let name: String
    let isFolder: Bool
    var typeLabel: String {
        self.isFolder ? "Folder" : (self.name as NSString).pathExtension.uppercased()
    }
}

struct FilesGridScreen: View {
    let title: String // "Files" at root, folder name when nested
    let entries: [WorkspaceGridEntry]
    let isNested: Bool
    let onClose: () -> Void // X at root / back when nested
    let onOpenFolder: (WorkspaceGridEntry) -> Void
    let onInfo: () -> Void // "i" pill — purpose TBD
    /// Fetches file bytes, returns a local temp URL for preview (workspace.get).
    let fetchPreviewURL: (WorkspaceGridEntry) async -> URL?

    @Environment(\.colorScheme) private var colorScheme
    @State private var previewURL: URL?
    @State private var loadingID: String?

    private let columns = [
        GridItem(.flexible(), spacing: 28),
        GridItem(.flexible()),
    ]

    var body: some View {
        ZStack(alignment: .top) {
            (self.colorScheme == .dark
                ? Color(red: 23 / 255, green: 23 / 255, blue: 23 / 255)
                : Color(red: 245 / 255, green: 244 / 255, blue: 250 / 255))
                .ignoresSafeArea()

            ScrollView {
                LazyVGrid(columns: self.columns, alignment: .leading, spacing: 20) {
                    ForEach(self.entries) { entry in
                        self.tile(entry)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 40)

                if self.entries.isEmpty {
                    Text("Nothing here yet.")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.primary.opacity(0.6))
                        .padding(.top, 32)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            ZStack {
                Text(self.title)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .frame(maxWidth: 200)
                HStack {
                    Button(action: self.onClose) {
                        Group {
                            if self.isNested {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(Color.primary)
                            } else {
                                Image("ChatBackGlyph")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 22, height: 22)
                                    .foregroundStyle(Color.primary)
                            }
                        }
                        .frame(width: 40, height: 40)
                        .background { self.glassChrome }
                        .shadow(color: .black.opacity(0.15), radius: 25, x: 0, y: 0)
                    }
                    Spacer()
                    // Info affordance is root-only; folder destinations omit it.
                    if !self.isNested {
                        Button(action: self.onInfo) {
                            Text("i")
                                .font(.system(size: 19))
                                .foregroundStyle(Color.primary)
                                .frame(width: 40, height: 40)
                                .background { self.glassChrome }
                                .shadow(color: .black.opacity(0.15), radius: 25, x: 0, y: 0)
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.top, 8)
            .padding(.bottom, 27)
        }
        .toolbar(.hidden, for: .navigationBar)
        .quickLookPreview(self.$previewURL)
    }

    /// Frosted glass chrome, matching the Usage/Instances/Skills nav buttons across the app.
    private var glassChrome: some View {
        ChatGlassBackground(
            shape: Circle(),
            fill: self.colorScheme == .dark
                ? Color(red: 30 / 255, green: 30 / 255, blue: 30 / 255).opacity(0.2)
                : Color(red: 245 / 255, green: 244 / 255, blue: 250 / 255).opacity(0.2))
    }

    private func tile(_ entry: WorkspaceGridEntry) -> some View {
        Button {
            if entry.isFolder {
                OpenClawHaptics.tap()
                self.onOpenFolder(entry)
            } else {
                self.loadingID = entry.id
                Task {
                    self.previewURL = await self.fetchPreviewURL(entry)
                    self.loadingID = nil
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(self.colorScheme == .dark ? Color.black : .white)
                    if self.loadingID == entry.id {
                        ProgressView()
                    } else {
                        Image(entry.isFolder ? "FilesFolderGlyph" : "FilesFileGlyph")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 37, height: 37)
                            .foregroundStyle(Color.primary.opacity(0.75))
                    }
                }
                .frame(height: 108)
                .frame(maxWidth: .infinity)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.name)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    Text(entry.typeLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.primary.opacity(0.6))
                        // Keep the subtitle to one line — an unusually long extension must truncate with
                        // "…" rather than wrap, which would grow the cell and misalign the grid row.
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Drawer host

/// Loads the active agent's workspace for the drawer's Files page and feeds `FilesGridScreen`, keeping
/// the proven `agents.workspace.list` / `agents.workspace.get` data layer (`AgentWorkspaceDirectoryList`
/// still owns encoding + error diagnostics). Folder taps push another grid; file taps stream bytes to a
/// temp file whose real name drives QuickLook's renderer.
struct FilesWorkspaceScreenHost: View {
    let onClose: () -> Void

    @Environment(NodeAppModel.self) private var appModel

    var body: some View {
        NavigationStack {
            FilesWorkspaceFolderView(
                agentId: self.activeAgentID,
                path: "",
                title: "Files",
                isNested: false,
                onClose: self.onClose)
        }
    }

    /// Workspace RPCs are agent-scoped; fall back through the same chain the Agent tab uses.
    private var activeAgentID: String {
        Self.normalized(self.appModel.selectedAgentId)
            ?? Self.normalized(self.appModel.gatewayDefaultAgentId)
            ?? "main"
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// One folder level. Loads its own path, renders the grid, and pushes a child view for subfolders.
struct FilesWorkspaceFolderView: View {
    @Environment(NodeAppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    let agentId: String
    let path: String
    let title: String
    let isNested: Bool
    let onClose: () -> Void // root: dismiss the drawer; nested levels pop via `dismiss`.

    @State private var entries: [WorkspaceGridEntry] = []
    @State private var pushedFolder: WorkspaceGridEntry?
    @State private var showsInfo = false

    var body: some View {
        FilesGridScreen(
            title: self.title,
            entries: self.entries,
            isNested: self.isNested,
            onClose: { self.isNested ? self.dismiss() : self.onClose() },
            onOpenFolder: { self.pushedFolder = $0 },
            onInfo: { self.showsInfo = true },
            fetchPreviewURL: { await self.preview($0) })
            .task(id: "\(self.agentId)|\(self.path)") { await self.load() }
            .navigationDestination(item: self.$pushedFolder) { folder in
                FilesWorkspaceFolderView(
                    agentId: self.agentId,
                    path: folder.id,
                    title: folder.name,
                    isNested: true,
                    onClose: self.onClose)
            }
            .alert("File not loading?", isPresented: self.$showsInfo) {
                Button {
                    self.showsInfo = false
                } label: {
                    Text("OK").font(.system(size: 17, weight: .medium))
                }
            } message: {
                Text("Update and restart the gateway, or change gateway access to \"Full Access\".")
            }
    }

    // MARK: - Data (reuses AgentWorkspaceDirectoryList's encoding + diagnostics)

    private func load() async {
        var collected: [AgentsWorkspaceEntry] = []
        var offset = 0
        var total = Int.max
        var guardCount = 0
        // The list RPC paginates; accumulate pages so the grid shows the whole folder.
        while collected.count < total, guardCount < 50 {
            guardCount += 1
            guard let page = await self.fetchPage(offset: offset) else { break }
            total = page.totalentries
            let known = Set(collected.map(\.path))
            let fresh = page.entries.filter { !known.contains($0.path) }
            if fresh.isEmpty {
                break
            }
            collected.append(contentsOf: fresh)
            offset = collected.count
        }
        self.entries = collected.map { entry in
            WorkspaceGridEntry(
                id: entry.path,
                name: entry.name,
                isFolder: (entry.kind.value as? String) == "directory")
        }
    }

    private func fetchPage(offset: Int) async -> AgentsWorkspaceListResult? {
        let method = "agents.workspace.list"
        let params = AgentsWorkspaceListParams(
            agentid: self.agentId,
            path: self.path.isEmpty ? nil : self.path,
            offset: offset == 0 ? nil : offset,
            limit: nil)
        let paramsJSON = (try? AgentWorkspaceDirectoryList.encodeParams(params)) ?? "{}"
        do {
            let data = try await self.appModel.operatorSession.request(
                method: method,
                paramsJSON: paramsJSON,
                timeoutSeconds: 12)
            return try JSONDecoder().decode(AgentsWorkspaceListResult.self, from: data)
        } catch {
            print("🗂️ [Files] list failed (path=\"\(self.path)\")\n\(AgentWorkspaceDirectoryList.describeError(error))")
            return nil
        }
    }

    private func preview(_ entry: WorkspaceGridEntry) async -> URL? {
        let method = "agents.workspace.get"
        let params = AgentsWorkspaceGetParams(agentid: self.agentId, path: entry.id)
        let paramsJSON = (try? AgentWorkspaceDirectoryList.encodeParams(params)) ?? "{}"
        do {
            let data = try await self.appModel.operatorSession.request(
                method: method,
                paramsJSON: paramsJSON,
                timeoutSeconds: 20)
            let file = try JSONDecoder().decode(AgentsWorkspaceGetResult.self, from: data).file
            return try Self.writeTempFile(file)
        } catch {
            let detail = AgentWorkspaceDirectoryList.describeError(error)
            print("🗂️ [Files] preview failed (path=\"\(entry.id)\")\n\(detail)")
            return nil
        }
    }

    /// Writes fetched bytes to a uniquely-nested temp file that keeps the real filename, so QuickLook
    /// picks the renderer from the extension (same trick as `ChatFileThumbnail`).
    private static func writeTempFile(_ file: AgentsWorkspaceFile) throws -> URL {
        let safeName = (file.name as NSString).lastPathComponent
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenClawWorkspaceFiles", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent(
            safeName.isEmpty ? "file" : safeName, isDirectory: false)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if (file.encoding.value as? String) == "base64", let bytes = Data(base64Encoded: file.content) {
            try bytes.write(to: fileURL, options: .atomic)
        } else {
            try file.content.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        return fileURL
    }
}
