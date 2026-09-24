import SwiftUI

// Canvas surfaces are delivered by the agent as `[embed …]` shortcodes in assistant messages, referencing
// gateway-hosted canvas documents. This file parses those embeds, renders them as inline chat cards and an
// archive list, and opens them in a web view (resolved against the gateway's capability-scoped host URL).

// MARK: - Model

/// A canvas embed parsed from an assistant message's `[embed …]` shortcode — the agent's canvas channel.
/// Durable by construction: it lives in chat history, so re-parsing the message re-creates it. `entryURL`
/// is the canvas document path (e.g. `/__openclaw__/canvas/documents/<id>/index.html`), resolved against
/// the gateway's capability-scoped canvas host URL at open time.
struct CanvasEmbed: Identifiable, Equatable {
    let id: String
    let title: String
    let entryURL: String
}

// MARK: - Index (session transcript → archive list)

/// Shared list of the `[embed]` canvases seen in the current transcript. `ChatRootSurface` populates it as
/// it projects rows (it owns the messages); the drawer's Canvas archive reads it (it doesn't). Newest first,
/// deduped by document URL so the same canvas referenced twice shows once in the archive.
@MainActor
@Observable
final class CanvasEmbedIndex {
    static let shared = CanvasEmbedIndex()

    private(set) var embeds: [CanvasEmbed] = []

    /// Replace with the transcript's embeds (passed oldest→newest). Kept as a no-op when unchanged so a
    /// rebuild that found the same set doesn't publish a spurious update.
    func update(fromTranscriptOrder transcriptEmbeds: [CanvasEmbed]) {
        var seen = Set<String>()
        let newestFirst = transcriptEmbeds.reversed().filter { seen.insert($0.entryURL).inserted }
        if self.embeds.map(\.id) != newestFirst.map(\.id) {
            self.embeds = newestFirst
        }
    }
}

// MARK: - Parsing

