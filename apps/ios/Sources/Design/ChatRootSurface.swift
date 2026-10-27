import OpenClawChatUI
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Redesigned iOS chat surface. Pure presentation over OpenClawChatViewModel;
/// the shared OpenClawChatUI kit remains untouched (macOS keeps its own UI).
struct ChatRootSurface: View {
    @Bindable var viewModel: OpenClawChatViewModel
    let onOpenSettings: () -> Void
    let onOpenTalk: () -> Void
    /// Opens the chat drawer (WhatsApp-style side panel); nil when hosted without a drawer.
    var onOpenDrawer: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var inputHeight: CGFloat = 0
    @State private var showsAttachmentTray = false
    /// Photo-library picker (images only — the shared attachment pipeline is image-only today).
    @State private var showsPhotoLibrary = false
    @State private var photoSelection: [PhotosPickerItem] = []
    /// Camera capture (photo only for now); presented full-screen over the chat.
    @State private var showsCamera = false
    /// GIF picker — the photo library, staged verbatim so animation is preserved (not JPEG-flattened).
    @State private var showsGifLibrary = false
    @State private var gifSelection: [PhotosPickerItem] = []
    /// Files — arbitrary documents via the system document picker.
    @State private var showsFileImporter = false
    /// Voice-note recorder — the composer mic records an m4a clip staged as an audio attachment.
    @State private var voiceRecorder = OpenClawVoiceNoteRecorder()
    /// On-device transcripts of staged voice notes, keyed by attachment id, sent as the message body.
    @State private var voiceTranscripts: [OpenClawPendingAttachment.ID: String] = [:]
    /// Transcript rows are projected once whenever `messages` changes — not per body pass — so the
    /// AssistantTextParser doesn't run on every keystroke / streamed token (what kept it off 60fps).
    @State private var rows: [ChatDisplayRow] = []
    /// Decoded attachment images kept across a turn's provisional→canonical swap, keyed by the stable
    /// idempotency key (the gateway drops the image bytes from the canonical user row — see rebuildRows).
    @State private var imageCache: [String: [UIImage]] = [:]
    /// Keys already written to the disk cache this session, so we encode/write each turn's images once.
    @State private var diskCachedKeys: Set<String> = []
    /// Decoded audio/file chips kept (in memory) across a turn's provisional→canonical swap.
    @State private var chipCache: [String: [ChatAttachmentChip]] = [:]
    /// Keys whose chips are already written to the disk cache this session.
    @State private var diskCachedChipKeys: Set<String> = []
    /// Armed on send; fires the reply-intro haptic once when the assistant's reply first appears.
    @State private var replyIntroArmed = false
    /// The `[embed]` canvas open in the viewer panel (tapped from an inline card).
    @State private var openEmbed: CanvasEmbed?
    /// Steps shown in the "Worked through N steps" detail sheet (nil = closed). A sheet keeps long runs
    /// from widening the transcript, which inline expansion did past ~3 steps.
    @State private var stepsSheet: ChatStepsPayload?

    /// Answer rows already present, so a freshly-finalized reply can be told apart from history on load.
    @State private var knownAnswerIDs: Set<String> = []
    /// The one answer row that should play the top-to-bottom reveal once. Under pessimistic classification
    /// the live indicator no longer streams untagged replies in place, so the reply "streams" here as it
    /// settles from the shimmer at finality (empty id = nothing to reveal).
    @State private var revealAnswerID: String = ""

    /// Gates the "Thinking" node's *appearance* until the just-sent user bubble has finished its spring/
    /// layout settle. Without it the node mounts in the same transaction as the bubble and rides its
    /// spring, popping in before the bubble sits in place. Default true so external/resumed runs (no local
    /// send) show the node immediately; a send flips it false, then a short delay (the spring duration)
    /// flips it back.
    @State private var nodeReady = true
    /// Height of the scroll viewport, tracked so the trailing spacer can reserve enough room for the
    /// newest question to spring up and rest near the top even in a near-empty chat.
    @State private var viewportHeight: CGFloat = 0
    /// The just-sent user turn's row id: it springs up to rest near the top and stays pinned (the trailing
    /// spacer holds the room) until the next send or a session switch. nil restores normal bottom-anchoring.
    @State private var pinTurnID: String?
    /// One-shot trigger: set on send, consumed once the pinned turn's row exists so the spring-to-top scroll
    /// runs exactly once (not on every subsequent `rows` change while the reply streams in below).
    @State private var pinScrollPending = false
    /// Live-measured layout of the pinned turn (in content coordinates), driving the dynamic bottom spacer:
    /// `pinnedQuestionTop` is the pinned question row's top; `contentTailBottom` is the bottom of the last
    /// real row. Their difference is the newest turn's rendered height, so the reserved room can shrink as
    /// the reply grows (question stays the scroll ceiling, no over-scroll, no reply-end snap).
    @State private var pinnedQuestionTop: CGFloat?
    @State private var contentTailBottom: CGFloat = 0
    /// App model — used to resolve `[embed]` canvas docs against the gateway's capability-scoped host URL.
    @Environment(NodeAppModel.self) private var appModel

    private static let bubbleRed = Color(red: 195 / 255, green: 63 / 255, blue: 51 / 255)
    /// Online presence dot (iOS system green) shown on the avatar while connected.
    private static let onlineGreen = Color(red: 52 / 255, green: 199 / 255, blue: 89 / 255)
    private static let bottomAnchorID = "chat-bottom-anchor"

    /// Ring around the presence dot — matches the app canvas so the badge reads as a cutout.
    private var onlineRing: Color {
        self.colorScheme == .dark
            ? Color(red: 23 / 255, green: 23 / 255, blue: 23 / 255)
            : Color(red: 245 / 255, green: 244 / 255, blue: 250 / 255)
    }

    /// Pill (48pt) in the single-line default; drops to 15pt once the field grows past one line.
    private var composerFieldCornerRadius: CGFloat {
        self.inputHeight > 44 ? 15 : 48
    }

    /// The assistant is working from send until the final message lands: keep the indicator up for the
    /// whole window (pending run / sending), not just the sub-second gap before the first token.
    private var isAssistantWorking: Bool {
        self.viewModel.pendingRunCount > 0 || self.viewModel.isSending
    }

    /// Where a pinned question comes to rest: ~120pt below the top so it clears the top bar / scrim.
    private var pinAnchor: UnitPoint {
        guard self.viewportHeight > 200 else { return .top }
        return UnitPoint(x: 0.5, y: min(0.4, 120 / self.viewportHeight))
    }

    /// Fixed padding kept between the last line and the bottom of the scroll content (the "note page"
    /// resting gap). A long reply bottoms out at exactly this.
    private static let bottomContentPadding: CGFloat = 10
    /// Named coordinate space on the scroll content, so the pin/tail probes measure content-relative
    /// offsets that don't move with the scroll position.
    private static let chatContentSpace = "chatContentSpace"

    /// Rendered height of the newest turn (pinned question → last line), from the live probes.
    private var pinnedTurnHeight: CGFloat {
        guard let top = pinnedQuestionTop else { return 0 }
        return max(0, self.contentTailBottom - top)
    }

    /// Dynamic room below the newest turn. Sized so the pinned question resting at `pinAnchor` is the
    /// furthest the content can scroll: reserve exactly enough that (question → last line) fills the
    /// viewport below the pin. As the reply grows, `pinnedTurnHeight` grows and this shrinks 1:1 — no net
    /// reflow and no teardown, so there's no reply-end snap and no over-scroll into dead space. A reply
    /// long enough to fill the viewport bottoms out at the fixed padding. Not pinned → just the padding.
    private var bottomSpacerHeight: CGFloat {
        guard self.pinTurnID != nil, self.viewportHeight > 0 else { return Self.bottomContentPadding }
        let pinOffset = self.pinAnchor.y * self.viewportHeight
        return max(Self.bottomContentPadding, self.viewportHeight - pinOffset - self.pinnedTurnHeight)
    }

    /// Reports the pinned question row's top (content coords) via preference; a no-op background for every
    /// other row. Only the pinned row emits, so the preference reduce yields exactly its offset (or nil).
    @ViewBuilder
    private func pinnedQuestionProbe(for row: ChatDisplayRow) -> some View {
        if row.id == self.pinTurnID {
            GeometryReader { geo in
                Color.clear.preference(
                    key: PinnedQuestionTopKey.self,
                    value: geo.frame(in: .named(Self.chatContentSpace)).minY)
            }
        } else {
            Color.clear
        }
    }

