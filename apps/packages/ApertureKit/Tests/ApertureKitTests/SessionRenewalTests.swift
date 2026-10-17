import Foundation
import Testing
@testable import ApertureAPI
@testable import ApertureDomain
@testable import ApertureUI

@Suite("Sign-in code exchange and PKCE (INT-22)")
struct SignInCodeExchangeTests {
    @Test("S256 challenge matches the RFC 7636 appendix B vector")
    func rfc7636Vector() {
        #expect(PKCEPair.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test("Generated verifiers and states are fresh, unreserved, and the right length")
    func generatedValues() {
        let first = PKCEPair.generate()
        let second = PKCEPair.generate()
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

        #expect(first.verifier.count == 43)
        #expect(first.challenge.count == 43)
        #expect(first.verifier != second.verifier)
        #expect(first.verifier.unicodeScalars.allSatisfy { unreserved.contains($0) })
        #expect(PKCEPair.generateState().count == 32)
        #expect(PKCEPair.generateState() != PKCEPair.generateState())
    }

    @Test("Callback parsing checks state before reading the code or the error")
    func callbackParsing() {
        let expected = "state-0123456789abcdef"
        func parse(_ query: String) -> EnterpriseSignInCallback {
            EnterpriseSignInCallback.parse(URL(string: "lapluma://auth/callback?\(query)")!, expectedState: expected)
        }

        #expect(parse("code=lpc1.abc&state=\(expected)") == .code("lpc1.abc"))
        #expect(parse("error=access_denied&error_description=invalid-signature&state=\(expected)") == .denied(reason: "invalid-signature"))
        #expect(parse("code=lpc1.abc&state=someone-else") == .mismatched)
        #expect(parse("code=lpc1.abc") == .mismatched)
        #expect(parse("error=access_denied") == .mismatched)
        #expect(parse("state=\(expected)") == .mismatched)
        // A token in the URL is never accepted as a sign-in.
        #expect(parse("token=eyJhbGciOi.payload.sig&state=\(expected)") == .mismatched)
    }

    @Test("Form encoding percent-encodes everything but unreserved characters")
    func formEncoding() {
        #expect(SessionTokenExchange.formEncode("lapluma://auth/callback") == "lapluma%3A%2F%2Fauth%2Fcallback")
        #expect(SessionTokenExchange.formEncode("lpc1.AZaz09-_~") == "lpc1.AZaz09-_~")
        #expect(SessionTokenExchange.formEncode("a+b c&d=é") == "a%2Bb%20c%26d%3D%C3%A9")
    }

    @Test("A redeemed code becomes a credential that expires when the backend says")
    func redeemSuccess() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let exchange = SessionTokenExchange(baseURL: URL(string: "https://gateway.example.test")!) { request in
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
            return Self.response(request, status: 200, body: """
            {"accessToken":"a.b.c","tokenType":"Bearer","expiresIn":3600,"tenantId":"tenant_x","userId":"u@x.org","email":"u@x.org","roles":["reviewer"]}
            """)
        }

        let credential = try await exchange.redeem(code: "lpc1.c", verifier: PKCEPair.generate().verifier, now: now)

        #expect(credential.accessToken == "a.b.c")
        #expect(credential.tenantID == "tenant_x")
        #expect(credential.roles == ["reviewer"])
        #expect(credential.expiresAt == now.addingTimeInterval(3600))
        #expect(credential.isUsable(at: now.addingTimeInterval(3500)))
        #expect(!credential.isUsable(at: now.addingTimeInterval(3550)))
    }

    @Test("A refused code surfaces the backend's problem type")
    func redeemRefused() async {
        let exchange = SessionTokenExchange(baseURL: URL(string: "https://gateway.example.test")!) { request in
            Self.response(request, status: 400, body: """
            {"type":"urn:lapluma:problem:auth-code-replayed","title":"x","status":400}
            """)
        }

        do {
            _ = try await exchange.redeem(code: "lpc1.c", verifier: PKCEPair.generate().verifier)
            Issue.record("Expected the exchange to fail")
        } catch {
            #expect(error as? EnterpriseSignInError == .exchangeFailed(status: 400, type: "urn:lapluma:problem:auth-code-replayed"))
        }
    }

