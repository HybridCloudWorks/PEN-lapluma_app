import Foundation
import ApertureDomain

/// A capture written to protected local storage before any network request begins.
/// The two idempotency keys are created once and survive relaunches and retries.
public struct PendingCapture: Identifiable, Codable, Sendable {
    public let id: String
    public let folderID: FolderID
    public let subjectPersonID: PersonID?
    public let originalName: String
    public let sizeBytes: Int64
    public let source: DocumentSource
    public let quality: CaptureQuality?
    public let contentSHA256: String?
    public let verifiedMIMEType: String?
    public let pageCount: Int?
    public let createdAt: Date
    public let createSessionIdempotencyKey: String
    public let completeUploadIdempotencyKey: String
}

public struct CaptureDrainResult: Sendable, Equatable {
    public let uploadedCount: Int
    public let remainingCount: Int

    public init(uploadedCount: Int, remainingCount: Int) {
        self.uploadedCount = uploadedCount
        self.remainingCount = remainingCount
    }
}

/// Durable queue for document bytes captured during poor or absent connectivity.
///
/// Payloads and the manifest use complete file protection on iOS. A failed upload is
/// retained with the same logical-operation keys; it is never silently duplicated or
/// discarded. The queue deliberately owns no networking so production background
/// transfer can be injected without weakening its persistence guarantees.
public actor PendingCaptureQueue {
    private let directoryURL: URL
    private let manifestURL: URL
    private var captures: [PendingCapture]

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
        manifestURL = directoryURL.appending(path: "manifest.json", directoryHint: .notDirectory)
        captures = Self.loadManifest(from: manifestURL)
    }

    @discardableResult
    public func enqueue(
        data: Data,
        folderID: FolderID,
        subjectPersonID: PersonID?,
        originalName: String,
        source: DocumentSource,
        quality: CaptureQuality? = nil,
        verifiedMIMEType: String? = nil,
        pageCount: Int? = nil,
        now: Date = .now
    ) throws -> PendingCapture {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let capture = PendingCapture(
            id: UUID().uuidString,
            folderID: folderID,
            subjectPersonID: subjectPersonID,
            originalName: originalName,
            sizeBytes: Int64(data.count),
            source: source,
            quality: quality,
            contentSHA256: CapturePayloadProcessor.sha256(of: data),
            verifiedMIMEType: verifiedMIMEType,
            pageCount: pageCount,
            createdAt: now,
            createSessionIdempotencyKey: IdempotencyKey.make(),
            completeUploadIdempotencyKey: IdempotencyKey.make()
        )
        let payloadURL = payloadURL(for: capture.id)
        try Self.writeProtected(data, to: payloadURL)
        captures.append(capture)
        do {
            try persistManifest()
        } catch {
            captures.removeAll { $0.id == capture.id }
            try? FileManager.default.removeItem(at: payloadURL)
            throw error
        }
        return capture
    }

    public func pendingCaptures() -> [PendingCapture] {
        captures.sorted { $0.createdAt < $1.createdAt }
    }

    public func pendingCount() -> Int { captures.count }

    public func pendingByteCount() -> Int64 {
        captures.reduce(0) { $0 + $1.sizeBytes }
    }

    public func payload(for capture: PendingCapture) throws -> Data {
        try Data(contentsOf: payloadURL(for: capture.id), options: .mappedIfSafe)
    }

    /// Drains in capture order and stops on the first failure. This avoids burning a
    /// metered connection by repeatedly attempting later payloads after connectivity
    /// has failed. Successfully processed payloads are removed immediately.
    public func drain(
        using operation: @Sendable (PendingCapture, Data) async throws -> Void
    ) async -> CaptureDrainResult {
        var uploadedCount = 0
        for capture in pendingCaptures() {
            do {
                let data = try payload(for: capture)
                try await operation(capture, data)
                try remove(capture)
                uploadedCount += 1
            } catch {
                break
            }
        }
        return CaptureDrainResult(uploadedCount: uploadedCount, remainingCount: captures.count)
    }

    public func erase() throws {
        captures.removeAll()
        if FileManager.default.fileExists(atPath: directoryURL.path) {
            try FileManager.default.removeItem(at: directoryURL)
        }
    }

    private func remove(_ capture: PendingCapture) throws {
        // Delete the sensitive payload first. If this fails, the manifest remains and
        // the capture is retried; a successful upload must never leave orphaned bytes.
        try FileManager.default.removeItem(at: payloadURL(for: capture.id))
        captures.removeAll { $0.id == capture.id }
        try persistManifest()
    }

    private func persistManifest() throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(captures)
        try Self.writeProtected(data, to: manifestURL)
    }

    private func payloadURL(for id: String) -> URL {
        directoryURL.appending(path: "capture-\(id).payload", directoryHint: .notDirectory)
    }

    private static func loadManifest(from url: URL) -> [PendingCapture] {
        guard let data = try? Data(contentsOf: url),
              let captures = try? JSONDecoder().decode([PendingCapture].self, from: data) else {
            return []
        }
        let directory = url.deletingLastPathComponent()
        return captures.filter { capture in
            let payload = directory.appending(
                path: "capture-\(capture.id).payload",
                directoryHint: .notDirectory
            )
            return FileManager.default.fileExists(atPath: payload.path)
        }
    }

    private static func writeProtected(_ data: Data, to url: URL) throws {
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
}
