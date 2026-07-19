import Combine
import CoreImage
import OpenClawKit
import PhotosUI
import SwiftUI
import UIKit

private enum OnboardingStep: Int, CaseIterable {
    case intro
    case welcome
    case mode
    case feedback
    case success

    var previous: Self? {
        Self(rawValue: rawValue - 1)
    }

    var title: LocalizedStringKey {
        switch self {
        case .intro: "Welcome"
        case .welcome: "Connect Gateway"
        case .mode: "Gateway Setup"
        case .feedback: ""
        case .success: "Connected"
        }
    }

    var canGoBack: Bool {
        self != .intro && self != .welcome && self != .success
            && self != .mode && self != .feedback
    }
}

struct GatewaySetupLinkStaging {
    private(set) var link: GatewayConnectDeepLink?

    mutating func stage(_ link: GatewayConnectDeepLink) {
        self.link = link
    }

    mutating func take() -> GatewayConnectDeepLink? {
        defer { self.link = nil }
        return self.link
    }

    @discardableResult
    mutating func cancel() -> Bool {
        guard self.link != nil else { return false }
        self.link = nil
        return true
    }
}

private enum OnboardingFocusedField: Hashable {
    case setupCode
    case manualHost
    case manualPort
    case discoveryDomain
    case gatewayToken
    case gatewayPassword
}

struct OnboardingWizardView: View {
    @Environment(NodeAppModel.self) private var appModel: NodeAppModel
    @Environment(GatewayConnectionController.self) private var gatewayController: GatewayConnectionController
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("node.instanceId") private var instanceId: String = UUID().uuidString
    @AppStorage("gateway.discovery.domain") private var discoveryDomain: String = ""
    @AppStorage("onboarding.developerMode") private var developerModeEnabled: Bool = false
    @State private var step: OnboardingStep
    @State private var selectedMode: OnboardingConnectionMode?
    @State private var manualHost: String = ""
    @State private var manualPort: Int = 18789
    @State private var manualPortText: String = "18789"
    @State private var manualTLS: Bool = true
    @State private var gatewayToken: String = ""
    @State private var gatewayPassword: String = ""
    @State private var gatewayCredentialFieldStableID: String?
    @State private var connectMessage: String?
    @State private var statusLine: String = ""
    @State private var connectingGatewayID: String?
    @State private var issue: GatewayConnectionIssue = .none
    @State private var didMarkCompleted = false
    @State private var pairingRequestId: String?
    @State private var discoveryRestartTask: Task<Void, Never>?
    @State private var showQRScanner: Bool = false
    @State private var scannerError: String?
    @State private var scannerResultHandoff = QRScannerResultHandoff()
    @State private var scannerScanID: UInt64 = 0
    @State private var pendingTargetSuppression = GatewayPendingTargetSuppression()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showGatewayProblemDetails: Bool = false
    @State private var lastPairingAutoResumeAttemptAt: Date?
    @State private var pendingManualAuthOverride: GatewayConnectionController.ManualAuthOverride?
    @State private var setupLinkStaging = GatewaySetupLinkStaging()
    @State private var setupCode: String = ""
    @State private var setupCodeStatus: String?
    @State private var setupAttemptID: UUID?
    @State private var manualEndpointOverride: (host: String, port: String)?
    @State private var feedbackContent: OnboardingFeedbackContent = .loading
    @State private var feedbackShownAt = Date()
    @State private var feedbackCommitTask: Task<Void, Never>?
    @State private var feedbackTimeoutTask: Task<Void, Never>?
    @State private var loadingDidFail = false
    @State private var credentialSubmitted = false
    /// Guards the one-shot auto-resubmit that fires when the gateway reveals its auth method after a
    /// credential was already submitted into the other slot. Reset on each fresh user submission.
    @State private var autoRetriedAfterMethodFlip = false
    @State private var feedbackReturnStep: OnboardingStep = .mode
    @FocusState private var focusedField: OnboardingFocusedField?
    private static let pairingAutoResumeTicker = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()

    let allowSkip: Bool
    let onRequestLocalNetworkAccess: (String) -> Void
    let onClose: () -> Void
    let onComplete: () -> Void

    init(
        allowSkip: Bool,
        onRequestLocalNetworkAccess: @escaping (String) -> Void,
        onClose: @escaping () -> Void,
        onComplete: @escaping () -> Void)
    {
        self.allowSkip = allowSkip
        self.onRequestLocalNetworkAccess = onRequestLocalNetworkAccess
        self.onClose = onClose
        self.onComplete = onComplete
        // Onboarding always opens on the redesigned welcome step; the gateway
        // connection is mandatory, so there is no separate first-run intro.
        _step = State(initialValue: .welcome)
    }

    private var isFullScreenStep: Bool {
        self.step == .intro || self.step == .welcome || self.step == .success
            || self.step == .mode || self.step == .feedback
    }

    private var currentProblem: GatewayConnectionProblem? {
        self.appModel.lastGatewayProblem
    }

    var body: some View {
        self.lifecycleContent
            .onChange(of: self.scenePhase) { _, newValue in
                guard newValue == ScenePhase.active else { return }
                self.applyPendingGatewaySetupLinkIfNeeded()
                self.attemptAutomaticPairingResumeIfNeeded()
                if self.step == .feedback, case .installTailscale = self.feedbackContent {
                    Task { await self.retryLastAttempt(silent: true) }
                }
            }
            .onReceive(Self.pairingAutoResumeTicker) { _ in
                self.attemptAutomaticPairingResumeIfNeeded()
            }
            .onChange(of: self.issue) { _, _ in self.refreshOnboardingFeedback() }
            .onChange(of: self.connectingGatewayID) { _, _ in self.refreshOnboardingFeedback() }
            .onChange(of: self.gatewayController.pendingTrustPrompt == nil) { wasCleared, isCleared in
                guard isCleared, !wasCleared else { return }
                self.failFeedbackIfTrustPromptDismissedWithoutConnecting()
            }
            .onChange(of: self.feedbackContent) { oldValue, newValue in
                self.handleFeedbackContentChange(from: oldValue, to: newValue)
            }
            // Host the TLS trust prompt on its own layer: SwiftUI honors only one `.alert` per view,
            // and the scanner-error alert on `lifecycleContent` would otherwise shadow it, leaving a
            // TLS connect parked at "Verify gateway TLS fingerprint" with no way to approve.
            .background { Color.clear.gatewayTrustPromptAlert() }
    }