    @Test("A success response without a bearer token is refused")
    func redeemMalformed() async {
        let exchange = SessionTokenExchange(baseURL: URL(string: "https://gateway.example.test")!) { request in
            Self.response(request, status: 200, body: """
            {"accessToken":"","tokenType":"Bearer","expiresIn":3600,"tenantId":"t","userId":"u"}
            """)
        }

        await #expect(throws: EnterpriseSignInError.malformedResponse) {
            _ = try await exchange.redeem(code: "lpc1.c", verifier: PKCEPair.generate().verifier)
        }
    }

    static func response(_ request: URLRequest, status: Int, body: String) -> (Data, URLResponse) {
        (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

@Suite("Session credential store renewal (INT-22)")
struct SessionCredentialStoreTests {
    private static func credential(_ token: String, expiresIn seconds: TimeInterval, from now: Date = Date()) -> SessionCredential {
        SessionCredential(accessToken: token, tenantID: "t", userID: "u", email: "u@x.org", roles: [], expiresAt: now.addingTimeInterval(seconds))
    }

    private static func makeStore() -> SessionCredentialStore {
        SessionCredentialStore(defaultsSuiteName: "lapluma.tests.\(UUID().uuidString)")
    }

    @Test("A usable token is sent without renewing")
    func usableTokenIsReused() async {
        let store = Self.makeStore()
        let calls = Counter()
        await store.setRenewalHandler { calls.increment(); return .failed }
        await store.store(Self.credential("held", expiresIn: 3600))

        #expect(await store.accessTokenForRequest() == "held")
        #expect(calls.value == 0)
    }

    @Test("A token about to expire is renewed first, once for concurrent requests")
    func nearExpiryRenewsOnce() async {
        let store = Self.makeStore()
        let calls = Counter()
        await store.store(Self.credential("old", expiresIn: 30))
        await store.setRenewalHandler {
            calls.increment()
            try? await Task.sleep(nanoseconds: 50_000_000)
            return .renewed(Self.credential("new", expiresIn: 3600))
        }

        async let first = store.accessTokenForRequest()
        async let second = store.accessTokenForRequest()
        let tokens = await [first, second]

        #expect(tokens == ["new", "new"])
        #expect(calls.value == 1)
        #expect(await store.current?.accessToken == "new")
    }

    @Test("A 401 renews, unless another request already replaced the refused token")
    func rejectionRenews() async {
        let store = Self.makeStore()
        let calls = Counter()
        await store.store(Self.credential("refused", expiresIn: 3600))
        await store.setRenewalHandler {
            calls.increment()
            return .renewed(Self.credential("renewed", expiresIn: 3600))
        }

        #expect(await store.tokenAfterRejection(of: "refused") == "renewed")
        #expect(await store.tokenAfterRejection(of: "refused") == "renewed")
        #expect(calls.value == 1)
    }

    @Test("A declined renewal is not retried until the cooldown passes")
    func failedRenewalCoolsDown() async {
        let clock = MutableClock()
        let store = SessionCredentialStore(defaultsSuiteName: "lapluma.tests.\(UUID().uuidString)", clock: { clock.now })
        let calls = Counter()
        await store.setRenewalHandler { calls.increment(); return .failed }

        #expect(await store.accessTokenForRequest() == nil)
        #expect(await store.accessTokenForRequest() == nil)
        #expect(calls.value == 1)

        clock.advance(SessionCredentialStore.renewalCooldown + 1)
        #expect(await store.accessTokenForRequest() == nil)
        #expect(calls.value == 2)
    }

    @Test("An unavailable renewal does not start the cooldown")
    func unavailableRenewalDoesNotCoolDown() async {
        let store = Self.makeStore()
        let calls = Counter()
        await store.setRenewalHandler { calls.increment(); return .unavailable }

        _ = await store.accessTokenForRequest()
        _ = await store.accessTokenForRequest()

        #expect(calls.value == 2)
    }

    @Test("Signing out during a renewal discards its result and the saved context")
    func signOutWins() async {
        let store = Self.makeStore()
        let started = Counter()
        await store.store(Self.credential("old", expiresIn: 10), context: EnterpriseSignInContext(domain: "x.org", provider: "ENTRA_ID_SAML", baseUrl: "https://g"))
        await store.setRenewalHandler {
            started.increment()
            try? await Task.sleep(nanoseconds: 500_000_000)
            return .renewed(Self.credential("late", expiresIn: 3600))
        }

        async let token = store.accessTokenForRequest()
        // Sign out only once the renewal is actually under way; bounded at two seconds.
        for _ in 0..<200 where started.value == 0 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(started.value == 1)
        await store.clear()

        #expect(await token == nil)
        #expect(await store.current == nil)
        #expect(await store.renewalContext() == nil)
    }
}

@Suite("Network client renews once on 401 (INT-22)", .serialized)
struct UnauthorizedRecoveryTests {
    @Test("A 401 is retried once with the renewed token")
    func retriesOnceWithRenewedToken() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecoveryURLProtocol.self]
        let seen = RequestRecorder()
        RecoveryURLProtocol.handler = { request in
            seen.record(request)
            let authorized = request.value(forHTTPHeaderField: "Authorization") == "Bearer renewed"
            let response = HTTPURLResponse(url: request.url!, statusCode: authorized ? 200 : 401, httpVersion: nil, headerFields: nil)!
            return (response, Data(authorized ? "[]".utf8 : "{}".utf8))
        }
        defer { RecoveryURLProtocol.handler = nil }
        let refusedTokens = RequestRecorder()
        let client = NetworkAPIClient(
            coreBaseURL: URL(string: "https://gateway.example.test")!,
            session: URLSession(configuration: configuration),
            tokenProvider: { "expired" },
            unauthorizedRecovery: { refused in
                refusedTokens.record(URLRequest(url: URL(string: "https://x.test/\(refused ?? "none")")!))
                return "renewed"
            }
        )

        let packages = try await client.catalogPackages(query: nil)

        #expect(packages.isEmpty)
        #expect(seen.requests.map { $0.value(forHTTPHeaderField: "Authorization") } == ["Bearer expired", "Bearer renewed"])
        #expect(refusedTokens.requests.map { $0.url?.lastPathComponent } == ["expired"])
    }

    @Test("Without a renewed token the 401 stands")
    func noRenewalLeavesTheFailure() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecoveryURLProtocol.self]
        let seen = RequestRecorder()
        RecoveryURLProtocol.handler = { request in
            seen.record(request)
            return (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
        }
        defer { RecoveryURLProtocol.handler = nil }
        let client = NetworkAPIClient(
            coreBaseURL: URL(string: "https://gateway.example.test")!,
            session: URLSession(configuration: configuration),
            tokenProvider: { "expired" },
            unauthorizedRecovery: { _ in nil }
        )

        do {
            _ = try await client.catalogPackages(query: nil)
            Issue.record("Expected a 401")
        } catch let problem as ProblemDetails {
            #expect(problem.status == 401)
        } catch {
            Issue.record("Unexpected error \(error)")
        }
        #expect(seen.requests.count == 1)
    }
}

