import AVFoundation
import Foundation
import Speech

/// On-device transcription of a recorded voice note. Prefers the iOS 26 `SpeechAnalyzer`/
/// `SpeechTranscriber` pipeline (which can download the on-device model via `AssetInventory`), and
/// falls back to `SFSpeechRecognizer` on-device on older systems. Audio never leaves the device — if no
/// on-device model can be obtained (or permission is denied) it yields `nil` and the note sends without
/// a transcript rather than reaching for a network request.
enum VoiceNoteTranscriber {
    static func transcribe(data: Data) async -> String? {
        guard await self.authorized() else { return nil }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vn-transcribe-\(UUID().uuidString).m4a")
        do {
            try data.write(to: url)
        } catch {
            return nil
        }
        defer { try? FileManager.default.removeItem(at: url) }

        if #available(iOS 26.0, *), let modern = await self.transcribeModern(url: url) {
            return modern
        }
        return await self.transcribeLegacy(url: url)
    }

    // MARK: - iOS 26 SpeechAnalyzer

    @available(iOS 26.0, *)
    private static func transcribeModern(url: URL) async -> String? {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) else {
            return nil
        }
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [])
        do {
            // Downloads/installs the on-device model for the locale if it isn't already present.
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
            let audioFile = try AVAudioFile(forReading: url)
            let analyzer = SpeechAnalyzer(modules: [transcriber])

            // Results arrive on an AsyncSequence; collect them while the file is analyzed.
            let collect = Task { () -> String in
                var text = ""
                for try await result in transcriber.results {
                    text += String(result.text.characters)
                }
                return text
            }

            if let last = try await analyzer.analyzeSequence(from: audioFile) {
                try await analyzer.finalizeAndFinish(through: last)
            } else {
                try await analyzer.cancelAndFinishNow()
            }

            let text = try await collect.value.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
    }

    // MARK: - Legacy SFSpeechRecognizer fallback

    private static func transcribeLegacy(url: URL) async -> String? {
        guard let recognizer = SFSpeechRecognizer(),
              recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition
        else { return nil }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false

        let text: String? = await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let box = TranscriptionResumeBox(continuation)
            recognizer.recognitionTask(with: request) { result, error in
                if error != nil {
                    box.finish(nil)
                } else if let result, result.isFinal {
                    box.finish(result.bestTranscription.formattedString)
                }
            }
        }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    private static func authorized() async -> Bool {
        if SFSpeechRecognizer.authorizationStatus() == .authorized {
            return true
        }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}

/// Resumes a continuation exactly once — the recognition handler can fire on an arbitrary queue and,
/// defensively, more than once.
private final class TranscriptionResumeBox: @unchecked Sendable {
    private var continuation: CheckedContinuation<String?, Never>?
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<String?, Never>) {
        self.continuation = continuation
    }

    func finish(_ value: String?) {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard let continuation = self.continuation else { return }
        self.continuation = nil
        continuation.resume(returning: value)
    }
}
