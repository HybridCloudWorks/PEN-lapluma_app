import Foundation
import Testing
@testable import ApertureAPI
@testable import ApertureDomain
@testable import ApertureUI

@Suite("Enterprise SSO & Multi-Tenant Identity Tests")
struct EnterpriseSSOTests {

    @Test("Google Workspace login URL enforces hosted domain parameter")
    func googleWorkspaceHostedDomainScoping() {
        let domain = "hybridcloudworks.com"
        let url = EnterpriseDomainPolicy.constructSamlLoginUrl(
            baseUrl: "https://api.lapluma.app",
            domain: domain,
            provider: .googleWorkspace,
            loginHint: "user@hybridcloudworks.com"
        )

        #expect(url != nil)
        let components = URLComponents(url: url!, resolvingAgainstBaseURL: false)
        #expect(components?.queryItems?.first(where: { $0.name == "domain" })?.value == domain)
        #expect(components?.queryItems?.first(where: { $0.name == "provider" })?.value == "google")
        #expect(components?.queryItems?.first(where: { $0.name == "hd" })?.value == domain)
        #expect(components?.queryItems?.first(where: { $0.name == "login_hint" })?.value == "user@hybridcloudworks.com")
    }

    @Test("Microsoft Entra ID login URL includes select_account prompt and optional tenant scoping")
    func entraIDMultiTenantAuthorityConstruction() {
        let domain = "legalaid.org"
        let tenantId = "8f1a2b3c-4d5e-6f7a-8b9c-0d1e2f3a4b5c"
        let url = EnterpriseDomainPolicy.constructSamlLoginUrl(
            baseUrl: "https://api.lapluma.app",
            domain: domain,
            provider: .entraID,
            loginHint: "attorney@legalaid.org",
            tenantId: tenantId
        )

        #expect(url != nil)
        let components = URLComponents(url: url!, resolvingAgainstBaseURL: false)
        #expect(components?.queryItems?.first(where: { $0.name == "domain" })?.value == domain)
        #expect(components?.queryItems?.first(where: { $0.name == "provider" })?.value == "entra")
        #expect(components?.queryItems?.first(where: { $0.name == "prompt" })?.value == "select_account")
        #expect(components?.queryItems?.first(where: { $0.name == "tenant_id" })?.value == tenantId)
        #expect(components?.queryItems?.first(where: { $0.name == "login_hint" })?.value == "attorney@legalaid.org")
    }

    @Test("Microsoft Entra ID admin consent URL constructs with canonical parameters")
    func entraAdminConsentUrlConstruction() {
        let consentUrl = EnterpriseDomainPolicy.constructEntraAdminConsentUrl(
            tenantId: "custom-tenant-guid",
            clientId: "custom-client-id",
            redirectUri: "https://example.com/callback",
            state: "sec-state-123"
        )

        #expect(consentUrl != nil)
        #expect(consentUrl?.host == "login.microsoftonline.com")
        #expect(consentUrl?.path == "/custom-tenant-guid/v2.0/adminconsent")

        let components = URLComponents(url: consentUrl!, resolvingAgainstBaseURL: false)
        #expect(components?.queryItems?.first(where: { $0.name == "client_id" })?.value == "custom-client-id")
        #expect(components?.queryItems?.first(where: { $0.name == "redirect_uri" })?.value == "https://example.com/callback")
        #expect(components?.queryItems?.first(where: { $0.name == "state" })?.value == "sec-state-123")
    }

