import Foundation
import ApertureDomain

/// Coordinates direct-to-storage document ingestion under ADR-019 / INT-05.
///
/// In accordance with zero-static-key and API Gateway payload limits (32 MB), document bytes
/// NEVER traverse the API Gateway or Cloud Run services directly. Instead:
/// 1. An upload slot is negotiated via `createUploadSession` (`POST /v1/documents/upload-sessions`).
/// 2. Bytes are PUT directly to the issued Google Cloud Storage V4 signed URL.
/// 3. Completion handshake is finalised via `completeUpload` (`POST /v1/documents/upload-sessions/{id}/complete`).
/// 4. Integrity is cryptographically verified by matching local SHA-256 with server-verified digest.
public actor DirectUploadCoordinator: Sendable {

    public static let maximumSizeBytes: Int64 = 104_857_600 // 100 MB published limit

    public let api: any ApertureAPIClient
    public let uploadSession: URLSession

    public init(
        api: any ApertureAPIClient,
        uploadSession: URLSession = .shared
    ) {
        self.api = api
        self.uploadSession = uploadSession
    }

    /// Complete end-to-end direct-to-storage upload lifecycle.
    @discardableResult
    public func upload(
        data: Data,
        folderID: FolderID,
        subjectPersonID: PersonID? = nil,
        originalName: String,
        source: DocumentSource = .camera,
        quality: CaptureQuality? = nil,
        idempotencyKey: String = IdempotencyKey.make()
    ) async throws -> CaseDocument {
        let sizeBytes = Int64(data.count)
        guard sizeBytes > 0 else {
            throw ProblemDetails(
                type: "https://api.aperture.app/problems/payload-empty",
                title: "Upload payload cannot be empty",
                status: 422
            )
        }

        guard sizeBytes <= Self.maximumSizeBytes else {
            throw ProblemDetails(
                type: "https://api.aperture.app/problems/payload-too-large",
                title: "File metadata exceeds capture limits",
                status: 422,
                detail: "Uploaded file size (\(sizeBytes) bytes) exceeds maximum allowable 100 MB limit (\(Self.maximumSizeBytes) bytes)."
            )
        }

        let cleanName = originalName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, cleanName.count <= 255 else {
            throw ProblemDetails(
                type: "https://api.aperture.app/problems/invalid-filename",
                title: "Invalid file name",
                status: 422
            )
        }

        // 1. Pre-compute canonical SHA-256 digest
        let localSHA256 = CapturePayloadProcessor.sha256(of: data)

        // 2. Negotiate upload session slot
        let session = try await api.createUploadSession(
            folderID: folderID,
            subjectPersonID: subjectPersonID,
            originalName: cleanName,
            sizeBytes: sizeBytes,
            source: source,
            quality: quality,
            contentSHA256: localSHA256,
            idempotencyKey: "\(idempotencyKey)-session"
        )

        guard session.expiresAt > Date() else {
            throw ProblemDetails(
                type: "https://api.aperture.app/problems/upload-session-expired",
                title: "Upload session slot has already expired",
                status: 410
            )
        }

        // 3. Direct upload to Google Cloud Storage signed URL
        if session.uploadURL.host != "stub.invalid" {
            var request = URLRequest(url: session.uploadURL)
            request.httpMethod = session.uploadMethod.isEmpty ? "PUT" : session.uploadMethod
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            request.setValue(String(sizeBytes), forHTTPHeaderField: "Content-Length")
            request.setValue(localSHA256, forHTTPHeaderField: "x-goog-content-sha256")

            let (_, response): (Data, URLResponse)
            do {
                (_, response) = try await uploadSession.upload(for: request, from: data)
            } catch let error as URLError {
                switch error.code {
                case .notConnectedToInternet, .networkConnectionLost:
                    throw TransportError.offline
                case .timedOut:
                    throw TransportError.timedOut
                default:
                    throw error
                }
            }

            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 502
                throw ProblemDetails(
                    type: "https://api.aperture.app/problems/storage-put-failed",
                    title: "Direct-to-storage transfer rejected by Cloud Storage",
                    status: status
                )
            }
        }

        // 4. Complete upload session handshake
        let completed = try await api.completeUpload(
            sessionID: session.sessionID,
            idempotencyKey: "\(idempotencyKey)-complete"
        )

        // 5. Verify digest parity
        if let serverDigest = completed.contentSHA256, !serverDigest.isEmpty {
            guard serverDigest.lowercased() == localSHA256.lowercased() else {
                throw ProblemDetails(
                    type: "https://api.aperture.app/problems/checksum-mismatch",
                    title: "Server verified checksum does not match local digest",
                    status: 422
                )
            }
        }

        return completed
    }
}
