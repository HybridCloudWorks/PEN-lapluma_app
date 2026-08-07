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
    /// Persisted delivery history. Optional fields keep manifests written by earlier
    /// app versions decodable without a migration pass.
    public internal(set) var retryCount: Int?
    public internal(set) var lastAttemptAt: Date?
    public internal(set) var deadLetterReason: String?

    public var isDeadLettered: Bool { deadLetterReason != nil }
}

public struct CaptureDrainResult: Sendable, Equatable {
    public let uploadedCount: Int
    public let remainingCount: Int
    public let deadLetterCount: Int
    public let wasAlreadyDraining: Bool

    public init(
        uploadedCount: Int,
        remainingCount: Int,
        deadLetterCount: Int = 0,
        wasAlreadyDraining: Bool = false
    ) {
        self.uploadedCount = uploadedCount
        self.remainingCount = remainingCount
        self.deadLetterCount = deadLetterCount
        self.wasAlreadyDraining = wasAlreadyDraining
    }
}

/// Operations should use `permanentlyInvalid` only for a capture that cannot
/// succeed unchanged (for example, a rejected checksum). Other errors are treated as
/// transient and receive bounded retries.
public enum CaptureDrainFailure: Error, Sendable, Equatable {
    case transient
    case permanentlyInvalid(reason: String)
}

