import Foundation

/// Selects which backend deployment the mobile application connects to.
public enum ApertureEnvironment: String, Sendable, CaseIterable, Codable {
    case local
    case development
    case staging
    case production

    /// Base URL for the Core API (Catalog, Document Library, SAML auth endpoints).
    public var coreApiBaseUrl: String {
        switch self {
        case .local:
            return "http://localhost:8080"
        case .development:
            return "https://lp-gateway-dev-2pou78uy.uc.gateway.dev"
        case .staging:
            return "https://lp-core-api-staging.us-central1.run.app"
        case .production:
            return "https://api.lapluma.app"
        }
    }

    /// Base URL for the Workflow API (Workforce, Case workflows, Scoped uploads).
    public var workflowApiBaseUrl: String {
        switch self {
        case .local:
            return "http://localhost:8081"
        case .development:
            return "https://lp-gateway-dev-2pou78uy.uc.gateway.dev"
        case .staging:
            return "https://lp-wf-api-staging.us-central1.run.app"
        case .production:
            return "https://workflow.lapluma.app"
        }
    }

    /// Primary authentication base URL for enterprise SSO.
    public var authBaseUrl: String {
        coreApiBaseUrl
    }

    /// Resolves the current active environment from application bundle settings or defaults to `.development`.
    public static var current: ApertureEnvironment {
        if let envString = Bundle.main.object(forInfoDictionaryKey: "ApertureEnvironment") as? String,
           let env = ApertureEnvironment(rawValue: envString) {
            return env
        }
        #if DEBUG
        return .development
        #else
        return .production
        #endif
    }
}
