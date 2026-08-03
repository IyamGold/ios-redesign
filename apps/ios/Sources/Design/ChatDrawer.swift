import SwiftUI

enum ChatDrawerDestination: Hashable, Identifiable {
    case dreaming, usage, instances, cron, files, canvas, skills

    var id: Self {
        self
    }
}

struct ChatDrawerSession: Identifiable, Equatable {
    let id: String
    let title: String
}

struct ChatDrawerHost<ChatContent: View>: View {
    @Binding var isOpen: Bool
    let sessions: [ChatDrawerSession]
    let versionText: String
    /// Gates drag-to-open. The drawer belongs to the chat surface only, so when another surface (e.g. a
    /// pushed Settings screen) covers the chat, opening must be disabled — otherwise the left-edge strip
    /// would still pull the drawer out from under it.
    var allowsOpen: Bool = true
    let onSelectDestination: (ChatDrawerDestination) -> Void
    let onSelectSession: (String) -> Void
    @ViewBuilder let chatContent: ChatContent

    @Environment(\.colorScheme) private var colorScheme
    /// Live drag translation. @State (not @GestureState) so the snap-back on release can be animated —
    /// a @GestureState reset is instantaneous and made the drawer jump.
    @State private var dragOffset: CGFloat = 0
    /// Suppresses the open/close click when the drawer closes as a side effect of picking an item —
    /// the click is for opening/dismissing the drawer, not for selection.
    @State private var suppressCloseHaptic = false

    private static var openOffset: CGFloat {
        305
    }

    private static var panelRadius: CGFloat {
        50
    }

    var body: some View {
        GeometryReader { proxy in
            let openOffset = min(Self.openOffset, proxy.size.width * 0.78)
            ZStack(alignment: .topLeading) {
                self.drawerCanvas.ignoresSafeArea()
                self.drawerContent
                    .padding(.leading, 22)
                    .padding(.top, 8)
                    .padding(.trailing, proxy.size.width - openOffset + 16)

                // Chat panel. The chat owns its own safe area (full-bleed canvas + composer inset),
                // so we mask with a safe-area-ignoring rounded rect — keeps it full-height when it
                // slides out, instead of clipping to the safe-area frame (which caused the top/bottom cut).
                self.chatContent
                    .opacity(self.isOpen ? 0.6 : 1)
                    .allowsHitTesting(!self.isOpen)
                    .overlay {
                        // Scrim sits ON the panel and BEFORE .offset, so it rides with the panel and
                        // only covers the chat. Drawer buttons stay tappable (the old overlay-after-offset
                        // spanned the whole screen and ate every tap).
                        if self.isOpen {
                            Color.black.opacity(0.001)
                                .contentShape(Rectangle())
                                .onTapGesture { self.close() }
                        }
                    }
                    .mask {
                        RoundedRectangle(
                            cornerRadius: self.isOpen ? Self.panelRadius : 0,
                            style: .continuous)
                            .ignoresSafeArea()
                    }
                    .shadow(
                        color: .black.opacity(self.isOpen ? 0.25 : 0),
                        radius: 15, x: -5, y: 0)
                    .offset(x: self.currentOffset(open: openOffset))
                    .gesture(self.panelDrag(open: openOffset))

                // Left-edge pan-to-open catcher (closed only). The chat is interactive when closed, so a
                // gesture on the panel itself loses to its scroll view; a dedicated edge strip reliably
                // starts the open drag. Omitted when opening is disallowed (e.g. Settings is up).
                if !self.isOpen, self.allowsOpen {
                    Color.clear
                        .frame(width: 20)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(self.panelDrag(open: openOffset))
                }
            }
        }
        // Crisp minimal click when the drawer opens or is dismissed — but not when it closes because
        // an item/session was picked (that's a navigation, not a drawer toggle).
        .onChange(of: self.isOpen) { _, _ in
            if self.suppressCloseHaptic {
                self.suppressCloseHaptic = false
                return
            }
            OpenClawHaptics.click()
        }
    }

    // MARK: - Geometry & gestures

    private func currentOffset(open: CGFloat) -> CGFloat {
        let base: CGFloat = self.isOpen ? open : 0
        return max(0, min(open, base + self.dragOffset))
    }

