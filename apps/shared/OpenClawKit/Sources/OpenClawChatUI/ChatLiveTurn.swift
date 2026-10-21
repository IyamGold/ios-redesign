import Foundation

/// A single in-flight assistant turn modeled as an ordered, append-only list of typed segments —
/// the structure the gateway already carries (typed `agent.*` events) but that the legacy client
/// flattened into one mutable string + a guessing machine. Rendering reads this directly as one
/// continuous collapsible timeline: a reasoning fold, preamble/tool steps, and the final answer that
/// streams in place below them. Nothing is shown-then-yanked and nothing is re-classified by heuristic.
///
/// Built only by `reduce(_:_:)` — one writer — so the two cumulative text sources can't fight.
public struct OpenClawChatLiveTurn: Equatable, Sendable, Identifiable {
    public enum State: String, Sendable, Equatable { case running, final, aborted, error }

    public var runId: String
    public var segments: [OpenClawChatTurnSegment]
    public var state: State

    public var id: String {
        self.runId
    }

    public init(runId: String, segments: [OpenClawChatTurnSegment] = [], state: State = .running) {
        self.runId = runId
        self.segments = segments
        self.state = state
    }

    /// Position-based final-answer identity: the last `.text` that comes AFTER the last tool call (or the
    /// last text overall when there are no tools). Everything else is a preamble/step. This is immune to
    /// the gateway's late-bound `phase` — a preamble can never masquerade as the answer just because its
    /// `phase: "commentary"` hadn't arrived yet.
    public var answerSegmentID: String? {
        let lastTool = self.segments.lastIndex {
            if case .toolCall = $0 {
                true
            } else {
                false
            }
        }
        let start = lastTool.map { $0 + 1 } ?? 0
        guard start < self.segments.count else { return nil }
        for index in stride(from: self.segments.count - 1, through: start, by: -1) {
            if case let .text(id, _, _) = self.segments[index] {
                return id
            }
        }
        return nil
    }

    /// The final answer text (the trailing post-tool text segment), or nil while none exists yet.
    public var trailingAnswerText: String? {
        guard let answerID = self.answerSegmentID else { return nil }
        for segment in self.segments {
            if case let .text(id, text, _) = segment, id == answerID {
                return text
            }
        }
        return nil
    }

    /// Ids of `.text` segments that are steps (preambles) — every text segment except the answer.
    public var stepTextIDs: Set<String> {
        let answerID = self.answerSegmentID
        var ids: Set<String> = []
        for segment in self.segments {
            if case let .text(id, _, _) = segment, id != answerID {
                ids.insert(id)
            }
        }
        return ids
    }

    public var runningToolCount: Int {
        self.segments.reduce(into: 0) { count, segment in
            if case let .toolCall(tool) = segment, tool.state == .running {
                count += 1
            }
        }
    }

    /// The turn's reasoning block (single per turn — matches the single "Thought for Ns" receipt), or nil.
    public var reasoning: OpenClawChatReasoningSegment? {
        for segment in self.segments {
            if case let .reasoning(block) = segment {
                return block
            }
        }
        return nil
    }
}

/// One typed part of a turn. `id` is stable across updates so SwiftUI keeps identity (no row churn).
public enum OpenClawChatTurnSegment: Equatable, Sendable, Identifiable {
    case reasoning(OpenClawChatReasoningSegment)
    /// Assistant prose. `isPreamble` is the server's `phase == "commentary"` hint; the authoritative
    /// preamble-vs-answer split is positional (see `answerSegmentID`), so the view keys off that.
    case text(id: String, text: String, isPreamble: Bool)
    case toolCall(OpenClawChatToolCallSegment)

    public var id: String {
        switch self {
        case let .reasoning(block): "reasoning:\(block.id)"
        case let .text(id, _, _): "text:\(id)"
        case let .toolCall(tool): "tool:\(tool.id)"
        }
    }
}

/// The turn's reasoning ("thinking"). A single accumulating block per turn. `startedAt`/`endedAt` (epoch
/// ms, supplied by the fold site so the reducer stays pure) drive the "Thought for Ns" receipt; `endedAt`
/// is nil while the model is still thinking and set when the turn goes terminal.
public struct OpenClawChatReasoningSegment: Equatable, Sendable, Identifiable {
    public var id: String
    public var text: String
    public var startedAt: Double?
    public var endedAt: Double?

    public var isOpen: Bool {
        self.endedAt == nil
    }