    @Test("Login URL carries the PKCE challenge, S256, the redirect URI and state")
    func samlLoginUrlCarriesPKCE() {
        let url = EnterpriseDomainPolicy.constructSamlLoginUrl(
            baseUrl: "https://api.lapluma.app",
            domain: "hybridcloudworks.com",
            provider: .entraID,
            redirectUri: "lapluma://auth/callback",
            codeChallenge: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
            state: "state-0123456789abcdef"
        )

        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first(where: { $0.name == name })?.value }
        #expect(url?.path == "/auth/saml/login")
        #expect(value("redirect_uri") == "lapluma://auth/callback")
        #expect(value("code_challenge") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(value("code_challenge_method") == "S256")
        #expect(value("state") == "state-0123456789abcdef")
        #expect(value("token") == nil)
    }

    @Test("SamlAuthenticationSession handles AADSTS90094 and populates adminConsentUrl")
    @MainActor
    func samlSessionAdminConsentErrorHandling() async {
        let session = SamlAuthenticationSession()
        let callback = URL(string: "lapluma://auth?error=consent_required&error_description=AADSTS90094:+The+grant+requires+admin+permission&tenant_id=test-org-123")!

        await session.handleCallback(url: callback)

        if case .adminApprovalRequired(let code, let msg, let consentUrl) = session.state {
            #expect(code == "AADSTS90094")
            #expect(msg.contains("admin permission") || msg.contains("Administrator approval"))
            #expect(consentUrl != nil)
            #expect(consentUrl?.host == "login.microsoftonline.com")
            #expect(consentUrl?.path == "/test-org-123/v2.0/adminconsent")
            #expect(session.state.adminConsentUrl == consentUrl)
        } else {
            Issue.record("Expected .adminApprovalRequired with consentUrl, got \(session.state)")
        }
    }

    @Test("SamlAuthenticationSession redeems the callback code with the PKCE verifier")
    @MainActor
    func samlSessionRedeemsTheCallbackCode() async throws {
        let harness = SignInHarness()
        let session = harness.makeSession { url in
            harness.callback(answering: url, query: "code=lpc1.test-code")
        }

        session.authenticate(
            emailOrDomain: "caseworker@legalaid.org",
            preferredProvider: .entraID,
            baseUrl: "https://gateway.example.test"
        )
        try await waitUntil { session.state.authenticatedCredentials != nil }

        let credentials = try #require(session.state.authenticatedCredentials)
        #expect(credentials.token == "header.payload.signature")
        #expect(credentials.tenantId == "tenant_legalaid")
        #expect(credentials.email == "caseworker@legalaid.org")

        let exchange = try #require(harness.exchangeRequests.first)
        #expect(harness.exchangeRequests.count == 1)
        #expect(exchange.url?.absoluteString == "https://gateway.example.test/auth/token")
        #expect(exchange.httpMethod == "POST")
        let form = SignInHarness.form(exchange)
        #expect(form["grant_type"] == "authorization_code")
        #expect(form["code"] == "lpc1.test-code")
        #expect(form["redirect_uri"] == "lapluma://auth/callback")
        // The verifier sent now hashes to the challenge sent through the browser.
        let verifier = try #require(form["code_verifier"])
        #expect(PKCEPair.challenge(for: verifier) == harness.lastChallenge)
        #expect(!(harness.lastLoginURL?.absoluteString.contains(verifier) ?? true))

        #expect(await harness.store.current?.accessToken == "header.payload.signature")
        let context = await harness.store.renewalContext()
        #expect(context == EnterpriseSignInContext(domain: "legalaid.org", provider: "ENTRA_ID_SAML", baseUrl: "https://gateway.example.test"))
        await harness.store.clear()
    }

    @Test("SamlAuthenticationSession refuses a callback whose state it did not send")
    @MainActor
    func samlSessionRefusesAForeignState() async throws {
        let harness = SignInHarness()
        let session = harness.makeSession { _ in
            URL(string: "lapluma://auth/callback?code=lpc1.injected&state=attacker-chosen-state")!
        }

        session.authenticate(emailOrDomain: "caseworker@legalaid.org", preferredProvider: .entraID, baseUrl: "https://gateway.example.test")
        try await waitUntil { if case .failed = session.state { return true } else { return false } }

        #expect(harness.exchangeRequests.isEmpty)
        #expect(await harness.store.current == nil)
    }

    @Test("SamlAuthenticationSession reports a sign-in the backend turned down")
    @MainActor
    func samlSessionReportsADenial() async throws {
        let harness = SignInHarness()
        let session = harness.makeSession { url in
            harness.callback(answering: url, query: "error=access_denied&error_description=unsolicited-response")
        }

        session.authenticate(emailOrDomain: "caseworker@legalaid.org", preferredProvider: .entraID, baseUrl: "https://gateway.example.test")
        try await waitUntil { if case .failed = session.state { return true } else { return false } }

        if case .failed(let reason) = session.state {
            #expect(reason.contains("unsolicited-response"))
        }
        #expect(harness.exchangeRequests.isEmpty)
    }

    @Test("A callback with no sign-in in progress is refused")
    @MainActor
    func samlSessionRefusesAnUnsolicitedCallback() async {
        let session = SamlAuthenticationSession(credentialStore: SessionCredentialStore(defaultsSuiteName: SignInHarness.suiteName()))

        await session.handleCallback(url: URL(string: "lapluma://auth/callback?code=lpc1.x&state=whatever-state-value")!)

        if case .failed = session.state {} else {
            Issue.record("Expected .failed, got \(session.state)")
        }
    }

    @Test("EnterpriseSSOBindingCoordinator initial state and passkey prompt flow")
    @MainActor
    func ssoBindingCoordinatorLifecycle() {
        let coordinator = EnterpriseSSOBindingCoordinator()
        #expect(coordinator.state == .idle)

        coordinator.promptPasskeyEnrollment(email: "attorney@legalaid.org", tenantId: "tenant_legalaid")
        if case .passkeyReadyForEnrollment(let email, let tenantId) = coordinator.state {
            #expect(email == "attorney@legalaid.org")
            #expect(tenantId == "tenant_legalaid")
        } else {
            Issue.record("Expected .passkeyReadyForEnrollment, got \(coordinator.state)")
        }

        coordinator.skip()
        #expect(coordinator.state == .skipped)

        coordinator.reset()
        #expect(coordinator.state == .idle)
    }
}