    private struct PinnedQuestionTopKey: PreferenceKey {
        static let defaultValue: CGFloat? = nil
        static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
            value = value ?? nextValue()
        }
    }

    private struct ContentTailBottomKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    private static func stepsLabel(_ count: Int) -> String {
        "Worked through \(count) step\(count == 1 ? "" : "s")"
    }

    var body: some View {
        ZStack {
            self.canvas.ignoresSafeArea()
            self.transcript
            // Voice-session gradient (one design for STT + S2S), amplitude-reactive. Inside the ZStack so the
            // top bar + composer (outer modifiers) stay ABOVE it — the voice button stays tappable to end the
            // session, and the transcript shows through. Renders nothing when no session is active.
            TalkVoiceOverlay(
                isActive: self.appModel.talkMode.isEnabled,
                level: self.appModel.talkMode.assistantLevel)
        }
        // Fades scrolling content out under the status bar / pills so it doesn't clash with the clock.
        .overlay(alignment: .top) { self.topScrim }
        .overlay(alignment: .top) { self.topBar }
        // Full-screen catcher closes the tray on any outside tap (composer + tray render above it).
        .overlay {
            if self.showsAttachmentTray {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { self.closeAttachmentTray() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            self.composer
        }
        .onChange(of: self.viewModel.messages, initial: true) { _, _ in
            self.rebuildRows()
        }
        // The `[embed]` canvas viewer, opened from an inline embed card. Resolves against a freshly
        // refreshed capability-scoped host URL (the token is short-lived).
        .sheet(item: self.$openEmbed) { embed in
            CanvasEmbedPanel(
                embed: embed,
                canvasHostProvider: {
                    if let refreshed = await self.appModel.refreshCanvasHostURL() {
                        return refreshed
                    }
                    return await self.appModel.canvasHostURL()
                },
                onClose: { self.openEmbed = nil })
                .presentationCornerRadius(47)
        }
        // "Worked through N steps" → a custom bottom-sheet overlay, NOT a system `.sheet`. iOS 26 renders
        // every sheet sizing (.form/.page/.fitted) as a horizontally-inset floating card with no public
        // API to pin it flush to the screen edges. Owning the card gives a true edge-to-edge, bottom-flush
        // panel with the app canvas + glass X, matching the drawer destinations.
        // Always-mounted so the card's `.move` slide + the scrim's `.opacity` fade run as independent
        // child transitions. If the overlay itself were conditionally inserted, SwiftUI would apply its
        // default (`.opacity`) transition to the whole subtree — making the card *fade* in instead of
        // *slide* up. `payload == nil` renders nothing and disables hit testing.
        .overlay {
            ChatStepsOverlay(payload: self.stepsSheet, onClose: { self.closeStepsSheet() })
        }
        // Kick the view model's bootstrap (history + health poll) on appear and whenever the model
        // instance changes. The shared kit view did this in its own `.onAppear`; without it the health
        // probe never runs, so sends queue offline forever and no reply ever comes back.
        .task(id: ObjectIdentifier(self.viewModel)) {
            // A different session's rows are about to load — drop any pin so its spacer doesn't linger.
            self.pinTurnID = nil
            self.pinScrollPending = false
            self.pinnedQuestionTop = nil
            self.viewModel.load()
        }
        // Images: system photo picker (images only). Loaded items feed the shared attachment pipeline.
        .photosPicker(
            isPresented: self.$showsPhotoLibrary,
            selection: self.$photoSelection,
            maxSelectionCount: 10,
            matching: .images)
        .onChange(of: self.photoSelection) { _, items in
            self.ingestPickedPhotos(items)
        }
        // Camera: capture a photo and stage it like any other image attachment.
        .fullScreenCover(isPresented: self.$showsCamera) {
            ChatCameraPicker { image in
                self.ingestCameraImage(image)
            }
            .ignoresSafeArea()
        }
        // GIFs: same photo library, but staged verbatim so animated GIFs keep their frames.
        .photosPicker(
            isPresented: self.$showsGifLibrary,
            selection: self.$gifSelection,
            maxSelectionCount: 5,
            matching: .images)
        .onChange(of: self.gifSelection) { _, items in
            self.ingestPickedGifs(items)
        }
        // Files: arbitrary documents; the gateway offloads non-images to the agent's workspace.
        .fileImporter(
            isPresented: self.$showsFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true)
        { result in
            self.ingestPickedFiles(result)
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(self.rows) { row in
                        self.messageView(for: row)
                            // The "Worked through N steps" row belongs to the answer below it, so drop it
                            // down (extra top space away from the user bubble) and tighten its gap to the
                            // reply (~40% less than the standard 25) so the two read as one group.
                                .padding(.top, row.progressLines.isEmpty ? 0 : 10)
                                .padding(.bottom, self.rowBottomSpacing(row))
                                // Measure the pinned question row's top (content coords) so the spacer can
                                // reserve exactly the room that keeps it at the scroll ceiling.
                                .background(self.pinnedQuestionProbe(for: row))
                                // User turns rise into place from below with a soft spring settle; assistant
                                // rows just fade so the reply doesn't shove the pinned question around.
                                .transition(row.isUser
                                    ? .move(edge: .bottom).combined(with: .opacity)
                                    : .opacity)
                    }
                    self.voiceTranscript
                    self.trailingIndicator
                        // Fade the live indicator in/out as the turn starts and ends (it hands off to the
                        // finalized rows on completion), and the node in once the user bubble has settled.
                            .animation(.easeInOut(duration: 0.25), value: self.viewModel.liveTurn == nil)
                            .animation(.easeInOut(duration: 0.25), value: self.isAssistantWorking)
                            .animation(.easeInOut(duration: 0.25), value: self.nodeReady)
                    // Marks the bottom of the last real row (content coords). Placed before the spacer so
                    // `contentTailBottom - pinnedQuestionTop` is the newest turn's rendered height.
                    Color.clear
                        .frame(height: 0)
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: ContentTailBottomKey.self,
                                    value: geo.frame(in: .named(Self.chatContentSpace)).minY)
                            })
                    // Dynamic room below the newest turn (see `bottomSpacerHeight`): shrinks as the reply
                    // grows so the pinned question stays the scroll ceiling; a bare `bottomContentPadding`
                    // when nothing is pinned.
                    Color.clear
                        .frame(height: self.bottomSpacerHeight)
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomAnchorID)
                }
                .padding(.horizontal, 14)
                .padding(.top, 108)
                .coordinateSpace(.named(Self.chatContentSpace))
            }
            // Recreate the ScrollView once when rows first arrive (empty→loaded). Otherwise history loads as
            // a bulk size-change that `.defaultScrollAnchor(.top, for: .sizeChanges)` throws into a limbo
            // where the LazyVStack won't paint until a physical scroll. Rebuilt with rows already present,
            // `.defaultScrollAnchor(.bottom)` positions AND paints the latest turns immediately.
            .id(self.rows.isEmpty)
            .defaultScrollAnchor(.bottom)
            // Retain the last non-nil top: once a long reply scrolls the pinned question off the top,
            // LazyVStack stops rendering it (probe → nil), but its content-space offset is stable through
            // the turn — dropping it would balloon the spacer and jump. Reset happens on send/session switch.
            .onPreferenceChange(PinnedQuestionTopKey.self) { newValue in
                if let newValue {
                    self.pinnedQuestionTop = newValue
                }
            }
            .onPreferenceChange(ContentTailBottomKey.self) { self.contentTailBottom = $0 }
            // Track the viewport height so the trailing spacer can size the "pin to top" room.
            .onScrollGeometryChange(for: CGFloat.self) { $0.containerSize.height } action: { _, new in
                self.viewportHeight = new
            }
            // Anchor the TOP on size changes so the finalized answer inserting at full height doesn't
            // instant-yank the transcript upward (the "snap"). New messages/answers still reach the
            // bottom via the explicit, animated scrollToBottom calls below — so the only motion is that
            // one smooth scroll, running while the answer reveals.
            .defaultScrollAnchor(.top, for: .sizeChanges)
            // The bottom anchor used to keep the last message above the keyboard for free; with sizeChanges
            // now top-anchored we re-pin explicitly whenever the composer/keyboard grows the bottom inset.
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentInsets.bottom } action: { old, new in
                if new > old {
                    self.scrollToBottom(proxy, animated: false, reason: "bottomInset")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            // On send, the new user turn springs up to rest near the top (once, when its row first lands);
            // while a turn is pinned, later rows (the reply) fill in BELOW without yanking to the bottom —
            // the `.top` size-change anchor keeps the question put. With no pin, keep the old behavior:
            // newly committed rows animate to the bottom; the very first population snaps.
            .onChange(of: self.rows.count) { old, new in
                ChatTimeline
                    .mark(
                        "view.rows.count \(old)->\(new) pinPending=\(self.pinScrollPending) pin=\(self.pinTurnID != nil)")
                // First row change after a send is the optimistic user turn — pin it to the top once.
                if self.pinScrollPending, let userRow = self.rows.last(where: { $0.isUser }) {
                    self.pinScrollPending = false
                    self.pinTurnID = userRow.id
                    ChatTimeline.mark("view.pin set + springScrollTo(top)")
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                        proxy.scrollTo(userRow.id, anchor: self.pinAnchor)
                    }
                } else if self.pinTurnID == nil {
                    self.scrollToBottom(proxy, animated: old != 0, reason: "rows.count")
                }
            }
            // Cold start / session switch can MOUNT with rows already populated (history loads from cache
            // before this view appears), so `rows.count` never changes and the initial scroll-to-bottom is
            // skipped — the LazyVStack then reads blank until a manual scroll materializes it. Fire once on
            // first appearance (`initial: true`), deferred a runloop so the cells are laid out before we scroll.
            .onChange(of: self.rows.isEmpty, initial: true) { _, isEmpty in
                guard !isEmpty, self.pinTurnID == nil else { return }
                Task { @MainActor in
                    self.scrollToBottom(proxy, animated: false, reason: "initialRows")
                }
            }
            // A long background suspends the transcript's LazyVStack; on foreground it renders blank until a
            // manual scroll re-materializes the cells. Refresh history (catch anything missed while
            // suspended) and re-assert the scroll so the rows render immediately. The iOS surface owns this —
            // the legacy macOS ChatView wired it in its own scenePhase handler; this one never did.
            .onChange(of: self.scenePhase) { _, phase in
                guard phase == .active else { return }
                self.viewModel.resumeFromForeground()
                self.scrollToBottom(proxy, animated: false, reason: "foreground")
            }
            // Streamed tokens: only track the bottom for a tool-free reply that has no pinned question above
            // it. When a question is pinned the reply grows downward into the reserved spacer and the top
            // anchor holds it steady — so we must NOT scroll on every token.
            .onChange(of: self.viewModel.streamingAssistantText) { _, _ in
                ChatTimeline.markThrottled(
                    "view.streamText",
                    "view.streamText len=\(self.viewModel.streamingAssistantText?.count ?? 0) "
                        + "pin=\(self.pinTurnID != nil)")
                // The live indicator renders the growing answer in place; when a question is pinned the top
                // anchor holds it, so only track the bottom for an unpinned reply.
                if self.pinTurnID == nil {
                    self.scrollToBottom(proxy, animated: false, reason: "streamToken")
                }
            }
            .onChange(of: self.assistantRowCount) { old, new in
                if new > old {
                    self.fireReplyIntroIfArmed()
                }
            }
            .onChange(of: self.isAssistantWorking) { old, new in
                ChatTimeline.mark("view.isAssistantWorking \(old)->\(new)")
                // Scroll the live indicator into view when a run starts (no token change fires here yet).
                if new {
                    self.scrollToBottom(proxy, animated: false, reason: "workStart")
                }
                // Run finished (pending cleared): only disarm the intro so a stale one can't fire later.
                // No closing haptic — a one-word reply lands start+end together and double-buzzed.
                if old, !new {
                    self.replyIntroArmed = false
                }
            }
            // A voice turn just committed (a "sent" user bubble, or the assistant's reply landed) — scroll it
            // into view so the growing conversation stays pinned to the bottom during a session.
            .onChange(of: self.appModel.talkMode.voiceTurns.count) { old, new in
                self.scrollToBottom(proxy, animated: true, reason: "voiceTurn")
                // A voice turn just committed — tap once. The user's bubble commits when they finish speaking;
                // the assistant's turn commits when its spoken reply ENDS, so both tap at the moment the
                // bubble lands. (Voice-overlay only — the real chat keeps its own reply-intro haptic.)
                if new > old {
                    OpenClawHaptics.tap()
                }
            }
        }
    }

    private var assistantRowCount: Int {
        self.rows.reduce(0) { $0 + ($1.isUser ? 0 : 1) }
    }

    /// A single reply haptic, armed on send: a warning pattern introduces the reply, fired once by whichever
    /// lands first (streamed token or finalized row) so it can't buzz while a transcript loads. There is no
    /// closing haptic — a one-word reply lands start+end in the same instant, which double-buzzed.
    private func fireReplyIntroIfArmed() {
        guard self.replyIntroArmed else { return }
        self.replyIntroArmed = false
        OpenClawHaptics.tap()
    }

    /// Matches the feel of a UIKit page-sheet present/dismiss: a smooth, near-critically-damped spring
    /// (~0.5s, no bounce). The real sheet timing is a private UIKit spring — this is a by-feel match, since
    /// a system `.sheet` exposes no animation parameters to copy.
    private static let stepsSheetSlide: Animation = .spring(response: 0.5, dampingFraction: 0.95)

    /// Open/close the custom steps overlay. Driving the state inside `withAnimation` is what actually
    /// animates the overlay's move/opacity transitions (an `.animation(value:)` on the chain does not
    /// reliably drive a conditionally-inserted overlay).
    private func openStepsSheet(_ steps: [String], reasoning: ChatStepsReasoning? = nil) {
        withAnimation(Self.stepsSheetSlide) {
            self.stepsSheet = ChatStepsPayload(steps: steps, reasoning: reasoning)
        }
    }

    private func closeStepsSheet() {
        withAnimation(Self.stepsSheetSlide) {
            self.stepsSheet = nil
        }
    }

    /// Bottom gap under a row: user bubbles 21, the "Worked through N steps" trail 15 (tightened toward
    /// its answer), all other assistant rows 25.
    private func rowBottomSpacing(_ row: ChatDisplayRow) -> CGFloat {
        if row.isUser {
            return 21
        }
        return row.progressLines.isEmpty ? 25 : 15
    }

    /// User turns stay in a chat bubble; assistant turns render free (no bubble, full width) so code
    /// blocks and wide content aren't boxed in.
    @ViewBuilder
    private func messageView(for row: ChatDisplayRow) -> some View {
        if let day = row.daySeparator {
            Text(day)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle((self.colorScheme == .dark ? Color.white : .black).opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 4)
        } else if !row.progressLines.isEmpty {
            ChatThinkingNode(
                label: Self.stepsLabel(row.progressLines.count),
                steps: row.progressLines,
                shimmer: false,
                colorScheme: self.colorScheme,
                onOpenSteps: {
                    // Persisted thinking has no timing, so the resting receipt is a plain "Thought".
                    let reasoning = row.reasoningText.map { ChatStepsReasoning(receipt: "Thought", text: $0) }
                    self.openStepsSheet(row.progressLines, reasoning: reasoning)
                })
        } else if let embed = row.canvasEmbed {
            CanvasEmbedCard(embed: embed, onOpen: { self.openEmbed = embed })
        } else if row.isUser {
            ChatUserBubble(row: row, colorScheme: self.colorScheme)
        } else {
            ChatAssistantMessage(
                row: row,
                colorScheme: self.colorScheme,
                // A freshly-finalized reply reveals once so it "streams" in as it settles from the shimmer at
                // finality (untagged providers don't stream it in the live indicator). History rows don't.
                reveal: row.id == self.revealAnswerID)
        }
    }

    /// The realtime (S2S) conversation, display-only: committed turns (both sides) plus the assistant's reply
    /// streaming live. The realtime audio transcript isn't a `chat.send`, so it lives in `talkMode.voiceTurns`
    /// rather than the gateway-synced `messages`, and renders here through the same bubble views.
    @ViewBuilder private var voiceTranscript: some View {
        ForEach(self.appModel.talkMode.voiceTurns) { turn in
            self.messageView(for: ChatDisplayRow(voiceTurn: turn))
                .padding(.bottom, 25)
                .transition(turn.isUser
                    ? .move(edge: .bottom).combined(with: .opacity)
                    : .opacity)
        }
        let assistant = self.appModel.talkMode.liveAssistantTranscript
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !assistant.isEmpty {
            self.messageView(for: ChatDisplayRow(voiceLiveAssistant: assistant))
                .padding(.bottom, 25)
                .animation(.easeOut(duration: 0.18), value: assistant)
        }
    }

    @ViewBuilder private var trailingIndicator: some View {
        // The in-flight turn renders as ONE continuous collapsible stack (reasoning fold → step group →
        // streaming answer) via `ChatTurnTimeline` — no node↔bubble split, no guessing. The only remaining
        // discontinuity (the live→resting handoff) is removed in T4.
        if let turn = viewModel.liveTurn, turn.state == .running {
            ChatTurnTimeline(
                turn: turn,
                nodeReady: self.nodeReady,
                colorScheme: self.colorScheme,
                textColor: self.colorScheme == .dark ? .white : .black,
                onOpenSteps: { steps, reasoning in self.openStepsSheet(steps, reasoning: reasoning) })
                .padding(.bottom, 25)
                .transition(.opacity)
        } else if self.isAssistantWorking, self.nodeReady {
            // Run started but no event folded yet — show the plain "Thinking" shimmer so there's no gap.
            ChatThinkingNode(label: "Thinking", steps: [], shimmer: true, colorScheme: self.colorScheme)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 25)
                .transition(.opacity)
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true, reason: String = "?") {
        ChatTimeline.mark("view.scrollToBottom [\(reason)] animated=\(animated)")
        guard animated else {
            proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
            return
        }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
        }
    }

    /// Project transcript messages into lightweight display rows once, parsing visible text a single
    /// time per message (the parser is the expensive part) instead of twice on every render.
    private func rebuildRows() {
        var result: [ChatDisplayRow] = []
        var allEmbeds: [CanvasEmbed] = []
        // Tool-use turns (stopReason "toolUse" / toolCall parts) each emit a one-line preamble before
        // calling tools; only the final turn is the answer. Buffer those preambles and flush them as a
        // single collapsible "steps" row just above the answer, instead of N standalone replies.
        var pendingProgress: [String] = []
        var pendingProgressTimestamp: Double?
        // The turn's persisted reasoning, concatenated across its tool-use messages, for the sheet's nested
        // "Thought" group. Flushed with the steps trail it belongs to.
        var pendingReasoning: [String] = []
        func flushProgress() {
            guard !pendingProgress.isEmpty else { return }
            result.append(ChatDisplayRow(
                progressLines: pendingProgress,
                reasoning: pendingReasoning.isEmpty ? nil : pendingReasoning.joined(separator: "\n\n"),
                timestamp: pendingProgressTimestamp))
            pendingProgress.removeAll()
            pendingReasoning.removeAll()
            pendingProgressTimestamp = nil
        }
        for message in self.viewModel.messages {
            let role = message.role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard role == "user" || role == "assistant" else { continue }
            let decoded = Self.decodeAttachments(from: message)
            var images = decoded.images
            var chips = decoded.chips
            // Persist a turn's attachments across the provisional→canonical swap: the gateway replaces the
            // optimistic user echo (which carries the bytes) with a text-only "See attached." row, so cache
            // the decoded pieces under the stable idempotency key and reuse them once the bytes vanish.
            if let key = Self.attachmentCacheKey(for: message) {
                if !images.isEmpty {
                    self.imageCache[key] = images
                    // Persist once per turn so images survive a cold start (memory cache starts empty).
                    if self.diskCachedKeys.insert(key).inserted {
                        ChatImageDiskCache.store(images, key: key)
                    }
                } else if let cached = imageCache[key] {
                    images = cached
                } else {
                    // Cold start: rehydrate from disk on the first byte-less encounter, then memoize.
                    let disk = ChatImageDiskCache.load(key: key)
                    if !disk.isEmpty {
                        self.imageCache[key] = disk
                        self.diskCachedKeys.insert(key)
                        images = disk
                    }
                }
                // Audio/file chips must be cached PAYLOAD-AWARE: unlike images (whose block is stripped
                // entirely), the canonical audio/file row keeps a byte-LESS block, so decodeAttachments
                // still yields a chip with a nil payload. Caching that would clobber the good bytes and
                // break playback/thumbnails + relaunch. So only cache/persist chips that carry bytes, and
                // recover from memory→disk whenever this render's chips lack them.
                if chips.contains(where: { $0.payload != nil }) {
                    self.chipCache[key] = chips
                    if self.diskCachedChipKeys.insert(key).inserted {
                        ChatChipDiskCache.store(chips, key: key)
                    }
                } else if let cachedChips = chipCache[key],
                          cachedChips.contains(where: { $0.payload != nil })
                {
                    chips = cachedChips
                } else {
                    let diskChips = ChatChipDiskCache.load(key: key)
                    if diskChips.contains(where: { $0.payload != nil }) {
                        self.chipCache[key] = diskChips
                        self.diskCachedChipKeys.insert(key)
                        chips = diskChips
                    }
                }
            }
            var text = ChatMessageVisibleText.visibleText(in: message)
            // A voice note's message body is its on-device transcript (or the "See attached." placeholder);
            // either way the audio bubble is the whole UI, so never render the text for an audio turn.
            if chips.contains(where: { $0.kind == .audio }) {
                text = ""
            } else if !images.isEmpty || !chips.isEmpty,
                      text.trimmingCharacters(in: .whitespacesAndNewlines) == "See attached."
            {
                text = ""
            }
            // Extract [embed] canvas shortcodes from assistant turns; they render as cards, not raw text.
            var embeds: [CanvasEmbed] = []
            if role == "assistant" {
                let parsed = CanvasEmbedParser.parse(messageID: message.id.uuidString, text: text)
                text = parsed.text
                embeds = parsed.embeds
            }
            let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard hasText || !images.isEmpty || !chips.isEmpty || !embeds.isEmpty else { continue }
            let isUser = role == "user"
            // A pure-text tool-use preamble collapses into the progress trail rather than its own row.
            if !isUser, hasText, images.isEmpty, chips.isEmpty, embeds.isEmpty,
               Self.isToolUseTurn(message)
            {
                pendingProgress.append(text)
                if let reasoning = ChatMessageVisibleText.reasoningText(in: message) {
                    pendingReasoning.append(reasoning)
                }
                pendingProgressTimestamp = message.timestamp
                continue
            }
            // Any real row flushes the accumulated progress trail so it sits just above the answer.
            flushProgress()
            // Canvas cards render ABOVE the reply text so they read as part of the reply, not as a
            // detached row beneath the text + timestamp.
            for embed in embeds {
                result.append(ChatDisplayRow(canvasEmbed: embed, timestamp: message.timestamp))
            }
            if hasText || !images.isEmpty || !chips.isEmpty {
                result.append(ChatDisplayRow(
                    id: message.id,
                    isUser: isUser,
                    text: text,
                    timestamp: message.timestamp,
                    isError: message.errorMessage != nil,
                    images: images,
                    chips: chips))
            }
            allEmbeds.append(contentsOf: embeds)
        }
        // While a live turn is streaming, ITS preamble/tool steps are shown by the live indicator, so keep
        // the trailing persisted preambles OUT of the transcript rows — otherwise the same steps would show
        // twice. Once the turn is no longer running, flush them as the collapsed "Worked through N steps"
        // row (the resting history view). Reads the turn's typed state — no phase guessing.
        if self.viewModel.liveTurn?.state == .running {
            pendingProgress.removeAll()
            pendingProgressTimestamp = nil
        } else {
            flushProgress()
        }
        let nextRows = Self.withDaySeparators(result)
        // Animate row insertions (spring settle + the per-row `.transition`) only during a live turn, so a
        // bulk history load / session switch repopulates instantly instead of cascading every row in.
        let animateRowInsertion = self.pinScrollPending || self.pinTurnID != nil || self.viewModel.liveTurn != nil
        let oldIDs = Set(rows.map(\.id))
        // Fix A: identical projection → skip reassigning `self.rows` entirely. A safety-net history refetch
        // that changed nothing visible (see the pending-run probes) would otherwise reassign the whole
        // array and make LazyVStack re-diff — the idle-time blank-until-touch. Canvas index still updates.
        guard nextRows != self.rows else {
            ChatTimeline.mark("view.rebuildRows SKIPPED (identical) rows=\(nextRows.count)")
            CanvasEmbedIndex.shared.update(fromTranscriptOrder: allEmbeds)
            return
        }
        let progressCount = nextRows.filter { !$0.progressLines.isEmpty }.count
        let answerCount = nextRows.filter(Self.isAnswerRow).count
        // ID churn: new/removed row identities. A high churn on a rebuild that didn't add real content is
        // the LazyVStack blank-until-touch smell (ForEach identity thrash from optimistic→canonical swaps).
        let newIDs = Set(nextRows.map(\.id))
        let addedIDs = newIDs.subtracting(oldIDs).count
        let removedIDs = oldIDs.subtracting(newIDs).count
        ChatTimeline.mark(
            "view.rebuildRows rows=\(nextRows.count) (prev=\(self.rows.count)) progress=\(progressCount) "
                + "answers=\(answerCount) idChurn=+\(addedIDs)/-\(removedIDs) "
                +
                "working=\(self.isAssistantWorking) animated=\(animateRowInsertion && nextRows.count != self.rows.count)")
        // A reply that just finalized — a new answer row appearing while a live turn is present — reveals
        // once so it streams in as it settles from the shimmer. A cold history load has no live turn, so
        // existing answers are recorded without revealing.
        if self.viewModel.liveTurn != nil,
           let fresh = nextRows.last(where: { Self.isAnswerRow($0) && !self.knownAnswerIDs.contains($0.id) })
        {
            self.revealAnswerID = fresh.id
        }
        self.knownAnswerIDs = Set(nextRows.filter(Self.isAnswerRow).map(\.id))
        if animateRowInsertion, nextRows.count != self.rows.count {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                self.rows = nextRows
            }
        } else {
            self.rows = nextRows
        }
        // Feed the drawer's Canvas archive from the same source as the inline cards.
        CanvasEmbedIndex.shared.update(fromTranscriptOrder: allEmbeds)
    }

    /// A rendered assistant answer row (not a user turn, day divider, steps trail, or canvas card).
    private static func isAnswerRow(_ row: ChatDisplayRow) -> Bool {
        !row.isUser
            && !row.text.isEmpty
            && row.canvasEmbed == nil
            && row.daySeparator == nil
            && row.progressLines.isEmpty
    }

    /// Insert a centered day-divider row wherever the calendar day changes between consecutive
    /// timestamped rows, so a transcript spanning days is legible ("Today" / "Monday" / "Sep 3").
    private static func withDaySeparators(_ rows: [ChatDisplayRow]) -> [ChatDisplayRow] {
        let calendar = Calendar.current
        var out: [ChatDisplayRow] = []
        var lastDay: DateComponents?
        for row in rows {
            if let timestamp = row.timestamp {
                let date = Date(timeIntervalSince1970: timestamp > 4_000_000_000 ? timestamp / 1000 : timestamp)
                let day = calendar.dateComponents([.year, .month, .day], from: date)
                if day != lastDay {
                    let key = "\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)"
                    out.append(ChatDisplayRow(daySeparator: Self.daySeparatorLabel(for: date), dayKey: key))
                    lastDay = day
                }
            }
            out.append(row)
        }
        return out
    }

    /// "Today" / "Yesterday" / weekday within the last week / "MMM d" / "MMM d, yyyy" once the year differs.
    private static func daySeparatorLabel(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        let formatter = DateFormatter()
        let startOfDate = calendar.startOfDay(for: date)
        let startOfNow = calendar.startOfDay(for: Date())
        let daysAgo = calendar.dateComponents([.day], from: startOfDate, to: startOfNow).day ?? 99
        if daysAgo > 0, daysAgo < 7 {
            formatter.dateFormat = "EEEE" // weekday name for the last week
            return formatter.string(from: date)
        }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: Date())
        formatter.dateFormat = sameYear ? "MMM d" : "MMM d, yyyy"
        return formatter.string(from: date)
    }

    /// A tool-use turn: the model narrates a one-line preamble then calls tools. Keyed on stopReason
    /// ("toolUse") or the presence of a toolCall content part — model-agnostic across providers.
    private static func isToolUseTurn(_ message: OpenClawChatMessage) -> Bool {
        if let stop = message.stopReason?.lowercased(), stop.contains("tool") {
            return true
        }
        return message.content.contains { ($0.type ?? "").lowercased().contains("toolcall") }
    }

    /// Project a message's attachment content blocks into renderable pieces, once, off the render path.
    /// Images decode to thumbnails when their bytes are present (user sends embed base64 — see
    /// ChatViewModel.send); everything else (files, voice notes, and images whose bytes a history reload
    /// dropped) becomes a metadata chip so we never fall back to the raw "See attached." text.
    private static func decodeAttachments(
        from message: OpenClawChatMessage) -> (images: [UIImage], chips: [ChatAttachmentChip])
    {
        var images: [UIImage] = []
        var chips: [ChatAttachmentChip] = []
        for block in message.content {
            let type = (block.type ?? "").lowercased()
            guard type == "image" || type == "file" || type == "attachment" else { continue }
            let mime = (block.mimeType ?? "").lowercased()
            let isImage = type == "image" || mime.hasPrefix("image/")
            if isImage, let image = Self.decodeImage(block) {
                images.append(image)
            } else if mime.hasPrefix("audio/") {
                chips.append(ChatAttachmentChip(
                    kind: .audio,
                    title: "Voice note",
                    fileName: block.fileName,
                    payload: Self.decodeData(block),
                    durationSeconds: block.durationSeconds ?? 0))
            } else if isImage {
                chips.append(ChatAttachmentChip(
                    kind: .photo,
                    title: block.fileName ?? "Photo",
                    fileName: block.fileName,
                    payload: nil,
                    durationSeconds: 0))
            } else {
                chips.append(ChatAttachmentChip(
                    kind: .file,
                    title: block.fileName ?? "Attachment",
                    fileName: block.fileName,
                    payload: Self.decodeData(block),
                    durationSeconds: 0))
            }
        }
        return (images, chips)
    }

    /// Decode a content block's base64 payload to raw bytes (audio for playback, files for QuickLook).
    private static func decodeData(_ block: OpenClawChatMessageContent) -> Data? {
        guard let raw = block.content?.value as? String else { return nil }
        let base64 = raw.firstIndex(of: ",").map { String(raw[raw.index(after: $0)...]) } ?? raw
        return Data(base64Encoded: base64)
    }

    /// Stable per-turn key for the image cache. Prefers the idempotency key, which the gateway persists
    /// on the canonical user row (see ChatViewModel+HistoryReconciliation.messageIdentityKey), so it
    /// survives the timestamp/id churn of reconciliation.
    private static func attachmentCacheKey(for message: OpenClawChatMessage) -> String? {
        guard message.role.lowercased() == "user" else { return nil }
        let key = message.idempotencyKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let key, !key.isEmpty else { return nil }
        return key
    }

    private static func decodeImage(_ block: OpenClawChatMessageContent) -> UIImage? {
        guard let raw = block.content?.value as? String else { return nil }
        // Tolerate a `data:image/...;base64,` prefix as well as a bare base64 payload.
        let base64 = raw.firstIndex(of: ",").map { String(raw[raw.index(after: $0)...]) } ?? raw
        return Data(base64Encoded: base64).flatMap(UIImage.init(data:))
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

    private var composerGlassFill: Color {
        self.colorScheme == .dark
            ? Color(red: 64 / 255, green: 64 / 255, blue: 64 / 255).opacity(0.2)
            : Color(red: 245 / 255, green: 244 / 255, blue: 250 / 255).opacity(0.2)
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            Button(action: { self.onOpenDrawer?() }) {
                HStack(spacing: 0) {
                    Image("ChatAvatarImage")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 34, height: 34)
                        .clipShape(Circle())
                        .overlay(alignment: .bottomTrailing) {
                            // WhatsApp-style presence badge: shown only while the transport is healthy
                            // (live delivery possible). The ring matches the canvas so it reads as a cutout.
                            if self.viewModel.healthOK {
                                Circle()
                                    .fill(Self.onlineGreen)
                                    .frame(width: 11, height: 11)
                                    .overlay { Circle().stroke(self.onlineRing, lineWidth: 2) }
                                    .offset(x: 1, y: 1)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .animation(.smooth(duration: 0.25), value: self.viewModel.healthOK)
                        .padding(3)
                    Text("OpenClaw")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .padding(.trailing, 14)
                }
                .background { self.glassCapsule }
            }
            .buttonStyle(.plain)
            .disabled(self.onOpenDrawer == nil)

            Spacer()

            Button(action: self.onOpenSettings) {
                Image("ChatSettingsGlyph")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(Color.primary)
                    .frame(width: 40, height: 40)
                    .background { self.glassCapsule }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .shadow(color: .black.opacity(0.15), radius: 25, x: 0, y: 0)
    }

    private var glassCapsule: some View {
        ChatGlassBackground(fill: self.glassFill)
    }

    /// A soft blur that fades out downward, covering the status bar + pill zone so transcript text
    /// scrolling underneath doesn't clash with the clock/notch. Sits below the pills, above content.
    private var topScrim: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            // `.ultraThinMaterial` is a light frost that samples/lightens whatever scrolls beneath, so in
            // dark mode we tint it toward the near-black canvas to keep the band dark and content-
            // independent. Light mode's frosted-white material already matches the canvas.
            .overlay { self.canvas.opacity(self.colorScheme == .dark ? 0.72 : 0) }
            .mask {
                // Cap the mask at ~50% so the blur is applied at half strength (sharp content shows
                // through), then fade to clear — a subtler scrim than a full-opacity material.
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.6), location: 0),
                        .init(color: .black.opacity(0.6), location: 0.55),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom)
            }
            .frame(height: 110)
            .frame(maxWidth: .infinity)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
    }

    // MARK: - Composer

    private var composer: some View {
        self.composerBar
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            // Composer-local tap catcher: closes the tray on taps inside the composer's own bounds (the
            // full-screen catcher covers everything above). Kept separate so it can't eat outside taps.
            .overlay {
                if self.showsAttachmentTray {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture { self.closeAttachmentTray() }
                }
            }
            // The tray is the plus button expanded: it grows out of the button's bottom-leading corner,
            // taking the place the button vacates (see the plus button's sequenced opacity below).
            .overlay(alignment: .bottomLeading) {
                if self.showsAttachmentTray {
                    self.attachmentTray
                        .padding(.leading, 14)
                        .padding(.bottom, 10)
                        .offset(y: self.attachmentGroupLift)
                        .transition(.scale(scale: 0.1, anchor: .bottomLeading).combined(with: .opacity))
                }
            }
    }

    private var composerBar: some View {
        // Bottom-aligned so the +/send buttons and the mic stay pinned as the field grows upward.
        HStack(alignment: .bottom, spacing: 10) {
            Button {
                if self.voiceRecorder.isRecording {
                    self.cancelRecording()
                } else if let note = self.stagedVoiceNote {
                    withAnimation(.spring(duration: 0.25)) {
                        self.viewModel.attachments.removeAll { $0.id == note.id }
                    }
                } else if self.showsAttachmentTray {
                    self.closeAttachmentTray()
                } else {
                    self.openAttachmentTray()
                }
            } label: {
                Image(self.plusButtonShowsClose ? "ChatCloseGlyph" : "ChatPlusGlyph")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .foregroundStyle(Color.primary)
                    .frame(width: 36, height: 36)
                    .background { ChatGlassBackground(fill: self.plusButtonFill) }
            }
            // The button yields its place to the tray: fade out fast when opening (first), then reappear
            // only after the tray has shrunk back on close.
            .opacity(self.showsAttachmentTray ? 0 : 1)
            .animation(
                self.showsAttachmentTray
                    ? .easeOut(duration: 0.1)
                    // Fade in promptly on close (no delay) so the button is visible through its dip.
                    : .easeOut(duration: 0.15),
                value: self.showsAttachmentTray)
            // Persistent group lift: rises on open, glides back on close (smooth, so it doesn't fight
            // the dip below).
            .offset(y: self.attachmentGroupLift)
            // Close bounce: the button draws down past its resting spot, then recoils up to rest.
            .keyframeAnimator(initialValue: CGFloat.zero, trigger: self.showsAttachmentTray) { view, dip in
                view.offset(y: dip)
            } keyframes: { _ in
                // Opening uses 0 (only the lift moves); closing dips down to 12 then springs back to 0.
                SpringKeyframe(self.showsAttachmentTray ? 0 : 12, duration: 0.16, spring: .snappy)
                SpringKeyframe(CGFloat.zero, duration: 0.34, spring: .bouncy)
            }

            self.composerFieldContent
                .background {
                    GeometryReader { proxy in
                        Color.clear.onChange(of: proxy.size.height, initial: true) { _, height in
                            self.inputHeight = height
                        }
                    }
                }
                .animation(.spring(duration: 0.3), value: self.viewModel.attachments.isEmpty)

            Button(action: self.trailingButtonAction) {
                ZStack {
                    Circle().fill(Self.bubbleRed.opacity(self.trailingButtonDisabled ? 0.5 : 1))
                    self.trailingButtonIcon
                }
                .frame(width: 36, height: 36)
            }
            .disabled(self.trailingButtonDisabled)
            .shadow(color: .black.opacity(0.2), radius: 25, x: 0, y: 0)
        }
    }

    /// A staged voice note plays back in the field itself; otherwise a recording readout, the plain pill
    /// input, or — when other attachments are staged — a glass panel stacking the strip over the input.
    @ViewBuilder private var composerFieldContent: some View {
        if self.voiceRecorder.isRecording {
            self.recordingField
                .frame(minHeight: 36)
                .background { self.fieldPillBackground }
        } else if let voiceNote = stagedVoiceNote {
            StagedVoiceNoteField(
                data: voiceNote.data,
                durationSeconds: voiceNote.durationSeconds ?? 0)
                .frame(minHeight: 36)
                .background {
                    ChatGlassBackground(
                        shape: RoundedRectangle(cornerRadius: 15, style: .continuous),
                        fill: self.composerGlassFill,
                        hairline: true)
                }
        } else if self.viewModel.attachments.isEmpty {
            self.inputField
                .frame(minHeight: 36)
                .background { self.fieldPillBackground }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                self.pendingAttachmentStrip
                self.inputField
            }
            .padding(5)
            .background { ChatGlassPanel(fill: self.composerGlassFill, cornerRadius: 15) }
        }
    }

    /// The first staged audio attachment (a voice note), if any — it takes over the composer field.
    private var stagedVoiceNote: OpenClawPendingAttachment? {
        self.viewModel.attachments.first { $0.type == "audio" || $0.mimeType.hasPrefix("audio/") }
    }

    /// The leading button becomes a discard/cancel ✕ while recording or while a voice note is staged.
    private var plusButtonShowsClose: Bool {
        self.voiceRecorder.isRecording || self.stagedVoiceNote != nil
    }

    /// Pill while single-line; tightens to 15pt once the text wraps so a tall field isn't a stadium.
    private var fieldPillBackground: some View {
        ChatGlassBackground(
            shape: RoundedRectangle(cornerRadius: self.composerFieldCornerRadius, style: .continuous),
            fill: self.composerGlassFill,
            hairline: true)
    }

    private var inputField: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(self.composerPlaceholder, text: self.$viewModel.input, axis: .vertical)
                .font(.system(size: 16))
                .lineLimit(1...8)
                .onSubmit(self.sendCurrentInput)
            // The mic only shows in the empty state — once attachments are staged the field is for a
            // caption (or is taken over by a voice note), so recording a new note there is out of place.
            if self.viewModel.attachments.isEmpty {
                Button(action: self.startRecording) {
                    Image("ChatMicGlyph")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .foregroundStyle(Color.primary.opacity(0.9))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private var recordingField: some View {
        // Cancel lives on the leading composer button (turns to ✕ while recording), so the field is just
        // the level meter + elapsed time.
        HStack(spacing: 10) {
            Circle()
                .fill(Self.bubbleRed)
                .frame(width: 8, height: 8)
            // Live mic levels scroll left as they arrive (no progress — it's happening now).
            ChatAmplitudeWaveform(
                levels: self.voiceRecorder.liveLevels,
                color: Color.primary.opacity(0.4))
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
            Text(Self.durationLabel(self.voiceRecorder.elapsedSeconds))
                .font(.system(size: 16).monospacedDigit())
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(minHeight: 36)
    }

    /// While recording the trailing button becomes a stop control (and is never disabled, so a take can
    /// always be finished); otherwise it is the usual talk/send control.
    private var trailingButtonDisabled: Bool {
        if self.voiceRecorder.isRecording {
            return false
        }
        return self.sendDisabled
    }

    private func trailingButtonAction() {
        if self.voiceRecorder.isRecording {
            self.finishRecording()
        } else {
            self.talkOrSend()
        }
    }

    @ViewBuilder private var trailingButtonIcon: some View {
        if self.voiceRecorder.isRecording {
            Image(systemName: "stop.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
        } else if self.hasDraft {
            Image(systemName: "arrow.up")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
        } else if self.appModel.talkMode.isEnabled {
            // Voice session active: the red button becomes a cancel affordance — tapping it ends the session
            // (`onOpenTalk` toggles voice off). The waveform reads as "start", so swap in the ✕ glyph.
            Image("ChatCloseGlyph")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(.white)
        } else {
            ChatWaveformGlyph()
        }
    }

    /// A staged attachment (or typed text) counts as a draft, so the send arrow shows and fires even
    /// for an image-only message with no text.
    private var hasDraft: Bool {
        !self.viewModel.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !self.viewModel.attachments.isEmpty
    }

    /// Live delivery is only possible once the transport is healthy. Gate sending on it so a draft
    /// can't queue offline into a gateway that may not be able to replay it.
    private var canSendLive: Bool {
        self.viewModel.healthOK
    }

    /// Only the send action is gated; the empty-field talk button stays available while connecting.
    private var sendDisabled: Bool {
        self.hasDraft && !self.canSendLive
    }

    private var composerPlaceholder: String {
        self.canSendLive ? "Chat with Molty" : "Connecting…"
    }

    private func talkOrSend() {
        if self.hasDraft {
            self.sendCurrentInput()
        } else {
            self.onOpenTalk()
        }
    }

    private func sendCurrentInput() {
        guard self.hasDraft, self.canSendLive else { return }
        // A voice note with no typed caption sends its on-device transcript as the message body so
        // OpenClaw can read it (hidden in the UI — see rebuildRows). Ensure the transcript is ready:
        // use the one prepared on finish, else transcribe on the spot (first note may download the model).
        if self.viewModel.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let note = stagedVoiceNote
        {
            Task { @MainActor in
                let transcript: String? = if let cached = self.voiceTranscripts[note.id] {
                    cached
                } else {
                    await VoiceNoteTranscriber.transcribe(data: note.data)
                }
                if let transcript, !transcript.isEmpty,
                   self.viewModel.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   self.viewModel.attachments.contains(where: { $0.id == note.id })
                {
                    self.viewModel.input = transcript
                }
                self.armAndSend()
            }
            return
        }
        self.armAndSend()
    }

    private func armAndSend() {
        ChatTimeline.begin("SEND (tap)")
        self.replyIntroArmed = true
        // Pin the turn we're about to send: the next `rows` change (its optimistic bubble) springs to top.
        self.pinScrollPending = true
        // Drop the retained top so the new question re-measures instead of sizing off the previous turn.
        self.pinnedQuestionTop = nil
        // Hold the "Thinking" node back until the user bubble's spring settles (matches the row-insert /
        // pin spring duration), so it doesn't ride that spring and pop in early.
        self.nodeReady = false
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.42))
            self.nodeReady = true
        }
        self.viewModel.send()
    }

    // MARK: - Voice notes

    private func startRecording() {
        OpenClawHaptics.tap()
        Task { await self.voiceRecorder.start() }
    }

    private func finishRecording() {
        guard let recording = voiceRecorder.finish() else { return }
        OpenClawHaptics.tap()
        Task { @MainActor in
            await self.viewModel.addVoiceNoteAttachment(
                fileURL: recording.fileURL,
                durationSeconds: recording.durationSeconds)
            // Reset .finished -> .idle so the next take can start (start() only proceeds from .idle).
            // addVoiceNoteAttachment already consumed/removed the file, so cancel()'s cleanup is a no-op.
            self.voiceRecorder.cancel()
            // Transcribe on-device in the background so the transcript is ready by the time we send.
            guard let note = self.viewModel.attachments.last(where: { $0.mimeType.hasPrefix("audio/") })
            else { return }
            let id = note.id
            let data = note.data
            Task {
                if let transcript = await VoiceNoteTranscriber.transcribe(data: data),
                   !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    self.voiceTranscripts[id] = transcript
                }
            }
        }
    }

    private func cancelRecording() {
        OpenClawHaptics.tap()
        self.voiceRecorder.cancel()
    }

    private static func durationLabel(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Attachment tray

    private var plusButtonFill: Color {
        if self.showsAttachmentTray {
            return Color(red: 64 / 255, green: 64 / 255, blue: 64 / 255).opacity(0.2)
        }
        return self.composerGlassFill
    }

    /// The +/tray group lifts as one when the tray opens (~5% nudge), then springs back on close. The
    /// same value drives the plus button and the tray overlay so they move together.
    private var attachmentGroupLift: CGFloat {
        self.showsAttachmentTray ? -12 : 0
    }

    private var attachmentTray: some View {
        VStack(alignment: .leading, spacing: 23) {
            self.trayRow("ChatStickerGlyph", "GIFs", iconSize: 22) { self.showsGifLibrary = true }
            self.trayRow("ChatImagePlusGlyph", "Images", iconSize: 22) { self.showsPhotoLibrary = true }
            self.trayRow("ChatCameraGlyph", "Camera", iconSize: 22) { self.showsCamera = true }
            self.trayRow("ChatFilesGlyph", "Files", iconSize: 24) { self.showsFileImporter = true }
        }
        .padding(17)
        .frame(width: 200, alignment: .leading)
        .background {
            ChatGlassPanel(
                fill: self.colorScheme == .dark
                    ? Color(red: 64 / 255, green: 64 / 255, blue: 64 / 255).opacity(0.2)
                    : Color.white.opacity(0.4),
                cornerRadius: 20)
        }
    }

    private func trayRow(
        _ asset: String,
        _ label: String,
        iconSize: CGFloat,
        action: @escaping () -> Void) -> some View
    {
        Button {
            OpenClawHaptics.tap()
            self.closeAttachmentTray()
            action()
        } label: {
            HStack(spacing: 12) {
                Image(asset)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                    .opacity(0.9)
                Text(label)
                    .font(.system(size: 17))
            }
            .foregroundStyle(Color.primary)
        }
    }

    private func openAttachmentTray() {
        withAnimation(.spring(duration: 0.35)) {
            self.showsAttachmentTray = true
        }
    }

    private func closeAttachmentTray() {
        // Smooth glide for the lift return; the plus button's keyframe dip provides the visible bounce.
        withAnimation(.spring(duration: 0.3)) {
            self.showsAttachmentTray = false
        }
    }

    // MARK: - Pending attachment strip

    private var pendingAttachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(self.viewModel.attachments) { attachment in
                    self.pendingAttachmentTile(attachment)
                }
            }
        }
    }

    private func pendingAttachmentTile(_ attachment: OpenClawPendingAttachment) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let preview = attachment.preview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFill()
                } else {
                    // Non-image file: a red card with its extension + name (no preview in the composer).
                    self.fileCardTile(attachment)
                }
            }
            .frame(width: 100, height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Button {
                OpenClawHaptics.tap()
                withAnimation(.spring(duration: 0.25)) {
                    self.viewModel.removeAttachment(attachment.id)
                }
            } label: {
                Image("ChatCloseGlyph")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
                    .foregroundStyle(.black)
                    .padding(2)
                    .background { Circle().fill(.white) }
                    // Keep the small chip pinned to the corner, but extend the tappable area inward over
                    // the image so the tap isn't lost to the horizontal scroll gesture.
                    .frame(width: 34, height: 34, alignment: .topTrailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(4)
        }
    }

    /// Composer file card: a red tile showing the extension label (top) and the file's name (bottom).
    private func fileCardTile(_ attachment: OpenClawPendingAttachment) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 195 / 255, green: 63 / 255, blue: 51 / 255))
            Text(Self.fileExtensionLabel(for: attachment))
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.leading, 6)
                .padding(.top, 10)
            Text(attachment.fileName.isEmpty
                ? "file"
                : (attachment.fileName as NSString).deletingPathExtension)
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 11)
        }
        .frame(width: 100, height: 100)
    }

    private static func fileExtensionLabel(for attachment: OpenClawPendingAttachment) -> String {
        let ext = (attachment.fileName as NSString).pathExtension
        return ext.isEmpty ? "FILE" : ext.uppercased()
    }

    // MARK: - Attachment ingestion

    /// Load picked photos as JPEG data into the shared pipeline. Clearing the selection first lets the
    /// same photo be re-picked later, and turns the follow-up empty `onChange` into a no-op.
    private func ingestPickedPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        self.photoSelection = []
        Task { @MainActor in
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    self.viewModel.addImageAttachment(data: data, fileName: "image.jpg", mimeType: "image/jpeg")
                }
            }
        }
    }

    private func ingestCameraImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.9) else { return }
        self.viewModel.addImageAttachment(data: data, fileName: "photo.jpg", mimeType: "image/jpeg")
    }

    /// Stage picked GIFs (and any other library image) verbatim via `addFileAttachment`, preserving the
    /// original type so an animated GIF keeps its frames instead of being flattened to a still JPEG.
    private func ingestPickedGifs(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        self.gifSelection = []
        Task { @MainActor in
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                let contentType = item.supportedContentTypes.first
                let ext = contentType?.preferredFilenameExtension ?? "gif"
                let mime = contentType?.preferredMIMEType ?? "image/gif"
                self.viewModel.addFileAttachment(data: data, fileName: "image.\(ext)", mimeType: mime)
            }
        }
    }

    private func ingestPickedFiles(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result else { return }
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            guard let data = try? Data(contentsOf: url) else { continue }
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            self.viewModel.addFileAttachment(data: data, fileName: url.lastPathComponent, mimeType: mime)
        }
    }
}

