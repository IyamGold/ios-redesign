import SwiftUI

/// Public seam over the kit's markdown pipeline so app-side chat surfaces can render assistant/user
/// text with full formatting (bold/italic, inline code, links, fenced code with highlighting, tables,
/// inline math) instead of a plain `Text`. Pass already-visible text (tool/thinking traces stripped).
public struct OpenClawChatMarkdownText: View {
    private let text: String
    private let isUser: Bool
    private let font: Font
    private let textColor: Color

    public init(text: String, isUser: Bool, font: Font, textColor: Color) {
        self.text = text
        self.isUser = isUser
        self.font = font
        self.textColor = textColor
    }

    public var body: some View {
        ChatMarkdownRenderer(
            text: self.text,
            context: self.isUser ? .user : .assistant,
            variant: .standard,
            font: self.font,
            textColor: self.textColor)
    }
}
