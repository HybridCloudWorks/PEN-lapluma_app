import Foundation
import SwiftUI
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
import ApertureAPI
import ApertureDomain

/// Enterprise SAML sign-in for the sign-in screen (INT-22).
///
/// `authenticate` opens `/auth/saml/login` with PKCE and a fresh `state` in
/// `ASWebAuthenticationSession`; the backend answers with `lapluma://auth/callback?code=…&state=…`,
/// and `handleCallback` checks the state and redeems the code at `POST /auth/token`. The session
/// token goes to `SessionCredentialStore`, never into a URL. In DEBUG builds launched with
/// `--ui-testing-auth-stub`, `UITestingAuthStub` stands in for the browser and the backend.
@MainActor
public final class SamlAuthenticationSession: ObservableObject {
    public enum AuthState: Equatable, Sendable {
        case idle
        case authenticating(provider: EnterpriseIdPProvider)
        case authenticated(token: String, tenantId: String, email: String)
        case adminApprovalRequired(code: String, message: String, adminConsentUrl: URL?)
        case failed(reason: String)

        public var adminConsentUrl: URL? {
            if case .adminApprovalRequired(_, _, let url) = self {
                return url
            }
            return nil
        }

        public var authenticatedCredentials: (token: String, tenantId: String, email: String)? {
            if case .authenticated(let token, let tenantId, let email) = self {
                return (token, tenantId, email)
            }
            return nil
        }
    }

    /// A sign-in waiting for its callback.
    struct PendingSignIn {
        let started: EnterpriseSignInFlow.Started
        let baseUrl: String
        let context: EnterpriseSignInContext
    }

    @Published public private(set) var state: AuthState = .idle

    private let credentialStore: SessionCredentialStore
    private let flow: EnterpriseSignInFlow
    private let webAuthenticator: EnterpriseSignInFlow.WebAuthenticator?
    private(set) var pending: PendingSignIn?

    public init(
        credentialStore: SessionCredentialStore = .shared,
        transport: @escaping SessionTokenExchange.Transport = SessionTokenExchange.urlSessionTransport,
        webAuthenticator: EnterpriseSignInFlow.WebAuthenticator? = nil
    ) {
        self.credentialStore = credentialStore
        self.webAuthenticator = webAuthenticator
        self.flow = EnterpriseSignInFlow(transport: transport, webAuthenticator: webAuthenticator)
    }

    public func authenticate(
        emailOrDomain: String,
        preferredProvider: EnterpriseIdPProvider? = nil,
        baseUrl: String = ApertureEnvironment.current.authBaseUrl,
        customScheme: String = SessionTokenExchange.callbackScheme
    ) {
        let domain: String
        let loginHint: String?
        if emailOrDomain.contains("@") {
            let validation = EnterpriseDomainPolicy.validate(email: emailOrDomain)
            switch validation {
            case .approved(let validDomain, _):
                domain = validDomain
                loginHint = emailOrDomain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            case .personalDomainDisallowed(let disDomain):
                state = .failed(reason: "Personal accounts (@\(disDomain)) are not permitted. Please use your institutional Google Workspace or Microsoft Entra ID account.")
                return
            case .invalidEmail:
                state = .failed(reason: "Please enter a valid institutional email address.")
                return
            case .domainNotConfigured(let nonDomain):
                state = .failed(reason: "Domain '@\(nonDomain)' is not configured for enterprise single sign-on.")
                return
            }
        } else {
            let trimmed = emailOrDomain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if EnterpriseDomainPolicy.disallowedConsumerDomains.contains(trimmed) {
                state = .failed(reason: "Personal accounts (@\(trimmed)) are not permitted.")
                return
            }
            domain = trimmed
            loginHint = nil
        }

        let provider = preferredProvider ?? (domain == EnterpriseDomainPolicy.primaryOrgDomain ? .googleWorkspace : .entraID)
        state = .authenticating(provider: provider)

        #if DEBUG
        if UITestingAuthStub.isActive {
            // No browser, no network, and no saved context: UI tests never reach real sign-in.
            let credential = UITestingAuthStub.credential(domain: domain)
            Task { await self.complete(with: credential, context: nil) }
            return
        }
        #endif

        guard let started = EnterpriseSignInFlow.start(
            baseUrl: baseUrl,
            domain: domain,
            provider: provider,
            loginHint: loginHint
        ) else {
            state = .failed(reason: "Could not construct SAML authentication URL.")
            return
        }
        pending = PendingSignIn(
            started: started,
            baseUrl: baseUrl,
            context: EnterpriseSignInContext(domain: domain, provider: provider.rawValue, baseUrl: baseUrl)
        )

        #if canImport(AuthenticationServices) && !os(watchOS)
        let presenter = webAuthenticator ?? Self.systemPresenter()
        Task { [weak self] in
            do {
                let callback = try await presenter(started.url, customScheme)
                await self?.handleCallback(url: callback)
            } catch {
                self?.handlePresentationError(error)
            }
        }
        #else
        pending = nil
        state = .failed(reason: "Enterprise sign-in needs AuthenticationServices, which this platform does not provide.")
        #endif
    }

