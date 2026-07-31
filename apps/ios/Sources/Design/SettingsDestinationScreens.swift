import AVFAudio
import AVFoundation
import Contacts
import CoreLocation
import EventKit
import OpenClawKit
import OpenClawProtocol
import Photos
import SwiftUI
import UserNotifications

// MARK: - Shared destination chrome

/// Header + canvas shared by the pushed Settings destinations: SF Pro medium title, neutral glass
/// back button (matching the chat floating buttons and the Settings root), adaptive canvas.
struct SettingsDestinationChrome<Content: View>: View {
    let title: String
    let onBack: () -> Void
    @ViewBuilder let content: Content

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .top) {
            self.canvas.ignoresSafeArea()
            self.content
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            self.header
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        ZStack {
            // Design calls for SF Pro medium here, not the branded Display face.
            Text(self.title)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.primary)
            HStack {
                Button(action: self.onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .frame(width: 40, height: 40)
                        .background { ChatGlassBackground(shape: Circle(), fill: self.glassFill) }
                        .shadow(color: .black.opacity(0.15), radius: 25, x: 0, y: 0)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .padding(.top, 8)
        .padding(.bottom, 21)
    }

    private var canvas: Color {
        self.colorScheme == .dark
            ? Color(red: 23 / 255, green: 23 / 255, blue: 23 / 255)
            : Color(red: 245 / 255, green: 244 / 255, blue: 250 / 255)
    }

    private var glassFill: Color {
        self.colorScheme == .dark
            ? Color(red: 30 / 255, green: 30 / 255, blue: 30 / 255).opacity(0.2)
            : Color(red: 245 / 255, green: 244 / 255, blue: 250 / 255).opacity(0.2)
    }
}

// MARK: - Approvals (empty state; populated design pending)

struct ApprovalsScreen: View {
    let onBack: () -> Void

    var body: some View {
        SettingsDestinationChrome(title: "Approvals", onBack: self.onBack) {
            VStack {
                Text("No approvals yet.")
                    .font(OpenClawType.body)
                    .foregroundStyle(Color.primary)
                    .padding(.top, 32)
                Spacer()
            }
        }
    }
}

// MARK: - Permissions

struct PermissionsScreen: View {
    let onBack: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @State private var statuses = PermissionStatuses()

    var body: some View {
        SettingsDestinationChrome(title: "Permissions", onBack: self.onBack) {
            ScrollView {
                VStack(spacing: 17) {
                    self.row("PermissionsPinGlyph", "Location", self.statuses.location)
                    self.divider
                    self.row("PermissionsCalendarGlyph", "Calendar", self.statuses.calendar)
                    self.divider
                    self.row("PermissionsClipboardGlyph", "Reminders", self.statuses.reminders)
                    self.divider
                    self.row("PermissionsContactGlyph", "Contacts", self.statuses.contacts)
                    self.divider
                    self.row("ChatMicGlyph", "Microphone", self.statuses.microphone)
                    self.divider
                    self.row("PermissionsImageGlyph", "Photos", self.statuses.photos)
                    self.divider
                    self.row("ChatCameraGlyph", "Camera", self.statuses.camera)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 12)
                .background {
                    RoundedRectangle(cornerRadius: 25, style: .continuous)
                        .fill(self.cardFill)
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
            }
        }
        .onAppear { self.statuses.refresh() }
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification))
        { _ in
            self.statuses.refresh() // reflect changes made in Settings.app
        }
    }

    /// 0.3 crisp single-pixel hairline, centered between 17pt-spaced rows (shared Settings token).
    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.3))
            .frame(maxWidth: .infinity)
            .frame(height: 1 / self.displayScale)
            .padding(.leading, 34)
    }

    private var cardFill: Color {
        self.colorScheme == .dark
            ? Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255)
            : .white
    }

    private func row(_ icon: String, _ title: String, _ value: String) -> some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 12) {
                Image(icon)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .foregroundStyle(Color.primary.opacity(0.7))
                Text(title)
                    .font(OpenClawType.body)
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 0)
                Text(value)
                    .font(OpenClawType.callout)
                    .foregroundStyle(Color.primary.opacity(0.6))
                Image("SettingsChevronRightGlyph")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(Color.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Read-only snapshot of the system permission authorization states shown on `PermissionsScreen`.
/// Reading these does not prompt; tapping a row opens Settings.app.
@Observable
final class PermissionStatuses {
    var location = "Never"
    var calendar = "Not allowed"
    var reminders = "Not allowed"
    var contacts = "Never"
    var microphone = "Never"
    var photos = "Never"
    var camera = "Never"

    func refresh() {
        self.location = Self.locationLabel(CLLocationManager().authorizationStatus)
        self.calendar = Self.eventKitLabel(EKEventStore.authorizationStatus(for: .event))
        self.reminders = Self.eventKitLabel(EKEventStore.authorizationStatus(for: .reminder))
        self.contacts = Self.contactsLabel(CNContactStore.authorizationStatus(for: .contacts))
        self.microphone = Self.micLabel(AVAudioApplication.shared.recordPermission)
        self.photos = Self.photosLabel(PHPhotoLibrary.authorizationStatus(for: .readWrite))
        self.camera = Self.cameraLabel(AVCaptureDevice.authorizationStatus(for: .video))
    }

    private static func locationLabel(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .authorizedAlways: "Always"
        case .authorizedWhenInUse: "While Using"
        case .denied, .restricted: "Never"
        default: "Never"
        }
    }

    private static func eventKitLabel(_ status: EKAuthorizationStatus) -> String {
        switch status {
        case .fullAccess: "Allowed"
        case .writeOnly: "Write Only"
        case .denied, .restricted: "Not allowed"
        default: "Not allowed"
        }
    }

    private static func contactsLabel(_ status: CNAuthorizationStatus) -> String {
        switch status {
        case .authorized: "Allowed"
        case .limited: "Limited"
        case .denied, .restricted: "Never"
        default: "Never"
        }
    }

    private static func micLabel(_ permission: AVAudioApplication.recordPermission) -> String {
        switch permission {
        case .granted: "While Using"
        case .denied: "Never"
        default: "Never"
        }
    }

    private static func photosLabel(_ status: PHAuthorizationStatus) -> String {
        switch status {
        case .authorized: "Always Allowed"
        case .limited: "Limited"
        case .denied, .restricted: "Never"
        default: "Never"
        }
    }

    private static func cameraLabel(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized: "While Using"
        case .denied, .restricted: "Never"
        default: "Never"
        }
    }
}

