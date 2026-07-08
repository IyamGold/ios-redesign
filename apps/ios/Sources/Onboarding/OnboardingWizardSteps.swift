import SwiftUI
import UIKit

private enum OnboardingVisual {
    static let maxWidth: CGFloat = 430
}

private struct OnboardingActivationCanvas<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                self.content
                    .frame(maxWidth: OnboardingVisual.maxWidth)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: max(0, proxy.size.height - 94), alignment: .top)
                    .padding(.horizontal, 20)
                    .padding(.top, 54)
                    .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .background(OpenClawBrand.activationCanvasGradient.ignoresSafeArea())
        }
    }
}

private struct OnboardingHeroGlyph: View {
    var body: some View {
        OpenClawActivationGlyph(size: 78)
    }
}

private struct OnboardingHeroHeader: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?

    var body: some View {
        VStack(spacing: 18) {
            OnboardingHeroGlyph()

            VStack(spacing: 8) {
                Text(self.title)
                    .font(OpenClawType.title1)
                    .multilineTextAlignment(.center)

                if let subtitle {
                    Text(subtitle)
                        .font(OpenClawType.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct OnboardingWelcomePrompt: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(self.text)
            .font(OpenClawType.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private typealias OnboardingPrimaryButtonStyle = OpenClawPrimaryActionButtonStyle

private enum OnboardingIntroPanelStyle {
    static let iconSize: CGFloat = 34
    static let contentSpacing: CGFloat = 12
    static let panelPadding: CGFloat = 16
    static let panelCornerRadius: CGFloat = 22

    static let panelFill = OpenClawBrand.activationNeutralSurface
    static let iconFill = OpenClawBrand.activationNeutralInsetSurface
    static let stroke = OpenClawBrand.activationNeutralStroke
}

private struct OnboardingIntroPanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        self.content
            .padding(Self.panelPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: OnboardingIntroPanelStyle.panelCornerRadius, style: .continuous)
                    .fill(OnboardingIntroPanelStyle.panelFill)
            }
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: OnboardingIntroPanelStyle.panelCornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.42), lineWidth: 0.5)
                    .blendMode(.plusLighter)
            }
            .overlay {
                RoundedRectangle(cornerRadius: OnboardingIntroPanelStyle.panelCornerRadius, style: .continuous)
                    .stroke(OnboardingIntroPanelStyle.stroke, lineWidth: 0.5)
            }
    }

    private static var panelPadding: CGFloat {
        OnboardingIntroPanelStyle.panelPadding
    }
}

private struct OnboardingIntroIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: self.symbol)
            .font(OpenClawType.subheadSemiBold)
            .foregroundStyle(self.tint)
            .frame(
                width: OnboardingIntroPanelStyle.iconSize,
                height: OnboardingIntroPanelStyle.iconSize)
            .background {
                Circle()
                    .fill(OnboardingIntroPanelStyle.iconFill)
            }
            .overlay {
                Circle()
                    .stroke(OnboardingIntroPanelStyle.stroke, lineWidth: 0.6)
            }
    }
}

private struct OnboardingSafetyRow: View {
    let symbol: String
    let title: LocalizedStringKey

