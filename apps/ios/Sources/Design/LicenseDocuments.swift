import Foundation
import SwiftUI

struct LicenseDocument: Identifiable {
    let id: String
    let title: String
    let filename: String
    let body: String
}

enum LicenseDocumentLoader {
    static let directoryName = "Licenses"

    static func bundledDocuments(bundle: Bundle = .main) -> [LicenseDocument] {
        guard let resourceURL = bundle.resourceURL else { return [] }
        return self.documents(in: resourceURL.appendingPathComponent(self.directoryName, isDirectory: true))
    }

    static func documents(in directoryURL: URL) -> [LicenseDocument] {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles])
        else {
            return []
        }

        return urls.compactMap(self.document(from:)).sorted { lhs, rhs in
            let titleComparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
            if titleComparison == .orderedSame {
                return lhs.filename.localizedCaseInsensitiveCompare(rhs.filename) == .orderedAscending
            }
            return titleComparison == .orderedAscending
        }
    }

    static func title(from filename: String) -> String {
        let name = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        let title = name
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return title.isEmpty ? filename : title
    }

    private static func document(from url: URL) -> LicenseDocument? {
        let filename = url.lastPathComponent
        guard !filename.hasPrefix("."),
              url.pathExtension.lowercased() == "txt"
        else {
            return nil
        }

        let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
        guard values?.isRegularFile == true else { return nil }
        guard let body = try? String(contentsOf: url, encoding: .utf8),
              !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        return LicenseDocument(
            id: filename,
            title: self.title(from: filename),
            filename: filename,
            body: body)
    }
}

// MARK: - Licenses (redesigned Settings destination)

/// Redesigned Settings → Licenses list. Rows are still discovered at runtime by
/// `LicenseDocumentLoader` (alphabetical, no hardcoded entries); tapping pushes the verbatim
/// monospace detail. Chrome/tokens match the sibling Settings destinations.
struct LicensesScreen: View {
    let onBack: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    private var documents: [LicenseDocument] {
        LicenseDocumentLoader.bundledDocuments()
    }

    var body: some View {
        SettingsDestinationChrome(title: "Licenses", onBack: self.onBack) {
            ScrollView {
                if self.documents.isEmpty {
                    Text("License files are not available in this build.")
                        .font(OpenClawType.body)
                        .foregroundStyle(Color.primary.opacity(0.6))
                        .padding(.top, 32)
                } else {
                    self.card
                    Text("OpenClaw appreciates its partners in the open-source community.")
                        .font(OpenClawType.footnote)
                        .foregroundStyle(Color.primary.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 40)
                        .padding(.top, 20)
                }
            }
        }
    }

    private var card: some View {
        VStack(spacing: 17) {
            ForEach(Array(self.documents.enumerated()), id: \.element.id) { index, document in
                self.row(document)
                if index < self.documents.count - 1 {
                    self.divider
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 15)
        .background {
            RoundedRectangle(cornerRadius: 25, style: .continuous).fill(self.cardFill)
        }
        .padding(.horizontal, 24)
        .padding(.top, 4)
        .accessibilityIdentifier("settings-licenses-list")
    }

    private func row(_ document: LicenseDocument) -> some View {
        NavigationLink {
            LicenseDocumentDetailView(document: document)
        } label: {
            HStack {
                Text(document.title)
                    .font(OpenClawType.body)
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 0)
                Image("SettingsChevronRightGlyph")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(Color.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 0.3 crisp single-pixel hairline centered between 17pt-spaced rows (shared Settings token).
    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.3))
            .frame(maxWidth: .infinity)
            .frame(height: 1 / self.displayScale)
    }

    private var cardFill: Color {
        self.colorScheme == .dark ? .black : .white
    }
}

struct LicenseDocumentDetailView: View {
    let document: LicenseDocument

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SettingsDestinationChrome(title: self.document.title, onBack: { self.dismiss() }) {
            ScrollView {
                Text(verbatim: self.document.body)
                    .font(OpenClawType.monoFootnote)
                    .foregroundStyle(Color.primary)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("licenses-detail-text")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
            }
        }
    }
}
