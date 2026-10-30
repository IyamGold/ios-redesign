import SwiftUI

// Agent-generated files arrive as documented `MEDIA:<path>` directives in the assistant's final reply
// (gateway `src/agents/system-prompt.ts` + parser `src/media/parse.ts`). WebChat normalizes these into
// attachments; the iOS node receives the raw `MEDIA:` line as plain text. This file parses those
// directives, strips them from the visible bubble, and renders a tappable file card — mirroring the
// canvas embed card (`CanvasArtifacts.swift`) with the files glyph. Tapping fetches the referenced
// workspace file via `agents.workspace.get` and opens it in QuickLook (wired in ChatRootSurface).

// MARK: - Model

/// A file attachment parsed from an assistant message's `MEDIA:<path>` directive. Durable by
/// construction: it lives in chat history, so re-parsing the message re-creates it.
struct FileEmbed: Identifiable, Equatable {
    let id: String
    /// Display name, e.g. `premier-league-top5-2026-10-30.csv`.
    let fileName: String
    /// Path for `agents.workspace.get`, relative to the agent workspace root.
    let workspacePath: String
}

// MARK: - Parsing

enum FileEmbedParser {
    // Mirrors the gateway's MEDIA_TOKEN_RE (`src/media/parse.ts`): a line that *starts* with `MEDIA:`
    // (plain text, outside code fences per the system prompt), value optionally backtick-wrapped.
    // Anchored to line start so stray prose containing "MEDIA:" mid-sentence never false-triggers.
    private static let media = try? NSRegularExpression(
        pattern: #"(?m)^[ \t]*MEDIA:[ \t]*`?([^\n`]+?)`?[ \t]*$"#, options: [])

    /// Extract `MEDIA:` directives; return the text with those lines removed + embeds in document order.
    static func parse(messageID: String, text: String) -> (text: String, embeds: [FileEmbed]) {
        guard text.contains("MEDIA:"), let media else { return (text, []) }
        let ns = text as NSString
        var occurrences: [(range: NSRange, value: String)] = []
        for match in media.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
            where match.numberOfRanges > 1
        {
            let value = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            occurrences.append((match.range, value))
        }
        guard !occurrences.isEmpty else { return (text, []) }

        var embeds: [FileEmbed] = []
        for (index, occ) in occurrences.enumerated() {
            if let embed = self.embed(from: occ.value, messageID: messageID, index: index) {
                embeds.append(embed)
            }
        }
        // Strip the MEDIA lines from the displayed text back-to-front so earlier ranges stay valid.
        var working = ns
        for occ in occurrences.sorted(by: { $0.range.location > $1.range.location }) {
            working = working.replacingCharacters(in: occ.range, with: "") as NSString
        }
        return ((working as String).trimmingCharacters(in: .whitespacesAndNewlines), embeds)
    }

    private static func embed(from raw: String, messageID: String, index: Int) -> FileEmbed? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Only workspace file paths are fetchable via `agents.workspace.get`; skip http(s) URLs here.
        guard !value.isEmpty, !value.lowercased().hasPrefix("http") else { return nil }
        let fileName = (value as NSString).lastPathComponent
        guard !fileName.isEmpty else { return nil }
        return FileEmbed(
            id: "media-\(messageID)-\(index)",
            fileName: fileName,
            workspacePath: self.workspaceRelativePath(value))
    }

    /// Map an absolute agent path to a workspace-relative path for `agents.workspace.get`:
    /// `/root/.openclaw/workspace/foo/bar.csv` → `foo/bar.csv`; already-relative paths pass through.
    private static func workspaceRelativePath(_ path: String) -> String {
        let marker = "/.openclaw/workspace/"
        if let range = path.range(of: marker) {
            return String(path[range.upperBound...])
        }
        return path.hasPrefix("/") ? String(path.dropFirst()) : path
    }
}

// MARK: - Chat card (interleaved in the conversation)

/// Inline chat card for an agent `MEDIA:` file — a clone of `CanvasEmbedCard` with the files glyph.
struct FileEmbedCard: View {
    let embed: FileEmbed
    let onOpen: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    /// Subtitle mirrors the canvas card's "Canvas" type label: the file's uppercased extension, else "File".
    private var subtitle: String {
        let ext = (self.embed.fileName as NSString).pathExtension
        return ext.isEmpty ? "File" : ext.uppercased()
    }

    var body: some View {
        Button(action: self.onOpen) {
            HStack(spacing: 17) {
                FileGlyphTile(
                    fill: self.colorScheme == .dark
                        ? Color(red: 23 / 255, green: 23 / 255, blue: 23 / 255)
                        : Color(red: 245 / 255, green: 244 / 255, blue: 250 / 255))
                VStack(alignment: .leading, spacing: 6) {
                    Text(self.embed.fileName)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(self.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.primary.opacity(0.6))
                }
                Spacer(minLength: 0)
                Image("SettingsChevronRightGlyph")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(Color.primary.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .frame(height: 70)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(self.colorScheme == .dark ? Color.black : Color.white.opacity(0.7))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.07), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

/// The file card's left tile: `ChatFilesGlyph` centered on a rounded fill (mirrors CanvasThumbnailTile).
private struct FileGlyphTile: View {
    let fill: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(self.fill)
            Image("ChatFilesGlyph")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 26, height: 26)
                .foregroundStyle(Color.primary.opacity(self.colorScheme == .dark ? 0.35 : 0.2))
        }
        .frame(width: 64, height: 47)
    }
}
