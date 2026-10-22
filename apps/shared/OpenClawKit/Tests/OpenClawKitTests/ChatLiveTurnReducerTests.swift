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
    func `tagged final answer grows one text segment and streams live`() {
        // A provider that tags phase (final_answer) streams the reply live — it's promoted while running.
        let turn = self.reduce([
            .assistantText(runId: "r1", itemId: "i1", role: .answer, text: "Hel"),
            .assistantText(runId: "r1", itemId: "i1", role: .answer, text: "Hello"),
            .assistantText(runId: "r1", itemId: "i1", role: .answer, text: "Hello there"),
        ])
        #expect(turn?.segments.count == 1)
        #expect(turn?.trailingAnswerText == "Hello there")
        #expect(turn?.runningToolCount == 0)
    }

    @Test
    func `untagged trailing text is not the live answer`() {
        // THE fix for untagged providers (openai-completions/xai): text streams with NO phase, so a preamble
        // and the real answer are indistinguishable mid-run. Nothing is promoted while live — it shimmers as
        // a step — so a preamble can never flash as a reply.
        let turn = self.reduce([
            .assistantText(runId: "r1", itemId: "p1", role: .unknown, text: "I'll pull exact prices."),
        ])
        #expect(turn?.answerSegmentID == nil)
        #expect(turn?.trailingAnswerText == nil)
        #expect(turn?.stepTextIDs.contains("p1") == true)
    }

    @Test
    func `terminal reveals untagged trailing text as the answer`() {
        // When the turn ends, the trailing untagged text IS the answer — revealed as the final reply.
        var turn = Turn.reduce(nil, .assistantText(runId: "r1", itemId: "a1", role: .unknown, text: "Done — 42."))
        #expect(turn?.answerSegmentID == nil) // shimmering step while live
        turn = Turn.reduce(turn, .terminal(runId: "r1", state: .final))
        #expect(turn?.answerSegmentID == "a1")
        #expect(turn?.trailingAnswerText == "Done — 42.")
    }

    @Test
    func `preamble tool then tagged final keeps ordered segments`() {
        let turn = self.reduce([
            .assistantText(runId: "r1", itemId: "p1", role: .preamble, text: "Let me check the fixtures."),
            .toolStart(runId: "r1", toolCallId: "t1", name: "search_web", argsPreview: nil),
            .toolResult(runId: "r1", toolCallId: "t1", isError: false),
            .assistantText(runId: "r1", itemId: "a1", role: .answer, text: "Today's matches are..."),
        ])
        // Preamble, tool, and final answer are three distinct ordered segments — nothing was yanked.
        #expect(turn?.segments.count == 3)
        guard case .text(_, _, .preamble)? = turn?.segments.first
        else { Issue.record("first segment should be preamble"); return }
        guard case let .toolCall(tool)? = turn?.segments[1] else { Issue.record("second should be tool"); return }
        #expect(tool.state == .done)
        guard case let .text(_, final, .answer)? = turn?.segments.last
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
            .assistantText(runId: "r1", itemId: "i1", role: .answer, text: "The full answer is here."),
            .assistantText(runId: "r1", itemId: "i1", role: .answer, text: "The full"),
        ])
        #expect(turn?.trailingAnswerText == "The full answer is here.")
    }

    @Test
    func `phase resolving mid-stream promotes the same segment`() {
        // Untagged early deltas (.unknown) that later resolve to .answer must UPDATE the same segment, not
        // fork a duplicate — latest role wins.
        let turn = self.reduce([
            .assistantText(runId: "r1", itemId: "i1", role: .unknown, text: "The answer"),
            .assistantText(runId: "r1", itemId: "i1", role: .answer, text: "The answer is 42."),
        ])
        #expect(turn?.segments.count == 1)
        #expect(turn?.answerSegmentID != nil)
        #expect(turn?.trailingAnswerText == "The answer is 42.")
    }

    @Test
    func `new run starts fresh turn without bleeding`() {
        let first = self.reduce([
            .assistantText(runId: "r1", itemId: "i1", role: .answer, text: "First run answer."),
        ])
        let second = Turn.reduce(first, .assistantText(runId: "r2", itemId: "i1", role: .answer, text: "Second"))
        #expect(second?.runId == "r2")
        #expect(second?.segments.count == 1)
        #expect(second?.trailingAnswerText == "Second")
    }

    @Test
    func `same run reconciles and does not wipe tool state`() {
        // Adopting more events for the SAME run must never discard the running-tool signal mid-run.
        var turn = Turn.reduce(nil, .toolStart(runId: "r1", toolCallId: "t1", name: "search", argsPreview: nil))
        turn = Turn.reduce(turn, .assistantText(runId: "r1", itemId: "a1", role: .unknown, text: "Working..."))
        #expect(turn?.runningToolCount == 1) // tool still running after more same-run events
        #expect(turn?.segments.count == 2)
    }

    @Test
    func `terminal for stale run is ignored`() {
        let turn = self.reduce([
            .assistantText(runId: "r1", itemId: "i1", role: .answer, text: "Answer"),
        ])
        let afterStaleTerminal = Turn.reduce(turn, .terminal(runId: "rOLD", state: .final))
        #expect(afterStaleTerminal?.runId == "r1")
        #expect(afterStaleTerminal?.state == .running)
        let afterRealTerminal = Turn.reduce(turn, .terminal(runId: "r1", state: .final))
        #expect(afterRealTerminal?.state == .final)
    }

    @Test
    func `commentary preamble is never the live answer`() {
        // A commentary-tagged preamble streaming before its tool must stay a step, never the answer.
        let turn = self.reduce([
            .assistantText(runId: "r1", itemId: "p1", role: .preamble, text: "I'll check what's left this week."),
        ])
        #expect(turn?.answerSegmentID == nil)
        #expect(turn?.trailingAnswerText == nil)
        #expect(turn?.stepTextIDs.contains("p1") == true)
    }

    @Test
    func `tagged final answer after a tool wins over earlier preambles`() {
        let turn = self.reduce([
            .assistantText(runId: "r1", itemId: "p1", role: .preamble, text: "Let me check the fixtures."),
            .toolStart(runId: "r1", toolCallId: "t1", name: "search_web", argsPreview: nil),
            .toolResult(runId: "r1", toolCallId: "t1", isError: false),
            .assistantText(runId: "r1", itemId: "a1", role: .answer, text: "Here is the answer."),
        ])
        #expect(turn?.answerSegmentID == "a1")
        #expect(turn?.trailingAnswerText == "Here is the answer.")
        #expect(turn?.stepTextIDs.contains("p1") == true)
        #expect(turn?.stepTextIDs.contains("a1") == false)
    }

    @Test
    func `untagged post-tool text shimmers until terminal`() {
        // The screenshot bug: after a tool, the model emits ANOTHER untagged preamble. It must stay a step
        // while live, then reveal as the answer only at terminal (the model had nothing more to do).
        var turn = self.reduce([
            .assistantText(runId: "r1", itemId: "p1", role: .unknown, text: "Porkbun's page was messy."),
            .toolStart(runId: "r1", toolCallId: "t1", name: "fetch", argsPreview: nil),
            .toolResult(runId: "r1", toolCallId: "t1", isError: false),
            .assistantText(runId: "r1", itemId: "p2", role: .unknown, text: "I'll pull exact prices."),
        ])
        #expect(turn?.answerSegmentID == nil) // still shimmering — no reply flash
        #expect(turn?.stepTextIDs.contains("p2") == true)
        turn = Turn.reduce(turn, .terminal(runId: "r1", state: .final))
        #expect(turn?.answerSegmentID == "p2")
        #expect(turn?.trailingAnswerText == "I'll pull exact prices.")
    }

    @Test
    func `text before a tool is never the answer`() {
        // While a tool is still the last segment, the trailing preamble must NOT be treated as the answer.
        let turn = self.reduce([
            .assistantText(runId: "r1", itemId: "p1", role: .preamble, text: "Looking it up."),
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