/// A fake browser and backend for the sign-in session: the browser answers with whatever the test
/// builds from the login URL, and the backend's token endpoint returns a fixed token.
@MainActor
final class SignInHarness {
    let store = SessionCredentialStore(defaultsSuiteName: SignInHarness.suiteName())
    private let recorder = RequestRecorder()
    private(set) var lastLoginURL: URL?

    var exchangeRequests: [URLRequest] { recorder.requests }

    var lastChallenge: String? {
        lastLoginURL.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems }?
            .first(where: { $0.name == "code_challenge" })?.value
    }

    nonisolated static func suiteName() -> String { "lapluma.tests.\(UUID().uuidString)" }

    func makeSession(browser: @escaping @MainActor (URL) -> URL) -> SamlAuthenticationSession {
        let recorder = recorder
        return SamlAuthenticationSession(
            credentialStore: store,
            transport: { request in
                recorder.record(request)
                let body = Data("""
                {"accessToken":"header.payload.signature","tokenType":"Bearer","expiresIn":3600,
                 "tenantId":"tenant_legalaid","userId":"caseworker@legalaid.org","email":"caseworker@legalaid.org","roles":["preparer"]}
                """.utf8)
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (body, response)
            },
            webAuthenticator: { [weak self] url, scheme in
                #expect(scheme == "lapluma")
                self?.lastLoginURL = url
                return browser(url)
            }
        )
    }

    /// The callback a backend would send for this login URL, with its state.
    func callback(answering loginURL: URL, query: String) -> URL {
        let state = URLComponents(url: loginURL, resolvingAgainstBaseURL: false)?.queryItems?
            .first(where: { $0.name == "state" })?.value ?? ""
        return URL(string: "lapluma://auth/callback?\(query)&state=\(state)")!
    }

    static func form(_ request: URLRequest) -> [String: String] {
        let body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        var fields: [String: String] = [:]
        for pair in body.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            fields[parts[0]] = parts[1].removingPercentEncoding
        }
        return fields
    }
}

final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URLRequest] = []

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func record(_ request: URLRequest) {
        lock.lock()
        recorded.append(request)
        lock.unlock()
    }
}

/// Polls a main-actor condition for up to two seconds, so a regression fails instead of hanging.
@MainActor
func waitUntil(_ condition: @MainActor () -> Bool) async throws {
    for _ in 0..<200 {
        if condition() { return }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    Issue.record("Condition not met within two seconds")
}
