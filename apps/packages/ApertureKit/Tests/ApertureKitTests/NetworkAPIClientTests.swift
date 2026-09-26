import Testing
import Foundation
@testable import ApertureAPI
@testable import ApertureDomain

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@Suite("Live Network API Client Tests", .serialized)
struct NetworkAPIClientTests {

    private func makeMockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    @Test("Builds correct URL, method, and standard headers")
    func testBuildRequest() async throws {
        let coreURL = URL(string: "https://lp-gateway-dev-2pou78uy.uc.gateway.dev")!
        let client = NetworkAPIClient(
            coreBaseURL: coreURL,
            session: makeMockSession(),
            tokenProvider: { "test-oidc-bearer-token" },
            activeTenantID: "tenant-nyc"
        )

        let request = await client.buildRequest(
            baseURL: coreURL,
            path: "v1/catalog/packages",
            method: "GET",
            queryItems: [URLQueryItem(name: "query", value: "i-130")],
            idempotencyKey: "idem-key-12345"
        )

        #expect(request.url?.host == "lp-gateway-dev-2pou78uy.uc.gateway.dev")
        #expect(request.url?.path == "/v1/catalog/packages")
        #expect(request.url?.query == "query=i-130")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-oidc-bearer-token")
        #expect(request.value(forHTTPHeaderField: "X-Tenant-ID") == "tenant-nyc")
        #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == "idem-key-12345")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/problem+json")
        #expect(request.value(forHTTPHeaderField: "X-Request-ID") != nil)
    }

    @Test("Decodes RFC 9457 Problem Details on HTTP 404/400 errors")
    func testProblemDetailsHandling() async throws {
        let coreURL = URL(string: "https://lp-gateway-dev-2pou78uy.uc.gateway.dev")!
        let session = makeMockSession()
        let client = NetworkAPIClient(coreBaseURL: coreURL, session: session)

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 404,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/problem+json"]
            )!
            let body = """
            {
                "type": "https://api.lapluma.app/problems/not-found",
                "title": "Catalog package not found",
                "status": 404,
                "correlationId": "corr-404-xyz"
            }
            """.data(using: .utf8)!
            return (response, body)
        }

        do {
            _ = try await client.requirements(packageCode: "INVALID_CODE")
            Issue.record("Expected ProblemDetails error to be thrown")
        } catch let problem as ProblemDetails {
            #expect(problem.status == 404)
            #expect(problem.title == "Catalog package not found")
            #expect(problem.correlationID == "corr-404-xyz")
            #expect(problem.isNotFoundOrUnentitled)
        }
    }

    @Test("Maps URLError offline error to TransportError.offline")
    func testOfflineTransportMapping() async throws {
        let coreURL = URL(string: "https://lp-gateway-dev-2pou78uy.uc.gateway.dev")!
        let session = makeMockSession()
        let client = NetworkAPIClient(coreBaseURL: coreURL, session: session, fallbackClient: nil)

        MockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        do {
            _ = try await client.catalogPackages(query: nil)
            Issue.record("Expected TransportError.offline to be thrown")
        } catch let transport as TransportError {
            if case .offline = transport {
                // Expected
            } else {
                Issue.record("Expected TransportError.offline, got \(transport)")
            }
        }
    }

    @Test("Falls back to fallback client on transport error when configured")
    func testFallbackClientIntegration() async throws {
        let coreURL = URL(string: "https://lp-gateway-dev-2pou78uy.uc.gateway.dev")!
        let session = makeMockSession()
        let stub = StubAPIClient()
        let client = NetworkAPIClient(coreBaseURL: coreURL, session: session, fallbackClient: stub)

        MockURLProtocol.requestHandler = { _ in
            throw URLError(.cannotConnectToHost)
        }

        let packages = try await client.catalogPackages(query: nil)
        #expect(!packages.isEmpty)
        #expect(packages.contains { $0.packageCode == "FAMILY_I130" })
    }

    @Test("Decodes direct catalog array response correctly")
    func testCatalogDirectArrayDecoding() async throws {
        let coreURL = URL(string: "https://lp-gateway-dev-2pou78uy.uc.gateway.dev")!
        let session = makeMockSession()
        let client = NetworkAPIClient(coreBaseURL: coreURL, session: session)

        let samplePackage = StubStorage.seeded(profile: .realisticInternal).catalog[0]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let sampleData = try encoder.encode([samplePackage])

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, sampleData)
        }

        let packages = try await client.catalogPackages(query: nil)
        #expect(!packages.isEmpty)
        #expect(packages[0].packageCode == samplePackage.packageCode)
        #expect(packages[0].title == samplePackage.title)
    }

    @Test("Decodes wrapped data catalog response envelope")
    func testCatalogEnvelopeDecoding() async throws {
        let coreURL = URL(string: "https://lp-gateway-dev-2pou78uy.uc.gateway.dev")!
        let session = makeMockSession()
        let client = NetworkAPIClient(coreBaseURL: coreURL, session: session)

        let samplePackage = StubStorage.seeded(profile: .realisticInternal).catalog[0]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        struct Wrapper: Encodable {
            let data: [FormPackage]
        }
        let sampleData = try encoder.encode(Wrapper(data: [samplePackage]))

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, sampleData)
        }

        let packages = try await client.catalogPackages(query: nil)
        #expect(!packages.isEmpty)
        #expect(packages[0].packageCode == samplePackage.packageCode)
    }

    @Test("createFolder dispatches POST /v1/clients to workflow base URL")
    func testCreateFolderCallsWorkflowApiClientsEndpoint() async throws {
        let workflowURL = URL(string: "https://lp-gateway-staging-am9yq93d.uc.gateway.dev")!
        let session = makeMockSession()
        let client = NetworkAPIClient(workflowBaseURL: workflowURL, session: session)

        let mockResponseData = """
        {
            "folderId": "folder-live-7788",
            "displayLabel": "Maria Elena Rostova"
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.path == "/v1/clients")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == "idem-folder-1")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 201,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, mockResponseData)
        }

        let folder = try await client.createFolder(name: "Maria Elena Rostova", idempotencyKey: "idem-folder-1")
        #expect(folder.id.rawValue == "folder-live-7788")
        #expect(folder.name == "Maria Elena Rostova")
    }

    @Test("commitSection dispatches POST with If-Match revision header")
    func testCommitSectionSendsOptimisticConcurrencyHeader() async throws {
        let workflowURL = URL(string: "https://lp-gateway-staging-am9yq93d.uc.gateway.dev")!
        let session = makeMockSession()
        let client = NetworkAPIClient(workflowBaseURL: workflowURL, session: session)

        let mockResponseData = """
        {
            "section": {
                "id": "identity",
                "revision": 2,
                "values": {
                    "applicant.name.first": "Maria"
                }
            }
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            #expect(request.url?.path == "/v1/cases/case-fixture-0002/sections/identity/commit")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "If-Match") == "\"1\"")
            #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == "idem-commit-1")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, mockResponseData)
        }

        let result = try await client.commitSection(
            caseID: CaseID("case-fixture-0002"),
            sectionID: "identity",
            baseRevision: 1,
            values: ["applicant.name.first": "Maria"],
            idempotencyKey: "idem-commit-1"
        )
        #expect(result.section.id == "identity")
        #expect(result.section.revision == 2)
    }
}