    private var lifecycleContent: some View {
        NavigationStack {
            Group {
                switch self.step {
                case .intro:
                    self.introStep
                case .welcome:
                    self.welcomeStep
                case .mode:
                    self.setupStep
                case .feedback:
                    self.feedbackStep
                case .success:
                    self.successStep
                }
            }
            .navigationTitle(self.isFullScreenStep ? "" : self.step.title)
            .navigationBarTitleDisplayMode(.inline)
            .tint(OpenClawBrand.activationPrimaryAction)
        }
        .safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0) {
            self.keyboardDismissControl
        }
        .overlay(alignment: .topLeading) {
            self.leadingChromeButton
                .padding(.leading, 16)
                .padding(.top, 10)
        }
        .alert("QR Scanner Unavailable", isPresented: Binding(
            get: { self.scannerError != nil },
            set: {
                if !$0 {
                    self.scannerError = nil
                }
            })) {
                Button(role: .cancel) {} label: {
                    Text("OK")
                        .font(OpenClawType.subheadSemiBold)
                }
        } message: {
            Text(self.scannerError ?? "")
                .font(OpenClawType.subhead)
        }
        .sheet(
            isPresented: self.$showQRScanner,
            onDismiss: {
                self.processQueuedScannerResult()
            },
            content: {
                self.qrScannerSheet
            })
        .sheet(isPresented: self.$showGatewayProblemDetails) {
            if let currentProblem = self.currentProblem {
                GatewayProblemDetailsSheet(
                    problem: currentProblem,
                    primaryActionTitle: self.gatewayProblemPrimaryActionTitle(currentProblem),
                    onPrimaryAction: {
                        Task { await self.handleGatewayProblemPrimaryAction(currentProblem) }
                    })
            }
        }
        .onAppear {
            self.initializeState()
            self.applyPendingGatewaySetupLinkIfNeeded()
            self.requestLocalNetworkAccessIfPastIntro(reason: "onboarding_appear")
        }
        .onDisappear {
            self.invalidateSetupAttempt()
            self.discoveryRestartTask?.cancel()
            self.discoveryRestartTask = nil
            self.scannerResultHandoff.cancel()
            self.pendingTargetSuppression.resumeAutoConnect(controller: self.gatewayController)
        }
        .onChange(of: self.discoveryDomain) { _, _ in
            self.scheduleDiscoveryRestart()
        }
        .onChange(of: self.manualPortText) { _, newValue in
            let digits = newValue.filter(\.isNumber)
            if digits != newValue {
                self.manualPortText = digits
                return
            }
            guard let parsed = Int(digits), parsed > 0 else {
                self.manualPort = 0
                return
            }
            self.manualPort = min(parsed, 65535)
        }
        .onChange(of: self.manualPort) { _, newValue in
            let normalized = newValue > 0 ? String(newValue) : ""
            if self.manualPortText != normalized {
                self.manualPortText = normalized
            }
        }
        .onChange(of: self.setupCode) { _, newValue in
            guard !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            self.clearStagedGatewaySetupLink()
        }
        .onChange(of: self.appModel.lastGatewayProblem) { _, newValue in
            self.updateConnectionIssue(problem: newValue, statusText: self.appModel.gatewayStatusText)
        }
        .onChange(of: self.appModel.gatewayStatusText) { _, newValue in
            self.updateConnectionIssue(problem: self.appModel.lastGatewayProblem, statusText: newValue)
        }
        .onChange(of: self.gatewayAuthMethod) { oldMethod, newMethod in
            // Only react when the gateway discloses a concrete method. Transitions to `.unknown`
            // (pairing / success / network) must never touch the credential slots — otherwise a
            // successful password auth moving on to pairing would migrate the password out of its slot.
            guard newMethod != .unknown, oldMethod != newMethod else { return }
            let wasSubmitting = self.credentialSubmitted
            let migrated = self.migrateCredentialToDetectedMethod(requiresPassword: newMethod == .password)
            // A submitted credential rejected only because the gateway had not yet disclosed its auth
            // method: resend it once in the corrected slot so a correct first entry connects without the
            // user pressing Continue again. The one-shot guard stops this from looping.
            guard migrated, wasSubmitting, !self.autoRetriedAfterMethodFlip else { return }
            self.autoRetriedAfterMethodFlip = true
            self.resetFeedbackForNewAttempt(returnStep: self.feedbackReturnStep)
            self.credentialSubmitted = true
            Task { await self.retryLastAttempt() }
        }
        .onChange(of: self.appModel.gatewaySetupRequestID) { _, _ in
            self.applyPendingGatewaySetupLinkIfNeeded()
        }
        .onChange(of: self.appModel.gatewayServerName) { _, newValue in
            guard newValue != nil, self.setupLinkStaging.link == nil else { return }
            self.credentialSubmitted = false
            self.showQRScanner = false
            self.statusLine = "Connected."
            if !self.didMarkCompleted {
                OnboardingStateStore.markCompleted(
                    mode: self.selectedMode ?? self.inferredCompletionMode)
                self.didMarkCompleted = true
            }
            if self.step == .feedback {
                let elapsed = Date().timeIntervalSince(self.feedbackShownAt)
                let wait = max(0, 2.0 - elapsed)
                self.feedbackCommitTask?.cancel()
                self.feedbackCommitTask = Task { @MainActor in
                    if wait > 0 {
                        try? await Task.sleep(for: .seconds(wait))
                    }
                    guard !Task.isCancelled else { return }
                    self.navigate(to: .success)
                }
            } else {
                self.navigate(to: .success)
            }
        }
    }

    private var qrScannerSheet: some View {
        let scanID = self.scannerScanID
        return NavigationStack {
            QRScannerView(
                onResult: { result in
                    self.queueScannedResult(result, scanID: scanID)
                },
                onError: { error in
                    guard self.scannerResultHandoff.isActive(scanID: scanID) else { return }
                    self.showQRScanner = false
                    self.statusLine = "Scanner error: \(error)"
                    self.scannerError = error
                },
                onDismiss: {
                    guard self.scannerResultHandoff.isActive(scanID: scanID) else { return }
                    self.showQRScanner = false
                })
                .ignoresSafeArea()
                .navigationTitle("Scan Setup Code")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text("Scan Setup Code")
                            .font(OpenClawType.headline)
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            self.scannerResultHandoff.cancel()
                            self.showQRScanner = false
                        } label: {
                            Text("Cancel")
                                .font(OpenClawType.subheadSemiBold)
                        }
                        .font(OpenClawType.subheadSemiBold)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        PhotosPicker(selection: self.$selectedPhoto, matching: .images) {
                            Label("Photos", systemImage: "photo")
                                .font(OpenClawType.subheadSemiBold)
                        }
                    }
                }
        }
        .onChange(of: self.selectedPhoto) { _, newValue in
            guard let item = newValue else { return }
            self.selectedPhoto = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    guard self.scannerResultHandoff.isActive(scanID: scanID) else { return }
                    self.showQRScanner = false
                    self.scannerError = "Could not load the selected image."
                    return
                }
                guard self.scannerResultHandoff.isActive(scanID: scanID) else { return }
                if let message = self.detectQRCode(from: data) {
                    if let link = GatewayConnectDeepLink.fromSetupInput(message) {
                        self.queueScannedResult(.gatewayLink(link), scanID: scanID)
                        return
                    }
                    if AppleReviewDemoMode.isSetupCode(message) {
                        self.queueScannedResult(.setupCode(message), scanID: scanID)
                        return
                    }
                }
                self.showQRScanner = false
                self.scannerError = "No valid QR code found in the selected image."
            }
        }
    }

    @ViewBuilder
    private var leadingChromeButton: some View {
        if self.step.canGoBack {
            Button {
                self.navigateBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(OpenClawType.subheadSemiBold)
                    .accessibilityLabel("Back")
            }
            .buttonStyle(OpenClawCloseButtonStyle())
        } else if self.allowSkip {
            // Close is only offered when onboarding is re-opened from an already
            // usable app (allowSkip). Mandatory first-run onboarding passes
            // allowSkip == false so the user cannot bypass the gateway connection.
            Button {
                self.invalidateSetupAttempt()
                self.onClose()
            } label: {
                Text("Close")
                    .font(OpenClawType.subheadSemiBold)
            }
            .buttonStyle(OpenClawCloseButtonStyle())
        }
    }

    @ViewBuilder
    private var keyboardDismissControl: some View {
        if self.focusedField != nil {
            Button {
                self.dismissKeyboard()
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(OpenClawType.headline)
                    .frame(width: 50, height: 44)
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(OpenClawBrand.activationPrimaryAction)
            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(OpenClawBrand.activationNeutralStroke, lineWidth: 0.6)
            }
            .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 4)
            .accessibilityLabel("Dismiss Keyboard")
            .padding(.trailing, 20)
            .padding(.bottom, 10)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
            .animation(.smooth(duration: 0.16), value: self.focusedField)
        }
    }

    private var introStep: some View {
        OnboardingIntroStep(onContinue: self.advanceFromIntro)
    }

    private var setupStep: some View {
        OnboardingSetupStep(
            onBack: { self.navigate(to: .welcome) },
            onApply: { raw, host, port in
                self.resetFeedbackForNewAttempt(returnStep: .mode)
                self.manualEndpointOverride = (host: host, port: port)
                self.setupCode = raw
                Task { await self.applySetupCodeAndConnect() }
            })
    }

    private var feedbackStep: some View {
        OnboardingFeedbackStep(
            content: self.feedbackContent,
            status: self.feedbackStatusText,
            credential: self.gatewayCredentialBinding,
            onBack: {
                self.feedbackCommitTask?.cancel()
                self.navigate(to: self.feedbackReturnStep)
            },
            onRetry: {
                // Explicit retry is a clean slate: drop the sticky pairing/auth issue so the new
                // attempt reclassifies from scratch (e.g. Tailscale turned off since → install-Tailscale).
                // The silent auto-retry path deliberately keeps the issue sticky and is untouched.
                self.issue = .none
                self.pairingRequestId = nil
                self.resetFeedbackForNewAttempt(returnStep: self.feedbackReturnStep)
                Task { await self.retryLastAttempt() }
            },
            onSubmitCredentials: {
                // Verify by connecting (shows the loading screen); a wrong credential comes back to the
                // auth prompt with the field in its error state (credentialSubmitted stays set).
                self.autoRetriedAfterMethodFlip = false
                self.resetFeedbackForNewAttempt(returnStep: self.feedbackReturnStep)
                self.credentialSubmitted = true
                Task { await self.retryLastAttempt() }
            },
            onCopyRequestId: { UIPasteboard.general.string = $0 })
    }

    private var welcomeStep: some View {
        OnboardingWelcomeStep(
            isConnecting: self.connectingGatewayID != nil,
            onScanQRCode: {
                self.openQRScannerFromOnboarding()
            },
            onManualSetup: {
                self.invalidateSetupAttempt()
                self.statusLine = ""
                self.navigate(to: .mode)
            })
    }

    @ViewBuilder
    private var modeStep: some View {
        self.setupCodeSection

        Section {
            OnboardingModeRow(
                title: "Home Network",
                subtitle: "LAN or Tailscale host",
                symbol: "house.and.flag",
                selected: self.selectedMode == .homeNetwork)
            {
                self.selectMode(.homeNetwork)
            }

            OnboardingModeRow(
                title: "Remote Domain",
                subtitle: "VPS with domain",
                symbol: "globe",
                selected: self.selectedMode == .remoteDomain)
            {
                self.selectMode(.remoteDomain)
            }

            if self.developerModeEnabled {
                self.developerModeToggleRow

                OnboardingModeRow(
                    title: "Same Machine (Dev)",
                    subtitle: "For local iOS app development",
                    symbol: "wrench.and.screwdriver",
                    selected: self.selectedMode == .developerLocal)
                {
                    self.selectMode(.developerLocal)
                }
            }
        } header: {
            Text("Manual Connection")
                .font(OpenClawType.footnoteSemiBold)
                .padding(.top, 12)
        }
        .disabled(self.connectingGatewayID != nil)

        Section {
            Button {
                self.navigate(to: .feedback)
            } label: {
                Text("Continue")
                    .font(OpenClawType.subheadSemiBold)
            }
            .disabled(self.selectedMode == nil || self.connectingGatewayID != nil)
            .buttonStyle(OpenClawPrimaryActionButtonStyle(height: 48, cornerRadius: 16))
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    private var developerModeToggleRow: some View {
        self.onboardingButtonToggle(
            "Developer mode",
            symbol: "wrench.and.screwdriver",
            isOn: Binding(
                get: { self.developerModeEnabled },
                set: { enabled in
                    self.developerModeEnabled = enabled
                    if !enabled, self.selectedMode == .developerLocal {
                        self.selectedMode = nil
                    }
                }))
    }

    private func onboardingButtonToggle(
        _ title: LocalizedStringKey,
        symbol: String? = nil,
        isOn: Binding<Bool>) -> some View
    {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                if let symbol {
                    OnboardingModeIcon(symbol: symbol, selected: false)
                }

                Text(title)
                    .font(OpenClawType.subheadSemiBold)
                    .foregroundStyle(.primary)
            }
            .frame(minHeight: 52)
        }
        .tint(OpenClawBrand.activationPrimaryAction)
        .contentShape(Rectangle())
        .overlay {
            Button {
                isOn.wrappedValue.toggle()
            } label: {
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        }
    }

    private var successStep: some View {
        OnboardingSuccessStepView(onFinished: { self.onComplete() })
    }
}

