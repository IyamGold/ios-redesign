import SwiftUI

/// The voice-session visual layered over the live chat — one design for BOTH speech-to-text and
/// speech-to-speech. A warm #C33F33 gradient rises from the bottom and brightens with the assistant's output
/// loudness (`TalkModeManager.assistantLevel`, 0–1). The transcript stays visible behind it (realtime also
/// broadcasts transcripts to the live chat), matching the ChatGPT-style voice overlay. Purely decorative and
/// non-interactive; renders nothing when no session is active.
struct TalkVoiceOverlay: View {
    /// A voice session is live (`talkMode.isEnabled`).
    let isActive: Bool
    /// Assistant output loudness 0–1, smoothed upstream.
    let level: Double

    /// The frame's sandy accent (#C33F33).
    private static let sandy = Color(red: 195 / 255, green: 63 / 255, blue: 51 / 255)

    var body: some View {
        if self.isActive {
            // Base glow so it reads as an active session, brightening as OpenClaw speaks.
            let intensity = 0.28 + 0.60 * self.level
            LinearGradient(
                colors: [.clear, Self.sandy.opacity(intensity)],
                startPoint: .top,
                endPoint: .bottom)
                .frame(height: 380)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .animation(.easeOut(duration: 0.14), value: self.level)
        }
    }
}
