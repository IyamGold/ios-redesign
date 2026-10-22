import OpenClawChatUI
import SwiftUI

/// Renders an in-flight assistant turn as ONE continuous, append-only collapsible — the Claude/ChatGPT
/// model. A SINGLE "steps" node shimmers through the whole process (reasoning → preambles → tool activity)
/// as tidy latest-line items, so there's never dead air and a preamble never flashes as a full reply.
/// When the real answer begins (`phase: final_answer`), the node settles to "Worked through N steps" and
/// the answer streams in place below. Tapping the settled node opens the steps sheet, where the model's
/// reasoning is the first nested "Thought for Ns" group followed by the tool/preamble steps.
///
/// There is no longer a separate reasoning fold: reasoning and the work steps are one group, which is what
/// keeps the thinking surface shimmering continuously (one node) instead of a reasoning receipt freezing
/// above a second node that renders preambles as replies.
struct ChatTurnTimeline: View {
    let turn: OpenClawChatLiveTurn
    /// Gates the node's entrance until the just-sent user bubble has settled (matches the old `nodeReady`),
    /// so the timeline doesn't ride the send spring and pop in early. The answer is ungated.
    let nodeReady: Bool
    let colorScheme: ColorScheme
    let textColor: Color
    /// Opens the steps sheet (settled only). Carries the tool/preamble step lines + the reasoning group.
    var onOpenSteps: ((_ steps: [String], _ reasoning: ChatStepsReasoning?) -> Void)?

    /// Wall-clock (ms) captured the instant the model stops thinking (first non-reasoning content appears),
    /// so "Thought for Ns" shows a real duration — the reducer's terminal close can't measure it.
    @State private var thinkingEndedAtMs: Double?

    /// The turn has produced its final answer (or ended) — the node settles to its quiet receipt and the
    /// answer streams below. Preambles/tools keep the node shimmering until this flips.
    private var isSettled: Bool {
        self.turn.state != .running || self.turn.answerSegmentID != nil
    }

    /// Any content beyond the reasoning block (a preamble, tool, or the answer). Its first appearance marks
    /// the end of the "pure thinking" phase and freezes the "Thought for Ns" duration.
    private var hasProcessContent: Bool {
        self.turn.segments.contains { segment in
            if case .reasoning = segment {
                false
            } else {
                true
            }
        }
    }

    /// Still in the pure-thinking phase: reasoning is streaming and nothing else exists yet.
    private var isThinkingLive: Bool {
        guard let reasoning = self.turn.reasoning, !reasoning.text.isEmpty else { return false }
        return self.turn.state == .running && !self.hasProcessContent
    }

    /// Tool/preamble step footprints in turn order (reasoning is NOT a step — it's the nested group).
    private var stepLines: [String] {
        self.turn.segments.compactMap { segment in
            switch segment {
            case let .toolCall(tool): tool.name
            case let .text(id, text, _): (id == self.turn.answerSegmentID || text.isEmpty) ? nil : text
            case .reasoning: nil
            }
        }
    }

    var body: some View {
        let answer = self.turn.trailingAnswerText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAnswer = !(answer ?? "").isEmpty
        let steps = self.stepLines
        let reasoning = self.turn.reasoning.flatMap { $0.text.isEmpty ? nil : $0 }
        let hasReasoning = reasoning != nil
        let showNode = self.nodeReady
            && (hasReasoning || !steps.isEmpty || (self.turn.state == .running && !hasAnswer))

        VStack(alignment: .leading, spacing: 10) {
            if showNode {
                let payload = reasoning.map {
                    ChatStepsReasoning(receipt: self.receipt(for: $0), text: $0.text)
                }
                let canOpen = self.isSettled && (hasReasoning || !steps.isEmpty)
                ChatThinkingNode(
                    label: self.nodeLabel(steps: steps, reasoning: reasoning),
                    steps: steps,
                    shimmer: !self.isSettled,
                    colorScheme: self.colorScheme,
                    onOpenSteps: canOpen ? { self.onOpenSteps?(steps, payload) } : nil)
            }

            if hasAnswer, let text = self.turn.trailingAnswerText {
                StreamingReplyBubble(fullText: text, textColor: self.textColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Reset per run so a previous turn's measured thinking duration never leaks into the next.
        .onChange(of: self.turn.runId) { _, _ in self.thinkingEndedAtMs = nil }
        .onChange(of: self.isThinkingLive) { _, live in
            if !live, self.thinkingEndedAtMs == nil, self.turn.reasoning != nil {
                self.thinkingEndedAtMs = Date().timeIntervalSince1970 * 1000
            }
        }
    }

    /// Live: the latest activity line (running tool → latest step → latest thought → "Thinking").
    /// Settled: "Worked through N steps" when there are steps, else the "Thought for Ns" receipt.
    private func nodeLabel(steps: [String], reasoning: OpenClawChatReasoningSegment?) -> String {
        if self.isSettled {
            if !steps.isEmpty {
                return Self.stepsLabel(steps.count)
            }
            if let reasoning {
                return self.receipt(for: reasoning)
            }
            return Self.stepsLabel(0)
        }
        for segment in self.turn.segments.reversed() {
            if case let .toolCall(tool) = segment, tool.state == .running {
                return tool.name
            }
        }
        if let last = steps.last {
            return last
        }
        if let reasoning {
            return Self.latestLine(of: reasoning.text)
        }
        return "Thinking"
    }

    private static func stepsLabel(_ count: Int) -> String {
        "Worked through \(count) step\(count == 1 ? "" : "s")"
    }

    /// Last non-empty line of the reasoning — the "current thought" shown live.
    private static func latestLine(of text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).last.map(String.init)
        let trimmed = (line ?? text).trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Thinking" : trimmed
    }

    /// "Thought for Ns" from the measured thinking window (frozen end), falling back to "Thought" when the
    /// window can't be measured (e.g. no `startedAt`).
    private func receipt(for reasoning: OpenClawChatReasoningSegment) -> String {
        let endMs = self.thinkingEndedAtMs ?? reasoning.endedAt
        guard let startMs = reasoning.startedAt, let endMs, endMs > startMs else { return "Thought" }
        let seconds = max(1, Int(((endMs - startMs) / 1000).rounded()))
        return seconds < 60 ? "Thought for \(seconds)s" : "Thought for \(seconds / 60)m \(seconds % 60)s"
    }
}