extension OnboardingWizardView {
    private var gatewayStatusSectionTitle: String {
        if self.issue.needsPairing || self.currentProblem?.needsPairingApproval == true {
            return "Gateway Approval"
        }
        if self.issue.needsAuthToken || self.currentProblem != nil {
            return "Authentication"
        }
        return "Gateway Status"
    }

    private var setupCodeSection: some View {
        Section {
            HStack(spacing: 12) {
                self.onboardingTextField("Enter setup code", text: self.$setupCode, focusedField: .setupCode)
                    .lineLimit(1)
                    .submitLabel(.go)
                    .onSubmit {
                        guard self.canApplySetupCode else { return }
                        Task { await self.applySetupCodeAndConnect() }
                    }

                Button {
                    Task { await self.applySetupCodeAndConnect() }
                } label: {
                    if self.connectingGatewayID == "setup-code" {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                    } else {
                        Text("Apply")
                            .font(OpenClawType.subheadSemiBold)
                    }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
                .tint(OpenClawBrand.activationPrimaryAction)
                .disabled(!self.canApplySetupCode)
            }
            .frame(minHeight: 50)

            if let setupCodeStatus, !setupCodeStatus.isEmpty {
                Text(setupCodeStatus)
                    .font(OpenClawType.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Setup Code")
                .font(OpenClawType.footnoteSemiBold)
        } footer: {
            Text("Use this if you have a setup code instead of scanning.")
                .font(OpenClawType.footnote)
        }
    }

    private var canApplySetupCode: Bool {
        !self.setupCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && self.connectingGatewayID == nil
    }

    private func manualConnectionFieldsSection(title: LocalizedStringKey) -> some View {
        Section {
            self.onboardingTextField("Host", text: self.manualHostBinding, focusedField: .manualHost)
            self.onboardingTextField("Port", text: self.manualPortTextBinding, focusedField: .manualPort)
                .keyboardType(.numberPad)
            self.manualConnectionSecurityRows
            self.onboardingTextField(
                "Discovery Domain (optional)",
                text: self.$discoveryDomain,
                focusedField: .discoveryDomain)
            if self.selectedMode == .remoteDomain {
                self.onboardingSecureField(
                    "Gateway Auth Token",
                    text: self.gatewayTokenBinding,
                    focusedField: .gatewayToken)
                self.onboardingSecureField(
                    "Gateway Password",
                    text: self.gatewayPasswordBinding,
                    focusedField: .gatewayPassword)
            }
            self.manualConnectButton
        } header: {
            Text(title)
                .font(OpenClawType.footnoteSemiBold)
        }
    }

    private var manualTransport: GatewayManualTransportPresentation {
        GatewayConnectionController.manualTransportPresentation(
            host: self.manualHost,
            requestedTLS: self.manualTLS)
    }

    private var manualTLSBinding: Binding<Bool> {
        Binding(
            get: { self.manualTransport.effectiveTLS },
            set: { enabled in
                guard !self.manualTransport.requiresTLS else { return }
                self.manualTLS = enabled
            })
    }

    @ViewBuilder
    private var manualConnectionSecurityRows: some View {
        Picker("Connection security", selection: self.manualTLSBinding) {
            Text("Unencrypted")
                .font(OpenClawType.captionSemiBold)
                .tag(false)
            Text("Secure (TLS)")
                .font(OpenClawType.captionSemiBold)
                .tag(true)
        }
        .pickerStyle(.segmented)
        .disabled(self.manualTransport.requiresTLS)

        if let helperText = self.manualTransport.helperText {
            Text(helperText)
                .font(OpenClawType.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func onboardingLabeledContent(_ title: LocalizedStringKey, value: String) -> some View {
        LabeledContent {
            Text(verbatim: value)
                .font(OpenClawType.body)
        } label: {
            Text(title)
                .font(OpenClawType.body)
        }
    }

    private func onboardingTextField(
        _ placeholder: LocalizedStringKey,
        text: Binding<String>,
        focusedField: OnboardingFocusedField) -> some View
    {
        TextField(
            "",
            text: text,
            prompt: Text(placeholder)
                .font(OpenClawType.subhead)
                .foregroundStyle(.tertiary))
            .font(OpenClawType.subhead)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused(self.$focusedField, equals: focusedField)
            .accessibilityLabel(placeholder)
    }

    private func onboardingSecureField(
        _ placeholder: LocalizedStringKey,
        text: Binding<String>,
        focusedField: OnboardingFocusedField) -> some View
    {
        ZStack(alignment: .leading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(OpenClawType.subhead)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            SecureField("", text: text)
                .font(OpenClawType.subhead)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused(self.$focusedField, equals: focusedField)
        }
        .accessibilityLabel(placeholder)
    }

    private var manualConnectButton: some View {
        Button {
            Task { await self.connectManual() }
        } label: {
            if self.connectingGatewayID == "manual" {
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(.circular)
                    Text("Connecting…")
                        .font(OpenClawType.subheadSemiBold)
                }
            } else {
                Text("Connect")
                    .font(OpenClawType.subheadSemiBold)
            }
        }
        .font(OpenClawType.subheadSemiBold)
        .disabled(!self.canConnectManual || self.connectingGatewayID != nil)
    }

    /// A gateway accepts a single auth method. The problem kind tells us which — but only while it is
    /// actively reporting an auth error. Pairing, success, and network states carry no method, so they
    /// map to `.unknown` and must never move the credential between slots.
    private enum DetectedGatewayAuthMethod: Equatable {
        case token
        case password
        case unknown
    }

    private var gatewayAuthMethod: DetectedGatewayAuthMethod {
        switch self.appModel.lastGatewayProblem?.kind {
        case .gatewayAuthPasswordMissing, .gatewayAuthPasswordMismatch, .gatewayAuthPasswordNotConfigured:
            .password
        case .gatewayAuthTokenMissing, .gatewayAuthTokenMismatch, .gatewayAuthTokenNotConfigured:
            .token
        default:
            .unknown
        }
    }

    /// Which slot the single auth field routes into. Defaults to token until the gateway asks for a
    /// password, so the placeholder/binding stay consistent while the field is on screen.
    private var gatewayRequiresPassword: Bool {
        self.gatewayAuthMethod == .password
    }

    private var desiredFeedbackContent: OnboardingFeedbackContent {
        if self.issue.needsPairing {
            return .awaitingApproval(requestId: self.issue.requestId ?? self.pairingRequestId)
        }
        if self.issue.needsAuthToken {
            // rejected once a submitted credential comes back still needing auth (any reject kind).
            return .passwordRequired(rejected: self.credentialSubmitted)
        }
        switch self.issue {
        case .network:
            return self.isLikelyTailnetTarget ? .installTailscale : .error
        case .unknown:
            return .error
        default:
            // A connect can end with no issue emitted — a stall, or a dismissed trust prompt. The
            // loadingDidFail flag makes the error sticky so a later refresh does not revert to loading.
            return self.loadingDidFail ? .error : .loading
        }
    }

    private var isLikelyTailnetTarget: Bool {
        // Fall back to `manualHost` (always set by applyGatewayLink) so the apply-code path — where no
        // staged link or manual override is present — still recognizes a *.ts.net tailnet endpoint.
        let host = (self.setupLinkStaging.link?.host
            ?? self.manualEndpointOverride?.host
            ?? self.manualHost).lowercased()
        return host.hasSuffix(".ts.net")
    }

    /// Live connection stage for the feedback loading subtitle. Prefer the controller's status text
    /// (e.g. "Connecting…", "Verify gateway TLS fingerprint", "Reconnecting…") so a stalled attempt is
    /// legible; fall back to the onboarding-level message when the controller has not set one yet.
    private var feedbackStatusText: String {
        let live = self.appModel.gatewayStatusText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !live.isEmpty {
            return live
        }
        if let message = self.connectMessage, !message.isEmpty {
            return message
        }
        return self.statusLine
    }

    private func refreshOnboardingFeedback() {
        guard self.step == .feedback else { return }
        self.setFeedbackContent(self.desiredFeedbackContent)
    }

    /// When a resolved state (pairing / password / install-Tailscale / error) transitions in over the
    /// loading spinner, a haptic marks the arrival. Compared by case so associated-value-only updates
    /// (e.g. `awaitingApproval`'s requestId arriving) don't re-fire the haptic.
    private func handleFeedbackContentChange(
        from old: OnboardingFeedbackContent,
        to new: OnboardingFeedbackContent)
    {
        guard self.step == .feedback else { return }
        if case .loading = new {
            return
        }
        guard Self.feedbackCaseID(old) != Self.feedbackCaseID(new) else { return }
        // A rejected credential arrival plays the field's own error haptic; suppress the handshake so
        // they don't double up. Every other state arrival gets the handshake.
        if case .passwordRequired(rejected: true) = new {
            return
        }
        OpenClawHaptics.play(.secured2)
    }

    private static func feedbackCaseID(_ content: OnboardingFeedbackContent) -> Int {
        switch content {
        case .loading: 0
        case .passwordRequired: 1
        case .awaitingApproval: 2
        case .installTailscale: 3
        case .error: 4
        }
    }

    /// A trust prompt dismissed without proceeding to connect (declined → gateway goes Offline) is a
    /// terminal failure of this attempt. Fail fast to the error state instead of leaving the loading
    /// spinner until the stall timeout. Accepting keeps a "Connecting…/Verifying…" status, so we only
    /// fail when nothing is progressing and the attempt has not otherwise resolved.
    private func failFeedbackIfTrustPromptDismissedWithoutConnecting() {
        guard self.step == .feedback else { return }
        guard self.issue == .none, self.appModel.gatewayServerName == nil else { return }
        let status = self.appModel.gatewayStatusText.lowercased()
        let progressing = status.contains("connect") || status.contains("verif")
        guard !progressing else { return }
        self.loadingDidFail = true
        self.refreshOnboardingFeedback()
    }

    private func setFeedbackContent(_ target: OnboardingFeedbackContent) {
        guard target != self.feedbackContent else { return }
        // Any committed state other than loading means the attempt resolved; drop the stall timeout.
        if case .loading = target {} else {
            self.feedbackTimeoutTask?.cancel()
            self.feedbackTimeoutTask = nil
        }
        self.feedbackCommitTask?.cancel()
        let elapsed = Date().timeIntervalSince(self.feedbackShownAt)
        let wait = max(0, 2.0 - elapsed)
        self.feedbackCommitTask = Task { @MainActor in
            if wait > 0 {
                try? await Task.sleep(for: .seconds(wait))
            }
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.3)) { self.feedbackContent = target }
            self.feedbackShownAt = Date()
        }
    }

    private func resetFeedbackForNewAttempt(returnStep: OnboardingStep) {
        self.feedbackCommitTask?.cancel()
        self.feedbackContent = .loading
        self.feedbackShownAt = Date()
        self.feedbackReturnStep = returnStep
        self.loadingDidFail = false
        self.credentialSubmitted = false
        self.scheduleFeedbackStallTimeout()
    }

    /// Guards against a silently hung connect: if the feedback step is still loading after two minutes
    /// (no pairing/auth/error surfaced, no gateway response), surface the error state so the user can retry.
    private func scheduleFeedbackStallTimeout() {
        self.feedbackTimeoutTask?.cancel()
        self.feedbackTimeoutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(120))
            guard !Task.isCancelled else { return }
            guard self.step == .feedback, case .loading = self.feedbackContent else { return }
            self.loadingDidFail = true
            self.refreshOnboardingFeedback()
        }
    }

    private var inferredCompletionMode: OnboardingConnectionMode {
        let host = (self.setupLinkStaging.link?.host
            ?? self.manualEndpointOverride?.host
            ?? "").lowercased()
        if host.hasSuffix(".local") || host.hasPrefix("192.168.") || host.hasPrefix("10.") {
            return .homeNetwork
        }
        return .remoteDomain
    }

    private func applyingManualEndpointOverride(to link: GatewayConnectDeepLink) -> GatewayConnectDeepLink {
        guard let override = self.manualEndpointOverride else { return link }
        let host = override.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = Int(override.port.trimmingCharacters(in: .whitespacesAndNewlines)) ?? link.port
        guard !host.isEmpty, host != link.host || port != link.port else { return link }
        return GatewayConnectDeepLink(
            host: host,
            port: port,
            tls: link.tls,
            bootstrapToken: link.bootstrapToken,
            token: link.token,
            password: link.password,
            fallbackEndpoints: [])
    }

    private func applySetupCodeAndConnect() async {
        self.setupCodeStatus = nil
        let raw = self.setupCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            self.setupCodeStatus = "Paste a setup code to continue."
            return
        }
        self.clearStagedGatewaySetupLink()

        if AppleReviewDemoMode.isSetupCode(raw) {
            self.setupCode = ""
            self.setupCodeStatus = "Apple Review demo mode enabled."
            self.handleScannedSetupCode(raw)
            return
        }

        guard let scannedLink = GatewayConnectDeepLink.fromSetupInput(raw) else {
            self.setupCodeStatus = "Setup code not recognized or uses an insecure ws:// gateway URL."
            return
        }
        let parsedLink = self.applyingManualEndpointOverride(to: scannedLink)

        guard let attemptID = self.beginSetupAttempt() else { return }
        defer { self.finishSetupAttempt(attemptID) }
        let link = await self.gatewayController.selectReachableSetupLink(parsedLink)
        guard self.setupAttemptID == attemptID else { return }

        await self.applyGatewayLink(link)
        self.setupCode = ""
        self.setupCodeStatus = "Setup code applied. Connecting…"
        self.connectMessage = "Connecting via setup code…"
        self.statusLine = "Setup code loaded. Connecting to \(link.host):\(link.port)…"
        await self.prepareFocusedFieldForStepTransition()
        self.resetFeedbackForNewAttempt(returnStep: .welcome)
        self.navigate(to: .feedback)
        await self.connectManual(setupAttemptID: attemptID)
    }

