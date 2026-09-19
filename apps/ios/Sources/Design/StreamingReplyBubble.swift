import SwiftUI

/// A live, paced "typewriter" reply bubble shown while the assistant is composing its answer.
///
/// Design notes:
/// - Renders **lightweight plain text** (no `ChatTextBlock.parse` / markdown) so it stays off the
///   60fps-critical parser path that `ChatRootSurface.rebuildRows` deliberately guards. The finalized,
///   fully-formatted bubble (`ChatFormattedText`) takes over once the run completes.
/// - A **pacing buffer** decouples what the user sees from bursty network arrivals: streamed tokens
///   land in `fullText` in clumps, but `revealedCount` walks toward them at a steady per-tick cadence,
///   so the reply reads as a smooth drip rather than popping in a chunk at a time.
/// - Option A gating lives in `ChatRootSurface` (only shown when no tool call is in flight), so tool-use
///   preambles never flash here — this view just renders whatever answer text it is handed.
struct StreamingReplyBubble: View {
    /// The full in-flight answer text so far. Streamed replies only ever grow (see `ChatViewModel.adoptRun`).
    let fullText: String
    let textColor: Color

    /// Characters currently revealed. Paced up toward `fullText.count` so the reveal is frame-smooth.
    @State private var revealedCount: Int = 0

    /// Reveal cadence. We accelerate when far behind the model so the drip never visibly lags a fast
    /// stream, then settles to near-per-character as it catches up to the head.
    private static let tickInterval: Duration = .milliseconds(14)
    private static let catchUpDivisor = 8

    var body: some View {
        let revealed = String(self.fullText.prefix(self.revealedCount))
        let caughtUp = self.revealedCount >= self.fullText.count
        return HStack(alignment: .bottom, spacing: 3) {
            // Honor the model's newlines while streaming; markdown formatting is applied only once the
            // finalized bubble replaces this view.
            Text(revealed)
                .font(.system(size: 16))
                .foregroundStyle(self.textColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeOut(duration: 0.12), value: self.revealedCount)
            StreamingCursor(color: self.textColor)
                .opacity(caughtUp ? 0 : 1)
        }
        // `.task(id:)` re-captures the LATEST `fullText` each time a token grows it (a plain Task would
        // capture a stale struct value). Each restart resumes the drip from the current `revealedCount`,
        // so revealed text is continuous across chunks.
        .task(id: self.fullText) {
            while !Task.isCancelled, self.revealedCount < self.fullText.count {
                let behind = self.fullText.count - self.revealedCount
                let step = max(1, behind / Self.catchUpDivisor)
                self.revealedCount = min(self.fullText.count, self.revealedCount + step)
                try? await Task.sleep(for: Self.tickInterval)
            }
        }
    }
}

/// Blinking caret that trails the streamed text until the reveal catches up to the model.
private struct StreamingCursor: View {
    let color: Color
    @State private var dim = false

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(self.color.opacity(0.55))
            .frame(width: 7, height: 18)
            .opacity(self.dim ? 0.15 : 1)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: self.dim)
            .onAppear { self.dim = true }
    }
}
