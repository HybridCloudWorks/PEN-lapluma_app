import Foundation
import SwiftUI
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
import ApertureDomain

@MainActor
public final class SamlAuthenticationSession: ObservableObject {
    public enum AuthState: Equatable, Sendable {
        case idle
        case authenticating(provider: EnterpriseIdPProvider)
        case authenticated(token: String, tenantId: String, email: String)
        case adminApprovalRequired(code: String, message: String)
        case failed(reason: String)
    }

    @Published public private(set) var state: AuthState = .idle

    public init() {}

    public func authenticate(
        emailOrDomain: String,
        preferredProvider: EnterpriseIdPProvider? = nil,
        baseUrl: String = ApertureEnvironment.current.authBaseUrl,
        customScheme: String = "lapluma"
    ) {
        let domain: String
        if emailOrDomain.contains("@") {
            let validation = EnterpriseDomainPolicy.validate(email: emailOrDomain)
            switch validation {
            case .approved(let validDomain, _):
                domain = validDomain
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
        }

        let provider = preferredProvider ?? (domain == EnterpriseDomainPolicy.primaryOrgDomain ? .googleWorkspace : .entraID)
        state = .authenticating(provider: provider)

        guard let loginUrl = EnterpriseDomainPolicy.constructSamlLoginUrl(baseUrl: baseUrl, domain: domain, provider: provider) else {
            state = .failed(reason: "Could not construct SAML authentication URL.")
            return
        }

        #if canImport(AuthenticationServices) && !os(watchOS)
        let session = ASWebAuthenticationSession(
            url: loginUrl,
            callbackURLScheme: customScheme
        ) { [weak self] callbackUrl, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                if let error = error {
                    let nsError = error as NSError
                    if nsError.domain == ASWebAuthenticationSessionError.errorDomain &&
                       nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        self.state = .idle
                        return
                    }
                    self.state = .failed(reason: error.localizedDescription)
                    return
                }

                guard let callbackUrl = callbackUrl else {
                    self.state = .failed(reason: "No callback URL received from authentication session.")
                    return
                }

                self.handleCallback(url: callbackUrl)
            }
        }

        session.prefersEphemeralWebBrowserSession = true
        session.start()
        #else
        // Mock / headless test environment
        let mockToken = "lp_saml_mock_token_\(domain)"
        state = .authenticated(token: mockToken, tenantId: "tenant_hybridcloudworks", email: "user@\(domain)")
        #endif
    }

    public func handleCallback(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            state = .failed(reason: "Invalid callback URL structure.")
            return
        }

        // Check for Entra ID admin consent error
        if let error = components.queryItems?.first(where: { $0.name == "error" })?.value,
           error.contains("AADSTS90094") || error.contains("consent_required") {
            let desc = components.queryItems?.first(where: { $0.name == "error_description" })?.value ?? "Administrator approval is required."
            state = .adminApprovalRequired(code: "AADSTS90094", message: desc)
            return
        }

        if let token = components.queryItems?.first(where: { $0.name == "token" })?.value {
            let tenant = components.queryItems?.first(where: { $0.name == "tenant_id" })?.value ?? "tenant_hybridcloudworks"
            let email = components.queryItems?.first(where: { $0.name == "email" })?.value ?? "user@hybridcloudworks.com"
            state = .authenticated(token: token, tenantId: tenant, email: email)
            return
        }

        state = .failed(reason: "Authentication response did not contain a session token.")
    }

    public func reset() {
        state = .idle
    }
}
