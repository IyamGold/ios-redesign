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
    /// Gates drag-to-open. The drawer belongs to the chat surface only, so when another surface (e.g. a
    /// pushed Settings screen) covers the chat, opening must be disabled — otherwise the left-edge strip
    /// would still pull the drawer out from under it.
    var allowsOpen: Bool = true
    let onSelectDestination: (ChatDrawerDestination) -> Void
    let onSelectSession: (String) -> Void
    /// Mint + switch to a fresh chat session (the compose affordance in the drawer header).
    let onNewSession: () -> Void
    /// Rename a session to a new label via the gateway (`sessions.patch { label }`).
    let onRenameSession: (String, String) -> Void
    /// The currently open session key, so its row reads as active.
    let activeSessionID: String?
    /// The destination tab currently shown (nil when the chat is showing), so its row reads as active.
    let activeDestination: ChatDrawerDestination?
    /// The gateway's resolved "home" session key (`agent:main:main` by default). It gets its own pinned
    /// "Main" section above the recents and is filtered out of the recent list so it never appears twice.
    let mainSessionID: String
    @ViewBuilder let chatContent: ChatContent

    @Environment(\.colorScheme) private var colorScheme
    /// Client-side pins + ordering for the session list (server truth untouched).
    @State private var prefs = ChatSessionPrefs.shared
    /// Session being renamed (drives the rename alert); nil when no rename is in progress.
    @State private var renameTargetID: String?
    @State private var renameText = ""
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
            // Scale the drawer PROPORTIONALLY to the chat's slide: 0.95 fully closed → 1 fully open, tracking
            // `currentOffset` so a half-open drawer sits ~0.975 instead of snapping between 0.95 and 1.
            let slideProgress = openOffset > 0 ? self.currentOffset(open: openOffset) / openOffset : 0
            let drawerScale = 0.95 + 0.05 * slideProgress
            ZStack(alignment: .topLeading) {
                // Static full-bleed backdrop, NOT scaled. Scaling a view whose children `ignoresSafeArea`
                // collapses their edge-bleed under the transform (the same "paper-cut" wall as the old sheet
                // recede). A same-color backdrop behind the scaled page fills those collapsed edges so no
                // trim ever shows — the trick the app root couldn't use, but this subview can.
                self.drawerCanvas.ignoresSafeArea()
                // The drawer page scales as one unit on top of that backdrop, so it reads as the page
                // receding. Horizontal insets are applied INSIDE drawerContent (to the list + header, not the
                // scrim), so the blurred scrim spans the full width with no vertical seams while rows stay in
                // the strip. Leading is 8 so the active-row pill bleeds 14pt left of its 22pt label.
                ZStack(alignment: .topLeading) {
                    self.drawerCanvas.ignoresSafeArea()
                    self.drawerContent(
                        topInset: proxy.safeAreaInsets.top,
                        trailingInset: proxy.size.width - openOffset + 16)
                }
                // Extend the page below the screen so the ScrollView's bottom clip lives off-screen — the
                // scale can lift the bottom edge without ever exposing a cut on-screen.
                .padding(.bottom, -Self.scaleBleed)
                // Anchor top-left (the corner the drawer emerges from), NOT center: pins the top edge so it
                // never moves under the scale — the header can't "push down" and the ignoresSafeArea top-bleed
                // can't collapse into a trim. Only the bottom/right inset, which the backdrop + chat panel hide.
                .scaleEffect(drawerScale, anchor: .topLeading)

                // Chat panel. The chat owns its own safe area (full-bleed canvas + composer inset),
                // so we mask with a safe-area-ignoring rounded rect — keeps it full-height when it
                // slides out, instead of clipping to the safe-area frame (which caused the top/bottom cut).
                self.chatContent
                    // Recede via BLUR, not opacity: dropping opacity made the whole panel see-through so the
                    // drawer bled through a destination tab. Blur keeps the panel fully opaque (nothing
                    // behind it shows) while still reading as "inactive" when the drawer is open.
                        .blur(radius: self.isOpen ? 0.6 : 0)
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
                        // Always-on: the "OneTab" panel keeps its drop shadow at all times (it's simply off-screen
                        // when the panel is closed/full-bleed), so the shadow is present throughout the open
                        // slide rather than fading in only once the drawer has settled.
                        .shadow(
                            color: .black.opacity(0.25),
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

    /// Reserve below the notch for the header (title + gap); the first list row rests here at rest.
    private static var headerReserve: CGFloat {
        62
    }

    /// How far the scaled page extends BELOW the screen. The scale (anchored top-left) lifts the bottom edge
    /// by up to ~5% of the page height (~45pt); extending past the screen by more than that keeps the
    /// ScrollView's bottom clip off-screen at every scale, so the list never shows a hard cut. The list's
    /// bottom content inset matches this so the last row still rests at the visible bottom.
    private static var scaleBleed: CGFloat {
        90
    }

    /// Soft blurred fade at the top of the list so rows dissolve as they scroll under the header instead of
    /// hitting a hard clip. It extends up under the notch (`ignoresSafeArea`) so its top edge IS the physical
    /// screen edge — no visible mid-screen band line — and its opaque zone covers the safe area + title band,
    /// fading to clear right where the first row rests.
    private func drawerTopScrim(topInset: CGFloat) -> some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            // Dark mode tints the frost toward the near-black canvas so the band stays dark and
            // content-independent; light mode's frosted white already matches the canvas.
            .overlay { self.drawerCanvas.opacity(self.colorScheme == .dark ? 0.72 : 0) }
            .mask {
                // Exact 1:1 with the chat top scrim's mask stops (0.6 capped, fade from 0.55 to clear).
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.6), location: 0),
                        .init(color: .black.opacity(0.6), location: 0.55),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom)
            }
            .frame(height: topInset + Self.headerReserve)
            .frame(maxWidth: .infinity)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
    }

    private var drawerHeader: some View {
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
        .padding(.leading, 14)
        .padding(.trailing, 8)
    }

    private func drawerContent(topInset: CGFloat, trailingInset: CGFloat) -> some View {
        // The list runs full-height and scrolls UNDER the pinned header (no hard cut-off). The whole stack
        // ignores the top safe area so the ScrollView + scrim reach the physical screen top — the clip and
        // the scrim's top edge land under the notch, not as a visible line above "OpenClaw". The scrim
        // between the list and header blurs rows out as they pass under the title (mirrors the chat).
        ZStack(alignment: .topLeading) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 23) {
                        self.drawerRow("DrawerMoonStarGlyph", "Dreaming", destination: .dreaming) {
                            self.select(.dreaming)
                        }
                        self.drawerRow("DrawerPieChartGlyph", "Usage", destination: .usage) {
                            self.select(.usage)
                        }
                        self.drawerRow("DrawerServerGlyph", "Instances", destination: .instances) {
                            self.select(.instances)
                        }
                        self.drawerRow("DrawerClockGlyph", "Cron Jobs", destination: .cron) {
                            self.select(.cron)
                        }
                        self.drawerRow("DrawerFilesGlyph", "Files", destination: .files) {
                            self.select(.files)
                        }
                        self.drawerRow("DrawerPaletteGlyph", "Canvas", destination: .canvas) {
                            self.select(.canvas)
                        }
                        self.drawerRow("DrawerScrollGlyph", "Skills", destination: .skills) {
                            self.select(.skills)
                        }
                    }

                    // "Main" pins the gateway's home session (agent:main:main by default) — where a cold
                    // start and every drawer destination live — in its own section above the recents.
                    VStack(alignment: .leading, spacing: 22) {
                        Text("Main")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.primary.opacity(0.6))
                            .padding(.leading, 14)
                        self.sessionRow(id: self.mainSessionID, title: self.mainSessionTitle, pinnable: false)
                    }
                    .padding(.top, 32)

                    VStack(alignment: .leading, spacing: 22) {
                        Text("Sessions")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.primary.opacity(0.6))
                            .padding(.leading, 14)
                        // Pins float to the top; the full list scrolls, so there is no visible-row cap.
                        // Main has its own section above, so it's dropped here (see `recentSessions`).
                        ForEach(self.prefs.ordered(self.recentSessions)) { session in
                            self.sessionRow(id: session.id, title: session.title, pinnable: true)
                        }
                    }
                    .padding(.top, 32)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Rows stay in the strip (leading 8 for the pill bleed; trailing clears the chat panel).
                .padding(.leading, 8)
                .padding(.trailing, trailingInset)
                // Reserve the notch + header so the first row rests just below the title, then scrolls up
                // and dissolves under the scrim.
                .padding(.top, topInset + Self.headerReserve)
                // Matches the off-screen bleed (+ normal 24) so the last row still rests at the visible
                // bottom while the ScrollView's clip sits below the screen.
                .padding(.bottom, Self.scaleBleed + 24)
            }
            .scrollIndicators(.hidden)

            // Full-width so the blurred band has no left/right seams (rows keep their own insets above).
            self.drawerTopScrim(topInset: topInset)

            // Header sits below the notch; the scrim behind it fades the scrolling rows out.
            self.drawerHeader
                .padding(.leading, 8)
                .padding(.trailing, trailingInset)
                .padding(.top, topInset + 8)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(edges: .top)
        .alert("Rename chat", isPresented: Binding(
            get: { self.renameTargetID != nil },
            set: {
                if !$0 {
                    self.renameTargetID = nil
                }
            })) {
                TextField("Name", text: self.$renameText)
                Button("Cancel", role: .cancel) { self.renameTargetID = nil }
                Button("Save") {
                    if let id = self.renameTargetID {
                        self.onRenameSession(id, self.renameText)
                    }
                    self.renameTargetID = nil
                }
        }
    }

    private func select(_ destination: ChatDrawerDestination) {
        self.onSelectDestination(destination)
        self.close()
    }

    /// Title for the Main row: the home session's cached display title if we have it, else the raw key.
    private var mainSessionTitle: String {
        self.sessions.first(where: { $0.id == self.mainSessionID })?.title ?? "Main"
    }

    /// Recents with the Main session removed — it lives in its own section above.
    private var recentSessions: [ChatDrawerSession] {
        self.sessions.filter { $0.id != self.mainSessionID }
    }

    /// One session row, shared by the Main section and the recents. `pinnable` is false for Main (it's the
    /// fixed home session), which drops only its pin indicator + pin/unpin menu; rename stays available.
    private func sessionRow(id: String, title: String, pinnable: Bool) -> some View {
        Button {
            self.onSelectSession(id)
            self.close()
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 17.13))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                if pinnable, self.prefs.isPinned(id) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.primary.opacity(0.4))
                }
                Spacer(minLength: 0)
            }
            // The active pill fills the row and sits at the ScrollView's left edge (so its rounded corners
            // aren't clipped); this 14pt inset is what makes the label read 14pt inside the pill.
            .padding(.leading, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Only the chat tab reflects the active session; while a destination tab is showing, its row owns
        // the highlight, so suppress the session highlight to avoid two active rows at once.
        .background { self.activeRowHighlight(self.activeDestination == nil && id == self.activeSessionID) }
        .contextMenu {
            Button {
                self.renameText = title
                self.renameTargetID = id
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            if pinnable {
                Button {
                    self.prefs.togglePin(id)
                } label: {
                    Label(
                        self.prefs.isPinned(id) ? "Unpin" : "Pin",
                        systemImage: self.prefs.isPinned(id) ? "pin.slash" : "pin")
                }
            }
        }
    }

    private func drawerRow(
        _ icon: String,
        _ label: String,
        destination: ChatDrawerDestination,
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
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.primary)
            // Matches the session rows: content inset 14pt so the active pill can fill the row from the
            // ScrollView's left edge without its rounded corners being clipped.
            .padding(.leading, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background { self.activeRowHighlight(destination == self.activeDestination) }
    }

    /// Active-item pill (per the Paper spec): a solid #000 (dark) / #FFF (light) fill, 32pt tall with a 10pt
    /// corner radius. It fills the row bounds (the row insets its own label 14pt), so the pill's left edge
    /// lands on the ScrollView's left edge and its rounded corners aren't clipped. Opacity-gated (not
    /// conditional) to keep view identity stable; text stays `Color.primary` — white on the dark fill,
    /// black on the light fill.
    private func activeRowHighlight(_ isActive: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(self.colorScheme == .dark ? Color.black : Color.white)
            .frame(height: 32)
            .opacity(isActive ? 1 : 0)
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
