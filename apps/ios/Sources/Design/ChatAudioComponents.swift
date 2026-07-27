import AVFoundation
import QuickLookThumbnailing
import SwiftUI

/// Native pause glyph per design: two rounded bars.
struct ChatPauseGlyph: View {
    var color: Color = .white

    var body: some View {
        HStack(spacing: 2.75) {
            RoundedRectangle(cornerRadius: 0.9, style: .continuous)
                .fill(self.color)
                .frame(width: 5.5, height: 16.5)
            RoundedRectangle(cornerRadius: 0.9, style: .continuous)
                .fill(self.color)
                .frame(width: 5.5, height: 16.5)
        }
    }
}

@MainActor
@Observable
final class ChatAudioPlayback {
    private var player: AVAudioPlayer?
    private var ticker: Task<Void, Never>?
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0

    var progress: Double {
        guard let player, player.duration > 0 else { return 0 }
        return min(1, self.currentTime / player.duration)
    }

    func toggle(data: Data) {
        if self.isPlaying {
            self.player?.pause()
            self.isPlaying = false
            self.ticker?.cancel()
            return
        }
        if self.player == nil {
            // Recording leaves voice notes as m4a; the file-type hint helps AVAudioPlayer decode raw data.
            self.player = (try? AVAudioPlayer(data: data))
                ?? (try? AVAudioPlayer(data: data, fileTypeHint: AVFileType.m4a.rawValue))
        }
        guard let player = self.player else { return }
        // Recording deactivates the shared session; reactivate it for playback or `play()` no-ops silently.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        if player.currentTime >= player.duration {
            player.currentTime = 0
        }
        player.prepareToPlay()
        player.play()
        self.isPlaying = true
        self.startTicker()
    }

    private func startTicker() {
        self.ticker?.cancel()
        self.ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
                if !player.isPlaying, self.isPlaying {
                    // Natural end: reset to idle.
                    self.isPlaying = false
                    self.currentTime = 0
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
}

func chatDurationLabel(_ seconds: Double) -> String {
    let total = Int(seconds.rounded())
    return String(format: "%d:%02d", total / 60, total % 60)
}

/// Staged voice note occupying the composer field (pre-send).
struct StagedVoiceNoteField: View {
    let data: Data
    let durationSeconds: Double
    @State private var playback = ChatAudioPlayback()
    @State private var levels: [Float] = []

    var body: some View {
        HStack(spacing: 12) {
            Button { self.playback.toggle(data: self.data) } label: {
                if self.playback.isPlaying {
                    ChatPauseGlyph(color: Color.primary)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.primary)
                }
            }
            ChatAmplitudeWaveform(
                levels: self.levels,
                color: Color.primary.opacity(0.4),
                activeColor: Color.primary,
                progress: self.playback.progress)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
            Text(chatDurationLabel(
                self.playback.currentTime > 0 ? self.playback.currentTime : self.durationSeconds))
                .font(.system(size: 12))
                .foregroundStyle(Color.primary)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 36)
        .task(id: self.data) {
            self.levels = await ChatAudioEnvelope.levels(from: self.data, barCount: 44)
        }
    }
}

/// QuickLook-backed document preview with extension fallback.
struct ChatFileThumbnail: View {
    let payload: Data?
    let fileName: String
    let fallbackLabel: String

    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.white.opacity(0.15))
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 75, height: 75)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                Text(self.fallbackLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(width: 75, height: 75)
        .task(id: self.fileName) {
            guard self.thumbnail == nil, let payload = self.payload else { return }
            self.thumbnail = await Self.generate(payload: payload, fileName: self.fileName)
        }
    }

    private static func generate(payload: Data, fileName: String) async -> UIImage? {
        let name = fileName.isEmpty ? UUID().uuidString : fileName
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("thumb-\(UUID().uuidString)-\(name)")
        do {
            try payload.write(to: url)
        } catch {
            return nil
        }
        defer { try? FileManager.default.removeItem(at: url) }
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 75, height: 75),
            scale: 3,
            representationTypes: .thumbnail)
        let representation = try? await QLThumbnailGenerator.shared
            .generateBestRepresentation(for: request)
        return representation?.uiImage
    }
}
