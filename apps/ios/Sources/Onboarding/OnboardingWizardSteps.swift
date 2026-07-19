import OpenClawKit
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
            // Bottom padding lifts the centered block above true center so it
            // reads as balanced against the bottom footer link.
            .padding(.bottom, 120)
            .frame(maxWidth: OnboardingVisual.maxWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // Full-screen background paint kept out of the layout so the footer
            // anchors identically in light and dark mode, regardless of the
            // dark-only starfield art that would otherwise resize the stack.
            OpenClawBrand.welcomeCanvas
                .overlay {
                    if self.colorScheme == .dark {
                        ZStack {
                            Image("OnboardingDustCloud")
                                .resizable()
                                .scaledToFill()
                            Image("OnboardingStars")
                                .resizable()
                                .scaledToFill()
                        }
                    }
                }
                .ignoresSafeArea()
                .accessibilityHidden(true)
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

struct OnboardingSetupStep: View {
    enum CodeValidation: Equatable {
        case idle
        case scanning
        case validated(revealsEndpoint: Bool)
        case invalid
    }

    let onBack: () -> Void
    let onApply: (_ rawCode: String, _ host: String, _ portText: String) -> Void

    @State private var code: String = ""
    @State private var host: String = ""
    @State private var portText: String = ""
    @State private var validation: CodeValidation = .idle
    @State private var scanTask: Task<Void, Never>?
    @State private var shakeCount = 0
    @State private var isApplying = false
    @State private var applyTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var fieldBackground: Color {
        self.colorScheme == .dark
            ? Color(red: 23 / 255, green: 23 / 255, blue: 23 / 255)
            : .white
    }

    private var neutralFieldBorder: Color {
        self.colorScheme == .dark ? .clear : Color.black.opacity(0.2)
    }

    private var progressActive: Color {
        self.colorScheme == .dark
            ? Color(red: 163 / 255, green: 163 / 255, blue: 163 / 255)
            : Color(red: 82 / 255, green: 82 / 255, blue: 82 / 255)
    }

    private var progressInactive: Color {
        self.colorScheme == .dark
            ? Color(red: 38 / 255, green: 38 / 255, blue: 38 / 255)
            : .white
    }

    private var backPillBackground: Color {
        self.colorScheme == .dark
            ? Color(red: 30 / 255, green: 30 / 255, blue: 30 / 255).opacity(0.2)
            : Color.white.opacity(0.2)
    }

    private static let setupErrorRed = Color(red: 211 / 255, green: 21 / 255, blue: 21 / 255)

    // Choreography constants — tune here if 0.1s feels too fast on device.
    private static let scanDuration: Duration = .milliseconds(800)
    private static let revealDelay: Duration = .milliseconds(100)
    private static let applyDuration: Duration = .milliseconds(800)

    private var fieldsRevealed: Bool {
        self.validation == .validated(revealsEndpoint: true)
    }

    private var applyEnabled: Bool {
        if case .validated = self.validation {
            return true
        }
        return false
    }

    var body: some View {
        ZStack(alignment: .top) {
            OpenClawBrand.welcomeCanvas
                .ignoresSafeArea()

            VStack(spacing: 0) {
                self.header
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 14) {
                    self.setupField(
                        "Paste code here",
                        text: self.$code,
                        borderColor: self.validation == .invalid
                            ? Self.setupErrorRed
                            : self.neutralFieldBorder)
                    {
                        self.codeStatusIcon
                    }
                    .keyframeAnimator(
                        initialValue: CGFloat.zero,
                        trigger: self.shakeCount)
                    { view, offset in
                        view.offset(x: offset)
                    } keyframes: { _ in
                        KeyframeTrack(\.self) {
                            CubicKeyframe(6, duration: 0.08)
                            CubicKeyframe(-6, duration: 0.06)
                            CubicKeyframe(4, duration: 0.08)
                            CubicKeyframe(0, duration: 0.06)
                        }
                    }

                    if self.fieldsRevealed {
                        self.setupField("Host", text: self.$host, keyboard: .URL) {
                            SetupCheckIcon()
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))

                        self.setupField("Port", text: self.$portText, keyboard: .numberPad) {
                            SetupCheckIcon()
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Button {
                        self.beginApplying()
                    } label: {
                        if self.isApplying {
                            SetupScanningSpinner()
                        } else {
                            Text("Apply code")
                                .font(.system(size: 17, weight: .medium))
                        }
                    }
                    .buttonStyle(OnboardingWelcomePillButtonStyle(
                        fill: OpenClawBrand.welcomePrimaryAction.opacity(self.applyEnabled ? 1 : 0.6),
                        foreground: self.applyEnabled ? Color.primary : Color.primary.opacity(0.6)))
                    .disabled(!self.applyEnabled || self.isApplying)

                    self.helperText
                        .padding(.leading, 21)
                }
                .padding(.top, 60)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: OnboardingVisual.maxWidth)
        }
        .onChange(of: self.code) { _, newValue in
            self.scheduleValidation(for: newValue)
        }
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 20) {
                Text("Manual Set Up")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.primary)

                HStack(spacing: 4) {
                    ForEach(0..<4, id: \.self) { index in
                        Capsule()
                            .fill(index < self.activeSegments
                                ? self.progressActive
                                : self.progressInactive)
                            .frame(width: 32, height: 3)
                    }
                }
            }

            HStack {
                Button(action: self.onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(OpenClawBrand.welcomePrimaryAction)
                        .frame(width: 40, height: 40)
                        .background {
                            Circle().fill(self.backPillBackground)
                        }
                }
                Spacer()
            }
        }
    }

    private var activeSegments: Int {
        self.fieldsRevealed ? 2 : 1
    }

    @ViewBuilder
    private var codeStatusIcon: some View {
        switch self.validation {
        case .idle:
            EmptyView()
        case .scanning:
            SetupScanningSpinner()
        case .validated:
            SetupCheckIcon()
        case .invalid:
            Button {
                self.code = ""
            } label: {
                SetupErrorIcon()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear setup code")
        }
    }

    private var helperText: some View {
        Group {
            if self.validation == .invalid {
                Text("Seems like your setup code is not correct.")
                    .foregroundColor(Self.setupErrorRed)
            } else if self.fieldsRevealed {
                Text("To get your host link, run ")
                    + Text("\u{201C}tailscale up\u{201D}")
                    .foregroundColor(Color(red: 0, green: 98 / 255, blue: 204 / 255))
                    + Text(" then ")
                    + Text("\u{201C}tailscale serve\u{201D}")
                    .foregroundColor(Color(red: 0, green: 98 / 255, blue: 204 / 255))
                    + Text(" in your terminal")
            } else if self.validation == .idle {
                // Default hint only shows in the empty/idle state — not while
                // scanning — so it does not flash between edits and the result.
                Text("If you don\u{2019}t have a set up code, run ")
                    + Text("\u{201C}openclaw qr\u{201D}")
                    .foregroundColor(Color(red: 0, green: 122 / 255, blue: 255 / 255))
                    + Text(" into your terminal.")
            }
        }
        .font(.system(size: 12))
        .opacity(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func setupField(
        _ placeholder: LocalizedStringKey,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default,
        borderColor: Color? = nil,
        @ViewBuilder trailing: () -> some View) -> some View
    {
        HStack(spacing: 11) {
            TextField(placeholder, text: text)
                .font(.system(size: 17))
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.leading, 21)
        .padding(.trailing, 16)
        .frame(height: 50)
        .background {
            Capsule(style: .continuous).fill(self.fieldBackground)
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(borderColor ?? self.neutralFieldBorder, lineWidth: 0.5)
        }
    }

    private func scheduleValidation(for raw: String) {
        self.scanTask?.cancel()
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            withAnimation(.smooth(duration: 0.2)) { self.validation = .idle }
            return
        }
        withAnimation(.smooth(duration: 0.2)) { self.validation = .scanning }
        self.scanTask = Task { @MainActor in
            try? await Task.sleep(for: Self.scanDuration)
            guard !Task.isCancelled else { return }

            if AppleReviewDemoMode.isSetupCode(trimmed) {
                withAnimation(.smooth(duration: 0.2)) {
                    self.validation = .validated(revealsEndpoint: false)
                }
                return
            }

            guard let link = GatewayConnectDeepLink.fromSetupInput(trimmed) else {
                self.enterInvalidState()
                return
            }

            withAnimation(.smooth(duration: 0.2)) {
                self.validation = .validated(revealsEndpoint: false)
            }
            try? await Task.sleep(for: Self.revealDelay)
            guard !Task.isCancelled else { return }
            self.host = link.host
            self.portText = String(link.port)
            withAnimation(.spring(duration: 0.35)) {
                self.validation = .validated(revealsEndpoint: true)
            }
            OpenClawHaptics.play(.secured2)
        }
    }

    private func enterInvalidState() {
        // The invalid state is sticky: it holds until the user taps the error
        // icon to clear the code (which resets validation back to .idle).
        withAnimation(.easeOut(duration: 0.15)) { self.validation = .invalid }
        OpenClawHaptics.play(.secured4)
        if !self.reduceMotion {
            self.shakeCount += 1
        }
    }

    private func beginApplying() {
        guard !self.isApplying else { return }
        // Show the spinner for a beat before applying — perceived work; the
        // actual connect kicks off in the wizard once onApply fires.
        self.applyTask?.cancel()
        withAnimation(.smooth(duration: 0.2)) { self.isApplying = true }
        self.applyTask = Task { @MainActor in
            try? await Task.sleep(for: Self.applyDuration)
            guard !Task.isCancelled else { return }
            self.onApply(
                self.code.trimmingCharacters(in: .whitespacesAndNewlines),
                self.host,
                self.portText)
            withAnimation(.smooth(duration: 0.2)) { self.isApplying = false }
        }
    }
}

private struct SetupScanningSpinner: View {
    @State private var spinning = false

    var body: some View {
        Image("SetupSpinnerGlyph")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 24, height: 24)
            .foregroundStyle(Color.primary.opacity(0.8))
            .rotationEffect(.degrees(self.spinning ? 360 : 0))
            .animation(
                .linear(duration: 0.9).repeatForever(autoreverses: false),
                value: self.spinning)
            .onAppear { self.spinning = true }
    }
}

