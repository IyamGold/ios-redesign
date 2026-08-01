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
    /// Armed on send; fires the crisp closing click once when the assistant's run completes.
    @State private var replyEndArmed = false

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

    private var streamingText: String? {
        guard let text = self.viewModel.streamingAssistantText else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    var body: some View {
        ZStack {
            self.canvas.ignoresSafeArea()
            self.transcript
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
        // Kick the view model's bootstrap (history + health poll) on appear and whenever the model
        // instance changes. The shared kit view did this in its own `.onAppear`; without it the health
        // probe never runs, so sends queue offline forever and no reply ever comes back.
        .task(id: ObjectIdentifier(self.viewModel)) {
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
                            .padding(.bottom, row.isUser ? 21 : 25)
                    }
                    self.trailingIndicator
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomAnchorID)
                }
                .padding(.horizontal, 14)
                .padding(.top, 108)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            // A newly committed message animates to the bottom once; the very first population snaps
            // without animation so the transcript paints at the bottom instead of scrolling up on open.
            .onChange(of: self.rows.count) { old, _ in
                self.scrollToBottom(proxy, animated: old != 0)
            }
            // Streaming tokens pin the bottom WITHOUT a per-token animation, so the transcript tracks
            // the reply smoothly instead of re-animating (and visibly repositioning) on every token.
            .onChange(of: self.viewModel.streamingAssistantText) { _, text in
                self.scrollToBottom(proxy, animated: false)
                if let text, !text.isEmpty {
                    self.fireReplyIntroIfArmed()
                }
            }
            .onChange(of: self.assistantRowCount) { old, new in
                if new > old {
                    self.fireReplyIntroIfArmed()
                }
            }
            .onChange(of: self.isAssistantWorking) { old, new in
                // Reveal the typing indicator when a run starts (no message/token change fires here yet).
                if new {
                    self.scrollToBottom(proxy, animated: false)
                }
                // Run finished (pending cleared): close the reply with one crisp click.
                if old, !new, self.replyEndArmed {
                    self.replyEndArmed = false
                    self.replyIntroArmed = false
                    OpenClawHaptics.click()
                }
            }
        }
    }

    private var assistantRowCount: Int {
        self.rows.reduce(0) { $0 + ($1.isUser ? 0 : 1) }
    }

    /// Two-phase reply haptics, both armed on send: a warning pattern introduces the reply (fired once by
    /// whichever lands first — streamed token or finalized row, so it can't buzz while a transcript loads),
    /// and a crisp click closes it out when the run completes (see the isAssistantWorking transition above).
    private func fireReplyIntroIfArmed() {
        guard self.replyIntroArmed else { return }
        self.replyIntroArmed = false
        OpenClawHaptics.play(.secured4)
    }

    /// User turns stay in a chat bubble; assistant turns render free (no bubble, full width) so code
    /// blocks and wide content aren't boxed in.
    @ViewBuilder
    private func messageView(for row: ChatDisplayRow) -> some View {
        if row.isUser {
            ChatUserBubble(row: row, colorScheme: self.colorScheme)
        } else {
            ChatAssistantMessage(row: row, colorScheme: self.colorScheme)
        }
    }

    @ViewBuilder private var trailingIndicator: some View {
        if let streaming = self.streamingText {
            // The reply as it streams in — same free layout as the finalized turn so nothing jumps.
            ChatAssistantMessage(
                row: ChatDisplayRow(streamingText: streaming),
                colorScheme: self.colorScheme)
                .padding(.bottom, 25)
        } else if self.isAssistantWorking {
            ChatTypingIndicator()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 25)
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
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
                } else if let cached = self.imageCache[key] {
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
                } else if let cachedChips = self.chipCache[key],
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
            let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard hasText || !images.isEmpty || !chips.isEmpty else { continue }
            let isUser = role == "user"
            result.append(ChatDisplayRow(
                id: message.id,
                isUser: isUser,
                text: text,
                timestamp: message.timestamp,
                isError: message.errorMessage != nil,
                images: images,
                chips: chips))
        }
        self.rows = result
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
                    : .easeOut(duration: 0.15).delay(0.1),
                value: self.showsAttachmentTray)

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
        } else if let voiceNote = self.stagedVoiceNote {
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
                .lineLimit(1...4)
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
           let note = self.stagedVoiceNote
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
        self.replyIntroArmed = true
        self.replyEndArmed = true
        self.viewModel.send()
    }

    // MARK: - Voice notes

    private func startRecording() {
        OpenClawHaptics.tap()
        Task { await self.voiceRecorder.start() }
    }

    private func finishRecording() {
        guard let recording = self.voiceRecorder.finish() else { return }
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
        while let data = try? Data(contentsOf: self.fileURL(key: key, index: index)),
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
        guard let manifest = try? Data(contentsOf: self.manifestURL(key)),
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
        guard let name = self.fileName else { return nil }
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
    }

    /// UIImage/chip aren't Equatable, so compare their derived counts; the row id + text already capture
    /// material message changes for SwiftUI diffing.
    static func == (lhs: ChatDisplayRow, rhs: ChatDisplayRow) -> Bool {
        lhs.id == rhs.id && lhs.isUser == rhs.isUser && lhs.text == rhs.text
            && lhs.timestamp == rhs.timestamp && lhs.isError == rhs.isError
            && lhs.isStreaming == rhs.isStreaming && lhs.images.count == rhs.images.count
            && lhs.chips.count == rhs.chips.count
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

    private static let bubbleFill = Color(red: 195 / 255, green: 63 / 255, blue: 51 / 255)

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
                    .foregroundStyle(.white)
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
        .white
    }
}

