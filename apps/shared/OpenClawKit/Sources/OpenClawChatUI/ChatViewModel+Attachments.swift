import Foundation
import OpenClawKit
import UniformTypeIdentifiers

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

extension OpenClawChatViewModel {
    /// Stages a recorded m4a voice note and removes its temporary file.
    public func addVoiceNoteAttachment(fileURL: URL, durationSeconds: Double) async {
        self.beginAttachmentStaging()
        defer {
            try? FileManager.default.removeItem(at: fileURL)
            self.endAttachmentStaging()
        }

        let data: Data
        do {
            data = try await Task.detached(priority: .userInitiated) {
                try Data(contentsOf: fileURL)
            }.value
        } catch {
            self.errorText = String(localized: "Could not attach voice note: \(error.localizedDescription)")
            return
        }

        guard data.count <= Self.maxAttachmentBytes else {
            self.errorText = String(localized: "Voice note exceeds the 5 MB attachment limit")
            return
        }

        let normalizedDuration = durationSeconds.isFinite
            ? min(max(0, durationSeconds), OpenClawVoiceNoteRecorder.maximumDurationSeconds)
            : 0
        self.attachments.append(
            OpenClawPendingAttachment(
                url: nil,
                data: data,
                fileName: fileURL.lastPathComponent,
                mimeType: "audio/mp4",
                preview: nil,
                durationSeconds: normalizedDuration))
    }

    func loadAttachments(urls: [URL]) async {
        for url in urls {
            do {
                let data = try await Task.detached { try Data(contentsOf: url) }.value
                await self.addImageAttachment(
                    url: url,
                    data: data,
                    fileName: url.lastPathComponent,
                    mimeType: Self.mimeType(for: url) ?? "application/octet-stream")
            } catch {
                await MainActor.run { self.errorText = error.localizedDescription }
            }
        }
    }

    static func mimeType(for url: URL) -> String? {
        let ext = url.pathExtension
        guard !ext.isEmpty else { return nil }
        return (UTType(filenameExtension: ext) ?? .data).preferredMIMEType
    }

    /// Stage a file attachment verbatim — no image re-encoding and no image-only guard — for documents
    /// and animated images (GIFs) that must reach the gateway unmodified. Static photos still go through
    /// `addImageAttachment` (JPEG normalization); this path preserves the original bytes and MIME so the
    /// gateway can sniff/route them (image/gif stays an image; other types offload to the agent sandbox).
    public func addFileAttachment(data: Data, fileName: String, mimeType: String) {
        self.beginAttachmentStaging()
        Task {
            defer { self.endAttachmentStaging() }
            await self.stageRawAttachment(data: data, fileName: fileName, mimeType: mimeType)
        }
    }

    func stageRawAttachment(data: Data, fileName: String, mimeType: String) async {
        guard data.count <= Self.maxAttachmentBytes else {
            self.errorText = "Attachment \(fileName) exceeds 5 MB limit"
            return
        }
        // Only images carry a thumbnail preview; UIImage/NSImage decodes a GIF's first frame, which is
        // enough for the composer chip while the full animated bytes still ship to the gateway.
        let uti = UTType(mimeType: mimeType) ?? UTType(filenameExtension: (fileName as NSString).pathExtension)
        let preview = (uti?.conforms(to: .image) ?? false) ? Self.previewImage(data: data) : nil
        self.attachments.append(
            OpenClawPendingAttachment(
                url: nil,
                data: data,
                fileName: fileName,
                mimeType: mimeType,
                type: "file",
                preview: preview))
    }

    func addImageAttachment(url: URL?, data: Data, fileName: String, mimeType: String) async {
        let uti: UTType = {
            if let url {
                return UTType(filenameExtension: url.pathExtension) ?? .data
            }
            return UTType(mimeType: mimeType) ?? .data
        }()
        guard uti.conforms(to: .image) else {
            self.errorText = "Only image attachments are supported right now"
            return
        }

        let processed: Data
        do {
            processed = try await Task.detached(priority: .userInitiated) {
                try ChatImageProcessor.processForUpload(data: data)
            }.value
        } catch {
            self.errorText = "Could not process \(fileName): \(error.localizedDescription)"
            return
        }

        if processed.count > Self.maxAttachmentBytes {
            self.errorText = "Attachment \(fileName) exceeds 5 MB limit after resizing"
            return
        }

        let outputFileName: String = {
            let baseName = (fileName as NSString).deletingPathExtension
            return baseName.isEmpty ? "image.jpg" : "\(baseName).jpg"
        }()

        let preview = Self.previewImage(data: processed)
        self.attachments.append(
            OpenClawPendingAttachment(
                url: url,
                data: processed,
                fileName: outputFileName,
                mimeType: "image/jpeg",
                preview: preview))
    }

    static func previewImage(data: Data) -> OpenClawPlatformImage? {
        #if canImport(AppKit)
        NSImage(data: data)
        #elseif canImport(UIKit)
        UIImage(data: data)
        #else
        nil
        #endif
    }
}