enum CanvasEmbedParser {
    private static let selfClosing = try? NSRegularExpression(
        pattern: #"\[embed\s+([^\]]*?)/\]"#, options: [.caseInsensitive])
    private static let block = try? NSRegularExpression(
        pattern: #"\[embed\s+([^\]]*?)\][\s\S]*?\[/embed\]"#, options: [.caseInsensitive])
    private static let attribute = try? NSRegularExpression(
        pattern: #"([A-Za-z_][A-Za-z0-9_-]*)\s*=\s*(?:"([^"]*)"|'([^']*)')"#, options: [])

    /// Parse `[embed …]` shortcodes out of a message's visible text (mirrors the gateway's canvas-render
    /// extraction). Returns the text with the tags removed and the embeds in document order.
    static func parse(messageID: String, text: String) -> (text: String, embeds: [CanvasEmbed]) {
        guard text.contains("[embed"), let selfClosing, let block else { return (text, []) }
        var occurrences: [(range: NSRange, attrs: String)] = []
        var working = text as NSString
        for regex in [block, selfClosing] {
            let full = NSRange(location: 0, length: working.length)
            for match in regex.matches(in: working as String, options: [], range: full) where match.numberOfRanges > 1 {
                occurrences.append((match.range, working.substring(with: match.range(at: 1))))
            }
        }
        occurrences.sort { $0.range.location < $1.range.location }
        var embeds: [CanvasEmbed] = []
        for (index, occ) in occurrences.enumerated() {
            if let embed = self.embed(from: occ.attrs, messageID: messageID, index: index) {
                embeds.append(embed)
            }
        }
        // Strip the tags from the displayed text back-to-front so earlier ranges stay valid.
        for occ in occurrences.sorted(by: { $0.range.location > $1.range.location }) {
            working = working.replacingCharacters(in: occ.range, with: "") as NSString
        }
        return ((working as String).trimmingCharacters(in: .whitespacesAndNewlines), embeds)
    }

    private static func embed(from attrs: String, messageID: String, index: Int) -> CanvasEmbed? {
        guard let attribute else { return nil }
        var map: [String: String] = [:]
        let ns = attrs as NSString
        for match in attribute.matches(in: attrs, options: [], range: NSRange(location: 0, length: ns.length)) {
            let key = ns.substring(with: match.range(at: 1)).lowercased()
            let doubleQuoted = match.range(at: 2)
            let singleQuoted = match.range(at: 3)
            if doubleQuoted.location != NSNotFound {
                map[key] = ns.substring(with: doubleQuoted)
            } else if singleQuoted.location != NSNotFound {
                map[key] = ns.substring(with: singleQuoted)
            }
        }
        let entryURL: String
        if let url = map["url"]?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
            entryURL = url
        } else if let ref = map["ref"]?.trimmingCharacters(in: .whitespacesAndNewlines), !ref.isEmpty {
            let encoded = ref.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ref
            entryURL = "/__openclaw__/canvas/documents/\(encoded)/index.html"
        } else {
            return nil
        }
        // Only canvas/a2ui document paths are renderable — ignore external/other embeds (desktop parity).
        guard entryURL.hasPrefix("/__openclaw__/canvas") || entryURL.hasPrefix("/__openclaw__/a2ui") else {
            return nil
        }
        let title = map["title"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return CanvasEmbed(
            id: "embed-\(messageID)-\(index)",
            title: title?.isEmpty == false ? title! : "Canvas",
            entryURL: entryURL)
    }
}

enum CanvasURLResolver {
    /// Swift port of the desktop `resolveCanvasIframeUrl`: splice the canvas entry path under the
    /// capability-scoped host prefix (`/__openclaw__/cap/<token>`) so the `oc_cap` rides in the PATH and
    /// the document's relative sub-resources inherit it. Returns nil when there's no usable host URL.
    static func absoluteURL(entryURL: String, canvasHostURL: String?) -> URL? {
        let entry = entryURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entry.isEmpty,
              entry.hasPrefix("/__openclaw__/canvas") || entry.hasPrefix("/__openclaw__/a2ui")
        else { return nil }
        guard let host = canvasHostURL?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty,
              let hostURL = URL(string: host),
              var components = URLComponents(url: hostURL, resolvingAgainstBaseURL: false),
              let entryComponents = URLComponents(string: entry)
        else { return nil }
        var scopedPrefix = hostURL.path
        while scopedPrefix.hasSuffix("/") {
            scopedPrefix.removeLast()
        }
        guard scopedPrefix.hasPrefix("/__openclaw__/cap") else { return nil }
        components.path = scopedPrefix + entryComponents.path
        components.query = entryComponents.query
        return components.url
    }
}

// MARK: - Shared bits

private struct CanvasThumbnailTile: View {
    let width: CGFloat
    let height: CGFloat
    /// Wrapper fill — differs by surface (archive page vs in-chat card), so the caller supplies it.
    let fill: Color
    /// The canvas page tile carries a soft edge shadow in both modes; the in-chat card tile is flat
    /// (no shadow, no stroke). The two surfaces are styled independently, not visually linked.
    let showsShadow: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(self.fill)
            Image("CanvasFileGlyph")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 33, height: 33)
                .foregroundStyle(Color.primary.opacity(self.colorScheme == .dark ? 0.35 : 0.2))
        }
        .frame(width: self.width, height: self.height)
        .shadow(color: self.showsShadow ? .white.opacity(0.15) : .clear, radius: 1)
    }
}

