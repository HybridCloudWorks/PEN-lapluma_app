import Foundation
import Testing
import CryptoKit
@testable import ApertureDomain
@testable import ApertureUI

@Suite("SharePlay Live Canvas & Apple Pencil Pro Biometric Attestation Tests")
struct SharePlayAttestationTests {

    @Test("SharePlay live canvas model synchronizes participant pointers and strokes")
    @MainActor
    func canvasModelParticipantSync() {
        let model = SharePlayLiveCanvasModel(caseID: "case-1234", localParticipantName: "Elena (Caseworker)", localRole: .caseworker)
        #expect(model.isSharePlayActive == false)
        #expect(model.activeParticipants.isEmpty)
        #expect(model.strokes.isEmpty)

        model.startLocalSession()
        #expect(model.isSharePlayActive == true)

        model.updateLocalPointer(x: 0.45, y: 0.60)
        #expect(model.activeParticipants.count == 1)
        #expect(model.activeParticipants.first?.participantName == "Elena (Caseworker)")
        #expect(model.activeParticipants.first?.role == .caseworker)
        #expect(model.activeParticipants.first?.normalizedX == 0.45)
        #expect(model.activeParticipants.first?.normalizedY == 0.60)

        let sampleStroke = CanvasStroke(
            authorName: "Carlos (Client)",
            authorRole: .client,
            points: [CanvasStroke.Point(x: 10, y: 20, pressure: 0.8), CanvasStroke.Point(x: 15, y: 25, pressure: 0.9)]
        )
        model.appendStroke(sampleStroke)
        #expect(model.strokes.count == 1)

        model.setPage(2)
        #expect(model.activePage == 2)

        model.clearStrokes()
        #expect(model.strokes.isEmpty)

        model.endSession()
        #expect(model.isSharePlayActive == false)
        #expect(model.activeParticipants.isEmpty)
    }

    @Test("Pencil Pro telemetry envelope computes metrics and detects barrel roll rotation")
    func pencilTelemetryMetricsAndBarrelRoll() {
        let sample1 = PencilProSample(x: 100, y: 200, pressure: 0.5, altitudeAngle: 0.8, azimuthAngle: 1.2, rollAngle: 0.05)
        let sample2 = PencilProSample(x: 110, y: 205, pressure: 0.7, altitudeAngle: 0.82, azimuthAngle: 1.25, rollAngle: 0.40)
        let sample3 = PencilProSample(x: 120, y: 210, pressure: 0.6, altitudeAngle: 0.85, azimuthAngle: 1.30, rollAngle: 0.55)

        let envelope = PencilProTelemetryEnvelope(samples: [sample1, sample2, sample3])

        #expect(envelope.sampleCount == 3)
        #expect(abs(envelope.averagePressure - 0.6) < 0.001)
        #expect(envelope.isBarrelRollDetected == true)
        #expect(!envelope.telemetryDigestHex.isEmpty)
        #expect(envelope.telemetryDigestHex.count == 64)
    }

    @Test("Secure Enclave attestation signer seals non-repudiable cryptographic signature and verifies")
    func cryptographicAttestationLifecycle() throws {
        let signer = SecureEnclaveAttestationSigner()
        let caseID = "case_ramirez_i130"
        let documentData = "USCIS Form I-130 Official Completed Form Data".data(using: .utf8)!

        let telemetry = [
            PencilProSample(x: 50, y: 100, pressure: 0.6, rollAngle: 0.1),
            PencilProSample(x: 60, y: 105, pressure: 0.8, rollAngle: 0.3)
        ]

        let result = try signer.signAttestation(
            caseID: caseID,
            documentData: documentData,
            telemetrySamples: telemetry
        )

        #expect(result.envelope.caseID == caseID)
        #expect(!result.envelope.signature.isEmpty)
        #expect(!result.envelope.publicKeyData.isEmpty)
        #expect(result.envelope.biometricHardwareSource.contains("Apple Pencil Pro"))

        // Verification must succeed against exact document data
        let isValid = SecureEnclaveAttestationSigner.verifyAttestation(
            envelope: result.envelope,
            documentData: documentData
        )
        #expect(isValid == true)

        // Tampered document data must fail verification
        let tamperedData = "Tampered Document Data".data(using: .utf8)!
        let isTamperedValid = SecureEnclaveAttestationSigner.verifyAttestation(
            envelope: result.envelope,
            documentData: tamperedData
        )
        #expect(isTamperedValid == false)
    }
}
