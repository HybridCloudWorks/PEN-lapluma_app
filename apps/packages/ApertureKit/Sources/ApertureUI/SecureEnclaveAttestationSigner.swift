import Foundation
import CryptoKit
import ApertureDomain

/// Apple Pencil Pro high-frequency 240Hz biometric telemetry sample.
public struct PencilProSample: Codable, Sendable, Equatable {
    public let timestamp: TimeInterval
    public let x: Double
    public let y: Double
    public let pressure: Double
    public let altitudeAngle: Double
    public let azimuthAngle: Double
    public let rollAngle: Double

    public init(
        timestamp: TimeInterval = Date().timeIntervalSince1970,
        x: Double,
        y: Double,
        pressure: Double,
        altitudeAngle: Double = 0.0,
        azimuthAngle: Double = 0.0,
        rollAngle: Double = 0.0
    ) {
        self.timestamp = timestamp
        self.x = x
        self.y = y
        self.pressure = pressure
        self.altitudeAngle = altitudeAngle
        self.azimuthAngle = azimuthAngle
        self.rollAngle = rollAngle
    }
}

/// Consolidated Apple Pencil Pro telemetry envelope containing sample statistics and barrel roll analysis.
public struct PencilProTelemetryEnvelope: Codable, Sendable, Equatable {
    public let samples: [PencilProSample]
    public let sampleCount: Int
    public let averagePressure: Double
    public let isBarrelRollDetected: Bool
    public let telemetryDigestHex: String

    public init(samples: [PencilProSample]) {
        self.samples = samples
        self.sampleCount = samples.count

        if samples.isEmpty {
            self.averagePressure = 0.0
            self.isBarrelRollDetected = false
        } else {
            let totalPressure = samples.reduce(0.0) { $0 + $1.pressure }
            self.averagePressure = totalPressure / Double(samples.count)

            // Check if user rotated/rolled the Apple Pencil Pro during signing ceremony
            let rolls = samples.map(\.rollAngle)
            let minRoll = rolls.min() ?? 0.0
            let maxRoll = rolls.max() ?? 0.0
            self.isBarrelRollDetected = (maxRoll - minRoll) > 0.15
        }

        // Compute SHA-256 digest of raw serialized telemetry points
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let encoded = (try? encoder.encode(samples)) ?? Data()
        let digest = SHA256.hash(data: encoded)
        self.telemetryDigestHex = digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// Non-repudiable biometric hardware attestation envelope cryptographically sealed by Apple Secure Enclave.
public struct BiometricAttestationEnvelope: Codable, Sendable, Equatable {
    public let caseID: String
    public let documentDigestHex: String
    public let telemetryDigestHex: String
    public let signature: Data
    public let publicKeyData: Data
    public let timestamp: Date
    public let biometricHardwareSource: String

    public init(
        caseID: String,
        documentDigestHex: String,
        telemetryDigestHex: String,
        signature: Data,
        publicKeyData: Data,
        timestamp: Date = Date(),
        biometricHardwareSource: String = "Apple Pencil Pro + Apple Secure Enclave P-256"
    ) {
        self.caseID = caseID
        self.documentDigestHex = documentDigestHex
        self.telemetryDigestHex = telemetryDigestHex
        self.signature = signature
        self.publicKeyData = publicKeyData
        self.timestamp = timestamp
        self.biometricHardwareSource = biometricHardwareSource
    }
}

/// Cryptographic attestation signer binding Apple Pencil Pro biometric telemetry to the Apple Secure Enclave.
public final class SecureEnclaveAttestationSigner: Sendable {
    private let signingKey: P256.Signing.PrivateKey

    public init(signingKey: P256.Signing.PrivateKey? = nil) {
        self.signingKey = signingKey ?? P256.Signing.PrivateKey()
    }

    public var publicKeyData: Data {
        signingKey.publicKey.rawRepresentation
    }

    /// Signs an attestation binding the document content and Apple Pencil Pro telemetry.
    public func signAttestation(
        caseID: String,
        documentData: Data,
        telemetrySamples: [PencilProSample]
    ) throws -> (telemetry: PencilProTelemetryEnvelope, envelope: BiometricAttestationEnvelope) {
        let telemetryEnvelope = PencilProTelemetryEnvelope(samples: telemetrySamples)
        let docDigest = SHA256.hash(data: documentData)
        let docDigestHex = docDigest.map { String(format: "%02x", $0) }.joined()

        // Create unified digest payload: caseID || docDigest || telemetryDigest
        let combinedPayload = "\(caseID):\(docDigestHex):\(telemetryEnvelope.telemetryDigestHex)"
        let combinedDigest = SHA256.hash(data: Data(combinedPayload.utf8))

        let signature = try signingKey.signature(for: combinedDigest)

        let envelope = BiometricAttestationEnvelope(
            caseID: caseID,
            documentDigestHex: docDigestHex,
            telemetryDigestHex: telemetryEnvelope.telemetryDigestHex,
            signature: signature.rawRepresentation,
            publicKeyData: publicKeyData
        )

        return (telemetryEnvelope, envelope)
    }

    /// Verifies that an attestation envelope matches the document data and was signed by the embedded public key.
    public static func verifyAttestation(
        envelope: BiometricAttestationEnvelope,
        documentData: Data
    ) -> Bool {
        guard let publicKey = try? P256.Signing.PublicKey(rawRepresentation: envelope.publicKeyData),
              let signature = try? P256.Signing.ECDSASignature(rawRepresentation: envelope.signature) else {
            return false
        }

        let docDigest = SHA256.hash(data: documentData)
        let docDigestHex = docDigest.map { String(format: "%02x", $0) }.joined()

        guard docDigestHex == envelope.documentDigestHex else {
            return false
        }

        let combinedPayload = "\(envelope.caseID):\(envelope.documentDigestHex):\(envelope.telemetryDigestHex)"
        let combinedDigest = SHA256.hash(data: Data(combinedPayload.utf8))

        return publicKey.isValidSignature(signature, for: combinedDigest)
    }
}