// MARK: - Notifications

struct NotificationsScreen: View {
    let onBack: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var authorized = false

    var body: some View {
        SettingsDestinationChrome(title: "Notifications", onBack: self.onBack) {
            ScrollView {
                Button(action: self.requestOrOpenSettings) {
                    HStack {
                        Text("Allow Notifications")
                            .font(OpenClawType.body)
                            .foregroundStyle(OpenClawBrand.welcomeLink)
                        Spacer(minLength: 0)
                        Text(self.authorized ? "Enabled" : "Disabled")
                            .font(OpenClawType.callout)
                            .foregroundStyle(Color.primary.opacity(0.6))
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                    .background { Capsule(style: .continuous).fill(self.cardFill) }
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
            }
        }
        .onAppear { self.refreshAuthorization() }
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification))
        { _ in
            self.refreshAuthorization()
        }
    }

    private var cardFill: Color {
        self.colorScheme == .dark ? Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255) : .white
    }

    private func refreshAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            Task { @MainActor in
                self.authorized = status == .authorized || status == .provisional
            }
        }
    }

    private func requestOrOpenSettings() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            Task { @MainActor in
                switch status {
                case .notDetermined:
                    let granted = try? await UNUserNotificationCenter.current()
                        .requestAuthorization(options: [.alert, .badge, .sound])
                    self.authorized = granted == true
                default:
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        _ = await UIApplication.shared.open(url)
                    }
                }
            }
        }
    }
}