private struct SetupCheckIcon: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(self.colorScheme == .dark ? "SetupCheckDarkGlyph" : "SetupCheckGlyph")
            .resizable()
            .scaledToFit()
            .frame(width: 24, height: 24)
    }
}

private struct SetupErrorIcon: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(self.colorScheme == .dark ? "SetupErrorDarkGlyph" : "SetupErrorGlyph")
            .resizable()
            .scaledToFit()
            .frame(width: 21, height: 21)
    }
}

enum OnboardingFeedbackContent: Equatable {
    case loading
    case passwordRequired(rejected: Bool)
    case awaitingApproval(requestId: String?)
    case installTailscale
    case error
}

struct OnboardingFeedbackStep: View {
    let content: OnboardingFeedbackContent
    let status: String
    // One field for either auth method; the parent routes the value into the token or password slot
    // based on which the gateway asks for, so the user never has to know or pick.
    @Binding var credential: String
    let onBack: () -> Void
    let onRetry: () -> Void
    let onSubmitCredentials: () -> Void
    let onCopyRequestId: (String) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var idCopied = false
    @State private var idCopyResetTask: Task<Void, Never>?
    @State private var credentialShakeCount = 0
    // Locally dismiss the rejected error the instant the user edits/clears the field. The `rejected`
    // prop comes from the debounced feedback content, which only recomputes on connection changes, so
    // without this the error stroke + X would stay stuck until the next connect attempt.
    @State private var credentialErrorDismissed = false
    @FocusState private var credentialFieldFocused: Bool