@Suite("Enterprise session renewer (INT-22)")
struct EnterpriseSessionRenewerTests {
    @Test("Nothing to renew without an enterprise sign-in on record")
    @MainActor
    func noContextIsUnavailable() async {
        let renewer = EnterpriseSessionRenewer(
            store: SessionCredentialStore(defaultsSuiteName: "lapluma.tests.\(UUID().uuidString)"),
            flow: EnterpriseSignInFlow(webAuthenticator: { _, _ in
                Issue.record("The browser must not open")
                throw EnterpriseSignInError.mismatchedCallback
            }),
            isForeground: { true }
        )

        #expect(await renewer.renew() == .unavailable)
    }

    @Test("No sign-in sheet while the app is in the background")
    @MainActor
    func backgroundIsUnavailable() async {
        let store = SessionCredentialStore(defaultsSuiteName: "lapluma.tests.\(UUID().uuidString)")
        await store.store(Self.credential, context: Self.context)
        let renewer = EnterpriseSessionRenewer(
            store: store,
            flow: EnterpriseSignInFlow(webAuthenticator: { _, _ in
                Issue.record("The browser must not open")
                throw EnterpriseSignInError.mismatchedCallback
            }),
            isForeground: { false }
        )

        #expect(await renewer.renew() == .unavailable)
    }