// MARK: - Image disk cache

/// Persists a sent turn's attachment images to the Caches directory, keyed by the message's stable
/// idempotency key, so they survive an app relaunch — the gateway drops the bytes from the canonical
/// transcript, so this is the only place they remain. Caches are OS-purgeable, which is acceptable here.
private enum ChatImageDiskCache {
    private static let directory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ChatAttachmentImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func fileURL(key: String, index: Int) -> URL {
        // Base64 of the key, made filename-safe, keeps a stable 1:1 name without a separate index.
        let safe = Data(key.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return self.directory.appendingPathComponent("\(safe)-\(index).jpg")
    }

    /// Encode on the calling (main) actor — UIImage isn't Sendable — then write off-main.
    static func store(_ images: [UIImage], key: String) {
        let datas = images.compactMap { $0.jpegData(compressionQuality: 0.9) }
        Task.detached(priority: .utility) {
            for (index, data) in datas.enumerated() {
                try? data.write(to: self.fileURL(key: key, index: index))
            }
        }
    }

    static func load(key: String) -> [UIImage] {
        var result: [UIImage] = []
        var index = 0
        while let data = try? Data(contentsOf: fileURL(key: key, index: index)),
              let image = UIImage(data: data)
        {
            result.append(image)
            index += 1
        }
        return result
    }
}

/// Persists audio/file chips (metadata + raw payload) so voice notes and files survive a relaunch —
/// the counterpart to `ChatImageDiskCache`, since the gateway drops the bytes from the canonical row.
private enum ChatChipDiskCache {
    private struct Entry: Codable {
        let kind: String
        let title: String
        let fileName: String?
        let durationSeconds: Double
        let hasPayload: Bool
    }