    private static let linkBlue = Color(red: 37 / 255, green: 99 / 255, blue: 235 / 255)
    private static let errorRed = Color(red: 211 / 255, green: 21 / 255, blue: 21 / 255) // #D31515
    private static let tailscaleAppStoreURL = URL(string: "https://apps.apple.com/app/tailscale/id1470499037")!

    var body: some View {
        ZStack(alignment: .top) {
            OpenClawBrand.welcomeCanvas
                .ignoresSafeArea()

            Group {
                switch self.content {
                case .loading:
                    self.loadingView
                case let .passwordRequired(rejected):
                    self.passwordView(rejected: rejected)
                case let .awaitingApproval(requestId):
                    self.awaitingView(requestId: requestId)
                case .installTailscale:
                    self.installTailscaleView
                case .error:
                    self.errorView
                }
            }
            .transition(.opacity)

            if self.showsBackPill {
                HStack {
                    self.backPill
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }

            if let active = self.progressActiveCount {
                self.progressRow(active: active)
                    .padding(.top, 56)
            }
        }
        .onChange(of: self.content) { oldValue, newValue in
            // On entering the rejected credential state: shake (unless reduced motion) + error haptic.
            guard case .passwordRequired(rejected: true) = newValue else { return }
            if case .passwordRequired(rejected: true) = oldValue {
                return
            }
            // A fresh rejection re-arms the error styling that a prior edit/clear locally dismissed.
            self.credentialErrorDismissed = false
            if !self.reduceMotion {
                self.credentialShakeCount += 1
            }
            OpenClawHaptics.play(.secured4)
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 31) {
            FeedbackLoaderSpinner()
            VStack(spacing: 10) {
                Text("Scanning your code")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                let trimmed = self.status.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    Text(trimmed)
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: -52)
    }

    private func passwordView(rejected: Bool) -> some View {
        let hasInput = !self.credential.trimmingCharacters(in: .whitespaces).isEmpty

        return VStack(spacing: 32) {
            self.titleText("Your Gateway requires authentication to continue.", width: 347)

            VStack(spacing: 14) {
                // One field for both methods; the parent routes it to the token or password slot the
                // gateway asks for, so the placeholder stays method-agnostic.
                self.credentialField(
                    "Gateway auth token or password...",
                    text: self.$credential,
                    rejected: rejected)
                    .keyframeAnimator(initialValue: CGFloat.zero, trigger: self.credentialShakeCount) { view, offset in
                        view.offset(x: offset)
                    } keyframes: { _ in
                        KeyframeTrack(\.self) {
                            CubicKeyframe(6, duration: 0.08)
                            CubicKeyframe(-6, duration: 0.06)
                            CubicKeyframe(4, duration: 0.08)
                            CubicKeyframe(0, duration: 0.06)
                        }
                    }

                Button(action: self.onSubmitCredentials) {
                    Text("Continue")
                        .font(.system(size: 17, weight: .medium))
                }
                .buttonStyle(OnboardingWelcomePillButtonStyle(
                    fill: OpenClawBrand.welcomePrimaryAction.opacity(hasInput ? 1 : 0.6),
                    foreground: hasInput ? Color.primary : Color.primary.opacity(0.6)))
                .disabled(!hasInput)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: OnboardingVisual.maxWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: -20)
    }

    private func awaitingView(requestId: String?) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 31) {
                self.stateGlyph("FeedbackInfoGlyph")
                VStack(spacing: 21) {
                    self.titleText("Follow the instructions below to continue.", width: 317)

                    VStack(spacing: 14) {
                        HStack(spacing: 4) {
                            Text("1. Copy your ID:")
                                .foregroundStyle(Color.primary.opacity(0.6))
                            Button {
                                if let requestId {
                                    self.onCopyRequestId(requestId)
                                    self.flashIdCopied()
                                }
                            } label: {
                                // Both labels stay stacked so the wider one fixes the width and the row
                                // never reflows; only opacity toggles, giving an instant swap (no animation).
                                ZStack {
                                    self.idCopyLabel("\u{201C}Click here to copy\u{201D}", shownWhenCopied: false)
                                    self.idCopyLabel("\u{201C}Copied!\u{201D}", shownWhenCopied: true)
                                }
                                .foregroundStyle(Self.linkBlue)
                            }
                            .buttonStyle(.plain)
                        }
                        Text("2. Run ").foregroundColor(Color.primary.opacity(0.6))
                            + Text("\u{201C}openclaw devices approve <your ID>\u{201D}")
                            .foregroundColor(Self.linkBlue)
                    }
                    .font(.system(size: 16))

                    FeedbackCopyChip(
                        foreground: self.copyChipForeground,
                        background: self.copyChipBackground)
                    {
                        if let requestId {
                            // Bottom chip copies the full approval command; step 1 copies the raw ID.
                            self.onCopyRequestId("openclaw devices approve \(requestId)")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(y: -40)
        }
        .overlay(alignment: .bottom) {
            self.bottomButton("Retry", action: self.onRetry)
        }
    }

    private var installTailscaleView: some View {
        VStack(spacing: 31) {
            self.stateGlyph("FeedbackTailscaleGlyph")
            VStack(spacing: 6) {
                self.titleText("Almost there!", width: 290)
                // "Tailscale" is an underlined, tappable App Store link; the Continue button retries the
                // connection once the user has enabled Tailscale, resuming into pairing/approval.
                Text(self.tailscaleInstallBody)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.primary.opacity(0.6))
                    .tint(Self.linkBlue)
                    .multilineTextAlignment(.center)
                    .frame(width: 290)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: -52)
        .overlay(alignment: .bottom) {
            self.bottomButton("Continue", action: self.onRetry)
        }
    }

    /// Body text with only the "Tailscale" link run underlined so it reads as a link while the rest
    /// stays plain. Falls back to the raw markdown string if parsing ever fails.
    private var tailscaleInstallBody: AttributedString {
        let markdown = "Please install [Tailscale](\(Self.tailscaleAppStoreURL.absoluteString)) "
            + "on your iPhone and login your account."
        guard var attributed = try? AttributedString(markdown: markdown) else {
            return AttributedString(markdown)
        }
        for range in attributed.runs.filter({ $0.link != nil }).map(\.range) {
            attributed[range].underlineStyle = .single
        }
        return attributed
    }

    /// One label of the step-1 copy button; the ZStack keeps both stacked so the wider label
    /// ("Click here to copy") fixes the layout width and the row never reflows on swap.
    private func idCopyLabel(_ text: String, shownWhenCopied: Bool) -> some View {
        Text(text).opacity(self.idCopied == shownWhenCopied ? 1 : 0)
    }

    private func flashIdCopied() {
        self.idCopyResetTask?.cancel()
        // Instant swap: opacity flips with no animation, reverting after a short delay.
        self.idCopied = true
        self.idCopyResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self.idCopied = false
        }
    }

    private var errorView: some View {
        VStack(spacing: 16) {
            self.stateGlyph("FeedbackErrorGlyph")
            self.titleText("Oops! Something went wrong somewhere.", width: 314)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: -40)
        .overlay(alignment: .bottom) {
            self.bottomButton("Try Again", action: self.onRetry)
        }
    }

    // MARK: - Shared pieces

    private var showsBackPill: Bool {
        if case .loading = self.content {
            return false
        }
        return true
    }

    private var progressActiveCount: Int? {
        switch self.content {
        case .installTailscale: 3
        case .awaitingApproval: 4
        default: nil
        }
    }

    private var copyChipBackground: Color {
        self.colorScheme == .dark
            ? .white
            : Color(red: 16 / 255, green: 16 / 255, blue: 16 / 255)
    }

    private var copyChipForeground: Color {
        self.colorScheme == .dark ? .black : .white
    }

    private var bottomButtonFill: Color {
        self.colorScheme == .dark
            ? Color(red: 23 / 255, green: 23 / 255, blue: 23 / 255)
            : .white
    }

    private var backPillBackground: Color {
        self.colorScheme == .dark
            ? Color(red: 30 / 255, green: 30 / 255, blue: 30 / 255).opacity(0.2)
            : Color.white.opacity(0.2)
    }

    private var backPill: some View {
        Button(action: self.onBack) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(OpenClawBrand.welcomePrimaryAction)
                .frame(width: 40, height: 40)
                .background { Circle().fill(self.backPillBackground) }
        }
    }

    private func progressRow(active: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(index < active
                        ? (self.colorScheme == .dark
                            ? Color(red: 163 / 255, green: 163 / 255, blue: 163 / 255)
                            : Color(red: 82 / 255, green: 82 / 255, blue: 82 / 255))
                        : (self.colorScheme == .dark
                            ? Color(red: 38 / 255, green: 38 / 255, blue: 38 / 255)
                            : .white))
                    .frame(width: 32, height: 3)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func titleText(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 30, weight: .medium))
            .foregroundStyle(Color.primary)
            .multilineTextAlignment(.center)
            .frame(width: width)
    }

    private func stateGlyph(_ name: String) -> some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(width: 70, height: 70)
    }

