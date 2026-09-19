import SwiftUI

struct ConnectionGatewayRow: Identifiable, Equatable {
    let id: String // stableID
    let name: String
    let isFocused: Bool
}

/// The "Connection" card-sheet: paired gateways (radio-select with a switch confirmation), gateway
/// access level, and a destructive Disconnect. Follows the app theme (same adaptive palette as the
/// Settings root); accent colors are constant across light/dark.
struct ConnectionSheet: View {
    let gateways: [ConnectionGatewayRow]
    let hasFullAccess: Bool
    let onSelectGateway: (String) -> Void
    let onScanFullAccess: () -> Void
    let onDisconnect: () -> Void
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var confirmingDisconnect = false
    @State private var confirmingFullAccess = false
    @State private var pendingSwitch: ConnectionGatewayRow?

    private static let destructiveRed = Color(red: 197 / 255, green: 62 / 255, blue: 56 / 255)
    private static let radioBlue = Color(red: 37 / 255, green: 99 / 255, blue: 235 / 255)
    private static let noteRed = Color(red: 195 / 255, green: 63 / 255, blue: 51 / 255)

    var body: some View {
        ZStack(alignment: .top) {
            self.canvas.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Image("ConnectionMascotImage")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 139, height: 139)
                        // Clear the close button so the mascot sits below it (per the frames).
                        .padding(.top, 56)

                    Text("Clicking disconnect will clear all gateway credentials and reset onboarding.")
                        .font(OpenClawType.subhead)
                        .foregroundStyle(Color.primary.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .frame(width: 301)
                        .padding(.top, 22)

                    Button {
                        self.confirmingDisconnect = true
                    } label: {
                        // SF Pro medium per the design (not the branded Display face). White on the red
                        // capsule in both light and dark.
                        Text("Disconnect")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(height: 50)
                            .frame(maxWidth: .infinity)
                            .background { Capsule(style: .continuous).fill(Self.destructiveRed) }
                    }
                    .padding(.top, 24)

                    self.sectionLabel("Paired Gateways")
                        .padding(.top, 37)
                    self.pairedGatewaysCard
                        .padding(.top, 5)

                    self.sectionLabel("Gateway Access")
                        .padding(.top, 26)
                    self.accessRow
                        .padding(.top, 5)

                    if !self.hasFullAccess {
                        self.accessNote
                            .padding(.top, 12)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
            }
        }
        .overlay(alignment: .topLeading) { self.closeButton }
        .confirmationDialog(
            "Disconnect from this gateway?",
            isPresented: self.$confirmingDisconnect,
            titleVisibility: .visible)
        {
            Button(role: .destructive) { self.onDisconnect() } label: {
                Text("Disconnect").font(OpenClawType.body)
            }
            Button(role: .cancel) {} label: {
                Text("Cancel").font(OpenClawType.body)
            }
        } message: {
            Text("This clears saved gateway credentials and reopens onboarding.")
                .font(OpenClawType.subhead)
        }
    }

    private var switchConfirmationTitle: String {
        let name = self.pendingSwitch?.name ?? "this gateway"
        return "Switch to \(name)?"
    }

    private var switchConfirmationBinding: Binding<Bool> {
        Binding(
            get: { self.pendingSwitch != nil },
            set: { isPresented in
                if !isPresented {
                    self.pendingSwitch = nil
                }
            })
    }

    private func confirmPendingSwitch() {
        guard let gateway = self.pendingSwitch else { return }
        self.onSelectGateway(gateway.id)
    }

    // MARK: - Chrome

    private var closeButton: some View {
        Button(action: self.onClose) {
            Image("ChatCloseGlyph")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .foregroundStyle(Color.primary)
                .frame(width: 40, height: 40)
                // Liquid Glass + soft shadow, matching the chat floating buttons.
                .background { ChatGlassBackground(shape: Circle(), fill: self.glassFill) }
                .shadow(color: .black.opacity(0.15), radius: 25, x: 0, y: 0)
        }
        .padding(.leading, 25)
        .padding(.top, 22)
    }

    private func sectionLabel(_ text: String) -> some View {
        // SF Pro medium per the design (matches the Settings root section headers).
        Text(text)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(Color.primary.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 15)
    }

    // MARK: - Paired gateways