    private static let directory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ChatAttachmentChips", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func safe(_ key: String) -> String {
        Data(key.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func manifestURL(_ key: String) -> URL {
        self.directory.appendingPathComponent("\(self.safe(key)).json")
    }

    private static func payloadURL(_ key: String, index: Int) -> URL {
        self.directory.appendingPathComponent("\(self.safe(key))-\(index).bin")
    }

    static func store(_ chips: [ChatAttachmentChip], key: String) {
        let entries = chips.map {
            Entry(
                kind: $0.kind.rawValue,
                title: $0.title,
                fileName: $0.fileName,
                durationSeconds: $0.durationSeconds,
                hasPayload: $0.payload != nil)
        }
        let payloads = chips.map(\.payload)
        guard let manifest = try? JSONEncoder().encode(entries) else { return }
        Task.detached(priority: .utility) {
            try? manifest.write(to: self.manifestURL(key))
            for (index, payload) in payloads.enumerated() {
                if let payload {
                    try? payload.write(to: self.payloadURL(key, index: index))
                }
            }
        }
    }

    static func load(key: String) -> [ChatAttachmentChip] {
        guard let manifest = try? Data(contentsOf: manifestURL(key)),
              let entries = try? JSONDecoder().decode([Entry].self, from: manifest)
        else { return [] }
        return entries.enumerated().map { index, entry in
            let payload = entry.hasPayload ? try? Data(contentsOf: self.payloadURL(key, index: index)) : nil
            return ChatAttachmentChip(
                kind: ChatAttachmentChip.Kind(rawValue: entry.kind) ?? .file,
                title: entry.title,
                fileName: entry.fileName,
                payload: payload ?? nil,
                durationSeconds: entry.durationSeconds)
        }
    }
}

// MARK: - Display model

/// A non-image attachment projected for the transcript: a voice note (playable), a document (QuickLook
/// thumbnail), or a bytes-less image. Carries the raw payload so audio can play and files can thumbnail.
private struct ChatAttachmentChip: Identifiable {
    enum Kind: String {
        case audio
        case file
        case photo
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let fileName: String?
    let payload: Data?
    let durationSeconds: Double