    private func queueScannedResult(_ result: QRScannerResult, scanID: UInt64) {
        guard self.scannerResultHandoff.queue(result, scanID: scanID) else { return }
        self.statusLine = "QR loaded. Closing scanner..."
        self.showQRScanner = false
    }

    private func processQueuedScannerResult() {
        let delivery = self.scannerResultHandoff.processAfterDismissal { result in
            switch result {
            case let .gatewayLink(link):
                self.handleScannedLink(link)
            case let .setupCode(code):
                self.handleScannedSetupCode(code)
            }
        }
        if delivery == nil {
            self.pendingTargetSuppression.resumeAutoConnect(.qrScanner, controller: self.gatewayController)
        }
    }

    private func handleScannedLink(_ link: GatewayConnectDeepLink) {
        self.showQRScanner = false
        guard let attemptID = self.beginSetupAttempt() else { return }
        self.setupCodeStatus = nil
        Task { await self.connectScannedLink(link, attemptID: attemptID) }
    }

    private func connectScannedLink(_ parsedLink: GatewayConnectDeepLink, attemptID: UUID) async {
        defer {
            self.finishSetupAttempt(attemptID)
            self.pendingTargetSuppression.resumeAutoConnect(.qrScanner, controller: self.gatewayController)
        }
        let link = await self.gatewayController.selectReachableSetupLink(parsedLink)
        guard self.setupAttemptID == attemptID else { return }
        await self.applyGatewayLink(link)
        self.connectMessage = "Connecting via setup code…"
        self.statusLine = "Setup code loaded. Connecting to \(link.host):\(link.port)…"
        self.resetFeedbackForNewAttempt(returnStep: .welcome)
        self.navigate(to: .feedback)
        await self.connectManual(setupAttemptID: attemptID)
    }

