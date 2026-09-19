import Foundation

/// Debug-only timeline logger for the chat pipeline. Every mark is stamped with Δt (seconds) since the
/// last `begin(...)` (the send tap), so the real ordering + timing of the two async sources of truth
/// (live stream vs canonical `messages`) can be read off the console. Flip `enabled` to false to make
/// every call a no-op. Additive instrumentation only — no behavior change.
public enum ChatTimeline {
    /// Master switch. When false every call is a cheap no-op.
    public nonisolated(unsafe) static var enabled = false

    /// Monotonic start marker (nanoseconds) set by `begin`; nil until the first send this session.
    private nonisolated(unsafe) static var startNanos: UInt64?

    /// Marks t=0 (call on the send tap). Subsequent `mark`s are relative to this.
    public static func begin(_ label: String) {
        guard self.enabled else { return }
        self.startNanos = DispatchTime.now().uptimeNanoseconds
        print("⏱️ [ChatTL] +0.000  \(label)")
    }

    /// Logs `label` with the elapsed seconds since the last `begin`.
    public static func mark(_ label: String) {
        guard self.enabled else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        let delta = self.startNanos.map { Double(now &- $0) / 1_000_000_000 } ?? 0
        print(String(format: "⏱️ [ChatTL] +%.3f  %@", delta, label))
    }

    /// Last print time (ns) per throttle key — keeps high-frequency streams (token deltas) from flooding.
    private nonisolated(unsafe) static var lastByKey: [String: UInt64] = [:]

    /// Like `mark` but at most once per `interval` seconds per `key` (default 0.25s).
    public static func markThrottled(_ key: String, _ label: String, interval: Double = 0.25) {
        guard self.enabled else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        if let last = self.lastByKey[key], Double(now &- last) / 1_000_000_000 < interval {
            return
        }
        self.lastByKey[key] = now
        self.mark(label)
    }
}