/// A recoverable startup condition. Payload bytes are intentionally retained so the
/// caller can offer recovery or support rather than silently treating the queue as
/// empty.
public enum PendingCaptureQueueRecoveryIssue: Sendable, Equatable {
    case partiallyRecovered(invalidEntryCount: Int)
    case corruptManifestPreserved(at: URL)
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
    // Loaded on first actor access so constructing the queue (typically during
    // app launch on the main thread) performs no disk I/O.
    private lazy var state: LoadedState = {
        let loaded = Self.loadManifest(from: manifestURL)
        return LoadedState(captures: loaded.captures, issue: loaded.issue)
    }()
    private struct LoadedState {
        var captures: [PendingCapture]
        let issue: PendingCaptureQueueRecoveryIssue?
    }
    private var captures: [PendingCapture] {
        get { state.captures }
        set { state.captures = newValue }
    }
    private var startupRecoveryIssue: PendingCaptureQueueRecoveryIssue? { state.issue }
    private var isDraining = false

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
        manifestURL = directoryURL.appending(path: "manifest.json", directoryHint: .notDirectory)
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
            completeUploadIdempotencyKey: IdempotencyKey.make(),
            retryCount: nil,
            lastAttemptAt: nil,
            deadLetterReason: nil
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
        captures.filter { !$0.isDeadLettered }.sorted { $0.createdAt < $1.createdAt }
    }

    /// Dead-lettered captures remain on disk for user recovery and support audit,
    /// but no longer block upload of later valid work.
    public func deadLetterCaptures() -> [PendingCapture] {
        captures.filter(\.isDeadLettered).sorted { $0.createdAt < $1.createdAt }
    }

    public func pendingCount() -> Int { captures.count(where: { !$0.isDeadLettered }) }

    public func deadLetterCount() -> Int { captures.count(where: \.isDeadLettered) }

    public func pendingByteCount() -> Int64 {
        captures.filter { !$0.isDeadLettered }.reduce(0) { $0 + $1.sizeBytes }
    }

    public func recoveryIssue() -> PendingCaptureQueueRecoveryIssue? {
        startupRecoveryIssue
    }

    public func payload(for capture: PendingCapture) throws -> Data {
        try Data(contentsOf: payloadURL(for: capture.id), options: .mappedIfSafe)
    }

    /// Drains in capture order. Transient failures stop the current pass to avoid
    /// burning a metered connection, but are dead-lettered after `maximumAttempts` so
    /// a poison item cannot block later valid work forever. Permanently invalid local
    /// captures are dead-lettered immediately. A reentrant caller observes the active
    /// drain rather than starting duplicate upload operations.
    public func drain(
        maximumAttempts: Int = 3,
        now: @Sendable () -> Date = { .now },
        using operation: @Sendable (PendingCapture, Data) async throws -> Void
    ) async -> CaptureDrainResult {
        guard !isDraining else {
            return CaptureDrainResult(
                uploadedCount: 0,
                remainingCount: pendingCount(),
                deadLetterCount: deadLetterCount(),
                wasAlreadyDraining: true
            )
        }
        isDraining = true
        defer { isDraining = false }

        let attemptLimit = max(1, maximumAttempts)
        var uploadedCount = 0
        captureLoop: for capture in pendingCaptures() {
            do {
                let data = try payload(for: capture)
                guard Int64(data.count) == capture.sizeBytes else {
                    throw CaptureDrainFailure.permanentlyInvalid(
                        reason: "local-payload-size-mismatch"
                    )
                }
                if let expectedSHA256 = capture.contentSHA256,
                   CapturePayloadProcessor.sha256(of: data) != expectedSHA256 {
                    throw CaptureDrainFailure.permanentlyInvalid(
                        reason: "local-payload-checksum-mismatch"
                    )
                }
                try await operation(capture, data)
                try remove(capture)
                uploadedCount += 1
            } catch let failure as CaptureDrainFailure {
                switch failure {
                case .permanentlyInvalid(let reason):
                    markDeadLetter(capture, reason: reason, attemptedAt: now())
                    try? persistManifest()
                    continue
                case .transient:
                    if recordTransientFailure(capture, limit: attemptLimit, attemptedAt: now()) {
                        try? persistManifest()
                        continue
                    }
                    try? persistManifest()
                    break captureLoop
                }
            } catch {
                // Local payload read failures cannot be repaired by retrying a network
                // request. Preserve the manifest entry for explicit recovery.
                if !FileManager.default.fileExists(atPath: payloadURL(for: capture.id).path) {
                    markDeadLetter(
                        capture,
                        reason: "local-payload-unavailable",
                        attemptedAt: now()
                    )
                    try? persistManifest()
                    continue
                }
                if recordTransientFailure(capture, limit: attemptLimit, attemptedAt: now()) {
                    try? persistManifest()
                    continue
                }
                try? persistManifest()
                break captureLoop
            }
        }
        return CaptureDrainResult(
            uploadedCount: uploadedCount,
            remainingCount: pendingCount(),
            deadLetterCount: deadLetterCount()
        )
    }

    public func erase() throws {
        if FileManager.default.fileExists(atPath: directoryURL.path) {
            try FileManager.default.removeItem(at: directoryURL)
        }
        captures.removeAll()
    }

    private func remove(_ capture: PendingCapture) throws {
        // Delete the sensitive payload first. If this fails, the manifest remains and
        // the capture is retried; a successful upload must never leave orphaned bytes.
        try FileManager.default.removeItem(at: payloadURL(for: capture.id))
        captures.removeAll { $0.id == capture.id }
        try persistManifest()
    }

    private func recordTransientFailure(
        _ capture: PendingCapture,
        limit: Int,
        attemptedAt: Date
    ) -> Bool {
        guard let index = captures.firstIndex(where: { $0.id == capture.id }) else { return false }
        captures[index].retryCount = (captures[index].retryCount ?? 0) + 1
        captures[index].lastAttemptAt = attemptedAt
        if captures[index].retryCount ?? 0 >= limit {
            captures[index].deadLetterReason = "retry-limit-exceeded"
            return true
        }
        return false
    }

    private func markDeadLetter(_ capture: PendingCapture, reason: String, attemptedAt: Date) {
        guard let index = captures.firstIndex(where: { $0.id == capture.id }) else { return }
        captures[index].retryCount = (captures[index].retryCount ?? 0) + 1
        captures[index].lastAttemptAt = attemptedAt
        captures[index].deadLetterReason = reason
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

    private struct ManifestLoadResult {
        let captures: [PendingCapture]
        let issue: PendingCaptureQueueRecoveryIssue?
    }

    private static func loadManifest(from url: URL) -> ManifestLoadResult {
        let directory = url.deletingLastPathComponent()
        let fileManager = FileManager.default
        let recoveryFiles = ((try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []).filter { $0.lastPathComponent.hasPrefix("manifest.corrupt-") }

        guard fileManager.fileExists(atPath: url.path) else {
            if let preserved = recoveryFiles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).last {
                return ManifestLoadResult(
                    captures: [],
                    issue: .corruptManifestPreserved(at: preserved)
                )
            }
            reapOrphanPayloads(in: directory, retaining: [])
            return ManifestLoadResult(captures: [], issue: nil)
        }

        guard let data = try? Data(contentsOf: url),
              let rawEntries = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            let preserved = preserveCorruptManifest(at: url)
            return ManifestLoadResult(
                captures: [],
                issue: preserved.map { .corruptManifestPreserved(at: $0) }
                    ?? .partiallyRecovered(invalidEntryCount: 1)
            )
        }

        var decoded: [PendingCapture] = []
        var invalidEntryCount = 0
        for rawEntry in rawEntries {
            guard JSONSerialization.isValidJSONObject(rawEntry),
                  let entryData = try? JSONSerialization.data(withJSONObject: rawEntry),
                  let capture = try? JSONDecoder().decode(PendingCapture.self, from: entryData) else {
                invalidEntryCount += 1
                continue
            }
            decoded.append(capture)
        }

        let captures = decoded.filter { capture in
            let payload = directory.appending(
                path: "capture-\(capture.id).payload",
                directoryHint: .notDirectory
            )
            return fileManager.fileExists(atPath: payload.path)
        }
        if invalidEntryCount > 0 {
            // Unknown payloads may belong to the entries that failed to decode, so do
            // not reap anything until the caller has addressed the recovery issue.
            return ManifestLoadResult(
                captures: captures,
                issue: .partiallyRecovered(invalidEntryCount: invalidEntryCount)
            )
        }

        reapOrphanPayloads(in: directory, retaining: Set(captures.map(\.id)))
        return ManifestLoadResult(captures: captures, issue: nil)
    }

    private static func preserveCorruptManifest(at url: URL) -> URL? {
        let destination = url.deletingLastPathComponent().appending(
            path: "manifest.corrupt-\(UUID().uuidString).json",
            directoryHint: .notDirectory
        )
        do {
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    private static func reapOrphanPayloads(in directory: URL, retaining ids: Set<String>) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        for file in files where file.lastPathComponent.hasPrefix("capture-")
            && file.pathExtension == "payload" {
            let name = file.deletingPathExtension().lastPathComponent
            let id = String(name.dropFirst("capture-".count))
            if !ids.contains(id) {
                try? FileManager.default.removeItem(at: file)
            }
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