    private func applyPendingGatewaySetupLinkIfNeeded() {
        guard let link = self.appModel.consumePendingGatewaySetupLink() else { return }
        self.showQRScanner = false
        self.scannerResultHandoff.cancel()
        self.showGatewayProblemDetails = false
        let lease = self.gatewayController.cancelPendingConnectionAttempts()
        self.pendingTargetSuppression.replace(owner: .setupLink, lease: lease)
        if self.selectedMode == nil {
            self.selectedMode = link.tls ? .remoteDomain : .homeNetwork
        }
        self.setupLinkStaging.stage(link)
        self.setupCodeStatus = "Setup link loaded for \(link.host):\(link.port). Tap Connect to apply."
        self.connectMessage = nil
        self.statusLine = self.setupCodeStatus ?? ""
        self.resetFeedbackForNewAttempt(returnStep: .welcome)
        self.navigate(to: .feedback)
    }

    private func connectStagedGatewaySetupLink() async {
        guard self.connectingGatewayID == nil else { return }
        guard let link = self.setupLinkStaging.link else { return }
        guard link.isValidEndpoint else {
            let message = "Setup link has an invalid gateway endpoint."
            self.setupCodeStatus = message
            self.statusLine = message
            return
        }
        self.connectingGatewayID = "manual"
        defer { self.connectingGatewayID = nil }
        let lease = self.gatewayController.cancelPendingConnectionAttempts()
        self.pendingTargetSuppression.replace(owner: .setupLink, lease: lease)
        defer { self.pendingTargetSuppression.resumeAutoConnect(.setupLink, controller: self.gatewayController) }
        await self.appModel.resetGatewaySessionsForTargetSwitch()
        guard self.setupLinkStaging.link == link else { return }
        _ = self.setupLinkStaging.take()
        await self.applyGatewayLink(link, disconnectExistingGatewayForBootstrap: false)
        self.setupCodeStatus = "Setup link applied. Connecting…"
        self.issue = .none
        self.connectMessage = "Connecting to \(link.host)…"
        self.statusLine = "Connecting to \(link.host):\(link.port)…"
        await self.connectCurrentManualGateway(host: link.host, port: link.port, forceReconnect: false)
    }

    private func clearStagedGatewaySetupLink() {
        guard self.setupLinkStaging.cancel() else { return }
        self.pendingTargetSuppression.resumeAutoConnect(.setupLink, controller: self.gatewayController)
        let message = "Setup link cleared."
        self.setupCodeStatus = message
        self.statusLine = message
    }

