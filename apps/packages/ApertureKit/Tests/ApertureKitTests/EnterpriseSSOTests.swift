import Foundation
import Testing
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

    @Test("SamlAuthenticationSession handles AADSTS90094 and populates adminConsentUrl")
    @MainActor
    func samlSessionAdminConsentErrorHandling() {
        let session = SamlAuthenticationSession()
        let callback = URL(string: "lapluma://auth?error=consent_required&error_description=AADSTS90094:+The+grant+requires+admin+permission&tenant_id=test-org-123")!

        session.handleCallback(url: callback)

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

    @Test("SamlAuthenticationSession decodes authenticated session tokens accurately")
    @MainActor
    func samlSessionSuccessfulTokenExtraction() {
        let session = SamlAuthenticationSession()
        let callback = URL(string: "lapluma://auth?token=jwt-secure-token-abc&tenant_id=tenant_stanford&email=caseworker@stanford.edu")!

        session.handleCallback(url: callback)

        if case .authenticated(let token, let tenant, let email) = session.state {
            #expect(token == "jwt-secure-token-abc")
            #expect(tenant == "tenant_stanford")
            #expect(email == "caseworker@stanford.edu")
            #expect(session.state.authenticatedCredentials?.token == "jwt-secure-token-abc")
        } else {
            Issue.record("Expected .authenticated, got \(session.state)")
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
