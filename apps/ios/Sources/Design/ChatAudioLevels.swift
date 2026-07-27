import AVFoundation
import SwiftUI

/// Amplitude-driven waveform: one capsule per sample, height mapped from level 0…1.
/// Replaces the fixed 4-bar-group placeholder wherever real audio exists.
struct ChatAmplitudeWaveform: View {
    let levels: [Float]
    let color: Color
    var activeColor: Color = .white
    var progress: Double = 0
    var maxBarHeight: CGFloat = 18
    var minBarHeight: CGFloat = 3

    var body: some View {
        HStack(alignment: .center, spacing: 2.25) {
            ForEach(Array(self.levels.enumerated()), id: \.offset) { index, level in
                let isActive = Double(index) / Double(max(self.levels.count, 1)) < self.progress
                Capsule()
                    .fill(isActive ? self.activeColor : self.color)
                    .frame(
                        width: 1.9,
                        height: self.minBarHeight
                            + (self.maxBarHeight - self.minBarHeight) * CGFloat(level))
            }
        }
        .animation(.linear(duration: 0.08), value: self.levels)
    }
}

/// Extracts a fixed-count amplitude envelope from finished audio data.
enum ChatAudioEnvelope {
    static func levels(from data: Data, barCount: Int) async -> [Float] {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("env-\(UUID().uuidString).m4a")
        do {
            try data.write(to: url)
        } catch {
            return Self.fallback(barCount)
        }
        defer { try? FileManager.default.removeItem(at: url) }
        guard let file = try? AVAudioFile(forReading: url) else { return Self.fallback(barCount) }
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount),
              (try? file.read(into: buffer)) != nil,
              let samples = buffer.floatChannelData?[0]
        else { return Self.fallback(barCount) }

        let total = Int(buffer.frameLength)
        let window = max(total / barCount, 1)
        var levels: [Float] = []
        levels.reserveCapacity(barCount)
        for bar in 0..<barCount {
            let start = bar * window
            guard start < total else {
                levels.append(0)
                continue
            }
            let end = min(start + window, total)
            var sum: Float = 0
            for index in start..<end {
                sum += samples[index] * samples[index]
            }
            levels.append(sqrt(sum / Float(end - start))) // RMS per window
        }
        // Normalize so the loudest window fills the tallest bar.
        let peak = levels.max() ?? 0
        guard peak > 0 else { return Self.fallback(barCount) }
        return levels.map { min($0 / peak, 1) }
    }

    private static func fallback(_ count: Int) -> [Float] {
        Array(repeating: 0.12, count: count) // near-silent flat line
    }
}