    @Test("Renewal signs in again against the saved domain and provider")
    @MainActor
    func renewsWithSavedContext() async throws {
        let store = SessionCredentialStore(defaultsSuiteName: "lapluma.tests.\(UUID().uuidString)")
        await store.store(Self.credential, context: Self.context)
        let opened = RequestRecorder()
        let flow = EnterpriseSignInFlow(
            transport: { request in
                SignInCodeExchangeTests.response(request, status: 200, body: """
                {"accessToken":"renewed.jwt.sig","tokenType":"Bearer","expiresIn":3600,"tenantId":"tenant_hcw","userId":"reviewer@hybridcloudworks.com"}
                """)
            },
            webAuthenticator: { url, _ in
                opened.record(URLRequest(url: url))
                let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                let state = items.first(where: { $0.name == "state" })?.value ?? ""
                return URL(string: "lapluma://auth/callback?code=lpc1.renewal&state=\(state)")!
            }
        )
        let renewer = EnterpriseSessionRenewer(store: store, flow: flow, isForeground: { true })

        let outcome = await renewer.renew()

        guard case .renewed(let renewed) = outcome else {
            Issue.record("Expected a renewal, got \(outcome)")
            return
        }
        #expect(renewed.accessToken == "renewed.jwt.sig")
        let loginURL = try #require(opened.requests.first?.url)
        let items = URLComponents(url: loginURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(loginURL.host == "gateway.example.test")
        #expect(items.first(where: { $0.name == "domain" })?.value == "hybridcloudworks.com")
        #expect(items.first(where: { $0.name == "provider" })?.value == "entra")
        #expect(items.first(where: { $0.name == "code_challenge_method" })?.value == "S256")
    }

    @Test("A cancelled sign-in sheet is a failed renewal")
    @MainActor
    func cancelledIsFailed() async {
        let store = SessionCredentialStore(defaultsSuiteName: "lapluma.tests.\(UUID().uuidString)")
        await store.store(Self.credential, context: Self.context)
        let renewer = EnterpriseSessionRenewer(
            store: store,
            flow: EnterpriseSignInFlow(webAuthenticator: { _, _ in throw CancellationError() }),
            isForeground: { true }
        )

        #expect(await renewer.renew() == .failed)
    }

    private static let credential = SessionCredential(
        accessToken: "old", tenantID: "tenant_hcw", userID: "u", email: "u@hybridcloudworks.com", roles: [], expiresAt: Date()
    )

    private static let context = EnterpriseSignInContext(
        domain: "hybridcloudworks.com", provider: "ENTRA_ID_SAML", baseUrl: "https://gateway.example.test"
    )
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock()
        current = current.addingTimeInterval(seconds)
        lock.unlock()
    }
}

/// Its own protocol class, so these tests never share a handler with `MockURLProtocol`'s suite.
final class RecoveryURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = RecoveryURLProtocol.handler else {
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