// MARK: - Audio bubble

/// A sent voice note: play/pause + waveform that fills as it plays, with the elapsed/total time. Holds
/// its own `ChatAudioPlayback` so each bubble tracks its own progress independently.
private struct AudioBubbleContent: View {
    let data: Data?
    let durationSeconds: Double
    let fill: Color
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
                        ChatPauseGlyph(color: .white)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                    }
                }
                .disabled(self.data == nil)
                ChatAmplitudeWaveform(
                    levels: self.levels,
                    color: .white.opacity(0.4),
                    activeColor: .white,
                    progress: self.playback.progress)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
                Text(chatDurationLabel(
                    self.playback.currentTime > 0
                        ? self.playback.currentTime
                        : self.durationSeconds))
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
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

/// Assistant turns render free of any bubble: full transcript width, no timestamp, with fenced code
/// rendered as standalone code cards. Removing the bubble is what lets code/wide content breathe.
private struct ChatAssistantMessage: View {
    let row: ChatDisplayRow
    let colorScheme: ColorScheme

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
                    textColor: self.colorScheme == .dark ? .white : .black)
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

/// Splits assistant/user text into blocks and gives headings real weight/size and lists real
/// bullet/number glyphs with hanging indent. Paragraphs, fenced code, and tables are delegated to the
/// kit's inline renderer (`OpenClawChatMarkdownText`) so code highlighting / tables stay intact.
private struct ChatFormattedText: View {
    let isUser: Bool
    let textColor: Color
    /// Parsed once at init — NOT a computed property. Re-parsing every body pass would mint fresh block
    /// identities each render and thrash ForEach (which pegged the main actor and stuck "Connecting…").
    private let blocks: [ChatTextBlock]

    init(text: String, isUser: Bool, textColor: Color) {
        self.isUser = isUser
        self.textColor = textColor
        self.blocks = ChatTextBlock.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(self.blocks.indices, id: \.self) { index in
                self.view(for: self.blocks[index])
            }
        }
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
            VStack(alignment: .leading, spacing: 4) {
                ForEach(items.indices, id: \.self) { index in
                    let item = items[index]
                    HStack(alignment: .top, spacing: 6) {
                        Text(item.marker)
                            .font(.system(size: 16))
                            .foregroundStyle(self.textColor.opacity(item.ordered ? 1 : 0.7))
                            .frame(minWidth: item.ordered ? 18 : 10, alignment: .leading)
                        self.inline(item.markdown, font: .system(size: 16))
                    }
                    .padding(.leading, CGFloat(item.depth) * 16)
                }
            }
        }
    }

    /// Render each source line as its own row. `Text(AttributedString(markdown:))` swallows both hard
    /// breaks and paragraph intents, so we honor the model's newlines by stacking lines ourselves — and
    /// a blank line becomes an empty-line gap so double line breaks read as a clear paragraph break.
    private func proseView(_ markdown: String) -> some View {
        let lines = markdown.components(separatedBy: "\n")
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(lines.indices, id: \.self) { index in
                if lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    Color.clear.frame(height: 10)
                } else {
                    self.inline(lines[index], font: .system(size: 16))
                }
            }
        }
    }

    private func inline(_ markdown: String, font: Font) -> some View {
        OpenClawChatMarkdownText(
            text: markdown,
            isUser: self.isUser,
            font: font,
            textColor: self.textColor)
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
private struct ChatTypingIndicator: View {
    private static let label = "Typing…"
    private static let font = Font.system(size: 16).italic()
    /// Seconds for one left-to-right sweep.
    private static let period: Double = 1.6

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let phase = (time.truncatingRemainder(dividingBy: Self.period)) / Self.period
            Text(Self.label)
                .font(Self.font)
                .foregroundStyle(Color.primary.opacity(0.35))
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
                        Text(Self.label).font(Self.font)
                    }
                }
                .fixedSize()
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

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: ChatCameraPicker

        init(_ parent: ChatCameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any])
        {
            if let image = info[.originalImage] as? UIImage {
                self.parent.onCapture(image)
            }
            self.parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
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
