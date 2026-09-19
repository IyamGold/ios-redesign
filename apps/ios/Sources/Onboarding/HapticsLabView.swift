import SwiftUI

/// TEMPORARY — haptic pattern audition lab. Delete before PR. Do not commit.
struct HapticsLabView: View {
    private let candidates: [(name: String, note: String, pattern: OpenClawHapticPattern)] = [
        ("1 · Minimalist", "one crisp click", .secured1),
        ("2 · Handshake", "click, firmer answer", .secured2),
        ("3 · v1 Draft", "click, answer, settling hum", .secured3),
        ("4 · Key Turn", "rising triplet", .secured4),
        ("5 · Echo", "double-tap, distant echo", .secured5),
        ("6 · Warning", "firm buzz, gap, softer buzz", .warning),
        ("7 · Lock Engaging", "swell into a click", .secured7),
        ("8 · Heartbeat", "two soft lub-dubs", .secured8),
        ("9 · Sealed", "low hum, stamped shut", .secured9),
        ("10 · Sparkle", "three feather ticks, thud", .secured10),
    ]

    var body: some View {
        ZStack {
            OpenClawBrand.welcomeCanvas
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 13) {
                    Text("Haptics Lab")
                        .font(.system(size: 20, weight: .medium))
                        .padding(.bottom, 8)

                    ForEach(self.candidates, id: \.name) { candidate in
                        Button {
                            OpenClawHaptics.play(candidate.pattern)
                        } label: {
                            HStack {
                                Text(candidate.name)
                                    .font(.system(size: 17, weight: .medium))
                                Spacer()
                                Text(candidate.note)
                                    .font(.system(size: 12))
                                    .opacity(0.5)
                            }
                            .foregroundStyle(Color.primary)
                            .padding(.horizontal, 21)
                            .frame(height: 50)
                            .frame(maxWidth: .infinity)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
            }
        }
    }
}