    var fileExtension: String? {
        guard let name = fileName else { return nil }
        let ext = (name as NSString).pathExtension
        return ext.isEmpty ? nil : ext
    }
}

/// Flat, pre-projected transcript row. Holding parsed text here keeps the parser off the render path.
private struct ChatDisplayRow: Identifiable, Equatable {
    let id: String
    let isUser: Bool
    let text: String
    let timestamp: Double?
    let isError: Bool
    /// A live streaming row shows no meta (timestamp/tick) and never collides with a persisted id.
    let isStreaming: Bool
    /// Decoded inline images (attachments the user sent); empty for plain text turns.
    let images: [UIImage]
    /// Non-image attachments (files, voice notes, bytes-less images) shown as metadata chips.
    let chips: [ChatAttachmentChip]
    /// Set for a `[embed]` canvas card projected from an assistant message; nil otherwise.
    let canvasEmbed: CanvasEmbed?
    /// Non-empty for a collapsed tool-use "steps" trail; each entry is one turn's preamble line.
    let progressLines: [String]
    /// The turn's persisted reasoning, shown as the nested "Thought" group in the steps sheet; nil when the
    /// provider saved no thinking. Only ever set on a `progressLines` row.
    let reasoningText: String?
    /// Set for a centered day-divider row (e.g. "Today", "Monday", "Sep 3"); nil for message rows.
    let daySeparator: String?