    var body: some View {
        HStack(spacing: OnboardingIntroPanelStyle.contentSpacing) {
            OnboardingIntroIcon(
                symbol: self.symbol,
                tint: OpenClawBrand.activationPrimaryAction)

            Text(self.title)
                .font(OpenClawType.subheadSemiBold)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct OnboardingSecurityNotice: View {
    var body: some View {
        OnboardingIntroPanel {
            HStack(alignment: .top, spacing: OnboardingIntroPanelStyle.contentSpacing) {
                OnboardingIntroIcon(
                    symbol: "exclamationmark.triangle.fill",
                    tint: OpenClawBrand.warn)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Security notice")
                        .font(OpenClawType.subheadSemiBold)
                        .foregroundStyle(.primary)
                    (
                        Text("The connected OpenClaw agent can use device capabilities you enable.")
                            + Text(verbatim: " ")
                            + Text(
                                "Camera, microphone, photos, contacts, calendar, and location may be available.")
                            + Text(verbatim: " ")
                            + Text(
                                "Continue only if you trust the gateway and agent you connect to."))
                        .font(OpenClawType.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct OnboardingCommandChip: View {
    @State private var didCopy = false
    private let command = "openclaw qr"

    var body: some View {
        HStack(spacing: 8) {
            Text(self.command)
                .font(OpenClawType.mono)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            Button {
                self.copyCommand()
            } label: {
                Image(systemName: self.didCopy ? "checkmark" : "doc.on.doc")
                    .font(OpenClawType.subheadSemiBold)
                    .foregroundStyle(
                        self.didCopy ? OpenClawBrand.activationPrimaryAction : Color.secondary.opacity(0.56))
                    .frame(width: 38, height: 38)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityLabel("Copy setup code command")
            .accessibilityValue(self.didCopy ? "Copied" : self.command)
        }
        .foregroundStyle(OpenClawBrand.activationPrimaryAction)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 54)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(OpenClawBrand.activationNeutralSurface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(OpenClawBrand.activationNeutralStroke, lineWidth: 0.5)
        }
    }

    private func copyCommand() {
        UIPasteboard.general.string = self.command
        withAnimation(.smooth(duration: 0.14)) {
            self.didCopy = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            withAnimation(.smooth(duration: 0.16)) {
                self.didCopy = false
            }
        }
    }
}

struct OnboardingIntroStep: View {
    let onContinue: () -> Void

    var body: some View {
        OnboardingActivationCanvas {
            VStack(alignment: .leading, spacing: 0) {
                OnboardingHeroHeader(
                    title: "OpenClaw",
                    subtitle: "Securely connect this iPhone to your gateway.")
                    .padding(.top, 18)

                OnboardingIntroPanel {
                    VStack(alignment: .leading, spacing: 14) {
                        OnboardingSafetyRow(
                            symbol: "link",
                            title: "Connect to your gateway")
                        OnboardingSafetyRow(
                            symbol: "hand.raised",
                            title: "Choose device permissions")
                        OnboardingSafetyRow(
                            symbol: "message.fill",
                            title: "Use OpenClaw from your phone")
                    }
                }
                .padding(.top, 44)

                OnboardingSecurityNotice()
                    .padding(.top, 18)

                Spacer(minLength: 40)

                VStack(spacing: 14) {
                    Button {
                        self.onContinue()
                    } label: {
                        Text("Continue")
                            .font(OpenClawType.subheadSemiBold)
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                }
            }
        }
    }
}

struct OnboardingWelcomeStep: View {
    let isConnecting: Bool
    let onScanQRCode: () -> Void
    let onManualSetup: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            OpenClawBrand.welcomeCanvas
                .ignoresSafeArea()

            if self.colorScheme == .dark {
                Image("OnboardingDustCloud")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .accessibilityHidden(true)

                Image("OnboardingStars")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }

            VStack(spacing: 21) {
                Image("openclaw mascot")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 146, height: 146)
                    .shadow(color: OpenClawBrand.welcomeGlow, radius: 10, x: 0, y: 0)
                    .accessibilityHidden(true)

                VStack(spacing: 31) {
                    Text("Run \u{201C}openclaw qr\u{201D} in your terminal.")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .frame(width: 266)

                    VStack(spacing: 13) {
                        Button(action: self.onScanQRCode) {
                            HStack(spacing: 7) {
                                if self.isConnecting {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .tint(.white)
                                    Text("Connecting…")
                                        .font(.system(size: 17))
                                } else {
                                    Image("QRCodeGlyph")
                                        .renderingMode(.template)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 24, height: 24)
                                    Text("Scan QR Code")
                                        .font(.system(size: 17))
                                }
                            }
                        }
                        .buttonStyle(OnboardingWelcomePillButtonStyle(
                            fill: OpenClawBrand.welcomePrimaryAction,
                            foreground: .white))
                        .disabled(self.isConnecting)

                        Button(action: self.onManualSetup) {
                            Text("Set Up Manually")
                                .font(.system(size: 17))
                        }
                        .buttonStyle(OnboardingWelcomePillButtonStyle(
                            fill: OpenClawBrand.welcomeSecondaryAction,
                            foreground: OpenClawBrand.welcomeSecondaryActionText))
                        .disabled(self.isConnecting)
                    }
                }
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: OnboardingVisual.maxWidth)
        }
        .overlay(alignment: .bottom) {
            Text(self.footerText)
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(width: 289)
                .padding(.bottom, 24)
        }
    }

    private var footerText: AttributedString {
        let head = AttributedString("If you don\u{2019}t understand what this means, please go ")
        var link = AttributedString("here")
        link.link = URL(string: "https://openclaw.ai/")
        link.foregroundColor = OpenClawBrand.welcomeLink
        link.underlineStyle = .single
        let tail = AttributedString(" to install OpenClaw.")
        return head + link + tail
    }
}

private struct OnboardingWelcomePillButtonStyle: ButtonStyle {
    let fill: Color
    let foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(self.foreground)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background {
                Capsule(style: .continuous)
                    .fill(self.fill)
            }
            .contentShape(Capsule(style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.smooth(duration: 0.14), value: configuration.isPressed)
    }
}

struct OnboardingSuccessStep: View {
    let gatewayName: String
    let gatewayAddress: String?
    let onGetStarted: () -> Void

    var body: some View {
        OnboardingActivationCanvas {
            VStack(spacing: 0) {
                Spacer(minLength: 54)

                ZStack(alignment: .bottomTrailing) {
                    OpenClawActivationGlyph(size: 86)
                        .shadow(color: OpenClawBrand.activationGlow.opacity(0.18), radius: 12, x: 0, y: 6)

                    Image(systemName: "checkmark")
                        .font(OpenClawType.headlineBold)
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background {
                            Circle()
                                .fill(OpenClawBrand.ok)
                        }
                        .overlay {
                            Circle()
                                .stroke(OpenClawBrand.activationCanvas, lineWidth: 3)
                        }
                }
                .padding(.bottom, 22)

                Text("You're connected")
                    .font(OpenClawType.title1)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 8)

                Text(verbatim: self.gatewayName)
                    .font(OpenClawType.subheadSemiBold)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let gatewayAddress, !gatewayAddress.isEmpty {
                    Text(verbatim: gatewayAddress)
                        .font(OpenClawType.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }

                Spacer(minLength: 40)

                Button {
                    self.onGetStarted()
                } label: {
                    Label("Go to Chat", systemImage: "bubble.left.and.bubble.right.fill")
                        .font(OpenClawType.subheadSemiBold)
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
            }
        }
    }
}

struct OnboardingModeIcon: View {
    let symbol: String
    let selected: Bool

    var body: some View {
        Image(systemName: self.symbol)
            .font(OpenClawType.subheadSemiBold)
            .foregroundStyle(self.selected ? OpenClawBrand.activationPrimaryActionText : .secondary)
            .frame(width: 34, height: 34)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(self.selected ? OpenClawBrand.activationPrimaryGradient : OpenClawBrand
                        .activationNeutralGradient)
                    .shadow(
                        color: self.selected ? OpenClawBrand.activationGlow.opacity(0.18) : .clear,
                        radius: 5,
                        x: 0,
                        y: 2)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        self.selected ? Color.white.opacity(0.30) : OpenClawBrand.activationNeutralStroke,
                        lineWidth: 0.5)
            }
    }
}

struct OnboardingModeRow: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let symbol: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            HStack(spacing: 12) {
                OnboardingModeIcon(symbol: self.symbol, selected: self.selected)

                VStack(alignment: .leading, spacing: 2) {
                    Text(self.title)
                        .font(OpenClawType.subheadSemiBold)
                    Text(self.subtitle)
                        .font(OpenClawType.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: self.selected ? "checkmark.circle.fill" : "circle")
                    .font(self.selected ? .title3.weight(.semibold) : .title3.weight(.regular))
                    .foregroundStyle(
                        self.selected
                            ? OpenClawBrand.activationPrimaryAction
                            : Color(uiColor: .quaternaryLabel).opacity(0.55))
            }
            .padding(.vertical, 6)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
