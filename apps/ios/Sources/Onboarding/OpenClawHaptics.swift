import CoreHaptics
import UIKit

/// TEMPORARY — audition patterns for the onboarding "connection secured" moment. The `.secured*`
/// cases are Haptics Lab candidates; the chosen one stays and the rest (plus the lab) go before PR.
enum OpenClawHapticPattern {
    case secured1
    case secured2
    case secured3
    case secured4
    case secured5
    case warning
    case secured7
    case secured8
    case secured9
    case secured10
}

enum OpenClawHaptics {
    @MainActor
    static func play(_ pattern: OpenClawHapticPattern) {
        HapticEngineHolder.shared.play(pattern)
    }

    /// A light selection-style tap for discrete UI actions (e.g. attachment tray rows).
    @MainActor
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

@MainActor
private final class HapticEngineHolder {
    static let shared = HapticEngineHolder()

    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private var engine: CHHapticEngine?

    func play(_ pattern: OpenClawHapticPattern) {
        guard self.supportsHaptics else {
            self.playFallback()
            return
        }
        do {
            let engine = try self.runningEngine()
            let recipe = Self.recipe(for: pattern)
            let hapticPattern = try CHHapticPattern(events: recipe.events, parameterCurves: recipe.curves)
            let player = try engine.makePlayer(with: hapticPattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            self.playFallback()
        }
    }

    private func runningEngine() throws -> CHHapticEngine {
        if let engine = self.engine {
            return engine
        }
        let engine = try CHHapticEngine()
        engine.isAutoShutdownEnabled = true
        // Reset can fire after an audio-session interruption (on an arbitrary queue); hop to the main
        // actor and restart so the next tap still plays.
        engine.resetHandler = { [weak self] in
            Task { @MainActor in try? self?.engine?.start() }
        }
        try engine.start()
        self.engine = engine
        return engine
    }

    private func playFallback() {
        Task { @MainActor in
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    // MARK: - Pattern construction

    private static func tap(_ time: TimeInterval, _ intensity: Float, _ sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: time)
    }

    private static func hum(
        _ time: TimeInterval,
        duration: TimeInterval,
        intensity: Float,
        sharpness: Float) -> CHHapticEvent
    {
        CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: time,
            duration: duration)
    }

    private static func intensityCurve(
        start: TimeInterval,
        from: Float,
        to: Float,
        over duration: TimeInterval) -> CHHapticParameterCurve
    {
        CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: from),
                CHHapticParameterCurve.ControlPoint(relativeTime: duration, value: to),
            ],
            relativeTime: start)
    }

    private static func recipe(
        for pattern: OpenClawHapticPattern)
        -> (events: [CHHapticEvent], curves: [CHHapticParameterCurve])
    {
        switch pattern {
        case .secured1: // Minimalist — one crisp click
            ([self.tap(0, 1.0, 0.9)], [])
        case .secured2: // Handshake — click, firmer answer
            ([self.tap(0, 0.6, 0.5), self.tap(0.12, 1.0, 0.85)], [])
        case .secured3: // v1 Draft — click, answer, settling hum
            (
                [
                    self.tap(0, 0.7, 0.6),
                    self.tap(0.1, 1.0, 0.8),
                    self.hum(0.2, duration: 0.35, intensity: 1.0, sharpness: 0.3),
                ],
                [self.intensityCurve(start: 0.2, from: 0.4, to: 0.0, over: 0.35)])
        case .secured4: // Key Turn — rising triplet
            ([self.tap(0, 0.5, 0.4), self.tap(0.09, 0.75, 0.65), self.tap(0.18, 1.0, 0.9)], [])
        case .secured5: // Echo — double-tap, distant echo
            ([self.tap(0, 0.9, 0.8), self.tap(0.08, 0.85, 0.8), self.tap(0.34, 0.3, 0.5)], [])
        case .warning: // two-buzz warning — firm buzz, gap, softer buzz
            (
                [
                    self.hum(0, duration: 0.04, intensity: 0.8, sharpness: 0.5),
                    self.hum(0.14, duration: 0.04, intensity: 0.6, sharpness: 0.5),
                ],
                [])
        case .secured7: // Lock Engaging — swell into a click
            (
                [self.hum(0, duration: 0.3, intensity: 1.0, sharpness: 0.3), self.tap(0.31, 1.0, 0.9)],
                [self.intensityCurve(start: 0, from: 0.15, to: 0.9, over: 0.3)])
        case .secured8: // Heartbeat — two soft lub-dubs
            (
                [
                    self.tap(0, 0.5, 0.3),
                    self.tap(0.13, 0.35, 0.25),
                    self.tap(0.5, 0.5, 0.3),
                    self.tap(0.63, 0.35, 0.25),
                ],
                [])
        case .secured9: // Sealed — low hum, stamped shut
            ([self.hum(0, duration: 0.4, intensity: 0.45, sharpness: 0.1), self.tap(0.42, 1.0, 0.7)], [])
        case .secured10: // Sparkle — three feather ticks, thud
            (
                [
                    self.tap(0, 0.3, 1.0),
                    self.tap(0.07, 0.3, 1.0),
                    self.tap(0.14, 0.3, 1.0),
                    self.tap(0.28, 1.0, 0.25),
                ],
                [])
        }
    }
}
