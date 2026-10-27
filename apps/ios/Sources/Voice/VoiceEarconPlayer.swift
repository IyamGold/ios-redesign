import AVFoundation
import UIKit

/// Plays the voice-mode entry earcon (the "warm" sound pack's `open.wav`) and fires one `.medium` haptic when
/// the audible chord lands (~1.4s) — so opening a voice session gets a tactile "landed" confirmation that
/// trails the sound. App-target only (UIKit/AVFoundation); the shared kit stays UI-free.
@MainActor
final class VoiceEarconPlayer: NSObject {
    static let shared = VoiceEarconPlayer()

    /// The audible chord ends ~1.4s in; the remainder of the 2.16s file is a quiet reverb tail. The haptic
    /// fires at the chord's end, while the mic stays muted until the full file ends (tail can't bleed in).
    private static let audibleEndSeconds: TimeInterval = 1.4

    private var player: AVAudioPlayer?
    /// Fired once when playback fully ends (or immediately if it can't play) — the caller uses this to unmute
    /// the realtime mic, which stays muted during the chime so it isn't transcribed as fake turns.
    private var onFinished: (() -> Void)?
    private var hapticTask: Task<Void, Never>?

    /// Play the entry earcon. The `.medium` impact fires ~1.4s in (end of the audible chord); `onFinished`
    /// runs once when the whole file (including the reverb tail) finishes.
    func playEntry(onFinished: @escaping () -> Void = {}) {
        self.onFinished = onFinished
        guard let url = Bundle.main.url(forResource: "open", withExtension: "wav") else {
            // No bundled chime: confirm immediately so the mic isn't left muted.
            self.fireEntryHaptic()
            self.finishPlayback()
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            self.player = player
            player.prepareToPlay()
            player.play()
            self.hapticTask?.cancel()
            self.hapticTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.audibleEndSeconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.fireEntryHaptic()
            }
        } catch {
            self.fireEntryHaptic()
            self.finishPlayback()
        }
    }

    /// Playback fully ended: drop the player and run the finished callback (unmute) once.
    private func finishPlayback() {
        self.player = nil
        let callback = self.onFinished
        self.onFinished = nil
        callback?()
    }

    private func fireEntryHaptic() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

// MARK: - AVAudioPlayerDelegate

extension VoiceEarconPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_: AVAudioPlayer, successfully _: Bool) {
        // Unmute fires at the true end of the file so the reverb tail can't bleed into the mic. The haptic
        // already fired at the audible chord's end (~1.4s) via `hapticTask`.
        Task { @MainActor in
            self.finishPlayback()
        }
    }
}