// MARK: - Channels

struct SettingsChannelItem: Identifiable, Equatable {
    let id: String
    let name: String
    let iconAsset: String? // nil → generic fallback glyph
    let isConnected: Bool
}

struct ChannelsScreen: View {
    let channels: [SettingsChannelItem]
    let hasAdminScope: Bool
    let onBack: () -> Void
    let onRemoveChannel: (SettingsChannelItem) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @State private var editing = false

    private static let destructiveRed = Color(red: 197 / 255, green: 62 / 255, blue: 56 / 255)
    private static let addChannelDocsURL = URL(string: "https://docs.openclaw.ai/start/getting-started")!

    var body: some View {
        ZStack(alignment: .top) {
            self.canvas.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 29) {
                    ForEach(self.channels) { channel in
                        self.channelPill(channel)
                    }
                    if self.hasAdminScope {
                        self.addChannelPill
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { self.header }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        ZStack {
            // Design calls for SF Pro medium here, not the branded Display face.
            Text("Channels")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.primary)
            HStack {
                Button(action: self.onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .frame(width: 40, height: 40)
                        .background { ChatGlassBackground(shape: Circle(), fill: self.glassFill) }
                }
                Spacer()
                if self.hasAdminScope, !self.channels.isEmpty {
                    Button {
                        withAnimation(.smooth(duration: 0.2)) { self.editing.toggle() }
                    } label: {
                        Text(self.editing ? "Done" : "Edit")
                            .font(OpenClawType.subhead)
                            .foregroundStyle(Color.primary)
                            .frame(width: 55, height: 33)
                            .background { ChatGlassBackground(fill: self.glassFill) }
                    }
                }
            }
            .padding(.horizontal, 24)
            .shadow(color: .black.opacity(0.15), radius: 25, x: 0, y: 0)
        }
        .padding(.top, 8)
        .padding(.bottom, 29)
    }

    private var canvas: Color {
        self.colorScheme == .dark
            ? Color(red: 23 / 255, green: 23 / 255, blue: 23 / 255)
            : Color(red: 245 / 255, green: 244 / 255, blue: 250 / 255)
    }

    private var glassFill: Color {
        self.colorScheme == .dark
            ? Color(red: 30 / 255, green: 30 / 255, blue: 30 / 255).opacity(0.2)
            : Color(red: 245 / 255, green: 244 / 255, blue: 250 / 255).opacity(0.2)
    }

    private var pillFill: Color {
        self.colorScheme == .dark ? Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255) : .white
    }

    private func channelPill(_ channel: SettingsChannelItem) -> some View {
        HStack(spacing: 12) {
            Group {
                if let asset = channel.iconAsset {
                    Image(asset) // full-color brand mark (Original)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image("SettingsUnplugGlyph") // generic fallback (template)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Color.primary.opacity(0.7))
                }
            }
            .frame(width: 22, height: 22)

            Text(channel.name)
                .font(OpenClawType.body)
                .foregroundStyle(Color.primary)
            Spacer(minLength: 0)

            if self.editing {
                Button {
                    OpenClawHaptics.error()
                    self.onRemoveChannel(channel)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Self.destructiveRed)
                }
            } else if channel.isConnected {
                Image("SetupCheckGlyph")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
            }
        }
        .padding(.horizontal, 17)
        .frame(height: 50)
        .background { Capsule(style: .continuous).fill(self.pillFill) }
    }

    private var addChannelPill: some View {
        Button {
            self.openURL(Self.addChannelDocsURL)
        } label: {
            HStack(spacing: 12) {
                Image("ChatPlusGlyph")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .foregroundStyle(OpenClawBrand.welcomeLink)
                Text("Add Channel")
                    .font(OpenClawType.body)
                    .foregroundStyle(OpenClawBrand.welcomeLink)
                Spacer(minLength: 0)
            }
            .padding(.leading, 17)
            .frame(height: 50)
            .background { Capsule(style: .continuous).fill(self.pillFill) }
        }
    }
}

