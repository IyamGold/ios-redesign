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
    /// Transcript rows are projected once whenever `messages` changes — not per body pass — so the
    /// AssistantTextParser doesn't run on every keystroke / streamed token (what kept it off 60fps).
    @State private var rows: [ChatDisplayRow] = []
    /// Decoded attachment images kept across a turn's provisional→canonical swap, keyed by the stable
    /// idempotency key (the gateway drops the image bytes from the canonical user row — see rebuildRows).
    @State private var imageCache: [String: [UIImage]] = [:]
    /// Keys already written to the disk cache this session, so we encode/write each turn's images once.
    @State private var diskCachedKeys: Set<String> = []
    /// Armed on send; fires the reply-intro haptic once when the assistant's reply first appears.
    @State private var replyIntroArmed = false

    private static let bubbleRed = Color(red: 195 / 255, green: 63 / 255, blue: 51 / 255)
    private static let bottomAnchorID = "chat-bottom-anchor"

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
            .onChange(of: self.rows.count) { _, _ in self.scrollToBottom(proxy) }
            .onChange(of: self.viewModel.streamingAssistantText) { _, text in
                self.scrollToBottom(proxy)
                if let text, !text.isEmpty {
                    self.fireReplyIntroIfArmed()
                }
            }
            .onChange(of: self.assistantRowCount) { old, new in
                if new > old {
                    self.fireReplyIntroIfArmed()
                }
            }
            .onChange(of: self.isAssistantWorking) { _, _ in self.scrollToBottom(proxy) }
        }
    }

    private var assistantRowCount: Int {
        self.rows.reduce(0) { $0 + ($1.isUser ? 0 : 1) }
    }

    /// Warning-pattern haptic that introduces an incoming reply. Armed on send and fired once by whichever
    /// signal lands first (streamed token or a finalized assistant row), so it can't double-fire or buzz
    /// while a transcript loads. The kit still fires its single tap when the run completes.
    private func fireReplyIntroIfArmed() {
        guard self.replyIntroArmed else { return }
        self.replyIntroArmed = false
        OpenClawHaptics.play(.warning)
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

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
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
            let chips = decoded.chips
            // Persist a turn's images across the provisional→canonical swap: the gateway replaces the
            // optimistic user echo (which carries the image bytes) with a text-only "See attached." row,
            // so cache decoded images under the stable idempotency key and reuse them once bytes vanish.
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
            }
            var text = ChatMessageVisibleText.visibleText(in: message)
            // When we can show the attachments themselves, drop the "See attached." placeholder the VM
            // stamps on attachment-only sends (ChatViewModel.send) so it doesn't caption them.
            if !images.isEmpty || !chips.isEmpty,
               text.trimmingCharacters(in: .whitespacesAndNewlines) == "See attached."
            {
                text = ""
            }
            let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard hasText || !images.isEmpty || !chips.isEmpty else { continue }
            let isUser = role == "user"
            // Collapse a duplicated turn a history-reconciliation miss can leave behind: the provisional
            // streamed copy and the canonical history copy have different ids/timestamps (so the VM's
            // dedupe misses) but identical role + visible text (and attachment counts), and land adjacent.
            if let last = result.last, last.isUser == isUser, last.text == text,
               last.images.count == images.count, last.chips.count == chips.count
            {
                continue
            }
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
                let title = block.durationSeconds
                    .map { "Voice note · \(Self.durationLabel($0))" } ?? "Voice note"
                chips.append(ChatAttachmentChip(systemImage: "waveform", title: title))
            } else if isImage {
                chips.append(ChatAttachmentChip(systemImage: "photo", title: block.fileName ?? "Photo"))
            } else {
                chips.append(ChatAttachmentChip(systemImage: "doc", title: block.fileName ?? "Attachment"))
            }
        }
        return (images, chips)
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
            HStack(spacing: 0) {
                Image("ChatAvatarImage")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 34, height: 34)
                    .clipShape(Circle())
                    .padding(3)
                Text("OpenClaw")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .padding(.trailing, 14)
            }
            .background { self.glassCapsule }

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
                if self.showsAttachmentTray {
                    self.closeAttachmentTray()
                } else {
                    self.openAttachmentTray()
                }
            } label: {
                Image("ChatPlusGlyph")
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

    /// Three states: a recording readout, the plain pill input, or — when attachments are staged — a
    /// glass panel that stacks the pending-attachment strip above the input row.
    @ViewBuilder private var composerFieldContent: some View {
        if self.voiceRecorder.isRecording {
            self.recordingField
                .frame(minHeight: 36)
                .background { self.fieldPillBackground }
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
            Button(action: self.startRecording) {
                Image("ChatMicGlyph")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(Color.primary.opacity(0.9))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private var recordingField: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Self.bubbleRed)
                .frame(width: 8, height: 8)
            Text(Self.durationLabel(self.voiceRecorder.elapsedSeconds))
                .font(.system(size: 16).monospacedDigit())
                .foregroundStyle(Color.primary)
            Spacer(minLength: 0)
            Button(action: self.cancelRecording) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.7))
            }
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
        self.replyIntroArmed = true
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
                } else if attachment.mimeType.hasPrefix("audio/") {
                    // Voice note: mic + duration instead of the temp .m4a filename.
                    self.fileTile(
                        systemImage: "mic.fill",
                        caption: Self.durationLabel(attachment.durationSeconds ?? 0))
                } else {
                    // Non-image file: a labeled tile so multiple files stay distinguishable.
                    self.fileTile(asset: "ChatFilesGlyph", caption: attachment.fileName)
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
                    .padding(6)
                    .background { Circle().fill(.white) }
                    // Pad the tappable area out to a comfortable target so the tap isn't lost to the
                    // horizontal scroll gesture, but keep the visible chip small.
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            .padding(.trailing, 2)
        }
    }

    /// A tile for non-preview attachments: a glyph (asset or SF Symbol) over a truncated caption.
    private func fileTile(asset: String? = nil, systemImage: String? = nil, caption: String) -> some View {
        VStack(spacing: 3) {
            Group {
                if let asset {
                    Image(asset)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: systemImage ?? "doc")
                        .resizable()
                        .scaledToFit()
                }
            }
            .frame(width: 20, height: 20)
            .foregroundStyle(Color.primary.opacity(0.7))
            Text(caption)
                .font(.system(size: 9))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(Color.primary.opacity(0.7))
                .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primary.opacity(0.08))
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

