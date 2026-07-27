import SwiftUI

struct ChatImageViewerPayload: Identifiable {
    let id = UUID()
    let images: [UIImage]
    let startIndex: Int
}

/// Shared tappable mosaic used by BOTH user and assistant messages.
/// Owns its own viewer presentation.
struct ChatImageMosaic: View {
    let images: [UIImage]

    @State private var viewerPayload: ChatImageViewerPayload?

    var body: some View {
        Group {
            let tile = RoundedRectangle(cornerRadius: 9, style: .continuous)
            switch self.images.count {
            case 0:
                EmptyView()
            case 1:
                self.tileImage(0, width: 244, height: 244, shape: tile)
            case 2:
                HStack(spacing: 2) {
                    self.tileImage(0, width: 129, height: 244, shape: tile)
                    self.tileImage(1, width: 113, height: 244, shape: tile)
                }
            default:
                HStack(spacing: 2) {
                    self.tileImage(0, width: 129, height: 244, shape: tile)
                    VStack(spacing: 2) {
                        self.tileImage(1, width: 113, height: 121, shape: tile)
                        ZStack {
                            self.tileImage(2, width: 113, height: 121, shape: tile)
                            if self.images.count > 3 {
                                tile.fill(Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255).opacity(0.5))
                                    .frame(width: 113, height: 121)
                                    .allowsHitTesting(false)
                                Text("+ \(self.images.count - 3)")
                                    .font(.system(size: 24))
                                    .tracking(-2.4)
                                    .foregroundStyle(.white)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                }
            }
        }
        .fullScreenCover(item: self.$viewerPayload) { payload in
            ChatImageViewer(payload: payload) {
                self.viewerPayload = nil
            }
        }
    }

    private func tileImage(
        _ index: Int,
        width: CGFloat,
        height: CGFloat,
        shape: RoundedRectangle) -> some View
    {
        Image(uiImage: self.images[index])
            .resizable()
            .scaledToFill()
            .frame(width: width, height: height)
            .clipShape(shape)
            .contentShape(shape)
            .onTapGesture {
                self.viewerPayload = ChatImageViewerPayload(
                    images: self.images, startIndex: index)
            }
    }
}

struct ChatImageViewer: View {
    let payload: ChatImageViewerPayload
    let onClose: () -> Void

    @State private var currentIndex: Int
    @State private var saved = false
    @State private var dismissDrag: CGSize = .zero
    @State private var anyZoomed = false

    init(payload: ChatImageViewerPayload, onClose: @escaping () -> Void) {
        self.payload = payload
        self.onClose = onClose
        self._currentIndex = State(initialValue: payload.startIndex)
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(self.backgroundOpacity)
                .ignoresSafeArea()

            TabView(selection: self.$currentIndex) {
                ForEach(Array(self.payload.images.enumerated()), id: \.offset) { index, image in
                    ZoomablePagedImage(image: image, anyZoomed: self.$anyZoomed)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .offset(y: self.dismissDrag.height)
            .scaleEffect(max(1 - self.dismissDrag.height / 2000, 0.85))
        }
        .simultaneousGesture(self.dismissGesture)
        .overlay(alignment: .top) {
            HStack {
                self.glassButton(asset: "ChatCloseGlyph", action: self.onClose)
                Spacer()
                self.glassButton(
                    asset: self.saved ? nil : "ChatDownloadGlyph",
                    systemImage: self.saved ? "checkmark" : nil,
                    action: self.saveCurrent)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .opacity(self.dismissDrag == .zero ? 1 : 0)
        }
        .statusBarHidden()
    }

    private var backgroundOpacity: Double {
        1 - min(Double(self.dismissDrag.height) / 400, 0.6)
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 15)
            .onChanged { value in
                guard !self.anyZoomed,
                      value.translation.height > 0,
                      abs(value.translation.height) > abs(value.translation.width)
                else { return }
                self.dismissDrag = value.translation
            }
            .onEnded { value in
                if !self.anyZoomed, value.translation.height > 120 {
                    self.onClose()
                } else {
                    withAnimation(.spring(duration: 0.3)) {
                        self.dismissDrag = .zero
                    }
                }
            }
    }

    private func glassButton(
        asset: String? = nil,
        systemImage: String? = nil,
        action: @escaping () -> Void) -> some View
    {
        Button(action: action) {
            Group {
                if let asset {
                    Image(asset)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                }
            }
            .frame(width: 24, height: 24)
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background {
                ChatGlassBackground(
                    fill: Color(red: 30 / 255, green: 30 / 255, blue: 30 / 255).opacity(0.2))
            }
        }
    }

    private func saveCurrent() {
        guard self.payload.images.indices.contains(self.currentIndex) else { return }
        UIImageWriteToSavedPhotosAlbum(
            self.payload.images[self.currentIndex], nil, nil, nil)
        OpenClawHaptics.success()
        withAnimation(.smooth(duration: 0.2)) { self.saved = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.smooth(duration: 0.2)) { self.saved = false }
        }
    }
}

/// One paged image with pinch-to-zoom, pan-while-zoomed, and double-tap toggle.
private struct ZoomablePagedImage: View {
    let image: UIImage
    @Binding var anyZoomed: Bool

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        Image(uiImage: self.image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(self.scale)
            .offset(self.offset)
            .gesture(self.magnification)
            .highPriorityGesture(self.scale > 1 ? self.pan : nil)
            .onTapGesture(count: 2) {
                withAnimation(.spring(duration: 0.3)) {
                    if self.scale > 1 {
                        self.resetZoom()
                    } else {
                        self.scale = 2.5
                        self.lastScale = 2.5
                        self.anyZoomed = true
                    }
                }
            }
            .onDisappear(perform: self.resetZoom)
    }

    private var magnification: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                self.scale = min(max(self.lastScale * value.magnification, 1), 4)
                self.anyZoomed = self.scale > 1.02
            }
            .onEnded { _ in
                if self.scale < 1.05 {
                    withAnimation(.spring(duration: 0.25)) { self.resetZoom() }
                } else {
                    self.lastScale = self.scale
                }
            }
    }

    private var pan: some Gesture {
        DragGesture()
            .onChanged { value in
                self.offset = CGSize(
                    width: self.lastOffset.width + value.translation.width,
                    height: self.lastOffset.height + value.translation.height)
            }
            .onEnded { _ in
                self.lastOffset = self.offset
            }
    }

    private func resetZoom() {
        self.scale = 1
        self.lastScale = 1
        self.offset = .zero
        self.lastOffset = .zero
        self.anyZoomed = false
    }
}
