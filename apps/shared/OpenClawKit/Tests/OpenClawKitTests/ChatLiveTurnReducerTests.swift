import Foundation
import Testing
@testable import OpenClawChatUI

/// Unit tests for the pure live-turn reducer — the single writer that replaces the old two-writer
/// string + guessing machine. These prove the invariants the smooth UI depends on.
struct ChatLiveTurnReducerTests {
    private typealias Turn = OpenClawChatLiveTurn
    private typealias Event = OpenClawChatLiveTurnEvent

    private func reduce(_ events: [Event]) -> Turn? {
        events.reduce(nil) { Turn.reduce($0, $1) }
    }

    @Test
    func `simple reply grows one text segment`() {
        let turn = self.reduce([
            .assistantText(runId: "r1", itemId: "i1", isPreamble: false, text: "Hel"),
            .assistantText(runId: "r1", itemId: "i1", isPreamble: false, text: "Hello"),
            .assistantText(runId: "r1", itemId: "i1", isPreamble: false, text: "Hello there"),
        ])
        #expect(turn?.segments.count == 1)
        #expect(turn?.trailingAnswerText == "Hello there")
        #expect(turn?.runningToolCount == 0)
    }

    @Test
    func `preamble tool then final keeps ordered segments`() {
        let turn = self.reduce([
            .assistantText(runId: "r1", itemId: "p1", isPreamble: true, text: "Let me check the fixtures."),
            .toolStart(runId: "r1", toolCallId: "t1", name: "search_web", argsPreview: nil),
            .toolResult(runId: "r1", toolCallId: "t1", isError: false),
            .assistantText(runId: "r1", itemId: "a1", isPreamble: false, text: "Today's matches are..."),
        ])
        // Preamble, tool, and final answer are three distinct ordered segments — nothing was yanked.
        #expect(turn?.segments.count == 3)
        guard case .text(_, _, true)? = turn?.segments.first
        else { Issue.record("first segment should be preamble"); return }
        guard case let .toolCall(tool)? = turn?.segments[1] else { Issue.record("second should be tool"); return }
        #expect(tool.state == .done)
        guard case .text(_, let final, false)? = turn?.segments.last
        else { Issue.record("last should be final answer"); return }
        #expect(final == "Today's matches are...")
        #expect(turn?.trailingAnswerText == "Today's matches are...")
    }

    @Test
    func `tool running signal is read not guessed`() {
        let turn = self.reduce([
            .toolStart(runId: "r1", toolCallId: "t1", name: "search_web", argsPreview: nil),
        ])
        #expect(turn?.runningToolCount == 1)
        let done = Turn.reduce(turn, .toolResult(runId: "r1", toolCallId: "t1", isError: false))
        #expect(done?.runningToolCount == 0)
    }

    @Test
    func `short replay snapshot cannot regress text`() {
        // A lagging/short cumulative snapshot from the other source must not shrink the visible reply.
        let turn = self.reduce([
            .assistantText(runId: "r1", itemId: "i1", isPreamble: false, text: "The full answer is here."),
            .assistantText(runId: "r1", itemId: "i1", isPreamble: false, text: "The full"),
        ])
        #expect(turn?.trailingAnswerText == "The full answer is here.")
    }

    @Test
    func `new run starts fresh turn without bleeding`() {
        let first = self.reduce([
            .assistantText(runId: "r1", itemId: "i1", isPreamble: false, text: "First run answer."),
        ])
        let second = Turn.reduce(first, .assistantText(runId: "r2", itemId: "i1", isPreamble: false, text: "Second"))
        #expect(second?.runId == "r2")
        #expect(second?.segments.count == 1)
        #expect(second?.trailingAnswerText == "Second")
    }

    @Test
    func `same run reconciles and does not wipe tool state`() {
        // Adopting more events for the SAME run must never discard the running-tool signal mid-run.
        var turn = Turn.reduce(nil, .toolStart(runId: "r1", toolCallId: "t1", name: "search", argsPreview: nil))
        turn = Turn.reduce(turn, .assistantText(runId: "r1", itemId: "a1", isPreamble: false, text: "Working..."))
        #expect(turn?.runningToolCount == 1) // tool still running after more same-run events
        #expect(turn?.segments.count == 2)
    }

    @Test
    func `terminal for stale run is ignored`() {
        let turn = self.reduce([
            .assistantText(runId: "r1", itemId: "i1", isPreamble: false, text: "Answer"),
        ])
        let afterStaleTerminal = Turn.reduce(turn, .terminal(runId: "rOLD", state: .final))
        #expect(afterStaleTerminal?.runId == "r1")
        #expect(afterStaleTerminal?.state == .running)
        let afterRealTerminal = Turn.reduce(turn, .terminal(runId: "r1", state: .final))
        #expect(afterRealTerminal?.state == .final)
    }

    @Test
    func `position decides answer vs step even when isPreamble is wrong`() {
        // Simulate the openai-responses late-phase case: the preamble is flagged non-preamble and the
        // answer is flagged preamble. Position (text after the last tool) must still pick the answer.
        let turn = self.reduce([
            .assistantText(runId: "r1", itemId: "p1", isPreamble: false, text: "Let me check the fixtures."),
            .toolStart(runId: "r1", toolCallId: "t1", name: "search_web", argsPreview: nil),
            .toolResult(runId: "r1", toolCallId: "t1", isError: false),
            .assistantText(runId: "r1", itemId: "a1", isPreamble: true, text: "Here is the answer."),
        ])
        #expect(turn?.answerSegmentID == "a1")
        #expect(turn?.trailingAnswerText == "Here is the answer.")
        #expect(turn?.stepTextIDs.contains("p1") == true)
        #expect(turn?.stepTextIDs.contains("a1") == false)
    }

    @Test
    func `text before a tool is never the answer`() {
        // While a tool is still the last segment, the trailing preamble must NOT be treated as the answer.
        let turn = self.reduce([
            .assistantText(runId: "r1", itemId: "p1", isPreamble: true, text: "Looking it up."),
            .toolStart(runId: "r1", toolCallId: "t1", name: "search_web", argsPreview: nil),
        ])
        #expect(turn?.answerSegmentID == nil)
        #expect(turn?.trailingAnswerText == nil)
        #expect(turn?.runningToolCount == 1)
    }

    @Test
    func `reasoning-only turn has no answer and stays open`() {
        let turn = self.reduce([
            .reasoning(runId: "r1", text: "Thinking about it", at: 1000),
        ])
        #expect(turn?.answerSegmentID == nil)
        #expect(turn?.trailingAnswerText == nil)
        #expect(turn?.reasoning?.text == "Thinking about it")
        #expect(turn?.reasoning?.isOpen == true)
        guard case .reasoning? = turn?.segments.first else { Issue.record("reasoning should lead the turn"); return }
    }

    @Test
    func `reasoning records start and closes on terminal`() {
        var turn = Turn.reduce(nil, .reasoning(runId: "r1", text: "Hmm", at: 1000))
        turn = Turn.reduce(turn, .reasoning(runId: "r1", text: "Hmm, let me check", at: 1500))
        #expect(turn?.reasoning?.startedAt == 1000)
        #expect(turn?.reasoning?.isOpen == true)
        turn = Turn.reduce(turn, .terminal(runId: "r1", state: .final))
        #expect(turn?.reasoning?.isOpen == false)
        #expect(turn?.reasoning?.endedAt != nil)
        // A short replay can't regress reasoning text.
        let regressed = Turn.reduce(turn, .reasoning(runId: "r1", text: "Hmm", at: 1600))
        #expect(regressed?.reasoning?.text == "Hmm, let me check")
    }
}
