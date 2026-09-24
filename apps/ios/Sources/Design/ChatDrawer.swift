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
    /// Mint + switch to a fresh chat session (the compose affordance in the drawer header).
    let onNewSession: () -> Void
    /// The currently open session key, so its row reads as active (medium weight).
    let activeSessionID: String?
    @ViewBuilder let chatContent: ChatContent

    @Environment(\.colorScheme) private var colorScheme
    /// Client-side pins + ordering for the session list (server truth untouched).
    @State private var prefs = ChatSessionPrefs.shared
    /// Live drag translation. @State (not @GestureState) so the snap-back on release can be animated —
    /// a @GestureState reset is instantaneous and made the drawer jump.
    @State private var dragOffset: CGFloat = 0
    /// Per-gesture latch for the closed-state open swipe: nil until the first significant movement, then
    /// true (a rightward, horizontally-dominant swipe → open) or false (vertical/leftward → yield to the
    /// transcript scroll). Latching once prevents a mid-drag direction change from flipping the decision.
    @State private var openSwipeEngaged: Bool?

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
                    // Simultaneous (not `.gesture`) so it coexists with the transcript scroll: the drag only
                    // moves the drawer for a rightward, horizontally-dominant swipe (see `panelDrag`), so the
                    // open-swipe can start anywhere across the chat while vertical scrolling still works.
                    .simultaneousGesture(self.panelDrag(open: openOffset))
            }
        }
        // Crisp minimal click on every drawer open/close. Selecting a destination/session closes the
        // drawer to reveal that tab, so this is also the tab-switch feedback — the drawer and its items
        // are one "OneTab" surface, so switching tabs should feel like the drawer moving.
        .onChange(of: self.isOpen) { _, _ in
            OpenClawHaptics.click()
        }
    }

    // MARK: - Geometry & gestures

    private func currentOffset(open: CGFloat) -> CGFloat {
        let base: CGFloat = self.isOpen ? open : 0
        return max(0, min(open, base + self.dragOffset))
    }

    /// Opens from a left→right swipe starting ANYWHERE across the chat (not just the edge), and closes on
    /// any drag while open. Runs as a `.simultaneousGesture` so it shares touches with the transcript's
    /// vertical scroll: a rightward, horizontally-dominant swipe opens the drawer; vertical (or leftward)
    /// drags fall through and scroll normally. The release decision uses the projected resting position so
    /// a quick flick commits.
    private func panelDrag(open: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if self.isOpen {
                    self.dragOffset = value.translation.width
                    return
                }
                guard self.allowsOpen else { return }
                if self.openSwipeEngaged == nil {
                    self.openSwipeEngaged = value.translation.width > 0
                        && abs(value.translation.width) > abs(value.translation.height)
                }
                if self.openSwipeEngaged == true {
                    self.dragOffset = max(0, value.translation.width)
                }
            }
            .onEnded { value in
                let engaged = self.isOpen || self.openSwipeEngaged == true
                let base: CGFloat = self.isOpen ? open : 0
                let projected = base + value.predictedEndTranslation.width
                withAnimation(.spring(duration: 0.35)) {
                    if engaged {
                        self.isOpen = projected > open / 2
                    }
                    self.dragOffset = 0
                }
                self.openSwipeEngaged = nil
            }
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
            HStack {
                Text("OpenClaw")
                    .font(.system(size: 25.6, weight: .semibold))
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 0)
                Button {
                    self.onNewSession()
                    self.close()
                } label: {
                    Image("ChatPlusGlyph")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .foregroundStyle(Color.primary)
                        .frame(width: 34, height: 34)
                        // App-standard glass chrome (matches the nav/close buttons), not a flat fill.
                        .background {
                            ChatGlassBackground(
                                shape: Circle(),
                                fill: self.colorScheme == .dark
                                    ? Color(red: 30 / 255, green: 30 / 255, blue: 30 / 255).opacity(0.2)
                                    : Color(red: 245 / 255, green: 244 / 255, blue: 250 / 255).opacity(0.2))
                        }
                        .shadow(color: .black.opacity(0.15), radius: 25, x: 0, y: 0)
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 8)

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
                // Pins float to the top; pull from a slightly wider window (8) so a pinned-but-older
                // session still surfaces within the four visible rows.
                ForEach(Array(self.prefs.ordered(Array(self.sessions.prefix(8))).prefix(4))) { session in
                    Button {
                        self.onSelectSession(session.id)
                        self.close()
                    } label: {
                        HStack(spacing: 6) {
                            Text(session.title)
                                .font(.system(
                                    size: 17.13,
                                    weight: session.id == self.activeSessionID ? .medium : .regular))
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                            if self.prefs.isPinned(session.id) {
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.primary.opacity(0.4))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            self.prefs.togglePin(session.id)
                        } label: {
                            Label(
                                self.prefs.isPinned(session.id) ? "Unpin" : "Pin",
                                systemImage: self.prefs.isPinned(session.id) ? "pin.slash" : "pin")
                        }
                    }
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