// MARK: - Display model

/// A non-image attachment rendered as a metadata chip (file / voice note / bytes-less photo).
private struct ChatAttachmentChip: Identifiable {
    let id = UUID()
    let systemImage: String
    let title: String
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
            } else if !self.row.chips.isEmpty {
                self.fileBubble
            } else {
                self.textBubble
            }
        }
        .frame(maxWidth: Self.maxBubbleWidth, alignment: .trailing)
        .frame(maxWidth: .infinity, alignment: .trailing)
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
                VStack(spacing: 6) {
                    self.imageMosaic
                    // A mixed send (image + document) shows the file chips under the mosaic.
                    ForEach(self.row.chips) { chip in
                        self.chipRow(chip)
                    }
                }
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

    @ViewBuilder
    private var imageMosaic: some View {
        let images = self.row.images
        let tile = RoundedRectangle(cornerRadius: 9, style: .continuous)
        switch images.count {
        case 0:
            EmptyView()
        case 1:
            Image(uiImage: images[0]).resizable().scaledToFill()
                .frame(width: 244, height: 244).clipShape(tile)
        case 2:
            HStack(spacing: 2) {
                Image(uiImage: images[0]).resizable().scaledToFill()
                    .frame(width: 129, height: 244).clipShape(tile)
                Image(uiImage: images[1]).resizable().scaledToFill()
                    .frame(width: 113, height: 244).clipShape(tile)
            }
        default:
            HStack(spacing: 2) {
                Image(uiImage: images[0]).resizable().scaledToFill()
                    .frame(width: 129, height: 244).clipShape(tile)
                VStack(spacing: 2) {
                    Image(uiImage: images[1]).resizable().scaledToFill()
                        .frame(width: 113, height: 121).clipShape(tile)
                    ZStack {
                        Image(uiImage: images[2]).resizable().scaledToFill()
                            .frame(width: 113, height: 121).clipShape(tile)
                        if images.count > 3 {
                            tile.fill(Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255).opacity(0.5))
                                .frame(width: 113, height: 121)
                            Text("+ \(images.count - 3)")
                                .font(.system(size: 24))
                                .tracking(-2.4)
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
        }
    }

    /// Non-image attachment turn (files, voice notes): a stack of metadata chips plus caption/meta.
    private var fileBubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(self.row.chips) { chip in
                self.chipRow(chip)
            }
            if !self.row.text.isEmpty {
                Text(self.row.text)
                    .font(.system(size: 16))
                    .foregroundStyle(self.textColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if self.showsMeta {
                self.metaRow
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 230, alignment: .leading)
        .background { self.bubbleShape.fill(Self.bubbleFill) }
    }

    private func chipRow(_ chip: ChatAttachmentChip) -> some View {
        HStack(spacing: 8) {
            Image(systemName: chip.systemImage)
                .font(.system(size: 16))
                .foregroundStyle(self.textColor)
                .frame(width: 22)
            Text(chip.title)
                .font(.system(size: 14))
                .foregroundStyle(self.textColor)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.15))
        }
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

// MARK: - Assistant message (bubble-less)

/// Assistant turns render free of any bubble: full transcript width, no timestamp, with fenced code
/// rendered as standalone code cards. Removing the bubble is what lets code/wide content breathe.
private struct ChatAssistantMessage: View {
    let row: ChatDisplayRow
    let colorScheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ChatFormattedText(
                text: self.row.text,
                isUser: false,
                textColor: self.colorScheme == .dark ? .white : .black)
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