    /// Handles the browser's callback: an Entra ID admin-consent error, or the answer to the
    /// sign-in in progress. A callback whose `state` is not the one sent is refused.
    public func handleCallback(url: URL) async {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            state = .failed(reason: "Invalid callback URL structure.")
            return
        }

        // Check for Entra ID admin consent error
        if let error = components.queryItems?.first(where: { $0.name == "error" })?.value,
           error.contains("AADSTS90094") || error.contains("consent_required") {
            let rawDesc = components.queryItems?.first(where: { $0.name == "error_description" })?.value ?? "Administrator approval is required."
            let desc = rawDesc.replacingOccurrences(of: "+", with: " ")
            let tenant = components.queryItems?.first(where: { $0.name == "tenant_id" })?.value ?? "organizations"
            let consentUrl = EnterpriseDomainPolicy.constructEntraAdminConsentUrl(tenantId: tenant)
            pending = nil
            state = .adminApprovalRequired(code: "AADSTS90094", message: desc, adminConsentUrl: consentUrl)
            return
        }

        guard let pending else {
            state = .failed(reason: "No sign-in is in progress for this response.")
            return
        }
        self.pending = nil

        do {
            let credential = try await flow.finish(callback: url, started: pending.started, baseUrl: pending.baseUrl)
            await complete(with: credential, context: pending.context)
        } catch EnterpriseSignInError.denied(let reason) {
            state = .failed(reason: "Your organization's sign-in did not succeed (\(reason)).")
        } catch EnterpriseSignInError.mismatchedCallback {
            state = .failed(reason: "The sign-in response did not match this request. Please try again.")
        } catch {
            state = .failed(reason: "Sign-in could not be completed. Please try again.")
        }
    }

    public func reset() {
        pending = nil
        state = .idle
    }

    private func complete(with credential: SessionCredential, context: EnterpriseSignInContext?) async {
        await credentialStore.store(credential, context: context)
        state = .authenticated(token: credential.accessToken, tenantId: credential.tenantID, email: credential.email)
    }

    private func handlePresentationError(_ error: any Error) {
        pending = nil
        #if canImport(AuthenticationServices) && !os(watchOS)
        let nsError = error as NSError
        if nsError.domain == ASWebAuthenticationSessionError.errorDomain &&
            nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
            state = .idle
            return
        }
        #endif
        state = .failed(reason: error.localizedDescription)
    }

    #if canImport(AuthenticationServices) && !os(watchOS)
    private static func systemPresenter() -> EnterpriseSignInFlow.WebAuthenticator {
        let runner = WebAuthenticationRunner()
        return { url, scheme in try await runner.run(url: url, callbackScheme: scheme) }
    }
    #endif
}
