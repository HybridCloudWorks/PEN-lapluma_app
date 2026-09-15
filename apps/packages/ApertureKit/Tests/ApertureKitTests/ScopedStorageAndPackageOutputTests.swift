import Foundation
import Testing
import ApertureDomain
@testable import ApertureAPI

@Suite("Scoped Storage and Package Output Suite (INT-05, INT-06, APP-07, APP-08)")
struct ScopedStorageAndPackageOutputTests {
    private let seededCase = CaseID("c_ramirez_i130")

    private func makeClient() async -> StubAPIClient {
        let api = StubAPIClient()
        await api.setDelay(.zero)
        return api
    }

    private func confirmEveryField(_ api: StubAPIClient, caseID: CaseID) async throws {
        let fields = try await api.reviewableFields(caseID: caseID)
        let confirmations = fields.map { field in
            ValueConfirmation(
                personID: field.subjectPersonID,
                canonicalPath: field.canonicalPath,
                value: field.displayValue ?? "Applicant response",
                resolvesDiscrepancyID: field.confirmed?.discrepancy?.id
            )
        }
        _ = try await api.confirmValues(
            caseID: caseID,
            confirmations: confirmations,
            idempotencyKey: "gate-confirm-\(caseID.rawValue)"
        )
    }

    private func linkBlockingEvidence(_ api: StubAPIClient, caseID: CaseID) async throws {
        let outstanding = try await api.missingItems(caseID: caseID).items
            .filter { $0.kind == .evidence && $0.severity == .blocking }
        for (offset, item) in outstanding.enumerated() {
            _ = try await api.linkEvidence(
                caseID: caseID,
                requirementCode: try #require(item.requirementCode),
                documentID: DocumentID("d_greencard"),
                idempotencyKey: "gate-link-\(caseID.rawValue)-\(offset)"
            )
        }
    }

    @Test("Pending capture queue persists payload across relaunches and deletes only on confirmed upload")
    func captureQueuePersistsAndDeletesOnlyAfterConfirmation() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "aperture-scoped-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let payload = Data("100mb-simulated-payload-bytes-and-metadata".utf8)
        let firstQueue = PendingCaptureQueue(directoryURL: directory)
        let queued = try await firstQueue.enqueue(
            data: payload,
            folderID: FolderID("f_test_scoped"),
            subjectPersonID: PersonID("p_applicant"),
            originalName: "large_capture.pdf",
            source: .camera
        )

        // Verify state survives relaunch
        let relaunchedQueue = PendingCaptureQueue(directoryURL: directory)
        let pending = await relaunchedQueue.pendingCaptures()
        #expect(pending.count == 1)
        let item = try #require(pending.first)
        #expect(item.id == queued.id)
        #expect(item.createSessionIdempotencyKey == queued.createSessionIdempotencyKey)
        #expect(item.completeUploadIdempotencyKey == queued.completeUploadIdempotencyKey)

        // Drain failure: file must NOT be deleted
        struct TransientNetworkError: Error {}
        let failedDrain = await relaunchedQueue.drain { _, _ in
            throw TransientNetworkError()
        }
        #expect(failedDrain.uploadedCount == 0)
        #expect(await relaunchedQueue.pendingCount() == 1)
        #expect(try await relaunchedQueue.payload(for: item) == payload)

        // Drain success: only now is payload deleted
        let successfulDrain = await relaunchedQueue.drain { capture, bytes in
            #expect(capture.id == queued.id)
            #expect(bytes == payload)
        }
        #expect(successfulDrain.uploadedCount == 1)
        #expect(await relaunchedQueue.pendingCount() == 0)
    }

    @Test("Direct upload session adheres to 15-minute TTL, PUT method, and SHA-256 binding")
    func uploadSessionContractVerification() async throws {
        let api = await makeClient()
        let contentHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        let session = try await api.createUploadSession(
            folderID: FolderID("f_test_scoped"),
            subjectPersonID: PersonID("p_applicant"),
            originalName: "id_scan.jpg",
            sizeBytes: 52428800,
            source: .camera,
            quality: nil,
            contentSHA256: contentHash,
            idempotencyKey: "test-upload-session-key"
        )

        #expect(session.uploadMethod == "PUT")
        #expect(session.expectedContentSHA256 == contentHash)
        #expect(session.expiresAt > Date())
        #expect(session.expiresAt.timeIntervalSinceNow <= 901)

        // Complete upload
        let doc = try await api.completeUpload(
            sessionID: session.sessionID,
            idempotencyKey: "test-complete-upload-key"
        )
        #expect(doc.id == session.documentID)
        #expect(doc.contentSHA256 == contentHash)
    }

    @Test("Package generation produces short-lived scoped download grant with refresh capability")
    func packageGenerationAndScopedDownloadGrantCycle() async throws {
        let api = await makeClient()
        try await confirmEveryField(api, caseID: seededCase)
        try await linkBlockingEvidence(api, caseID: seededCase)

        let pkg = try await api.requestPackageGeneration(
            caseID: seededCase,
            idempotencyKey: "pkg-gen-test"
        )
        #expect(pkg.verification.passed)

        // Request scoped download grant
        let grant = try await api.packageDownload(
            caseID: seededCase,
            packageID: pkg.id,
            idempotencyKey: "dl-grant-test-1"
        )

        #expect(grant.packageID == pkg.id)
        #expect(grant.caseID == seededCase)
        #expect(grant.downloadURL.absoluteString.contains("storage.googleapis.com"))
        #expect(!grant.isExpired)
        #expect(grant.expiresAt > Date())

        // Re-requesting download grant transparently generates a fresh grant
        let refreshedGrant = try await api.packageDownload(
            caseID: seededCase,
            packageID: pkg.id,
            idempotencyKey: "dl-grant-test-2"
        )
        #expect(refreshedGrant.packageID == pkg.id)
        #expect(!refreshedGrant.isExpired)
    }

    @Test("Section edit invalidates case approval and blocks package download")
    func sectionEditInvalidatesApprovalAndBlocksDownload() async throws {
        let api = await makeClient()
        try await confirmEveryField(api, caseID: seededCase)
        try await linkBlockingEvidence(api, caseID: seededCase)

        let pkg = try await api.requestPackageGeneration(
            caseID: seededCase,
            idempotencyKey: "pkg-gen-invalidation-test"
        )

        // Valid download succeeds before section mutation
        let initialGrant = try await api.packageDownload(
            caseID: seededCase,
            packageID: pkg.id,
            idempotencyKey: "dl-initial-grant"
        )
        #expect(!initialGrant.isExpired)

        // Preparer commits section edit
        let commitResult = try await api.commitSection(
            caseID: seededCase,
            sectionID: "applicant-biographical",
            baseRevision: 1,
            values: ["givenName": "Maria Elena"],
            idempotencyKey: "section-edit-invalidation"
        )
        #expect(commitResult.invalidatedApproval)

        // Verify case state moved back to validating
        let summary = try await api.caseSummary(id: seededCase)
        #expect(summary.state == .validating)

        // Package download must be rejected because package and approval were invalidated
        do {
            _ = try await api.packageDownload(
                caseID: seededCase,
                packageID: pkg.id,
                idempotencyKey: "dl-after-invalidation"
            )
            Issue.record("Download must fail after section modification invalidated approval")
        } catch let problem as ProblemDetails {
            #expect(problem.status == 404 || problem.status == 409)
        }
    }
}