    /// Drag opens (from the left edge when closed) and closes (any drag on the panel when open).
    /// The release decision uses the projected resting position so a quick flick commits.
    private func panelDrag(open: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard self.dragEngaged(value) else { return }
                self.dragOffset = value.translation.width
            }
            .onEnded { value in
                let engaged = self.dragEngaged(value)
                let base: CGFloat = self.isOpen ? open : 0
                let projected = base + value.predictedEndTranslation.width
                withAnimation(.spring(duration: 0.35)) {
                    if engaged {
                        self.isOpen = projected > open / 2
                    }
                    self.dragOffset = 0
                }
            }
    }

    /// Closed drags only engage from the left edge so mid-screen chat gestures aren't hijacked;
    /// open drags engage anywhere on the panel.
    private func dragEngaged(_ value: DragGesture.Value) -> Bool {
        self.isOpen || (self.allowsOpen && value.startLocation.x <= 60)
    }

    private func close() {
        withAnimation(.spring(duration: 0.35)) { self.isOpen = false }
    }

    // MARK: - Palette

    private var drawerCanvas: Color {
        self.colorScheme == .dark
            ? Color(red: 23 / 255, green: 23 / 255, blue: 23 / 255)
            : Color(red: 245 / 255, green: 244 / 255, blue: 250 / 255)
    }

    // MARK: - Drawer content

    private var drawerContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("OpenClaw")
                .font(.system(size: 25.6, weight: .semibold))
                .foregroundStyle(Color.primary)

            VStack(alignment: .leading, spacing: 23) {
                self.drawerRow("DrawerMoonStarGlyph", "Dreaming") {
                    self.select(.dreaming)
                }
                self.drawerRow("DrawerPieChartGlyph", "Usage") {
                    self.select(.usage)
                }
                self.drawerRow("DrawerServerGlyph", "Instances") {
                    self.select(.instances)
                }
                self.drawerRow("DrawerClockGlyph", "Cron Jobs") {
                    self.select(.cron)
                }
                self.drawerRow("DrawerFilesGlyph", "Files") {
                    self.select(.files)
                }
                self.drawerRow("DrawerPaletteGlyph", "Canvas") {
                    self.select(.canvas)
                }
                self.drawerRow("DrawerScrollGlyph", "Skills") {
                    self.select(.skills)
                }
            }
            .padding(.top, 28)

            VStack(alignment: .leading, spacing: 22) {
                Text("Sessions")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.primary.opacity(0.6))
                ForEach(self.sessions.prefix(4)) { session in
                    Button {
                        self.suppressCloseHaptic = true
                        self.onSelectSession(session.id)
                        self.close()
                    } label: {
                        Text(session.title)
                            .font(.system(size: 17.13))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 32)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Text("Latest version:")
                    .font(.system(size: 14.46))
                    .foregroundStyle(Color.primary.opacity(0.6))
                Text(self.versionText)
                    .font(.system(size: 14.46))
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background {
                        RoundedRectangle(cornerRadius: 3.4, style: .continuous)
                            .fill(self.colorScheme == .dark ? Color.black : .white)
                    }
            }
            .padding(.bottom, 14)
        }
    }

    private func select(_ destination: ChatDrawerDestination) {
        self.suppressCloseHaptic = true
        self.onSelectDestination(destination)
        self.close()
    }

    private func drawerRow(
        _ icon: String,
        _ label: String,
        action: @escaping () -> Void) -> some View
    {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(icon)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .opacity(0.9)
                Text(label)
                    .font(.system(size: 17.13))
            }
            .foregroundStyle(Color.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Redesigned glass "cancel" button — the same close control as the Connection sheet, reused as the
/// dismiss affordance across every drawer destination for a consistent feel.
struct DrawerCloseButton: View {
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: self.onClose) {
            Image("ChatCloseGlyph")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .foregroundStyle(Color.primary)
                .frame(width: 40, height: 40)
                .background { ChatGlassBackground(shape: Circle(), fill: self.glassFill) }
                .shadow(color: .black.opacity(0.15), radius: 25, x: 0, y: 0)
        }
        .buttonStyle(.plain)
        .padding(.leading, 25)
        .padding(.top, 22)
    }

    private var glassFill: Color {
        self.colorScheme == .dark
            ? Color(red: 30 / 255, green: 30 / 255, blue: 30 / 255).opacity(0.2)
            : Color(red: 245 / 255, green: 244 / 255, blue: 250 / 255).opacity(0.2)
    }
}

/// Minimal host for the shared canvas web view. The drawer's Canvas item points here at the existing
/// `ScreenController` surface so it can be evaluated in context before a dedicated redesign. The
/// dismiss control is the shared `DrawerCloseButton`, overlaid by the presenter.
struct DrawerCanvasScreen: View {
    @Environment(NodeAppModel.self) private var appModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            // Respect the top inset (the close button's reserved space) so the web content isn't under
            // the X; still bleed to the bottom edge.
            ScreenWebView(controller: self.appModel.screen)
                .ignoresSafeArea(edges: .bottom)
        }
        .onAppear { self.appModel.screen.showDefaultCanvas() }
    }
}