    private func credentialField(
        _ placeholder: LocalizedStringKey,
        text: Binding<String>,
        rejected: Bool) -> some View
    {
        // Error styling shows while the credential is rejected, but a local dismiss flag hides it the
        // instant the user edits/clears — the `rejected` prop itself only clears on the next connect.
        let showError = rejected && !self.credentialErrorDismissed
        // A SecureField writes an empty string to its binding when it mounts/unmounts across the
        // full-screen loading transition. Routed straight to `persist…` that would wipe the stored
        // credential and reset the rejected flag, so accept the field's own writes only while it is
        // focused (a genuine edit). The red X clears via `text` directly, bypassing this guard.
        let focusGuardedText = Binding(
            get: { text.wrappedValue },
            set: { newValue in
                guard self.credentialFieldFocused else { return }
                self.credentialErrorDismissed = true
                text.wrappedValue = newValue
            })
        return HStack(spacing: 11) {
            SecureField(placeholder, text: focusGuardedText)
                .focused(self.$credentialFieldFocused)
                .font(.system(size: 17))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Spacer(minLength: 0)
            if showError {
                Button {
                    self.credentialErrorDismissed = true
                    text.wrappedValue = ""
                } label: {
                    SetupErrorIcon()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.leading, 21)
        .padding(.trailing, 16)
        .frame(height: 50)
        .frame(maxWidth: .infinity)
        .background {
            Capsule(style: .continuous)
                .fill(self.colorScheme == .dark
                    ? Color(red: 23 / 255, green: 23 / 255, blue: 23 / 255)
                    : .white)
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(
                    showError ? Self.errorRed : (self.colorScheme == .dark ? .clear : Color.black.opacity(0.2)),
                    lineWidth: showError ? 1 : 0.5)
        }
    }

    private func bottomButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .medium))
        }
        .buttonStyle(OnboardingWelcomePillButtonStyle(
            fill: self.bottomButtonFill,
            foreground: Color.primary))
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .frame(maxWidth: OnboardingVisual.maxWidth)
    }
}

