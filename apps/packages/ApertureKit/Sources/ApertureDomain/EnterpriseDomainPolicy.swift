import Foundation

public enum EnterpriseIdPProvider: String, Sendable, CaseIterable, Codable {
    case googleWorkspace = "GOOGLE_WORKSPACE"
    case entraID = "ENTRA_ID_SAML"

    public var displayName: String {
        switch self {
        case .googleWorkspace: "Google Workspace"
        case .entraID: "Microsoft Entra ID"
        }
    }
}

public enum EnterpriseDomainValidationResult: Equatable, Sendable {
    case approved(domain: String, provider: EnterpriseIdPProvider)
    case personalDomainDisallowed(domain: String)
    case invalidEmail
    case domainNotConfigured(domain: String)

    public var isApproved: Bool {
        if case .approved = self { return true }
        return false
    }
}

public enum EnterpriseDomainPolicy {
    public static let primaryOrgDomain = "hybridcloudworks.com"

    public static let disallowedConsumerDomains: Set<String> = [
        "gmail.com",
        "googlemail.com",
        "outlook.com",
        "hotmail.com",
        "live.com",
        "msn.com",
        "yahoo.com",
        "icloud.com",
        "aol.com"
    ]

    public static func validate(email: String) -> EnterpriseDomainValidationResult {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let atIndex = trimmed.firstIndex(of: "@"), atIndex != trimmed.startIndex else {
            return .invalidEmail
        }

        let domain = String(trimmed[trimmed.index(after: atIndex)...])
        guard !domain.isEmpty, domain.contains(".") else {
            return .invalidEmail
        }

        if disallowedConsumerDomains.contains(domain) {
            return .personalDomainDisallowed(domain: domain)
        }

        if domain == primaryOrgDomain {
            return .approved(domain: domain, provider: .googleWorkspace)
        }

        return .approved(domain: domain, provider: .entraID)
    }

    public static func constructSamlLoginUrl(
        baseUrl: String = ApertureEnvironment.current.authBaseUrl,
        domain: String,
        provider: EnterpriseIdPProvider? = nil,
        loginHint: String? = nil,
        tenantId: String? = nil
    ) -> URL? {
        var components = URLComponents(string: "\(baseUrl)/auth/saml/login")
        var queryItems = [URLQueryItem(name: "domain", value: domain)]
        if let provider = provider {
            let pStr = provider == .googleWorkspace ? "google" : "entra"
            queryItems.append(URLQueryItem(name: "provider", value: pStr))
            if provider == .googleWorkspace {
                // Enforce Google Workspace hosted domain scoping (prevents personal @gmail selection)
                queryItems.append(URLQueryItem(name: "hd", value: domain))
            } else if provider == .entraID {
                queryItems.append(URLQueryItem(name: "prompt", value: "select_account"))
                if let tenantId = tenantId {
                    queryItems.append(URLQueryItem(name: "tenant_id", value: tenantId))
                }
            }
        }
        if let loginHint = loginHint, !loginHint.isEmpty {
            queryItems.append(URLQueryItem(name: "login_hint", value: loginHint))
        }
        components?.queryItems = queryItems
        return components?.url
    }

    public static func constructEntraAdminConsentUrl(
        tenantId: String = "organizations",
        clientId: String = "lapluma-enterprise-app",
        redirectUri: String = "https://lp-gateway-dev-2pou78uy.uc.gateway.dev/auth/saml/callback",
        state: String? = nil
    ) -> URL? {
        var components = URLComponents(string: "https://login.microsoftonline.com/\(tenantId)/v2.0/adminconsent")
        var queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "scope", value: "https://graph.microsoft.com/.default")
        ]
        if let state = state {
            queryItems.append(URLQueryItem(name: "state", value: state))
        }
        components?.queryItems = queryItems
        return components?.url
    }
}
