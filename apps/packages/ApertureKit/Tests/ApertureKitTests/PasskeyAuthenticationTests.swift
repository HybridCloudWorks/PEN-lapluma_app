import Testing
import Foundation
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
@testable import ApertureUI
@testable import ApertureDomain

@Suite("Passkey Authentication Session Tests (ADR-011 / WebAuthn)")
struct PasskeyAuthenticationTests {

    @Test("Initializes with configured relying party identifier")
    @MainActor
    func testInitialization() {
        let session = PasskeyAuthenticationSession(relyingPartyIdentifier: "lp-gateway-dev-2pou78uy.uc.gateway.dev")
        #expect(session.relyingPartyIdentifier == "lp-gateway-dev-2pou78uy.uc.gateway.dev")
        #expect(session.state == .idle)
    }

    #if canImport(AuthenticationServices)
    @Test("Builds valid ASAuthorization registration request with parameters")
    @MainActor
    func testRegistrationRequestBuilding() {
        let session = PasskeyAuthenticationSession(relyingPartyIdentifier: "lp-gateway-dev-2pou78uy.uc.gateway.dev")
        let challenge = "mock-challenge-data".data(using: .utf8)!
        let userID = "user-12345".data(using: .utf8)!
        let userName = "applicant@example.com"

        let request = session.makeRegistrationRequest(
            userName: userName,
            userID: userID,
            challenge: challenge
        )

        #expect(request.relyingPartyIdentifier == "lp-gateway-dev-2pou78uy.uc.gateway.dev")
        #expect(request.name == userName)
        #expect(request.userID == userID)
        #expect(request.challenge == challenge)
    }

    @Test("Builds valid ASAuthorization assertion request with parameters")
    @MainActor
    func testAssertionRequestBuilding() {
        let session = PasskeyAuthenticationSession(relyingPartyIdentifier: "lp-gateway-dev-2pou78uy.uc.gateway.dev")
        let challenge = "mock-assertion-challenge".data(using: .utf8)!

        let request = session.makeAssertionRequest(challenge: challenge)

        #expect(request.relyingPartyIdentifier == "lp-gateway-dev-2pou78uy.uc.gateway.dev")
        #expect(request.challenge == challenge)
    }
    #endif

    @Test("Session reset transitions state back to idle")
    @MainActor
    func testSessionReset() {
        let session = PasskeyAuthenticationSession()
        session.reset()
        #expect(session.state == .idle)
    }

    @Test("Passkey registration and assertion result structs model credential outputs accurately")
    func testResultModels() {
        let credID = "cred-id-abc".data(using: .utf8)!
        let attestation = "attestation-raw".data(using: .utf8)!
        let userID = "uid-456".data(using: .utf8)!
        let sig = "signature-bytes".data(using: .utf8)!

        let regResult = PasskeyRegistrationResult(credentialID: credID, rawAttestationObject: attestation)
        #expect(regResult.credentialID == credID)
        #expect(regResult.rawAttestationObject == attestation)

        let assertResult = PasskeyAssertionResult(credentialID: credID, userID: userID, signature: sig)
        #expect(assertResult.credentialID == credID)
        #expect(assertResult.userID == userID)
        #expect(assertResult.signature == sig)
    }
}
