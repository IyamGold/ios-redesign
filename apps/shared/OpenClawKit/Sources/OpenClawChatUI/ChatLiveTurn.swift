import Foundation

/// A single in-flight assistant turn modeled as an ordered, append-only list of typed segments —
/// the structure the gateway already carries (typed `agent.*` events with `itemId`, `phase`, and tool
/// start/result) but that the legacy client flattened into one mutable string + a guessing machine.
/// Rendering reads this directly: a tool in `.running` shows a step; a trailing `text` segment with no
/// running tool is the streaming bubble that grows in place into the final answer. Nothing is ever
/// shown-then-yanked, and nothing is re-classified by heuristic.
///
/// Built only by `reduce(_:_:)` — one writer — so the two cumulative text sources can no longer fight.
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

    /// The trailing non-preamble text — what a legacy single-string consumer wants for the "current
    /// streaming reply" (used by the macOS projection in a later stage).
    public var trailingAnswerText: String? {
        for segment in self.segments.reversed() {
            switch segment {
            case let .text(_, text, isPreamble): return isPreamble ? nil : text
            case .toolCall: return nil
            case .reasoning: continue
            }
        }
        return nil
    }

    public var runningToolCount: Int {
        self.segments.reduce(into: 0) { count, segment in
            if case let .toolCall(tool) = segment, tool.state == .running {
                count += 1
            }
        }
    }
}

/// One typed part of a turn. `id` is stable across updates so SwiftUI keeps identity (no row churn).
public enum OpenClawChatTurnSegment: Equatable, Sendable, Identifiable {
    /// Model reasoning / "thinking" (from `agent.thinking`), collapsible.
    case reasoning(id: String, text: String)
    /// Assistant prose. `isPreamble` is the server's `phase == "commentary"` — pre-tool narration vs
    /// the final answer. Both are ordered text segments; order alone separates them.
    case text(id: String, text: String, isPreamble: Bool)
    case toolCall(OpenClawChatToolCallSegment)

    public var id: String {
        switch self {
        case let .reasoning(id, _): "reasoning:\(id)"
        case let .text(id, _, _): "text:\(id)"
        case let .toolCall(tool): "tool:\(tool.id)"
        }
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
/// call site, keeping the reducer pure and unit-testable.
public enum OpenClawChatLiveTurnEvent: Sendable, Equatable {
    /// Cumulative text for one assistant message (`itemId`); resets per message server-side.
    case assistantText(runId: String, itemId: String?, isPreamble: Bool, text: String)
    case reasoning(runId: String, itemId: String?, text: String)
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
    /// The single reducer. Same `runId` reconciles into the existing turn (grows text, transitions
    /// tools) and NEVER wipes the running-tool / preamble state; a genuinely different `runId` starts a
    /// fresh turn (a new user turn). A terminal for a run that isn't the active turn is ignored.
    ///
    /// Text is length-monotonic per segment: a cumulative snapshot replaces a segment only when it
    /// advances the visible text, so a lagging/short replay from either source can never regress it.
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
        case let .reasoning(_, itemId, text):
            Self.applyReasoning(&turn.segments, id: itemId ?? "\(runId):reasoning", text: text)
        case let .toolStart(_, toolCallId, name, argsPreview):
            Self.startTool(&turn.segments, toolCallId: toolCallId, name: name, argsPreview: argsPreview)
        case let .toolResult(_, toolCallId, isError):
            Self.finishTool(&turn.segments, toolCallId: toolCallId, isError: isError)
        case let .terminal(_, state):
            turn.state = state
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

    private static func applyReasoning(_ segments: inout [OpenClawChatTurnSegment], id: String, text: String) {
        if let index = segments
            .firstIndex(where: {
                if case let .reasoning(existing, _) = $0 {
                    existing == id
                } else {
                    false
                }
            })
        {
            guard case let .reasoning(_, existing) = segments[index], text.count >= existing.count else { return }
            segments[index] = .reasoning(id: id, text: text)
        } else if !text.isEmpty {
            segments.append(.reasoning(id: id, text: text))
        }
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
