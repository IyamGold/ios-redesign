import Foundation

/// Stage B (shadow): fold the typed gateway transport events into the `liveTurn` timeline alongside the
/// legacy `streamingAssistantText`/`pendingToolCallsById` state. Text / reasoning / tools come from the
/// richer `agent.*` lane (it carries `itemId` and `phase`, unlike the `chat.*` lane); the `chat.*` lane
/// only contributes the terminal state. Nothing renders `liveTurn` yet — this exists so the reducer runs
/// against real traffic and can be validated before the iOS view switches over in Stage C.
extension OpenClawChatViewModel {
    func foldLiveTurn(_ evt: OpenClawChatTransportEvent) {
        switch evt {
        case let .agent(agent):
            // Mirror handleAgentEvent's ownership gate so other sessions' runs never pollute the turn.
            guard self.pendingRuns.contains(agent.runId)
                || (self.pendingRuns.isEmpty && self.sessionId == agent.runId)
            else { return }
            self.foldAgentEvent(agent)
        case let .chat(chat):
            self.foldChatTerminal(chat)
        case .seqGap:
            self.liveTurn = nil
        default:
            break
        }
    }

    private func foldAgentEvent(_ evt: OpenClawAgentEventPayload) {
        let runId = evt.runId
        switch evt.stream {
        case "assistant":
            guard let text = evt.data["text"]?.value as? String else { return }
            let itemId = evt.data["itemId"]?.value as? String
            // Many providers (openai-completions/xai) never tag phase while streaming → .unknown, which the
            // reducer treats as a shimmering step until finality rather than promoting it to the reply.
            let role: OpenClawChatTextRole = switch evt.data["phase"]?.value as? String {
            case "final_answer": .answer
            case "commentary": .preamble
            default: .unknown
            }
            self.liveTurn = OpenClawChatLiveTurn.reduce(
                self.liveTurn,
                .assistantText(runId: runId, itemId: itemId, role: role, text: text))
        case "thinking":
            guard let text = evt.data["text"]?.value as? String else { return }
            // Single accumulating reasoning block per turn; carry the event timestamp for "Thought for Ns".
            self.liveTurn = OpenClawChatLiveTurn.reduce(
                self.liveTurn, .reasoning(runId: runId, text: text, at: evt.ts.map(Double.init)))
        case "tool":
            guard let phase = evt.data["phase"]?.value as? String,
                  let toolCallId = evt.data["toolCallId"]?.value as? String
            else { return }
            if phase == "start" {
                let name = (evt.data["name"]?.value as? String) ?? "tool"
                self.liveTurn = OpenClawChatLiveTurn.reduce(
                    self.liveTurn,
                    .toolStart(runId: runId, toolCallId: toolCallId, name: name, argsPreview: nil))
            } else if phase == "result" {
                let isError = (evt.data["isError"]?.value as? Bool) ?? false
                self.liveTurn = OpenClawChatLiveTurn.reduce(
                    self.liveTurn, .toolResult(runId: runId, toolCallId: toolCallId, isError: isError))
            }
        case "lifecycle":
            if let state = Self.liveTurnTerminalState(fromLifecycle: evt) {
                self.liveTurn = OpenClawChatLiveTurn.reduce(self.liveTurn, .terminal(runId: runId, state: state))
            }
        default:
            break
        }
    }

    private func foldChatTerminal(_ chat: OpenClawChatEventPayload) {
        guard let runId = chat.runId else { return }
        let state: OpenClawChatLiveTurn.State
        switch chat.state {
        case "final": state = .final
        case "aborted": state = .aborted
        case "error": state = .error
        default: return
        }
        self.liveTurn = OpenClawChatLiveTurn.reduce(self.liveTurn, .terminal(runId: runId, state: state))
    }

    private static func liveTurnTerminalState(fromLifecycle evt: OpenClawAgentEventPayload) -> OpenClawChatLiveTurn
    .State? {
        let phase = (evt.data["phase"]?.value as? String)?.lowercased()
        let status = (evt.data["status"]?.value as? String)?.lowercased()
        let aborted = (evt.data["aborted"]?.value as? Bool) ?? false
        if aborted || phase == "aborted" || status == "aborted" {
            return .aborted
        }
        if phase == "error" || phase == "failed" || status == "error" || status == "failed" {
            return .error
        }
        let terminalPhase = phase == "end" || phase == "complete" || phase == "completed"
        let okStatus = status == "ok" || status == "success" || status == "succeeded"
            || status == "complete" || status == "completed"
        return (terminalPhase || okStatus) ? .final : nil
    }
}
