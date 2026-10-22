import Foundation

/// Plain-text projection of a transcript message: exactly what the reader sees
/// in the bubble, with tool traces and non-text blocks removed. Shared by the
/// transcript exporter and the Listen action so exported and spoken text
/// always match the visible transcript.
public enum ChatMessageVisibleText {
    public static func visibleText(in message: OpenClawChatMessage) -> String {
        let text = self.primaryText(in: message)
        let role = message.role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard role != "user" else { return text }
        return AssistantTextParser.visibleSegments(from: text)
            .map(\.text)
            .joined(separator: "\n\n")
    }

    public static func hasVisibleText(in message: OpenClawChatMessage) -> Bool {
        !self.visibleText(in: message)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    /// The model's reasoning ("thinking") persisted on an assistant message, concatenated across content
    /// blocks, or nil when none was saved. `visibleText` deliberately drops this; the steps sheet uses it to
    /// show the "Thought" group at rest (openai-responses often persists no thinking → nil → no group).
    public static func reasoningText(in message: OpenClawChatMessage) -> String? {
        let parts = message.content.compactMap { content -> String? in
            let thinking = content.thinking?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (thinking?.isEmpty == false) ? thinking : nil
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    private static func primaryText(in message: OpenClawChatMessage) -> String {
        let parts = message.content.compactMap { content -> String? in
            let kind = (content.type ?? "text").lowercased()
            guard kind == "text" || kind.isEmpty else { return nil }
            return content.text
        }
        return OpenClawChatMessage.displayText(
            contentText: parts.joined(separator: "\n"),
            role: message.role,
            stopReason: message.stopReason,
            errorMessage: message.errorMessage)
    }
}