    init(
        id: UUID,
        isUser: Bool,
        text: String,
        timestamp: Double?,
        isError: Bool,
        images: [UIImage] = [],
        chips: [ChatAttachmentChip] = [])
    {
        self.id = id.uuidString
        self.isUser = isUser
        self.text = text
        self.timestamp = timestamp
        self.isError = isError
        self.isStreaming = false
        self.images = images
        self.chips = chips
        self.canvasEmbed = nil
        self.progressLines = []
        self.reasoningText = nil
        self.daySeparator = nil
    }

    init(streamingText: String) {
        self.id = "streaming"
        self.isUser = false
        self.text = streamingText
        self.timestamp = nil
        self.isError = false
        self.isStreaming = true
        self.images = []
        self.chips = []
        self.canvasEmbed = nil
        self.progressLines = []
        self.reasoningText = nil
        self.daySeparator = nil
    }

    /// A completed realtime voice turn (display-only). Carries a timestamp so a committed user turn shows the
    /// sent meta, matching a normal sent bubble.
    init(voiceTurn: TalkVoiceTurn) {
        self.id = voiceTurn.id
        self.isUser = voiceTurn.isUser
        self.text = voiceTurn.text
        self.timestamp = voiceTurn.timestamp
        self.isError = false
        self.isStreaming = false
        self.images = []
        self.chips = []
        self.canvasEmbed = nil
        self.progressLines = []
        self.reasoningText = nil
        self.daySeparator = nil
    }

    /// The assistant's in-progress spoken reply during a realtime session — streams in place (stable id).
    init(voiceLiveAssistant text: String) {
        self.id = "voice-live-assistant"
        self.isUser = false
        self.text = text
        self.timestamp = nil
        self.isError = false
        self.isStreaming = true
        self.images = []
        self.chips = []
        self.canvasEmbed = nil
        self.progressLines = []
        self.reasoningText = nil
        self.daySeparator = nil
    }

    init(canvasEmbed: CanvasEmbed, timestamp: Double?) {
        self.id = canvasEmbed.id
        self.isUser = false
        self.text = ""
        self.timestamp = timestamp
        self.isError = false
        self.isStreaming = false
        self.images = []
        self.chips = []
        self.canvasEmbed = canvasEmbed
        self.progressLines = []
        self.reasoningText = nil
        self.daySeparator = nil
    }

    init(progressLines: [String], reasoning: String?, timestamp: Double?) {
        // Deterministic id from content so identical trails diff stably across rebuilds.
        self.id = "progress-\(progressLines.joined(separator: "|").hashValue)"
        self.isUser = false
        self.text = ""
        self.timestamp = timestamp
        self.isError = false
        self.isStreaming = false
        self.images = []
        self.chips = []
        self.canvasEmbed = nil
        self.progressLines = progressLines
        self.reasoningText = reasoning
        self.daySeparator = nil
    }

    init(daySeparator label: String, dayKey: String) {
        self.id = "day-\(dayKey)"
        self.isUser = false
        self.text = ""
        self.timestamp = nil
        self.isError = false
        self.isStreaming = false
        self.images = []
        self.chips = []
        self.canvasEmbed = nil
        self.progressLines = []
        self.reasoningText = nil
        self.daySeparator = label
    }

    /// UIImage/chip aren't Equatable, so compare their derived counts; the row id + text already capture
    /// material message changes for SwiftUI diffing. The artifact's updatedAt captures live canvas edits.
    static func == (lhs: ChatDisplayRow, rhs: ChatDisplayRow) -> Bool {
        lhs.id == rhs.id && lhs.isUser == rhs.isUser && lhs.text == rhs.text
            && lhs.timestamp == rhs.timestamp && lhs.isError == rhs.isError
            && lhs.isStreaming == rhs.isStreaming && lhs.images.count == rhs.images.count
            && lhs.chips.count == rhs.chips.count
            && lhs.canvasEmbed?.id == rhs.canvasEmbed?.id
            && lhs.progressLines == rhs.progressLines
            && lhs.reasoningText == rhs.reasoningText
            && lhs.daySeparator == rhs.daySeparator
    }
}

// MARK: - User bubble

/// Short wall-clock label (e.g. "9:41AM") for a transcript timestamp, tolerating ms epochs.
private func chatTimeString(for timestamp: Double?) -> String {
    guard let timestamp else { return "" }
    let date = Date(timeIntervalSince1970: timestamp > 4_000_000_000 ? timestamp / 1000 : timestamp)
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mma"
    return formatter.string(from: date)
}

private struct ChatUserBubble: View {
    let row: ChatDisplayRow
    let colorScheme: ColorScheme
    /// Measured wrapped text width, so the meta row can right-align across the bubble's content width
    /// while the text itself stays left — without forcing the bubble to fill the full max width.
    @State private var textWidth: CGFloat = 0

    private static let maxBubbleWidth: CGFloat = 296

    /// Neutral user bubble: white in light mode, black in dark. Text/controls invert via `textColor`.
    private static let bubbleFill = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .black : .white
    })

    /// Cap the bubble width, then push the capped bubble to the trailing side. Proven wrap-and-hug
    /// recipe: short text hugs, long text wraps at the cap — no truncation.
    var body: some View {
        Group {
            if !self.row.images.isEmpty {
                self.imageBubble
            } else if let audioChip = self.audioChip {
                self.audioStack(audioChip)
            } else if !self.fileChips.isEmpty {
                self.fileStack
            } else {
                self.textBubble
            }
        }
        .frame(maxWidth: Self.maxBubbleWidth, alignment: .trailing)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var audioChip: ChatAttachmentChip? {
        self.row.chips.first { $0.kind == .audio }
    }

    private var fileChips: [ChatAttachmentChip] {
        self.row.chips.filter { $0.kind != .audio }
    }

    /// A voice note plays back in its own bubble; a typed caption becomes a separate bubble below it.
    private func audioStack(_ chip: ChatAttachmentChip) -> some View {
        VStack(alignment: .trailing, spacing: 5) {
            self.audioBubble(data: chip.payload, durationSeconds: chip.durationSeconds)
            if !self.row.text.isEmpty {
                self.textBubble
            }
        }
    }

    /// One card per file; a typed caption becomes a separate bubble below.
    private var fileStack: some View {
        VStack(alignment: .trailing, spacing: 5) {
            ForEach(self.fileChips) { chip in
                self.fileCardBubble(chip)
            }
            if !self.row.text.isEmpty {
                self.textBubble
            }
        }
    }

    private func audioBubble(data: Data?, durationSeconds: Double) -> some View {
        AudioBubbleContent(
            data: data,
            durationSeconds: durationSeconds,
            fill: Self.bubbleFill,
            foreground: self.textColor,
            shape: self.bubbleShape,
            metaRow: AnyView(self.metaRow))
    }

    /// A file card: QuickLook thumbnail on the left, name centered, meta in the corner.
    private func fileCardBubble(_ chip: ChatAttachmentChip) -> some View {
        ZStack(alignment: .topLeading) {
            self.bubbleShape.fill(Self.bubbleFill)
            HStack(spacing: 0) {
                ChatFileThumbnail(
                    payload: chip.payload,
                    fileName: chip.fileName ?? chip.title,
                    fallbackLabel: chip.fileExtension?.uppercased() ?? "FILE")
                    .padding(.leading, 7)
                    .padding(.vertical, 6)
                Text(chip.title)
                    .font(.system(size: 16))
                    .foregroundStyle(self.textColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
            }
        }
        .frame(width: 237, height: 87)
        .overlay(alignment: .bottomTrailing) {
            self.metaRow.padding(.trailing, 10).padding(.bottom, 2)
        }
    }

    private var textBubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            ChatFormattedText(text: self.row.text, isUser: true, textColor: self.textColor)
                .background {
                    GeometryReader { proxy in
                        Color.clear.onChange(of: proxy.size.width, initial: true) { _, width in
                            self.textWidth = width
                        }
                    }
                }

            if self.showsMeta {
                self.metaRow
                    .frame(minWidth: self.textWidth, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background { self.bubbleShape.fill(Self.bubbleFill) }
    }

    /// Image attachment turn: the mosaic fills the bubble; a typed caption (if any) sits below with the
    /// meta row, otherwise a compact meta chip overlays the image's bottom-trailing corner.
    private var imageBubble: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                ChatImageMosaic(images: self.row.images)
                if self.row.text.isEmpty {
                    self.overlayMetaChip
                        .padding(4)
                }
            }
            if !self.row.text.isEmpty {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(self.row.text)
                        .font(.system(size: 16))
                        .foregroundStyle(self.textColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    self.metaRow
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 7)
            }
        }
        .padding(3)
        .frame(width: 250)
        .background { self.bubbleShape.fill(Self.bubbleFill) }
    }

    private var metaRow: some View {
        HStack(spacing: 2) {
            Text(chatTimeString(for: self.row.timestamp))
                .font(.system(size: 12))
                .foregroundStyle(self.textColor.opacity(0.6))
            Image(self.row.isError ? "ChatCheckGlyph" : "ChatCheckCheckGlyph")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(self.textColor.opacity(0.6))
        }
    }

    /// White-on-scrim meta chip for an image-only bubble (no caption row to carry the meta).
    private var overlayMetaChip: some View {
        HStack(spacing: 2) {
            Text(chatTimeString(for: self.row.timestamp))
                .font(.system(size: 12))
                .foregroundStyle(.white)
            Image(self.row.isError ? "ChatCheckGlyph" : "ChatCheckCheckGlyph")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.black.opacity(0.4))
        }
    }

    private var bubbleShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 12,
            bottomLeadingRadius: 12,
            bottomTrailingRadius: 3,
            topTrailingRadius: 12,
            style: .continuous)
    }

    private var showsMeta: Bool {
        !self.row.isStreaming && self.row.timestamp != nil
    }

    private var textColor: Color {
        self.colorScheme == .dark ? .white : .black
    }
}

// MARK: - Audio bubble

/// A sent voice note: play/pause + waveform that fills as it plays, with the elapsed/total time. Holds
/// its own `ChatAudioPlayback` so each bubble tracks its own progress independently.
private struct AudioBubbleContent: View {
    let data: Data?
    let durationSeconds: Double
    let fill: Color
    let foreground: Color
    let shape: UnevenRoundedRectangle
    let metaRow: AnyView
    @State private var playback = ChatAudioPlayback()
    @State private var levels: [Float] = []

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 12) {
                Button {
                    if let data = self.data {
                        self.playback.toggle(data: data)
                    }
                } label: {
                    if self.playback.isPlaying {
                        ChatPauseGlyph(color: self.foreground)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(self.foreground)
                    }
                }
                .disabled(self.data == nil)
                ChatAmplitudeWaveform(
                    levels: self.levels,
                    color: self.foreground.opacity(0.4),
                    activeColor: self.foreground,
                    progress: self.playback.progress)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
                Text(chatDurationLabel(
                    self.playback.currentTime > 0
                        ? self.playback.currentTime
                        : self.durationSeconds))
                    .font(.system(size: 12))
                    .foregroundStyle(self.foreground)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
            self.metaRow
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 242)
        .background { self.shape.fill(self.fill) }
        .task(id: self.data) {
            guard let data = self.data else { return }
            self.levels = await ChatAudioEnvelope.levels(from: data, barCount: 36)
        }
    }
}

// MARK: - Assistant message (bubble-less)

