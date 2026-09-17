import Foundation
import SwiftUI
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import ApertureDomain

public struct PasskeyRegistrationResult: Sendable, Equatable {
    public let credentialID: Data
    public let rawAttestationObject: Data?

    public init(credentialID: Data, rawAttestationObject: Data? = nil) {
        self.credentialID = credentialID
        self.rawAttestationObject = rawAttestationObject
    }
}

public struct PasskeyAssertionResult: Sendable, Equatable {
    public let credentialID: Data
    public let userID: Data
    public let signature: Data?

    public init(credentialID: Data, userID: Data, signature: Data? = nil) {
        self.credentialID = credentialID
        self.userID = userID
        self.signature = signature
    }
}

/// Native biometric Passkey / WebAuthn session manager under ADR-011 (Passkeys primary, no SMS).
///
/// Implements native Apple `AuthenticationServices` platform authenticators (Face ID / Touch ID / Optic ID),
/// managing registration and assertion credential presentation ceremonies with the system dialog.
@MainActor
public final class PasskeyAuthenticationSession: NSObject, ObservableObject {

    public enum PasskeyState: Equatable, Sendable {
        case idle
        case performingRegistration
        case performingAssertion
        case registered(PasskeyRegistrationResult)
        case authenticated(PasskeyAssertionResult)
        case canceled
        case failed(reason: String)
    }

    @Published public private(set) var state: PasskeyState = .idle

    public let relyingPartyIdentifier: String

    private var registrationContinuation: CheckedContinuation<PasskeyRegistrationResult, any Error>?
    private var assertionContinuation: CheckedContinuation<PasskeyAssertionResult, any Error>?

    public init(relyingPartyIdentifier: String = "lp-gateway-dev-2pou78uy.uc.gateway.dev") {
        self.relyingPartyIdentifier = relyingPartyIdentifier
        super.init()
    }

    #if canImport(AuthenticationServices)
    /// Builds a registration request with the configured relying party identifier.
    public func makeRegistrationRequest(
        userName: String,
        userID: Data,
        challenge: Data
    ) -> ASAuthorizationPlatformPublicKeyCredentialRegistrationRequest {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingPartyIdentifier)
        return provider.createCredentialRegistrationRequest(challenge: challenge, name: userName, userID: userID)
    }

    /// Builds an assertion request with the configured relying party identifier.
    public func makeAssertionRequest(
        challenge: Data
    ) -> ASAuthorizationPlatformPublicKeyCredentialAssertionRequest {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingPartyIdentifier)
        return provider.createCredentialAssertionRequest(challenge: challenge)
    }

    /// Initiates passkey registration ceremony.
    public func registerPasskey(
        userName: String,
        userID: Data,
        challenge: Data
    ) {
        state = .performingRegistration
        let request = makeRegistrationRequest(userName: userName, userID: userID, challenge: challenge)
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    /// Initiates passkey assertion ceremony.
    public func assertPasskey(
        challenge: Data
    ) {
        state = .performingAssertion
        let request = makeAssertionRequest(challenge: challenge)
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    /// Async/await variant for passkey registration.
    public func registerPasskeyAsync(
        userName: String,
        userID: Data,
        challenge: Data
    ) async throws -> PasskeyRegistrationResult {
        try await withCheckedThrowingContinuation { continuation in
            self.registrationContinuation = continuation
            self.registerPasskey(userName: userName, userID: userID, challenge: challenge)
        }
    }

    /// Async/await variant for passkey assertion.
    public func assertPasskeyAsync(
        challenge: Data
    ) async throws -> PasskeyAssertionResult {
        try await withCheckedThrowingContinuation { continuation in
            self.assertionContinuation = continuation
            self.assertPasskey(challenge: challenge)
        }
    }
    #endif

    public func reset() {
        state = .idle
        registrationContinuation = nil
        assertionContinuation = nil
    }
}

#if canImport(AuthenticationServices)
extension PasskeyAuthenticationSession: ASAuthorizationControllerPresentationContextProviding {
    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        #if canImport(UIKit)
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
           let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first {
            return window
        }
        return ASPresentationAnchor()
        #elseif canImport(AppKit)
        return NSApplication.shared.windows.first ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
}

extension PasskeyAuthenticationSession: ASAuthorizationControllerDelegate {
    public func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration {
            let result = PasskeyRegistrationResult(
                credentialID: credential.credentialID,
                rawAttestationObject: credential.rawAttestationObject
            )
            state = .registered(result)
            registrationContinuation?.resume(returning: result)
            registrationContinuation = nil
        } else if let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion {
            let result = PasskeyAssertionResult(
                credentialID: credential.credentialID,
                userID: credential.userID,
                signature: credential.signature
            )
            state = .authenticated(result)
            assertionContinuation?.resume(returning: result)
            assertionContinuation = nil
        }
    }

    public func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            state = .canceled
        } else {
            state = .failed(reason: error.localizedDescription)
        }
        registrationContinuation?.resume(throwing: error)
        registrationContinuation = nil
        assertionContinuation?.resume(throwing: error)
        assertionContinuation = nil
    }
}
#endif
