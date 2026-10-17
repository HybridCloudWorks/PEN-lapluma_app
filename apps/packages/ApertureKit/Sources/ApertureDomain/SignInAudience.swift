import Foundation

/// Who is signing in, which decides how (APP-16, ADR-011).
///
/// Consumer applicants register and sign in with a passkey on whatever email
/// address they already have; a personal domain such as gmail.com is the expected
/// case, not an error. Only workforce members sign in through their institution's
/// directory (Google Workspace or Microsoft Entra ID SAML), and only that path is
/// restricted to institutional domains, because SAML has no directory to send a
/// consumer address to.
public enum SignInAudience: String, Sendable, CaseIterable, Identifiable {
    case applicant
    case workforce

    public var id: String { rawValue }
}

/// The client-side gates in front of each sign-in path. They decide only whether
/// the Continue button is enabled; the passkey ceremony and the server decide
/// whether the person is who they say they are.
public enum SignInEligibility {
    /// Workspace and location codes are at least this long.
    public static let minimumWorkspaceCodeLength = 3

    /// An applicant continues to the passkey with any email address, on any
    /// domain. This is the same check registration applies.
    public static func applicantCanContinue(email: String) -> Bool {
        email.contains("@")
    }

    /// A workforce member needs an institutional address and a workspace code.
    /// Consumer domains stay blocked on this path only.
    public static func workforceCanContinue(email: String, workspaceCode: String) -> Bool {
        guard email.contains("@") else { return false }
        if case .personalDomainDisallowed = EnterpriseDomainPolicy.validate(email: email) {
            return false
        }
        return normalizedWorkspaceCode(workspaceCode).count >= minimumWorkspaceCodeLength
    }

    /// Whether to tell a workforce sign-in that the address is a consumer domain.
    public static func isConsumerDomain(email: String) -> Bool {
        guard email.contains("@") else { return false }
        if case .personalDomainDisallowed = EnterpriseDomainPolicy.validate(email: email) {
            return true
        }
        return false
    }

    public static func normalizedWorkspaceCode(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}