/// Collapsed trail of a run's tool-use preambles ("I'll grab…", "Pulling the timeline…"). Renders as a
/// single muted, tappable "Worked through N steps" line so a multi-tool run reads as one turn, not many.
/// Expands to show each step. De-spams the transcript while keeping the agent's narration available.
/// The single "thinking" node — one persistent element whose label mutates through a run: "Thinking",
/// then the live tool/preamble line (shimmering), and finally settling (static) into the in-transcript
/// "Worked through N steps" trail. Same footprint throughout, so the states crossfade in place instead
/// of rows popping in and out. `shimmer` marks the active phase; `steps.count > 1` makes it expandable.
struct ChatThinkingNode: View {
    let label: String
    let steps: [String]
    let shimmer: Bool
    let colorScheme: ColorScheme
    /// Resting-only: tapping opens the steps sheet. Nil for the live (shimmering) node, which is never tappable.
    var onOpenSteps: (() -> Void)?

    private var tint: Color {
        (self.colorScheme == .dark ? Color.white : .black).opacity(0.55)
    }

    /// Openable only in the resting state — the chevron + steps sheet belong to "Worked through N steps",
    /// never the live footprints. Covers a single step too (we no longer skip 1-step runs).
    private var canOpen: Bool {
        !self.shimmer && !self.steps.isEmpty && self.onOpenSteps != nil
    }

    var body: some View {
        Button {
            self.onOpenSteps?()
        } label: {
            HStack(spacing: 6) {
                // Stable view (no `.id`) so a label change swaps text in place via the shimmer's
                // content transition rather than destroying/recreating the node (which visibly shifted).
                self.collapsedLabel
                if self.canOpen {
                    // Right chevron: the steps now open a sheet, not an inline drop-down.
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(self.tint)
                }
            }
            // Crossfade the label as it mutates ("Thinking" → tool line → "Worked through N steps").
            .animation(.easeInOut(duration: 0.25), value: self.label)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!self.canOpen)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var collapsedLabel: some View {
        if self.shimmer {
            ChatShimmerLabel(text: self.label)
        } else {
            Text(self.label)
                .font(.system(size: 16).italic())
                .foregroundStyle(self.tint)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

/// The reasoning group shown at the top of the steps sheet: the "Thought for Ns" receipt + the full
/// thought body (expandable). Nil when the turn had no reasoning (or none was persisted at rest).
struct ChatStepsReasoning: Equatable {
    let receipt: String
    let text: String
}

/// Identifies the steps payload driving the "Worked through N steps" detail sheet. A fresh id per open
/// keeps `.sheet(item:)` presenting even when the same run's steps are reopened.
private struct ChatStepsPayload: Identifiable {
    let id = UUID()
    let steps: [String]
    let reasoning: ChatStepsReasoning?
}

/// The "Worked through N steps" detail as a self-owned bottom-sheet overlay (system sheets can't go
/// edge-to-edge on iOS 26 — every sizing renders as a horizontally-inset floating card). A dimmed scrim
/// plus an opaque canvas card: full width, bottom-flush, grabber + drag-down / tap-scrim to dismiss.
/// Layout follows the Paper spec — 19pt centered title over the glass X, 5pt bullets at a 40pt margin.
private struct ChatStepsOverlay: View {
    /// Optional so this view stays mounted while closed — see the stable-parent note below. Nil = closed.
    let payload: ChatStepsPayload?
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var dragOffset: CGFloat = 0
    /// The nested "Thought for Ns" group is collapsed by default; tap to read the full reasoning.
    @State private var reasoningExpanded = false

    /// Card fill is the app canvas (#F5F4FA light / #171717 dark), matching every other surface.
    private var canvas: Color {
        self.colorScheme == .dark
            ? Color(red: 23 / 255, green: 23 / 255, blue: 23 / 255)
            : Color(red: 245 / 255, green: 244 / 255, blue: 250 / 255)
    }

    private var bullet: Color {
        (self.colorScheme == .dark ? Color.white : .black).opacity(0.5)
    }

    private var tint: Color {
        (self.colorScheme == .dark ? Color.white : .black).opacity(0.55)
    }

    /// A reasoning-only turn has no work steps, so the sheet reads "Thought Process"; otherwise it counts
    /// the tool/preamble steps.
    private func title(_ payload: ChatStepsPayload) -> String {
        if payload.steps.isEmpty, payload.reasoning != nil {
            return "Thought Process"
        }
        let count = payload.steps.count
        return "Worked through \(count) step\(count == 1 ? "" : "s")"
    }

    var body: some View {
        GeometryReader { geo in
            // This GeometryReader/ZStack is the STABLE parent (always mounted). The scrim + card are
            // conditionally inserted INSIDE it, so each runs its own transition — the card slides
            // (`.move`) and the scrim fades (`.opacity`), instead of the whole overlay fading in as one.
            ZStack(alignment: .bottom) {
                if let payload = self.payload {
                    // Dimmed backdrop; tap outside the card to dismiss. Fades while the card slides.
                    Color.black.opacity(0.35)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: self.onClose)
                        .transition(.opacity)

                    self.card(
                        payload: payload,
                        maxHeight: geo.size.height * 0.62,
                        bottomInset: geo.safeAreaInsets.bottom)
                        .offset(y: max(0, self.dragOffset))
                        .gesture(self.dragToDismiss)
                        .transition(.move(edge: .bottom))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        // When closed the overlay is empty and must not eat taps meant for the chat beneath it.
        .allowsHitTesting(self.payload != nil)
    }

    private func card(payload: ChatStepsPayload, maxHeight: CGFloat, bottomInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.primary.opacity(0.25))
                .frame(width: 40, height: 5)
                .padding(.top, 8)

            self.header(payload)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    // Reasoning leads the sheet as a nested, expandable "Thought for Ns" group — the whole
                    // process in one place, with the thought first and the work steps following.
                    if let reasoning = payload.reasoning {
                        self.reasoningGroup(reasoning)
                    }
                    ForEach(payload.steps.indices, id: \.self) { index in
                        HStack(alignment: .top, spacing: 12) {
                            Circle()
                                .fill(self.bullet)
                                .frame(width: 5, height: 5)
                                .padding(.top, 8)
                            Text(payload.steps[index])
                                .font(.system(size: 16))
                                .foregroundStyle(Color.primary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                // Bullets sit at a 40pt left margin (spec), further in than the X's 24pt.
                .padding(.leading, 40)
                .padding(.trailing, 24)
                .padding(.top, 4)
                // Clear the home indicator so the last step never sits under it.
                .padding(.bottom, bottomInset + 24)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: maxHeight + bottomInset, alignment: .top)
        .background(self.canvas)
        .clipShape(.rect(topLeadingRadius: 47, topTrailingRadius: 47))
    }

    /// The nested "Thought for Ns" group: a tappable receipt row that expands to the full reasoning body.
    /// Sits at the bullets' 40pt margin so it aligns with the work steps beneath it.
    private func reasoningGroup(_ reasoning: ChatStepsReasoning) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { self.reasoningExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(reasoning.receipt)
                        .font(.system(size: 16).italic())
                        .foregroundStyle(self.tint)
                    Image(systemName: self.reasoningExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(self.tint)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if self.reasoningExpanded {
                Text(reasoning.text)
                    .font(.system(size: 14))
                    .foregroundStyle(self.tint)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func header(_ payload: ChatStepsPayload) -> some View {
        // Centered 19pt title over the leading glass X — the app's unified nav treatment.
        ZStack {
            Text(self.title(payload))
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Color.primary)
            HStack {
                Button(action: self.onClose) {
                    Image("ChatCloseGlyph")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .foregroundStyle(Color.primary)
                        .frame(width: 40, height: 40)
                        .background {
                            ChatGlassBackground(
                                shape: Circle(),
                                fill: self.colorScheme == .dark
                                    ? Color(red: 30 / 255, green: 30 / 255, blue: 30 / 255).opacity(0.2)
                                    : Color(red: 245 / 255, green: 244 / 255, blue: 250 / 255).opacity(0.2))
                        }
                        .shadow(color: .black.opacity(0.15), radius: 25, x: 0, y: 0)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .padding(.top, 14)
        .padding(.bottom, 16)
    }

    /// Drag the card down past a threshold to dismiss; a short drag springs back.
    private var dragToDismiss: some Gesture {
        DragGesture()
            .onChanged { value in
                self.dragOffset = value.translation.height
            }
            .onEnded { value in
                if value.translation.height > 120 {
                    self.onClose()
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { self.dragOffset = 0 }
                }
            }
    }
}

/// Assistant turns render free of any bubble: full transcript width, no timestamp, with fenced code
/// rendered as standalone code cards. Removing the bubble is what lets code/wide content breathe.
private struct ChatAssistantMessage: View {
    let row: ChatDisplayRow
    let colorScheme: ColorScheme
    /// True only for the just-finalized live answer — plays the top-to-bottom reveal once.
    var reveal: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Assistant-delivered images get the same tap → viewer → zoom → save experience as user images.
            if !self.row.images.isEmpty {
                ChatImageMosaic(images: self.row.images)
            }
            if !self.row.text.isEmpty {
                ChatFormattedText(
                    text: self.row.text,
                    isUser: false,
                    textColor: self.colorScheme == .dark ? .white : .black,
                    reveal: self.reveal)
            }
            if !self.row.isStreaming, self.row.timestamp != nil {
                Text(chatTimeString(for: self.row.timestamp))
                    .font(.system(size: 12))
                    .foregroundStyle((self.colorScheme == .dark ? Color.white : .black).opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Block-level markdown

/// Splits assistant/user text into blocks so headings get real weight/size and lists get real
/// bullet/number glyphs with hanging indent. Each paragraph, fenced code, and table is delegated to the
/// kit's inline renderer (`OpenClawChatMarkdownText`) — but PER PARAGRAPH, not per whole message: a
/// single `Text(AttributedString(markdown: .full))` collapses list/paragraph structure into a run-on
/// wall (SwiftUI drops block presentation intents), so block splitting has to happen here.
private struct ChatFormattedText: View {
    let isUser: Bool
    let textColor: Color
    /// Parsed once at init — NOT a computed property. Re-parsing every body pass would mint fresh block
    /// identities each render and thrash ForEach (which pegged the main actor and stuck "Connecting…").
    private let blocks: [ChatTextBlock]
    /// When true, the reply unravels top-to-bottom once on appear via a descending soft-edge mask.
    private let reveal: Bool
    /// Approximate rendered-line count, used to pace the sweep so long replies aren't glacial.
    private let lineCount: Int
    /// 0 = fully masked (hidden), 1 = fully shown. Drives an animatable wipe Shape (not a gradient — a
    /// plain Double feeding gradient stops does NOT tween, so the reveal popped instead of sweeping).
    @State private var revealFraction: Double

    /// Seconds each rendered line takes to unravel, and the clamped total sweep bounds.
    private static let perLine: Double = 0.085
    private static let minDuration: Double = 0.55
    private static let maxDuration: Double = 2.2
    /// Blur on the wipe's edge (points) — feathers each line's fade-in as the reveal front passes it.
    private static let feather: CGFloat = 16
    /// Line-height between wrapped lines within a paragraph (overrides the kit's default 4pt) — this is
    /// the dominant "spacing" lever for dense replies where block/paragraph gaps rarely appear.
    private static let proseLineSpacing: CGFloat = 8

    init(text: String, isUser: Bool, textColor: Color, reveal: Bool = false) {
        self.isUser = isUser
        self.textColor = textColor
        let parsed = ChatTextBlock.parse(text)
        self.blocks = parsed
        self.reveal = reveal
        self.lineCount = Self.revealLineCount(parsed)
        _revealFraction = State(initialValue: reveal ? 0 : 1)
    }

    private var revealDuration: Double {
        min(Self.maxDuration, max(Self.minDuration, Double(self.lineCount) * Self.perLine))
    }

    var body: some View {
        // Height is committed on frame 1 (blocks parsed once); the mask only changes what's *visible*, so
        // the reply never reflows. A blurred wipe grows top→bottom, so each line materializes after the one
        // above it — an in-place unravel rather than one whole-element fade.
        let content = VStack(alignment: .leading, spacing: 20) {
            ForEach(self.blocks.indices, id: \.self) { index in
                self.view(for: self.blocks[index])
            }
        }
        if self.reveal {
            content
                .mask(alignment: .top) {
                    ChatRevealWipe(fraction: self.revealFraction, overshoot: Self.feather * 2)
                        .fill(Color.black)
                        .blur(radius: Self.feather)
                }
                .onAppear {
                    guard self.revealFraction < 1 else { return }
                    withAnimation(.linear(duration: self.revealDuration)) {
                        self.revealFraction = 1
                    }
                }
        } else {
            content
        }
    }

    /// Count rendered lines/items so the sweep paces with content length (prose lines + list items + one
    /// per code/heading block).
    private static func revealLineCount(_ blocks: [ChatTextBlock]) -> Int {
        var count = 0
        for block in blocks {
            switch block.kind {
            case let .prose(markdown):
                count += markdown
                    .components(separatedBy: "\n")
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    .count
            case let .list(items):
                count += items.count
            case .code, .heading:
                count += 1
            }
        }
        return max(count, 1)
    }

    @ViewBuilder
    private func view(for block: ChatTextBlock) -> some View {
        switch block.kind {
        case let .prose(markdown):
            self.proseView(markdown)
        case let .code(language, code):
            CodeBlockView(language: language, code: code)
        case let .heading(level, markdown):
            self.inline(markdown, font: Self.headingFont(level))
        case let .list(items):
            VStack(alignment: .leading, spacing: 15) {
                ForEach(items.indices, id: \.self) { index in
                    let item = items[index]
                    HStack(alignment: .top, spacing: 8) {
                        Text(item.marker)
                            .font(.system(size: 16))
                            .foregroundStyle(self.textColor.opacity(item.ordered ? 1 : 0.7))
                            .frame(minWidth: item.ordered ? 20 : 14, alignment: .leading)
                        self.inline(item.markdown, font: .system(size: 16))
                    }
                    .padding(.leading, CGFloat(item.depth) * 16)
                }
            }
        }
    }

    /// Render each paragraph (blank-line-separated) as ONE kit block. Per paragraph the kit preserves
    /// soft breaks as hard breaks AND applies its 4pt line-spacing; a `Text` per source line instead would
    /// throw away line-height, and one `Text` for the whole run collapses the paragraph breaks.
    private func proseView(_ markdown: String) -> some View {
        let paragraphs = Self.paragraphs(in: markdown)
        return VStack(alignment: .leading, spacing: 20) {
            ForEach(paragraphs.indices, id: \.self) { index in
                self.inline(paragraphs[index], font: .system(size: 16))
            }
        }
    }

    /// Split a prose run into paragraphs on blank lines; each paragraph keeps its internal single
    /// newlines so the kit renders them as soft breaks.
    private static func paragraphs(in markdown: String) -> [String] {
        var paragraphs: [String] = []
        var current: [String] = []
        for line in markdown.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !current.isEmpty {
                    paragraphs.append(current.joined(separator: "\n"))
                    current = []
                }
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty {
            paragraphs.append(current.joined(separator: "\n"))
        }
        return paragraphs
    }

    private func inline(_ markdown: String, font: Font) -> some View {
        OpenClawChatMarkdownText(
            text: markdown,
            isUser: self.isUser,
            font: font,
            textColor: self.textColor,
            lineSpacing: Self.proseLineSpacing)
    }

    private static func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .system(size: 20, weight: .bold)
        case 2: .system(size: 18, weight: .semibold)
        default: .system(size: 16, weight: .semibold)
        }
    }
}

private struct ChatTextBlock {
    enum Kind {
        /// Prose/tables passed verbatim to the kit's inline renderer so soft/hard line breaks and
        /// blank-line paragraph spacing are preserved.
        case prose(String)
        /// A fenced code block, rendered as a standalone code card with a copy button.
        case code(language: String?, code: String)
        case heading(level: Int, text: String)
        case list([Item])
    }

    struct Item {
        let marker: String
        let ordered: Bool
        let depth: Int
        let markdown: String
    }

    let kind: Kind

    /// Line-oriented block split. Not a full CommonMark parser — it peels out the block types the design
    /// needs (headings, lists, code, tables) and treats everything else as inline paragraphs.
    static func parse(_ text: String) -> [ChatTextBlock] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [ChatTextBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                // Opening fence: the rest of the line is the (optional) language hint.
                let language = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                index += 1
                var codeLines: [String] = []
                while index < lines.count {
                    if lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        index += 1
                        break
                    }
                    codeLines.append(lines[index])
                    index += 1
                }
                blocks.append(ChatTextBlock(kind: .code(
                    language: language.isEmpty ? nil : language,
                    code: codeLines.joined(separator: "\n"))))
                continue
            }

            if line.contains("|"), index + 1 < lines.count, Self.isTableSeparator(lines[index + 1]) {
                var table = [line]
                index += 1
                while index < lines.count, lines[index].contains("|") {
                    table.append(lines[index])
                    index += 1
                }
                blocks.append(ChatTextBlock(kind: .prose(table.joined(separator: "\n"))))
                continue
            }

            if let heading = Self.heading(trimmed) {
                blocks.append(ChatTextBlock(kind: .heading(level: heading.level, text: heading.text)))
                index += 1
                continue
            }

            if Self.listItem(line) != nil {
                var items: [Item] = []
                while index < lines.count, let parsed = Self.listItem(lines[index]) {
                    items.append(parsed)
                    index += 1
                }
                blocks.append(ChatTextBlock(kind: .list(items)))
                continue
            }

            if trimmed.isEmpty {
                index += 1
                continue
            }

            // Prose run: keep ORIGINAL lines including internal blank lines (so paragraph breaks survive
            // as empty-line gaps in `proseView`) until a real block boundary — heading / list / fence /
            // table. proseView stacks the lines, so single and double newlines both render.
            var run = [line]
            index += 1
            while index < lines.count {
                let next = lines[index]
                let nextTrimmed = next.trimmingCharacters(in: .whitespaces)
                let startsTable = next.contains("|") && index + 1 < lines.count
                    && Self.isTableSeparator(lines[index + 1])
                if nextTrimmed.hasPrefix("```") || startsTable
                    || Self.heading(nextTrimmed) != nil || Self.listItem(next) != nil
                {
                    break
                }
                run.append(next)
                index += 1
            }
            while let last = run.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
                run.removeLast()
            }
            blocks.append(ChatTextBlock(kind: .prose(run.joined(separator: "\n"))))
        }

        return blocks
    }

    private static func heading(_ trimmed: String) -> (level: Int, text: String)? {
        guard trimmed.hasPrefix("#") else { return nil }
        let hashes = trimmed.prefix { $0 == "#" }
        let level = hashes.count
        guard level >= 1, level <= 6 else { return nil }
        let rest = trimmed.dropFirst(level)
        guard rest.first == " " else { return nil }
        return (level, rest.trimmingCharacters(in: .whitespaces))
    }

    private static func listItem(_ line: String) -> Item? {
        let leading = line.prefix { $0 == " " }.count
        let content = line.drop { $0 == " " }
        guard let first = content.first else { return nil }
        let depth = leading / 2

        if first == "-" || first == "*" || first == "+" {
            let after = content.dropFirst()
            guard after.first == " " else { return nil }
            return Item(
                marker: "•",
                ordered: false,
                depth: depth,
                markdown: after.trimmingCharacters(in: .whitespaces))
        }

        let digits = content.prefix { $0.isNumber }
        if !digits.isEmpty {
            let afterDigits = content.dropFirst(digits.count)
            guard let delimiter = afterDigits.first, delimiter == "." || delimiter == ")" else { return nil }
            let rest = afterDigits.dropFirst()
            guard rest.first == " " else { return nil }
            return Item(
                marker: "\(digits).",
                ordered: true,
                depth: depth,
                markdown: rest.trimmingCharacters(in: .whitespaces))
        }

        return nil
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("-"), trimmed.contains("|") else { return false }
        return trimmed.allSatisfy { $0 == "|" || $0 == "-" || $0 == ":" || $0 == " " }
    }
}

// MARK: - Typing indicator

/// "Typing…" in regular-italic SF Pro with a highlight that sweeps across the glyphs. The sweep is
/// driven off `TimelineView(.animation)` (position computed from the frame clock) so parent re-renders
/// can't interrupt it and freeze the shimmer mid-cycle.
/// A shimmering italic label — the "…in progress" affordance. Shared by the typing indicator and the
/// agent-working activity element so their collapsed footprint is byte-identical.
struct ChatShimmerLabel: View {
    let text: String
    private static let font = Font.system(size: 16).italic()
    /// Seconds for one left-to-right sweep.
    private static let period: Double = 1.6

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let phase = (time.truncatingRemainder(dividingBy: Self.period)) / Self.period
            Text(self.text)
                .font(Self.font)
                .foregroundStyle(Color.primary.opacity(0.35))
                .contentTransition(.opacity)
                .overlay {
                    GeometryReader { geo in
                        let width = geo.size.width
                        let band = width * 0.55
                        LinearGradient(
                            colors: [.clear, Color.primary.opacity(0.9), .clear],
                            startPoint: .leading,
                            endPoint: .trailing)
                            .frame(width: band)
                            // Sweep from fully off the leading edge to fully off the trailing edge.
                            .offset(x: -band + phase * (width + band))
                    }
                    .mask {
                        Text(self.text).font(Self.font).contentTransition(.opacity)
                    }
                }
                .lineLimit(1)
                .truncationMode(.tail)
                // Swap footprints in place (crossfade the glyphs) rather than a hard cut / view replace.
                .animation(.easeInOut(duration: 0.3), value: self.text)
        }
    }
}

// MARK: - Code block

/// A fenced code block: monospaced, horizontally scrollable, on a plain white/black card with an
/// optional language label and a copy button (reuses the FeedbackCopyGlyph asset).
private struct CodeBlockView: View {
    let language: String?
    let code: String

    @Environment(\.colorScheme) private var colorScheme
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            self.header
            ScrollView(.horizontal, showsIndicators: false) {
                Text(self.code)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(self.colorScheme == .dark ? .white : .black)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(self.colorScheme == .dark ? .black : .white)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            if let language = self.language {
                Text(language)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.5))
            }
            Spacer(minLength: 0)
            Button(action: self.copy) {
                HStack(spacing: 4) {
                    if self.copied {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .semibold))
                    } else {
                        Image("FeedbackCopyGlyph")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 14, height: 14)
                    }
                    Text(self.copied ? "Copied" : "Copy")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Color.primary.opacity(0.6))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func copy() {
        UIPasteboard.general.string = self.code
        OpenClawHaptics.tap()
        withAnimation(.easeOut(duration: 0.15)) {
            self.copied = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(.easeOut(duration: 0.15)) {
                self.copied = false
            }
        }
    }
}

// MARK: - Shared pieces

private struct ChatWaveformGlyph: View {
    var body: some View {
        HStack(spacing: 2.25) {
            ForEach([10.1, 13.5, 18, 9], id: \.self) { height in
                Capsule()
                    .fill(Color(red: 217 / 255, green: 217 / 255, blue: 217 / 255))
                    .frame(width: 1.9, height: height)
            }
        }
    }
}

struct ChatGlassBackground<S: InsettableShape>: View {
    let shape: S
    let fill: Color
    var hairline: Bool = false

    init(shape: S = Capsule(style: .continuous), fill: Color, hairline: Bool = false) {
        self.shape = shape
        self.fill = fill
        self.hairline = hairline
    }

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                self.shape
                    .fill(self.fill)
                    .glassEffect(.regular, in: self.shape)
            } else {
                self.shape
                    .fill(.regularMaterial)
                    .overlay { self.shape.fill(self.fill) }
            }
        }
        .overlay {
            if self.hairline {
                self.shape
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.3)
            }
        }
    }
}

