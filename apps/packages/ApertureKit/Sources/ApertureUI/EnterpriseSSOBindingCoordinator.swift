import Foundation
import ApertureDomain

/// Coordinates the Enterprise-to-Passkey Trust Pipeline.
///
/// Once an enterprise user authenticates via Microsoft Entra ID or Google Workspace SSO,
/// this coordinator orchestrates the step-up enrollment of a platform Passkey in the Apple
/// Secure Enclave, binding the hardware key to the verified enterprise identity.
@MainActor
public final class EnterpriseSSOBindingCoordinator: ObservableObject {
    public enum BindingState: Equatable, Sendable {
        case idle
        case passkeyReadyForEnrollment(email: String, tenantId: String)
        case enrollingPasskey
        case enrolled(credentialID: Data)
        case skipped
        case failed(reason: String)
    }

    @Published public private(set) var state: BindingState = .idle

    public init() {}

    public func promptPasskeyEnrollment(email: String, tenantId: String) {
        state = .passkeyReadyForEnrollment(email: email, tenantId: tenantId)
    }

    public func enrollPasskey(
        passkeySession: PasskeyAuthenticationSession,
        email: String,
        tenantId: String
    ) async throws -> PasskeyRegistrationResult {
        state = .enrollingPasskey
        let challenge = Data("enterprise-bind-\(tenantId)-\(UUID().uuidString)".utf8)
        let userID = Data("\(tenantId):\(email)".utf8)

        #if canImport(AuthenticationServices)
        do {
            let result = try await passkeySession.registerPasskeyAsync(
                userName: email,
                userID: userID,
                challenge: challenge
            )
            state = .enrolled(credentialID: result.credentialID)
            return result
        } catch {
            state = .failed(reason: error.localizedDescription)
            throw error
        }
        #else
        let fallback = PasskeyRegistrationResult(credentialID: userID)
        state = .enrolled(credentialID: fallback.credentialID)
        return fallback
        #endif
    }

    public func skip() {
        state = .skipped
    }

    public func reset() {
        state = .idle
    }
}