    private func applyGatewayLink(
        _ link: GatewayConnectDeepLink,
        disconnectExistingGatewayForBootstrap: Bool = true) async
    {
        self.manualHost = link.host
        self.manualPort = link.port
        self.manualPortText = String(link.port)
        self.manualTLS = link.tls
        let setupAuth = GatewayConnectionController.ManualAuthOverride.setupAuth(from: link)
        self.gatewayCredentialFieldStableID = setupAuth.targetStableID
        if setupAuth.hasBootstrapToken {
            await GatewayOnboardingReset.prepareForBootstrapPairing(
                appModel: self.appModel,
                instanceId: GatewaySettingsStore.currentInstanceID(),
                gatewayStableID: setupAuth.targetStableID,
                disconnectGateway: disconnectExistingGatewayForBootstrap)
        }
        self.gatewayToken = setupAuth.token
        self.gatewayPassword = setupAuth.password
        self.pendingManualAuthOverride = setupAuth.manualAuthOverride
        let instanceId = GatewaySettingsStore.currentInstanceID()
        if !instanceId.isEmpty {
            GatewaySettingsStore.saveGatewayCredentials(
                token: setupAuth.token,
                bootstrapToken: setupAuth.bootstrapToken,
                password: setupAuth.password,
                gatewayStableID: setupAuth.targetStableID,
                suppressStoredDeviceAuth: true,
                instanceId: instanceId)
        }
        if self.selectedMode == nil {
            self.selectedMode = link.tls ? .remoteDomain : .homeNetwork
        }
    }

    private func handleScannedSetupCode(_ code: String) {
        guard AppleReviewDemoMode.isSetupCode(code) else { return }
        self.showQRScanner = false
        self.invalidateSetupAttempt()
        self.connectMessage = "Apple Review demo mode enabled."
        self.statusLine = "Apple Review demo mode enabled."
        self.selectedMode = .homeNetwork
        self.appModel.enterAppleReviewDemoMode()
        self.pendingTargetSuppression.releaseAutoConnect(.qrScanner, controller: self.gatewayController)
    }

    private func openQRScannerFromOnboarding(status: String = "Opening QR scanner…") {
        // Stop active reconnect loops before scanning new credentials.
        self.invalidateSetupAttempt()
        let lease = self.gatewayController.cancelPendingConnectionAttempts(suspendCurrentGateway: true)
        _ = self.setupLinkStaging.cancel()
        self.pendingTargetSuppression.replace(owner: .qrScanner, lease: lease)
        self.scannerScanID = self.scannerResultHandoff.beginScan()
        self.connectingGatewayID = nil
        self.connectMessage = nil
        self.issue = .none
        self.pairingRequestId = nil
        self.statusLine = status
        self.showQRScanner = true
    }

    private func resumeAfterPairingApproval() {
        // We intentionally stop reconnect churn while unpaired to avoid generating multiple pending requests.
        self.appModel.gatewayAutoReconnectEnabled = true
        self.appModel.gatewayPairingPaused = false
        self.appModel.gatewayPairingRequestId = nil
        // Pairing state is sticky to prevent UI flip-flop during reconnect churn.
        // Once the user explicitly resumes after approving, clear the sticky issue
        // so new status/auth errors can surface instead of being masked as pairing.
        self.issue = .none
        self.connectMessage = "Retrying after approval…"
        self.statusLine = "Retrying after approval…"
        Task { await self.retryLastAttempt() }
    }

    private func resumeAfterPairingApprovalInBackground() {
        // Keep the pairing issue sticky to avoid visual flicker while we probe for approval.
        self.appModel.gatewayAutoReconnectEnabled = true
        self.appModel.gatewayPairingPaused = false
        self.appModel.gatewayPairingRequestId = nil
        Task { await self.retryLastAttempt(silent: true) }
    }

    private func attemptAutomaticPairingResumeIfNeeded() {
        guard self.scenePhase == .active else { return }
        guard self.step == .feedback else { return }
        guard self.issue.needsPairing else { return }
        guard self.connectingGatewayID == nil else { return }

        let now = Date()
        if let last = lastPairingAutoResumeAttemptAt, now.timeIntervalSince(last) < 6 {
            return
        }
        self.lastPairingAutoResumeAttemptAt = now
        self.resumeAfterPairingApprovalInBackground()
    }

    private func updateConnectionIssue(problem: GatewayConnectionProblem?, statusText: String) {
        let next = GatewayConnectionIssue.detect(problem: problem)
        let fallback = next == .none ? GatewayConnectionIssue.detect(from: statusText) : next

        // Avoid "flip-flopping" the UI by clearing actionable issues when the underlying connection
        // transitions through intermediate statuses (e.g. Offline/Connecting while reconnect churns).
        if self.issue.needsPairing, fallback.needsPairing {
            let mergedRequestId = fallback.requestId ?? self.issue.requestId ?? self.pairingRequestId
            self.issue = .pairingRequired(requestId: mergedRequestId)
        } else if self.issue.needsPairing, !fallback.needsPairing {
            // Ignore non-pairing statuses until the user explicitly retries/scans again, or we connect.
        } else if self.issue.needsAuthToken, !fallback.needsAuthToken, !fallback.needsPairing {
            // Same idea for auth: once we learn credentials are missing/rejected, keep that sticky until
            // the user retries/scans again or we successfully connect.
        } else {
            self.issue = fallback
        }

        if let requestId = problem?.requestId ?? fallback.requestId, !requestId.isEmpty {
            self.pairingRequestId = requestId
        }

        if self.issue.needsAuthToken || self.issue.needsPairing || problem?.pauseReconnect == true {
            // Route actionable outcomes into the redesigned feedback step; a background reconnect that
            // surfaces one from .welcome/.intro resets to loading first, an in-flight attempt keeps its
            // existing feedback timeline so the state transition stays smooth.
            if self.step != .feedback {
                self.resetFeedbackForNewAttempt(returnStep: self.step)
                self.step = .feedback
            }
            self.refreshOnboardingFeedback()
        }

        if let problem {
            self.connectMessage = problem.message
            self.statusLine = problem.message
            return
        }

        let trimmedStatus = statusText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedStatus.isEmpty {
            self.connectMessage = trimmedStatus
            self.statusLine = trimmedStatus
        }
    }

    private func detectQRCode(from data: Data) -> String? {
        guard let ciImage = CIImage(data: data) else { return nil }
        let detector = CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let features = detector?.features(in: ciImage) ?? []
        for feature in features {
            if let qr = feature as? CIQRCodeFeature, let message = qr.messageString {
                return message
            }
        }
        return nil
    }

    private func advanceFromIntro() {
        OnboardingStateStore.markFirstRunIntroSeen()
        self.requestLocalNetworkAccess(reason: "onboarding_continue")
        self.statusLine = ""
        self.navigate(to: .welcome)
    }

    private func requestLocalNetworkAccessIfPastIntro(reason: String) {
        guard self.step != .intro else { return }
        self.requestLocalNetworkAccess(reason: reason)
    }

    private func requestLocalNetworkAccess(reason: String) {
        self.onRequestLocalNetworkAccess(reason)
    }

    private func navigateBack() {
        guard let target = step.previous else { return }
        self.invalidateSetupAttempt()
        self.connectMessage = nil
        self.navigate(to: target)
    }

    private func prepareFocusedFieldForStepTransition() async {
        guard self.focusedField != nil else { return }
        self.dismissKeyboard()
        await Task.yield()
        try? await Task.sleep(nanoseconds: 120_000_000)
    }

