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
}
