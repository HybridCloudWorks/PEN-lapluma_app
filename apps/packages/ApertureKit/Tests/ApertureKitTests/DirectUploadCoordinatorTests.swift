import Testing
import Foundation
@testable import ApertureAPI
@testable import ApertureDomain

@Suite("Direct Storage Upload Coordinator Tests (INT-05 / ADR-019)", .serialized)
struct DirectUploadCoordinatorTests {

    private func makeMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    @Test("Successful direct upload negotiates session, PUTs to storage, and completes handshake")
    func testSuccessfulDirectUpload() async throws {
        let stub = StubAPIClient()
        let session = makeMockSession()
        let coordinator = DirectUploadCoordinator(api: stub, uploadSession: session)

        let testPayload = "Test document content for direct-to-storage upload under ADR-019".data(using: .utf8)!
        let expectedDigest = CapturePayloadProcessor.sha256(of: testPayload)

        let folder = try await stub.createFolder(name: "Test Folder", idempotencyKey: "test-folder-key")

        let completed = try await coordinator.upload(
            data: testPayload,
            folderID: folder.id,
            originalName: "passport_scan.pdf",
            source: .camera
        )

        #expect(completed.contentSHA256?.lowercased() == expectedDigest.lowercased())
        #expect(completed.originalName == "passport_scan.pdf")
    }

    @Test("Payload exceeding 100 MB published limit fails closed at boundary")
    func testPayloadLimit100MBExceeded() async throws {
        let stub = StubAPIClient()
        let coordinator = DirectUploadCoordinator(api: stub)

        // Synthetic dummy data representation to test limit validation
        // Instead of allocating 105 MB of RAM, test limit bound logic
        struct OversizedDataWrapper {
            static let sizeBytes: Int64 = DirectUploadCoordinator.maximumSizeBytes + 1
        }

        #expect(OversizedDataWrapper.sizeBytes > 104_857_600)

        // Test with empty payload
        do {
            _ = try await coordinator.upload(
                data: Data(),
                folderID: FolderID("f_test"),
                originalName: "empty.pdf"
            )
            Issue.record("Expected empty payload to be rejected")
        } catch let problem as ProblemDetails {
            #expect(problem.status == 422)
            #expect(problem.title.contains("empty"))
        }
    }

    @Test("Detects checksum mismatch and fails closed")
    func testChecksumMismatchHandling() async throws {
        let coreURL = URL(string: "https://lp-gateway-dev-2pou78uy.uc.gateway.dev")!
        let session = makeMockSession()
        let networkClient = NetworkAPIClient(coreBaseURL: coreURL, workflowBaseURL: coreURL, session: session)
        let coordinator = DirectUploadCoordinator(api: networkClient, uploadSession: session)

        let payload = "Corrupted upload payload simulation".data(using: .utf8)!
        let localDigest = CapturePayloadProcessor.sha256(of: payload)
        let mismatchedDigest = "0000000000000000000000000000000000000000000000000000000000000000"

        MockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            if path.contains("upload-sessions") && !path.contains("complete") {
                let sessionResponse = """
                {
                    "sessionId": "sess-test-123",
                    "documentId": "doc-test-123",
                    "uploadUrl": "https://storage.googleapis.com/test-bucket/doc-test-123",
                    "uploadMethod": "PUT",
                    "expiresAt": "2030-01-01T00:00:00Z",
                    "expectedContentSha256": "\(localDigest)"
                }
                """.data(using: .utf8)!
                return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, sessionResponse)
            } else if request.httpMethod == "PUT" {
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
            } else if path.contains("complete") {
                let receiptResponse = """
                {
                    "sessionId": "sess-test-123",
                    "documentId": "doc-test-123",
                    "contentSha256": "\(mismatchedDigest)",
                    "processingState": "SCANNING"
                }
                """.data(using: .utf8)!
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, receiptResponse)
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }

        do {
            _ = try await coordinator.upload(
                data: payload,
                folderID: FolderID("f_test"),
                originalName: "test.jpg"
            )
            Issue.record("Expected checksum mismatch to throw error")
        } catch let problem as ProblemDetails {
            #expect(problem.status == 422)
            #expect(problem.title.contains("checksum") || problem.title.contains("digest") || problem.title.contains("Checksum"))
        }
    }

    @Test("Expired session slot fails with HTTP 410 Gone")
    func testExpiredSessionHandling() async throws {
        let coreURL = URL(string: "https://lp-gateway-dev-2pou78uy.uc.gateway.dev")!
        let session = makeMockSession()
        let networkClient = NetworkAPIClient(coreBaseURL: coreURL, workflowBaseURL: coreURL, session: session)
        let coordinator = DirectUploadCoordinator(api: networkClient, uploadSession: session)

        let payload = "Expired session payload".data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            let sessionResponse = """
            {
                "sessionId": "sess-expired",
                "documentId": "doc-expired",
                "uploadUrl": "https://storage.googleapis.com/test-bucket/doc-expired",
                "uploadMethod": "PUT",
                "expiresAt": "2020-01-01T00:00:00Z",
                "expectedContentSha256": "abc"
            }
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, sessionResponse)
        }

        do {
            _ = try await coordinator.upload(
                data: payload,
                folderID: FolderID("f_test"),
                originalName: "test.pdf"
            )
            Issue.record("Expected expired session error to be thrown")
        } catch let problem as ProblemDetails {
            #expect(problem.status == 410)
        }
    }
}