    private func dismissKeyboard() {
        self.focusedField = nil
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil)
    }

    private func navigate(to target: OnboardingStep) {
        self.focusedField = nil
        self.step = target
    }

    private func beginSetupAttempt() -> UUID? {
        guard self.connectingGatewayID == nil else { return nil }
        let attemptID = UUID()
        self.setupAttemptID = attemptID
        self.connectingGatewayID = "setup-code"
        return attemptID
    }

    private func finishSetupAttempt(_ attemptID: UUID) {
        guard self.setupAttemptID == attemptID else { return }
        self.invalidateSetupAttempt()
    }

    private func invalidateSetupAttempt() {
        self.setupAttemptID = nil
        self.connectingGatewayID = nil
    }

    private var canConnectManual: Bool {
        let host = self.manualHost.trimmingCharacters(in: .whitespacesAndNewlines)
        return !host.isEmpty && self.resolvedManualPort(host: host) != nil
    }

    private func initializeState() {
        if self.manualHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let active = GatewaySettingsStore.activeGatewayEntry(),
               active.kind == .manual,
               let host = active.host,
               let port = active.port
            {
                self.manualHost = host
                self.manualPort = port
                self.manualTLS = active.useTLS
            } else {
                self.manualHost = "openclaw.local"
                self.manualPort = 18789
                self.manualTLS = true
            }
        }
        self.manualPortText = self.manualPort > 0 ? String(self.manualPort) : ""
        if self.selectedMode == nil {
            let lastMode = OnboardingStateStore.lastMode()
            if lastMode == .developerLocal {
                self.developerModeEnabled = true
            }
            if self.developerModeEnabled || lastMode != .developerLocal {
                self.selectedMode = lastMode
            }
        }
        if self.selectedMode == .developerLocal, self.manualHost == "openclaw.local" {
            self.manualHost = "localhost"
            self.manualTLS = false
        }

        let trimmedInstanceId = self.instanceId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedInstanceId.isEmpty,
           let stableID = self.currentManualGatewayStableID
        {
            let credentials = GatewaySettingsStore.loadGatewayCredentials(
                instanceId: trimmedInstanceId,
                gatewayStableID: stableID)
            let ownsFields = credentials.hasCredentials || credentials.suppressStoredDeviceAuth
            self.gatewayCredentialFieldStableID = ownsFields ? stableID : nil
            self.gatewayToken = credentials.token ?? ""
            self.gatewayPassword = credentials.password ?? ""
            self.pendingManualAuthOverride = GatewayConnectionController.ManualAuthOverride.persisted(
                instanceId: trimmedInstanceId,
                targetStableID: stableID)
        }

        let hasSavedGateway = GatewaySettingsStore.activeGatewayEntry() != nil
        let hasToken = !self.gatewayToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasPassword = !self.gatewayPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !hasSavedGateway, !hasToken, !hasPassword {
            self.statusLine = ""
        }
    }

    private func scheduleDiscoveryRestart() {
        self.discoveryRestartTask?.cancel()
        self.discoveryRestartTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            self.gatewayController.restartDiscovery()
        }
    }

    private var currentManualGatewayStableID: String? {
        let host = self.manualHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, let port = self.resolvedManualPort(host: host) else { return nil }
        return GatewayConnectionController.ManualAuthOverride.manualStableID(
            host: host,
            port: port)
    }

    private var gatewayCredentialTargetStableID: String? {
        // Auth fields follow the selected route. Otherwise a discovered-gateway retry can save
        // credentials under the unrelated manual endpoint and immediately reload an empty bundle.
        self.gatewayCredentialFieldStableID ?? self.currentManualGatewayStableID
    }

    private func resolvedManualPort(host: String) -> Int? {
        guard self.manualPortText.isEmpty || self.manualPort > 0 else { return nil }
        return GatewayConnectionController.resolvedManualPort(
            host: host,
            port: self.manualPort)
    }

    private var gatewayTokenBinding: Binding<String> {
        Binding(
            get: { self.gatewayToken },
            set: { self.persistGatewayToken($0) })
    }

    private var gatewayPasswordBinding: Binding<String> {
        Binding(
            get: { self.gatewayPassword },
            set: { self.persistGatewayPassword($0) })
    }

    /// The auth screen's single field. It reads whichever slot currently holds a value and routes new
    /// input into the slot the gateway asks for, so a password is never sent in the token slot.
    private var gatewayCredentialBinding: Binding<String> {
        Binding(
            get: { self.gatewayPassword.isEmpty ? self.gatewayToken : self.gatewayPassword },
            set: { value in
                if self.gatewayRequiresPassword {
                    self.persistGatewayPassword(value)
                } else {
                    self.persistGatewayToken(value)
                }
            })
    }

    /// When the gateway discloses its auth method (e.g. a stale setup-link token is rejected and it then
    /// reports a password is required), carry the already-typed credential into the newly detected slot
    /// so the single field keeps it and the next connect sends it the right way. Returns whether a value
    /// actually moved slots.
    @discardableResult
    private func migrateCredentialToDetectedMethod(requiresPassword: Bool) -> Bool {
        if requiresPassword, self.gatewayPassword.isEmpty, !self.gatewayToken.isEmpty {
            self.persistGatewayPassword(self.gatewayToken)
            return true
        }
        if !requiresPassword, self.gatewayToken.isEmpty, !self.gatewayPassword.isEmpty {
            self.persistGatewayToken(self.gatewayPassword)
            return true
        }
        return false
    }

    private var manualHostBinding: Binding<String> {
        Binding(
            get: { self.manualHost },
            set: { value in
                let previousStableID = self.currentManualGatewayStableID
                self.manualHost = value
                if previousStableID != self.currentManualGatewayStableID {
                    self.clearManualCredentialFields()
                }
            })
    }

    private var manualPortTextBinding: Binding<String> {
        Binding(
            get: { self.manualPortText },
            set: { value in
                let previousStableID = self.currentManualGatewayStableID
                let digits = value.filter(\.isNumber)
                self.manualPortText = digits
                self.manualPort = min(Int(digits) ?? 0, 65535)
                if previousStableID != self.currentManualGatewayStableID {
                    self.clearManualCredentialFields()
                }
            })
    }

    private func persistGatewayToken(_ value: String) {
        self.gatewayToken = value
        // A typed token is the sole auth method for this endpoint: drop the competing password so the
        // two single-field auth modes never send conflicting credentials.
        self.gatewayPassword = ""
        // Editing the credential clears the rejected/error state so the field returns to normal.
        self.credentialSubmitted = false
        self.persistExclusiveCredential(token: value, password: nil)
    }

    private func persistGatewayPassword(_ value: String) {
        self.gatewayPassword = value
        // A typed password is the sole auth method for this endpoint. Drop the setup-link token so it
        // cannot win the gateway's auth-frame precedence (token > bootstrap > password) and leave the
        // password unevaluated — the gateway would keep reporting "password missing" no matter what.
        self.gatewayToken = ""
        // Editing the credential clears the rejected/error state so the field returns to normal.
        self.credentialSubmitted = false
        self.persistExclusiveCredential(token: nil, password: value)
    }

    /// Persists a single explicit credential as the only auth for this endpoint, clearing any staged
    /// setup-link bootstrap token so the typed token/password is the sole value sent on the next connect.
    private func persistExclusiveCredential(token: String?, password: String?) {
        let instanceId = GatewaySettingsStore.currentInstanceID()
        guard !instanceId.isEmpty, let stableID = self.gatewayCredentialTargetStableID else { return }
        self.gatewayCredentialFieldStableID = stableID
        let saved = GatewaySettingsStore.saveGatewayCredentials(
            token: token,
            bootstrapToken: nil,
            password: password,
            gatewayStableID: stableID,
            suppressStoredDeviceAuth: true,
            instanceId: instanceId)
        self.pendingManualAuthOverride = saved
            ? GatewayConnectionController.ManualAuthOverride.persisted(
                instanceId: instanceId,
                targetStableID: stableID)
            : nil
    }

    private func clearManualCredentialFields() {
        self.gatewayToken = ""
        self.gatewayPassword = ""
        self.gatewayCredentialFieldStableID = nil
        self.pendingManualAuthOverride = nil
    }

    private func selectGatewayCredentialTarget(_ stableID: String, allowManualOverride: Bool) {
        let instanceId = GatewaySettingsStore.currentInstanceID()
        if self.gatewayCredentialFieldStableID != stableID {
            let credentials = GatewaySettingsStore.loadGatewayCredentials(
                instanceId: instanceId,
                gatewayStableID: stableID)
            self.gatewayCredentialFieldStableID = stableID
            self.gatewayToken = credentials.token ?? ""
            self.gatewayPassword = credentials.password ?? ""
        }
        guard allowManualOverride else {
            self.pendingManualAuthOverride = nil
            return
        }
        // Each attempt consumes the in-memory override. Reload durable bootstrap auth even
        // when the endpoint fields did not change so retry never erases a one-time token.
        self.pendingManualAuthOverride = GatewayConnectionController.ManualAuthOverride.persisted(
            instanceId: instanceId,
            targetStableID: stableID)
    }

    private func connectDiscoveredGateway(_ gateway: GatewayDiscoveryModel.DiscoveredGateway) async {
        self.selectGatewayCredentialTarget(gateway.stableID, allowManualOverride: false)
        self.connectingGatewayID = gateway.id
        self.issue = .none
        self.connectMessage = "Connecting to \(gateway.name)…"
        self.statusLine = "Connecting to \(gateway.name)…"
        defer { self.connectingGatewayID = nil }
        await self.gatewayController.connect(gateway)
    }

    private func selectMode(_ mode: OnboardingConnectionMode) {
        self.selectedMode = mode
        self.applyModeDefaults(mode)
    }

    private func applyModeDefaults(_ mode: OnboardingConnectionMode) {
        let previousStableID = self.currentManualGatewayStableID
        defer {
            if previousStableID != self.currentManualGatewayStableID {
                self.clearManualCredentialFields()
            }
        }
        let host = self.manualHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hostIsDefaultLike = host.isEmpty || host == "openclaw.local" || host == "localhost"

        switch mode {
        case .homeNetwork:
            if hostIsDefaultLike {
                self.manualHost = "openclaw.local"
            }
            self.manualTLS = true
            if self.manualPort <= 0 || self.manualPort > 65535 {
                self.manualPort = 18789
            }
        case .remoteDomain:
            if host == "openclaw.local" || host == "localhost" {
                self.manualHost = ""
            }
            self.manualTLS = true
            if self.manualPort <= 0 || self.manualPort > 65535 {
                self.manualPort = 18789
            }
        case .developerLocal:
            if hostIsDefaultLike {
                self.manualHost = "localhost"
            }
            self.manualTLS = false
            if self.manualPort <= 0 || self.manualPort > 65535 {
                self.manualPort = 18789
            }
        }
    }

    private func gatewayHasResolvableHost(_ gateway: GatewayDiscoveryModel.DiscoveredGateway) -> Bool {
        let lanHost = gateway.lanHost?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !lanHost.isEmpty {
            return true
        }
        let tailnetDns = gateway.tailnetDns?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !tailnetDns.isEmpty
    }

    private func connectManual(setupAttemptID: UUID? = nil) async {
        if let setupAttemptID {
            guard self.setupAttemptID == setupAttemptID else { return }
        } else {
            self.invalidateSetupAttempt()
        }
        let host = self.manualHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, let port = self.resolvedManualPort(host: host) else { return }
        self.connectingGatewayID = "manual"
        self.issue = .none
        self.connectMessage = "Connecting to \(host)…"
        self.statusLine = "Connecting to \(host):\(port)…"
        defer { self.connectingGatewayID = nil }
        await self.connectCurrentManualGateway(host: host, port: port, forceReconnect: false)
    }

    private func connectCurrentManualGateway(host: String, port: Int, forceReconnect: Bool) async {
        let stableID = GatewayConnectionController.ManualAuthOverride.manualStableID(
            host: host,
            port: port)
        self.selectGatewayCredentialTarget(stableID, allowManualOverride: true)
        if self.appModel.activeGatewayConnectConfig?.effectiveStableID == stableID,
           self.appModel.activeGatewayConnectConfig?.nodeOptions.allowStoredDeviceAuth == true
        {
            self.pendingManualAuthOverride = nil
        }
        let fieldsMatchTarget = self.gatewayCredentialFieldStableID == stableID
        let pendingOverride = self.pendingManualAuthOverride?.targetStableID == stableID
            ? self.pendingManualAuthOverride
            : nil
        let authOverride = GatewayConnectionController.ManualAuthOverride.currentManualInput(
            token: fieldsMatchTarget ? self.gatewayToken : nil,
            pendingOverride: pendingOverride,
            password: fieldsMatchTarget ? self.gatewayPassword : nil,
            targetStableID: stableID)
        let instanceId = GatewaySettingsStore.currentInstanceID()
        if !instanceId.isEmpty, fieldsMatchTarget || pendingOverride != nil {
            GatewaySettingsStore.saveGatewayCredentials(
                token: authOverride?.token,
                bootstrapToken: authOverride?.bootstrapToken,
                password: authOverride?.password,
                gatewayStableID: stableID,
                suppressStoredDeviceAuth: authOverride?.suppressStoredDeviceAuth == true,
                instanceId: instanceId)
        }
        await self.gatewayController.connectManual(
            host: host,
            port: port,
            useTLS: self.manualTLS,
            authOverride: authOverride,
            forceReconnect: forceReconnect)
        // The controller now owns this attempt's immutable override. A later retry must reload
        // durable state so a spent bootstrap token cannot be resurrected from the live view.
        self.pendingManualAuthOverride = nil
    }

    private func retryLastAttempt(silent: Bool = false) async {
        self.connectingGatewayID = silent ? "retry-auto" : "retry"
        // Keep current auth/pairing issue sticky while retrying to avoid Step 3 UI flip-flop.
        if !silent {
            self.connectMessage = "Retrying…"
            self.statusLine = "Retrying last connection…"
        }
        defer { self.connectingGatewayID = nil }

        switch GatewaySettingsStore.activeGatewayEntry()?.kind {
        case .discovered:
            await self.gatewayController.connectActiveGateway()
        case .manual, .none:
            // connectActiveGateway() replays the persisted endpoint and credentials,
            // so token/host/port edits made on this screen would be ignored and
            // a missing stored connection would silently do nothing. Manual
            // retries must dial the current form input instead.
            let host = self.manualHost.trimmingCharacters(in: .whitespacesAndNewlines)
            if !host.isEmpty, let port = self.resolvedManualPort(host: host) {
                await self.connectCurrentManualGateway(host: host, port: port, forceReconnect: true)
                return
            }
            if !silent {
                self.connectMessage = nil
                self.statusLine = "No connection to retry. Check the gateway host and port."
            }
        }
    }

    private func gatewayProblemPrimaryActionTitle(_ problem: GatewayConnectionProblem) -> String? {
        GatewayProblemPrimaryAction.title(
            for: problem,
            retryTitle: "Retry connection",
            resetTitle: "Scan QR again")
    }

    private func handleGatewayProblemPrimaryAction(_ problem: GatewayConnectionProblem) async {
        if problem.suggestsOnboardingReset {
            await GatewayOnboardingReset.reset(appModel: self.appModel, instanceId: self.instanceId)
            self.gatewayToken = ""
            self.gatewayPassword = ""
            self.gatewayCredentialFieldStableID = nil
            self.pendingManualAuthOverride = nil
            self.connectingGatewayID = nil
            self.connectMessage = nil
            self.issue = .none
            self.pairingRequestId = nil
            self.resetFeedbackForNewAttempt(returnStep: .welcome)
            self.navigate(to: .feedback)
            self.openQRScannerFromOnboarding(status: "Scan a fresh setup QR code from this gateway.")
            return
        }
        if problem.canTrustRotatedCertificate {
            self.connectingGatewayID = "trust-certificate"
            self.connectMessage = "Updating gateway certificate…"
            self.statusLine = "Updating gateway certificate…"
            defer { self.connectingGatewayID = nil }
            _ = await self.gatewayController.trustRotatedGatewayCertificate(from: problem)
            return
        }
        if GatewayProblemPrimaryAction.handleProtocolMismatchIfNeeded(problem) {
            return
        }
        guard problem.retryable else { return }
        await self.retryLastAttempt()
    }
}