/// Reusable glass close + centered title, shared by the canvas surfaces.
private struct CanvasPanelHeader: View {
    let title: String
    let onClose: () -> Void
    // Archive screen (a drawer tab) passes the back chevron so its leading button opens the drawer;
    // the embed viewer panels are sheets and keep the default close X.
    var leadingGlyph = "ChatCloseGlyph"
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Text(self.title)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .frame(maxWidth: 240)
            HStack {
                Button(action: self.onClose) {
                    Image(self.leadingGlyph)
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
        }
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
}

// MARK: - Chat card (interleaved in the conversation)

/// Inline chat card for a `[embed]` canvas.
struct CanvasEmbedCard: View {
    let embed: CanvasEmbed
    let onOpen: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: self.onOpen) {
            HStack(spacing: 17) {
                CanvasThumbnailTile(
                    width: 64,
                    height: 47,
                    fill: self.colorScheme == .dark
                        ? Color(red: 23 / 255, green: 23 / 255, blue: 23 / 255)
                        : Color(red: 245 / 255, green: 244 / 255, blue: 250 / 255),
                    showsShadow: false)
                VStack(alignment: .leading, spacing: 6) {
                    Text(self.embed.title)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    Text("Canvas")
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

// MARK: - Archive page (drawer destination)

struct CanvasArchiveScreen: View {
    let onClose: () -> Void
    let onOpenEmbed: (CanvasEmbed) -> Void

    @State private var index = CanvasEmbedIndex.shared
    @State private var query = ""
    @Environment(\.colorScheme) private var colorScheme

    /// Live filter: title contains the (case-insensitive) query; empty query shows everything.
    private var results: [CanvasEmbed] {
        let trimmed = self.query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return self.index.embeds }
        return self.index.embeds.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            (self.colorScheme == .dark
                ? Color(red: 23 / 255, green: 23 / 255, blue: 23 / 255)
                : Color(red: 245 / 255, green: 244 / 255, blue: 250 / 255))
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 31) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 17))
                            .foregroundStyle(Color.primary.opacity(0.7))
                        TextField("Search", text: self.$query)
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
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(
                                self.colorScheme == .dark ? .clear : Color.black.opacity(0.2),
                                lineWidth: 0.5)
                    }

                    let rows = self.results
                    VStack(spacing: 12) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, embed in
                            VStack(spacing: 12) {
                                Button {
                                    self.onOpenEmbed(embed)
                                } label: {
                                    HStack(spacing: 13) {
                                        CanvasThumbnailTile(
                                            width: 49,
                                            height: 54,
                                            fill: self.colorScheme == .dark ? .black : .white,
                                            showsShadow: true)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(embed.title)
                                                .font(.system(size: 17, weight: .medium))
                                                .foregroundStyle(Color.primary)
                                                .lineLimit(1)
                                            Text("Canvas")
                                                .font(.system(size: 13))
                                                .foregroundStyle(Color.primary.opacity(0.6))
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                // Divider only between rows — never after the last (or a lone) item.
                                if index < rows.count - 1 {
                                    Rectangle()
                                        .fill(Color.primary.opacity(0.1))
                                        .frame(height: 0.5)
                                        .padding(.leading, 63)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            CanvasPanelHeader(title: "Canvas", onClose: self.onClose, leadingGlyph: "ChatBackGlyph")
                .padding(.top, 8)
                .padding(.bottom, 14)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Viewer panel

/// Viewer for a `[embed]` canvas: refreshes the capability-scoped host URL, resolves the document URL, and
/// loads it in a dedicated web view (a fresh controller so it never disturbs the live canvas). The web view
/// is only mounted once the URL is resolved, so the controller never flashes its default scaffold page.
struct CanvasEmbedPanel: View {
    let embed: CanvasEmbed
    /// Provides the current (freshly refreshed) capability-scoped canvas host URL.
    let canvasHostProvider: () async -> String?
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var replayController = ScreenController()
    @State private var loadState: LoadState = .resolving

    private enum LoadState {
        case resolving
        case ready
        case failed
    }

    private var canvasBackground: Color {
        self.colorScheme == .dark
            ? Color(red: 23 / 255, green: 23 / 255, blue: 23 / 255)
            : Color(red: 245 / 255, green: 244 / 255, blue: 250 / 255)
    }

    var body: some View {
        ZStack {
            self.canvasBackground.ignoresSafeArea()
            switch self.loadState {
            case .ready:
                // Mounted only after the target URL is set on the controller, so attach → reload loads the
                // real doc directly instead of the default scaffold.
                ScreenWebView(controller: self.replayController)
                    .ignoresSafeArea(edges: .bottom)
            case .failed:
                Image("CanvasFileGlyph")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .foregroundStyle(Color.primary.opacity(0.15))
            case .resolving:
                EmptyView()
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            CanvasPanelHeader(title: self.embed.title, onClose: self.onClose)
        }
        .task {
            let host = await self.canvasHostProvider()
            guard let url = CanvasURLResolver.absoluteURL(
                entryURL: self.embed.entryURL, canvasHostURL: host)
            else {
                self.loadState = .failed
                return
            }
            // Point the controller at the real doc before the web view mounts (below), so it loads that
            // directly — no scaffold flash.
            self.replayController.present(urlString: url.absoluteString)
            self.loadState = .ready
        }
    }
}
