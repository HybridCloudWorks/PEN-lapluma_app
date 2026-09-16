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
        provider: EnterpriseIdPProvider? = nil
    ) -> URL? {
        var components = URLComponents(string: "\(baseUrl)/auth/saml/login")
        var queryItems = [URLQueryItem(name: "domain", value: domain)]
        if let provider = provider {
            let pStr = provider == .googleWorkspace ? "google" : "entra"
            queryItems.append(URLQueryItem(name: "provider", value: pStr))
        }
        components?.queryItems = queryItems
        return components?.url
    }
}