// MARK: - Camera capture

/// Thin `UIImagePickerController` wrapper for capturing a single photo. Falls back to the photo
/// library on devices/simulators without a camera so the flow still works in the simulator.
private struct ChatCameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.mediaTypes = ["public.image"]
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_: UIImagePickerController, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: ChatCameraPicker

        init(_ parent: ChatCameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any])
        {
            if let image = info[.originalImage] as? UIImage {
                self.parent.onCapture(image)
            }
            self.parent.dismiss()
        }

        func imagePickerControllerDidCancel(_: UIImagePickerController) {
            self.parent.dismiss()
        }
    }
}

struct ChatGlassPanel: View {
    let fill: Color
    let cornerRadius: CGFloat

    var body: some View {
        if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
                .fill(self.fill)
                .glassEffect(.regular, in: .rect(cornerRadius: self.cornerRadius))
        } else {
            RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
                        .fill(self.fill)
                }
        }
    }
}

/// Reveal mask for the answer unravel: a rect covering the top `fraction` of the height. `animatableData`
/// makes the growth tween frame-by-frame (a Shape animates; a Double feeding gradient stops does not), so
/// the reveal front sweeps smoothly. Overshoots the width so a blurred edge doesn't clip the sides.
private struct ChatRevealWipe: Shape {
    var fraction: Double
    /// The mask overshoots the content by this much top and bottom so the blurred (feathered) edges fall
    /// OUTSIDE the text. Without it, a short reply sits entirely inside the feather and stays dimmed even
    /// when fully revealed.
    let overshoot: CGFloat

    var animatableData: Double {
        get { self.fraction }
        set { self.fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clamped = CGFloat(max(0, min(1, fraction)))
        let top = -self.overshoot
        // At fraction 1 the front reaches height + overshoot, so the bottom feather clears the last line.
        let bottom = top + clamped * (rect.height + 2 * self.overshoot)
        return Path(CGRect(x: -20, y: top, width: rect.width + 40, height: max(0, bottom - top)))
    }
}