/// Copy chip that animates from a clip/"Copy" resting state to a checkmark/"Copied!" state on tap.
/// The icons cross-fade with a scale+blur pop; the label cross-fades via contentTransition and the
/// chip widens to fit "Copied!" while keeping its horizontal padding constant.
private struct FeedbackCopyChip: View {
    let foreground: Color
    let background: Color
    let action: () -> Void

    @State private var copied = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        Button {
            self.action()
            self.flashCopied()
        } label: {
            HStack(spacing: 3) {
                ZStack {
                    self.icon(.asset("FeedbackCopyGlyph"), visible: !self.copied)
                    self.icon(.symbol("checkmark"), visible: self.copied)
                }
                .frame(width: 16, height: 16)

                Text(self.copied ? "Copied!" : "Copy")
                    .font(.system(size: 13))
                    .contentTransition(.opacity)
            }
            .foregroundStyle(self.foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(self.background)
            }
        }
        .buttonStyle(.plain)
    }

    private enum Glyph {
        case asset(String)
        case symbol(String)
    }

    private func icon(_ glyph: Glyph, visible: Bool) -> some View {
        Group {
            switch glyph {
            case let .asset(name):
                Image(name).renderingMode(.template).resizable().scaledToFit()
            case let .symbol(name):
                Image(systemName: name).resizable().scaledToFit().fontWeight(.semibold)
            }
        }
        .frame(width: 16, height: 16)
        .opacity(visible ? 1 : 0)
        .scaleEffect(visible ? 1 : 0.25)
        .blur(radius: visible ? 0 : 4)
    }

    private func flashCopied() {
        self.resetTask?.cancel()
        withAnimation(.smooth(duration: 0.3)) { self.copied = true }
        self.resetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.3)) { self.copied = false }
        }
    }
}

private struct FeedbackLoaderSpinner: View {
    @State private var spinning = false

    var body: some View {
        Image("FeedbackLoaderGlyph")
            .resizable()
            .scaledToFit()
            .frame(width: 70, height: 70)
            .rotationEffect(.degrees(self.spinning ? 360 : 0))
            .animation(
                .linear(duration: 1.2).repeatForever(autoreverses: false),
                value: self.spinning)
            .onAppear { self.spinning = true }
    }
}

struct OnboardingSuccessStepView: View {
    let onFinished: () -> Void

    var body: some View {
        ZStack {
            OpenClawBrand.welcomeCanvas
                .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 31) {
                    Image("FeedbackSuccessGlyph")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 70, height: 70)
                    Text("Connection secured.")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(Color.primary)
                        .multilineTextAlignment(.center)
                        .frame(width: 317)
                }
                Text("Logging you in...")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.primary.opacity(0.6))
                    .padding(.top, 27)
            }
            .offset(y: -52)
        }
        .task {
            try? await Task.sleep(for: .seconds(1.5))
            self.onFinished()
        }
    }
}
