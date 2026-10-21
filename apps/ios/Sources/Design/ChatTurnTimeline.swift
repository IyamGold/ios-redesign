import OpenClawChatUI
import SwiftUI

/// Renders an assistant turn as ONE continuous, append-only vertical stack — the Claude/ChatGPT model —
/// so the thinking process never has dead air, nothing is shown-then-yanked, and completion is a collapse
/// in place rather than a node→rows swap. Order:
///   1. a reasoning fold ("Thinking…" latest line live → "Thought for Ns" receipt),
///   2. a step group (preamble lines + tool steps; shimmering while working, collapsing to
///      "Worked through N steps"),
///   3. the trailing answer, streaming in place below the steps.
///
/// Stage T3 renders the LIVE turn (answer via `StreamingReplyBubble`); Stage T4 reuses this same view for
/// completed/history turns (folds pre-collapsed, answer static) so the live→resting transition is a
/// collapse on one identity.
struct ChatTurnTimeline: View {
    let turn: OpenClawChatLiveTurn
    /// Gates the node/fold entrance until the just-sent user bubble has settled (matches the old
    /// `nodeReady`), so the timeline doesn't ride the send spring and pop in early. The answer is ungated.
    let nodeReady: Bool
    let colorScheme: ColorScheme
    let textColor: Color
    /// Resting-only: open the "Worked through N steps" sheet. Nil while live (steps aren't tappable).
    var onOpenSteps: (([String]) -> Void)?

    /// The turn has moved past "working" — the answer is streaming or the run ended — so the reasoning and
    /// step folds settle to their quiet receipts.
    private var isSettled: Bool {
        self.turn.state != .running || self.turn.answerSegmentID != nil
    }

    /// Step footprints in turn order: preamble texts (every non-answer `.text`, positional) + tool names.
    private var stepLines: [String] {
        self.turn.segments.compactMap { segment in
            switch segment {
            case let .toolCall(tool): tool.name
            case let .text(id, text, _): (id == self.turn.answerSegmentID || text.isEmpty) ? nil : text
            case .reasoning: nil
            }
        }
    }

    /// The node's live "latest activity" line: a running tool wins, else the most recent step line.
    private func stepLatestLine(_ steps: [String]) -> String {
        for segment in self.turn.segments.reversed() {
            if case let .toolCall(tool) = segment, tool.state == .running {
                return tool.name
            }
        }
        return steps.last ?? "Working"
    }

    private static func stepsLabel(_ count: Int) -> String {
        "Worked through \(count) step\(count == 1 ? "" : "s")"
    }

    var body: some View {
        let answer = self.turn.trailingAnswerText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAnswer = !(answer ?? "").isEmpty
        let steps = self.stepLines

        VStack(alignment: .leading, spacing: 10) {
            if let reasoning = self.turn.reasoning, !reasoning.text.isEmpty, self.nodeReady {
                ChatReasoningFold(
                    reasoning: reasoning,
                    isThinkingLive: !self.isSettled,
                    colorScheme: self.colorScheme)
            }

            if !steps.isEmpty, self.nodeReady {
                ChatThinkingNode(
                    label: self.isSettled ? Self.stepsLabel(steps.count) : self.stepLatestLine(steps),
                    steps: steps,
                    shimmer: !self.isSettled,
                    colorScheme: self.colorScheme,
                    onOpenSteps: self.isSettled ? { self.onOpenSteps?(steps) } : nil)
            } else if self.turn.reasoning == nil, !hasAnswer, self.turn.state == .running, self.nodeReady {
                // Live turn with nothing folded yet — a plain "Thinking" shimmer so the surface never freezes.
                ChatThinkingNode(label: "Thinking", steps: [], shimmer: true, colorScheme: self.colorScheme)
            }

            if hasAnswer, let text = self.turn.trailingAnswerText {
                StreamingReplyBubble(fullText: text, textColor: self.textColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The reasoning ("thinking") fold: a shimmering latest-thought line while the model thinks, settling to a
/// quiet "Thought for Ns" receipt. Collapsed by default; tap to expand the full reasoning. Manual toggle
/// wins over the auto state.
private struct ChatReasoningFold: View {
    let reasoning: OpenClawChatReasoningSegment
    let isThinkingLive: Bool
    let colorScheme: ColorScheme

    @State private var expanded = false
    /// Frozen "Thought for Ns" captured the moment thinking ends, so the receipt is stable even before the
    /// terminal event stamps `endedAt`.
    @State private var frozenReceipt: String?

    private var tint: Color {
        (self.colorScheme == .dark ? Color.white : .black).opacity(0.55)
    }

    /// Last non-empty line of the reasoning — the "current thought" shown live.
    private var latestLine: String {
        let line = self.reasoning.text.split(whereSeparator: \.isNewline).last.map(String.init)
        let trimmed = (line ?? self.reasoning.text).trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Thinking" : trimmed
    }

    private func receipt() -> String {
        let endMs = self.reasoning.endedAt ?? (Date().timeIntervalSince1970 * 1000)
        guard let startMs = self.reasoning.startedAt, endMs > startMs else { return "Thought" }
        let seconds = max(1, Int(((endMs - startMs) / 1000).rounded()))
        return seconds < 60 ? "Thought for \(seconds)s" : "Thought for \(seconds / 60)m \(seconds % 60)s"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { self.expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    if self.isThinkingLive {
                        ChatShimmerLabel(text: self.latestLine)
                    } else {
                        Text(self.frozenReceipt ?? self.receipt())
                            .font(.system(size: 16).italic())
                            .foregroundStyle(self.tint)
                            .lineLimit(1)
                    }
                    Image(systemName: self.expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(self.tint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            if self.expanded {
                Text(self.reasoning.text)
                    .font(.system(size: 14))
                    .foregroundStyle(self.tint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .onChange(of: self.isThinkingLive) { _, live in
            // Freeze the duration the instant thinking ends (answer begins), before `endedAt` is stamped.
            if !live, self.frozenReceipt == nil {
                self.frozenReceipt = self.receipt()
            }
        }
    }
}