    public init(id: String, text: String = "", startedAt: Double? = nil, endedAt: Double? = nil) {
        self.id = id
        self.text = text
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

public struct OpenClawChatToolCallSegment: Equatable, Sendable, Identifiable {
    public enum State: String, Sendable, Equatable { case running, done, error }

    public var toolCallId: String
    public var name: String
    public var argsPreview: String?
    public var state: State

    public var id: String {
        self.toolCallId
    }

    public init(toolCallId: String, name: String, argsPreview: String? = nil, state: State = .running) {
        self.toolCallId = toolCallId
        self.name = name
        self.argsPreview = argsPreview
        self.state = state
    }
}

/// The typed inputs the reducer folds. The view model maps raw transport events into these at the one
/// fold site, keeping the reducer pure and unit-testable.
public enum OpenClawChatLiveTurnEvent: Sendable, Equatable {
    /// Cumulative text for one assistant message (`itemId`); resets per message server-side.
    case assistantText(runId: String, itemId: String?, isPreamble: Bool, text: String)
    /// Cumulative reasoning text for the turn, with the event timestamp (epoch ms) for the receipt.
    case reasoning(runId: String, text: String, at: Double?)
    case toolStart(runId: String, toolCallId: String, name: String, argsPreview: String?)
    case toolResult(runId: String, toolCallId: String, isError: Bool)
    case terminal(runId: String, state: OpenClawChatLiveTurn.State)

    public var runId: String {
        switch self {
        case let .assistantText(runId, _, _, _): runId
        case let .reasoning(runId, _, _): runId
        case let .toolStart(runId, _, _, _): runId
        case let .toolResult(runId, _, _): runId
        case let .terminal(runId, _): runId
        }
    }
}

extension OpenClawChatLiveTurn {
    /// The single reducer. Same `runId` reconciles into the existing turn (grows text, transitions tools)
    /// and NEVER wipes running-tool / preamble state; a genuinely different `runId` starts a fresh turn. A
    /// terminal for a run that isn't the active turn is ignored. Text/reasoning are length-monotonic per
    /// segment, so a lagging/short replay from either source can never regress the visible content.
    public static func reduce(
        _ current: OpenClawChatLiveTurn?,
        _ event: OpenClawChatLiveTurnEvent) -> OpenClawChatLiveTurn?
    {
        let runId = event.runId
        var turn: OpenClawChatLiveTurn
        if let current, current.runId == runId {
            turn = current
        } else {
            if case .terminal = event {
                return current
            }
            turn = OpenClawChatLiveTurn(runId: runId)
        }

        switch event {
        case let .assistantText(_, itemId, isPreamble, text):
            let key = itemId ?? "\(runId):answer:\(isPreamble ? "pre" : "final")"
            Self.applyText(&turn.segments, id: key, text: text, isPreamble: isPreamble)
        case let .reasoning(_, text, at):
            Self.applyReasoning(&turn.segments, runId: runId, text: text, at: at)
        case let .toolStart(_, toolCallId, name, argsPreview):
            Self.startTool(&turn.segments, toolCallId: toolCallId, name: name, argsPreview: argsPreview)
        case let .toolResult(_, toolCallId, isError):
            Self.finishTool(&turn.segments, toolCallId: toolCallId, isError: isError)
        case let .terminal(_, state):
            turn.state = state
            Self.closeReasoning(&turn.segments, at: nil)
        }
        return turn
    }

    private static func textIndex(_ segments: [OpenClawChatTurnSegment], id: String) -> Int? {
        segments.firstIndex {
            if case let .text(existing, _, _) = $0 {
                existing == id
            } else {
                false
            }
        }
    }

    private static func applyText(
        _ segments: inout [OpenClawChatTurnSegment],
        id: String,
        text: String,
        isPreamble: Bool)
    {
        if let index = textIndex(segments, id: id) {
            guard case let .text(_, existing, _) = segments[index], text.count >= existing.count else { return }
            segments[index] = .text(id: id, text: text, isPreamble: isPreamble)
        } else if !text.isEmpty {
            segments.append(.text(id: id, text: text, isPreamble: isPreamble))
        }
    }

    private static func reasoningIndex(_ segments: [OpenClawChatTurnSegment]) -> Int? {
        segments.firstIndex {
            if case .reasoning = $0 {
                true
            } else {
                false
            }
        }
    }

    /// Single accumulating reasoning block per turn, keyed `<runId>:reasoning`. Length-monotonic; records
    /// `startedAt` on the first delta. The block closes at terminal (see `closeReasoning`).
    private static func applyReasoning(
        _ segments: inout [OpenClawChatTurnSegment],
        runId: String,
        text: String,
        at: Double?)
    {
        if let index = reasoningIndex(segments), case let .reasoning(block) = segments[index] {
            guard text.count >= block.text.count else { return }
            var updated = block
            updated.text = text
            if updated.startedAt == nil {
                updated.startedAt = at
            }
            segments[index] = .reasoning(updated)
        } else if !text.isEmpty {
            segments.insert(
                .reasoning(OpenClawChatReasoningSegment(id: "\(runId):reasoning", text: text, startedAt: at)),
                at: 0)
        }
    }

    private static func closeReasoning(_ segments: inout [OpenClawChatTurnSegment], at: Double?) {
        guard let index = reasoningIndex(segments), case let .reasoning(block) = segments[index], block.isOpen
        else { return }
        var updated = block
        updated.endedAt = at ?? block.startedAt ?? 0
        segments[index] = .reasoning(updated)
    }

    private static func toolIndex(_ segments: [OpenClawChatTurnSegment], id: String) -> Int? {
        segments.firstIndex {
            if case let .toolCall(tool) = $0 {
                tool.toolCallId == id
            } else {
                false
            }
        }
    }

    private static func startTool(
        _ segments: inout [OpenClawChatTurnSegment],
        toolCallId: String,
        name: String,
        argsPreview: String?)
    {
        if let index = toolIndex(segments, id: toolCallId) {
            guard case let .toolCall(tool) = segments[index] else { return }
            var updated = tool
            updated.name = name
            if argsPreview != nil {
                updated.argsPreview = argsPreview
            }
            segments[index] = .toolCall(updated)
        } else {
            segments.append(.toolCall(OpenClawChatToolCallSegment(
                toolCallId: toolCallId, name: name, argsPreview: argsPreview, state: .running)))
        }
    }

    private static func finishTool(_ segments: inout [OpenClawChatTurnSegment], toolCallId: String, isError: Bool) {
        guard let index = toolIndex(segments, id: toolCallId) else { return }
        guard case let .toolCall(tool) = segments[index], tool.state == .running else { return }
        var updated = tool
        updated.state = isError ? .error : .done
        segments[index] = .toolCall(updated)
    }
}