/// Owns the gateway channel data and renders `ChannelsScreen`. Fetches `channels.status` and maps
/// entries to display items; "remove" logs out each of a channel's accounts (admin + connected gated).
struct ChannelsScreenHost: View {
    let onBack: () -> Void

    @Environment(NodeAppModel.self) private var appModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var snapshot: ChannelsStatusResult?
    @State private var busy = false

    var body: some View {
        ChannelsScreen(
            channels: self.channelItems,
            hasAdminScope: self.appModel.hasOperatorAdminScope,
            onBack: self.onBack,
            onRemoveChannel: { item in Task { await self.remove(item) } })
            .task(id: self.reloadKey) { await self.load() }
    }

    /// Re-fetch when the gateway connects or the app returns to the foreground.
    private var reloadKey: String {
        "\(self.appModel.isOperatorGatewayConnected)-\(self.scenePhase == .active)"
    }

    private var channelItems: [SettingsChannelItem] {
        guard let snapshot else { return [] }
        let ids = snapshot.channelorder.isEmpty ? snapshot.channels.keys.sorted() : snapshot.channelorder
        return ids.map { id in
            let accounts = snapshot.channelaccounts[id]?.arrayValue ?? []
            let connected = accounts.contains { account in
                let fields = account.dictionaryValue ?? [:]
                return fields["connected"]?.boolValue == true || fields["running"]?.boolValue == true
            }
            let name = snapshot.channellabels[id]?.stringValue ?? id.capitalized
            return SettingsChannelItem(
                id: id,
                name: name,
                iconAsset: Self.brandAsset(id),
                isConnected: connected)
        }
    }

    private static func brandAsset(_ id: String) -> String? {
        switch id.lowercased() {
        case "telegram": "ChannelTelegramGlyph"
        case "discord": "ChannelDiscordGlyph"
        case "whatsapp": "ChannelWhatsappGlyph"
        default: nil
        }
    }

    private func load() async {
        guard self.scenePhase == .active, self.appModel.isOperatorGatewayConnected else { return }
        do {
            let params = ChannelsStatusParams(probe: false, timeoutms: 10000, channel: nil)
            let data = try await self.request(method: "channels.status", params: params, timeoutSeconds: 12)
            self.snapshot = try JSONDecoder().decode(ChannelsStatusResult.self, from: data)
        } catch {
            // Keep the last snapshot; the screen shows what it already has.
        }
    }

    /// "Remove" = log out every account of the channel, then reload.
    private func remove(_ item: SettingsChannelItem) async {
        guard !self.busy, self.appModel.isOperatorGatewayConnected, self.appModel.hasOperatorAdminScope
        else { return }
        self.busy = true
        defer { self.busy = false }
        let accounts = self.snapshot?.channelaccounts[item.id]?.arrayValue ?? []
        let accountIDs = accounts.compactMap { $0.dictionaryValue?["accountId"]?.stringValue }
        let targets: [String?] = accountIDs.isEmpty ? [nil] : accountIDs.map { Optional($0) }
        for accountID in targets {
            let params = ChannelsLogoutParams(channel: item.id, accountid: accountID)
            _ = try? await self.request(method: "channels.logout", params: params, timeoutSeconds: 20)
        }
        await self.load()
    }

    private func request(method: String, params: some Encodable, timeoutSeconds: Int) async throws -> Data {
        let data = try JSONEncoder().encode(params)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return try await self.appModel.operatorSession.request(
            method: method,
            paramsJSON: json,
            timeoutSeconds: timeoutSeconds)
    }
}