    private var pairedGatewaysCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(self.gateways.enumerated()), id: \.element.id) { index, gateway in
                Button {
                    guard !gateway.isFocused else { return }
                    OpenClawHaptics.tap()
                    self.pendingSwitch = gateway
                } label: {
                    HStack {
                        Text(gateway.name)
                            .font(OpenClawType.body)
                            .foregroundStyle(Color.primary)
                        Spacer(minLength: 0)
                        self.radio(filled: gateway.isFocused)
                    }
                    .frame(height: 51)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < self.gateways.count - 1 {
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(height: 0.5)
                }
            }
        }
        .padding(.horizontal, 15)
        .openClawSectionBackground(self.cardFill)
        .confirmationDialog(
            self.switchConfirmationTitle,
            isPresented: self.switchConfirmationBinding,
            titleVisibility: .visible)
        {
            Button { self.confirmPendingSwitch() } label: {
                Text("Switch").font(OpenClawType.body)
            }
            Button(role: .cancel) {} label: {
                Text("Cancel").font(OpenClawType.body)
            }
        } message: {
            Text("OpenClaw will reconnect to this gateway.")
                .font(OpenClawType.subhead)
        }
    }

    private func radio(filled: Bool) -> some View {
        ZStack {
            Circle()
                .strokeBorder(filled ? Self.radioBlue : Color.primary.opacity(0.5), lineWidth: 1.6)
            if filled {
                Circle()
                    .fill(Self.radioBlue)
                    .frame(width: 11, height: 11)
            }
        }
        .frame(width: 20, height: 20)
    }

    // MARK: - Gateway access

    private var accessRow: some View {
        HStack {
            Text("Levels")
                .font(OpenClawType.body)
                .foregroundStyle(Color.primary)
            Spacer(minLength: 0)
            if self.hasFullAccess {
                Text("Full access")
                    .font(OpenClawType.callout)
                    .foregroundStyle(Color.primary.opacity(0.6))
            } else {
                Menu {
                    Button { self.confirmingFullAccess = true } label: {
                        Text("Full access").font(OpenClawType.body)
                    }
                } label: {
                    HStack(spacing: 7) {
                        Text("Limited access")
                            .font(OpenClawType.callout)
                            .foregroundStyle(Color.primary.opacity(0.6))
                        Image("SettingsChevronsUpDownGlyph")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                            .foregroundStyle(Color.primary)
                    }
                }
            }
        }
        .padding(.horizontal, 17)
        .frame(height: 50)
        .openClawSectionBackground(self.cardFill)
        .confirmationDialog(
            "Switch to full access?",
            isPresented: self.$confirmingFullAccess,
            titleVisibility: .visible)
        {
            Button { self.onScanFullAccess() } label: {
                Text("Scan QR Code").font(OpenClawType.body)
            }
            Button(role: .cancel) {} label: {
                Text("Cancel").font(OpenClawType.body)
            }
        } message: {
            Text("Switching to full access mode requires you to scan a new QR code to take effect.")
                .font(OpenClawType.subhead)
        }
    }

    private var accessNote: some View {
        (Text("Switching to ").foregroundColor(Color.primary.opacity(0.6))
            + Text("full access mode").foregroundColor(Self.noteRed)
            + Text(" requires you to scan ").foregroundColor(Color.primary.opacity(0.6))
            + Text("a new qr code").foregroundColor(Self.noteRed)
            + Text(" to take effect").foregroundColor(Color.primary.opacity(0.6)))
            .font(OpenClawType.subhead)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 15)
    }

    // MARK: - Palette (matches the Settings root)

    private var canvas: Color {
        self.colorScheme == .dark
            ? Color(red: 23 / 255, green: 23 / 255, blue: 23 / 255)
            : Color(red: 245 / 255, green: 244 / 255, blue: 250 / 255)
    }

    private var cardFill: Color {
        self.colorScheme == .dark
            ? Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255)
            : .white
    }

    /// Subtle tint under the Liquid Glass nav circle (matches the chat floating buttons).
    private var glassFill: Color {
        self.colorScheme == .dark
            ? Color(red: 30 / 255, green: 30 / 255, blue: 30 / 255).opacity(0.2)
            : Color(red: 245 / 255, green: 244 / 255, blue: 250 / 255).opacity(0.2)
    }
}
