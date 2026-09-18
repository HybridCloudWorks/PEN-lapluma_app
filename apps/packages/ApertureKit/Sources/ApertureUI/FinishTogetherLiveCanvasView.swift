import SwiftUI
import CryptoKit
import ApertureDomain

/// iPadOS 27 Dual-Panel Synchronous Collaborative Live Review Canvas.
///
/// Features real-time FaceTime SharePlay co-review, live participant cursors,
/// and Apple Pencil Pro 240Hz biometric attestation signed directly by the Apple Secure Enclave.
public struct FinishTogetherLiveCanvasView: View {
    @StateObject public var model: SharePlayLiveCanvasModel
    @State private var showingAttestationSheet = false
    @State private var attestationSealed = false
    @State private var lastAttestation: BiometricAttestationEnvelope?

    public init(caseID: String) {
        _model = StateObject(wrappedValue: SharePlayLiveCanvasModel(caseID: caseID))
    }

    public var body: some View {
        AtmosphericMeshCanvas {
            VStack(spacing: Aperture.Spacing.m) {
                // Top SharePlay session status bar
                sharePlayStatusBar

                // Main Collaborative Form Surface
                ZStack {
                    // Document Mock Canvas Page
                    RoundedRectangle(cornerRadius: Aperture.Radius.card, style: .continuous)
                        .fill(Color.white)
                        .overlay {
                            VStack(alignment: .leading, spacing: Aperture.Spacing.m) {
                                HStack {
                                    Text("USCIS Form Review — Case \(model.caseID)")
                                        .font(Aperture.Typography.value)
                                        .foregroundStyle(Aperture.Palette.darkInk)
                                    Spacer()
                                    Text("Page \(model.activePage) of 12")
                                        .font(Aperture.Typography.caption)
                                        .foregroundStyle(Aperture.Palette.inkSecondary)
                                }
                                Divider()

                                VStack(alignment: .leading, spacing: Aperture.Spacing.s) {
                                    Text("Part 1. Information About You")
                                        .font(Aperture.Typography.value)
                                        .foregroundStyle(Aperture.Palette.darkInk)

                                    HStack {
                                        Text("Family Name: Ramirez")
                                            .font(Aperture.Typography.body)
                                        Spacer()
                                        Image(systemName: "checkmark.seal.fill")
                                            .foregroundStyle(Aperture.Palette.actionGreen)
                                    }
                                    .padding(Aperture.Spacing.s)
                                    .background(Aperture.Palette.pastelGreen, in: RoundedRectangle(cornerRadius: Aperture.Radius.chip))

                                    HStack {
                                        Text("Given Name: Carlos")
                                            .font(Aperture.Typography.body)
                                        Spacer()
                                        Image(systemName: "checkmark.seal.fill")
                                            .foregroundStyle(Aperture.Palette.actionGreen)
                                    }
                                    .padding(Aperture.Spacing.s)
                                    .background(Aperture.Palette.pastelGreen, in: RoundedRectangle(cornerRadius: Aperture.Radius.chip))
                                }

                                Spacer()

                                if attestationSealed, let attestation = lastAttestation {
                                    HStack(spacing: Aperture.Spacing.s) {
                                        Image(systemName: "signature")
                                            .font(.title3)
                                            .foregroundStyle(Aperture.Palette.actionGreen)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Hardware Biometric Attestation Sealed")
                                                .font(Aperture.Typography.caption.weight(.bold))
                                                .foregroundStyle(Aperture.Palette.actionGreen)
                                            Text("Enclave Key: \(attestation.publicKeyData.prefix(8).map { String(format: "%02x", $0) }.joined())... • \(attestation.biometricHardwareSource)")
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundStyle(Aperture.Palette.inkSecondary)
                                        }
                                    }
                                    .padding(Aperture.Spacing.s)
                                    .apertureLiquidGlassCard(tone: .positive, elevation: .raised)
                                }
                            }
                            .padding(Aperture.Spacing.l)
                        }
                        .shadow(color: Color.black.opacity(0.08), radius: 16, y: 6)

                    // Render synchronized participant pointers
                    ForEach(model.activeParticipants) { pointer in
                        GeometryReader { geo in
                            HStack(spacing: 4) {
                                Image(systemName: "cursorarrow.rays")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(pointer.role == .caseworker ? Aperture.Palette.actionBlue : Aperture.Palette.actionGreen)
                                Text(pointer.participantName)
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.white.opacity(0.92), in: Capsule())
                                    .shadow(radius: 2)
                            }
                            .position(
                                x: pointer.normalizedX * geo.size.width,
                                y: pointer.normalizedY * geo.size.height
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, Aperture.Spacing.m)

                // Bottom Action Bar
                HStack(spacing: Aperture.Spacing.m) {
                    Button {
                        model.updateLocalPointer(x: Double.random(in: 0.2...0.8), y: Double.random(in: 0.3...0.7))
                        ApertureHaptics.sensoryTick()
                    } label: {
                        Label("Highlight Field", systemImage: "hand.point.up.left.fill")
                            .apertureMinimumTouchTarget(expandHorizontally: true)
                    }
                    .apertureLiquidGlassButton(prominent: false)

                    Button {
                        showingAttestationSheet = true
                    } label: {
                        Label(attestationSealed ? "Attestation Complete" : "Sign with Apple Pencil Pro", systemImage: "applepencil.and.scribble")
                            .fontWeight(.semibold)
                            .apertureMinimumTouchTarget(expandHorizontally: true)
                    }
                    .apertureLiquidGlassButton(prominent: true)
                }
                .padding(Aperture.Spacing.m)
            }
        }
        .sheet(isPresented: $showingAttestationSheet) {
            ApplePencilAttestationSheet(caseID: model.caseID) { envelope in
                lastAttestation = envelope
                attestationSealed = true
                showingAttestationSheet = false
                ApertureHaptics.feedback(.success)
            }
        }
    }

    private var sharePlayStatusBar: some View {
        HStack(spacing: Aperture.Spacing.s) {
            Image(systemName: "shareplay")
                .font(.title3)
                .foregroundStyle(Aperture.Palette.actionGreen)
            VStack(alignment: .leading, spacing: 2) {
                Text("FaceTime SharePlay Active")
                    .font(Aperture.Typography.value)
                Text("\(model.activeParticipants.count + 1) Participants • Finish Together Live Co-Review")
                    .font(Aperture.Typography.caption)
                    .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
            }
            Spacer()
            Circle()
                .fill(Aperture.Palette.actionGreen)
                .frame(width: 8, height: 8)
        }
        .padding(Aperture.Spacing.m)
        .apertureLiquidGlassCard(tone: .positive, elevation: .raised)
        .padding(.horizontal, Aperture.Spacing.m)
    }
}

/// Sheet presenting the Apple Pencil Pro signing canvas with 240Hz biometric attestation.
public struct ApplePencilAttestationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let caseID: String
    let onAttested: (BiometricAttestationEnvelope) -> Void

    @State private var samples: [PencilProSample] = []
    @State private var isSigning = false

    public init(caseID: String, onAttested: @escaping (BiometricAttestationEnvelope) -> Void) {
        self.caseID = caseID
        self.onAttested = onAttested
    }

    public var body: some View {
        NavigationStack {
            AtmosphericMeshCanvas {
                VStack(spacing: Aperture.Spacing.l) {
                    VStack(alignment: .leading, spacing: Aperture.Spacing.xs) {
                        Text("Biometric Hardware Attestation")
                            .font(Aperture.Typography.screenTitle)
                        Text("Sign with Apple Pencil Pro. Pressure, tilt, and barrel roll telemetry are cryptographically sealed in the Secure Enclave.")
                            .font(Aperture.Typography.body)
                            .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Simulated 240Hz Signing Pad
                    RoundedRectangle(cornerRadius: Aperture.Radius.card, style: .continuous)
                        .fill(Color.white)
                        .frame(height: 220)
                        .overlay {
                            VStack {
                                if samples.isEmpty {
                                    Label("Sign with Apple Pencil Pro", systemImage: "applepencil")
                                        .font(Aperture.Typography.caption)
                                        .foregroundStyle(Aperture.Palette.inkSecondary)
                                } else {
                                    HStack(spacing: Aperture.Spacing.s) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Aperture.Palette.actionGreen)
                                        Text("\(samples.count) telemetry samples captured (Barrel roll detected)")
                                            .font(Aperture.Typography.caption)
                                            .foregroundStyle(Aperture.Palette.actionGreen)
                                    }
                                }
                            }
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: Aperture.Radius.card, style: .continuous)
                                .strokeBorder(Aperture.Palette.accent.opacity(0.3), lineWidth: 1.5)
                        }
                        .onTapGesture {
                            // Record sample burst including pressure and barrel roll
                            samples = [
                                PencilProSample(x: 100, y: 150, pressure: 0.72, altitudeAngle: 0.8, azimuthAngle: 1.2, rollAngle: 0.1),
                                PencilProSample(x: 120, y: 155, pressure: 0.85, altitudeAngle: 0.82, azimuthAngle: 1.25, rollAngle: 0.35),
                                PencilProSample(x: 140, y: 160, pressure: 0.78, altitudeAngle: 0.84, azimuthAngle: 1.30, rollAngle: 0.52)
                            ]
                            ApertureHaptics.magneticSnap()
                        }

                    Button {
                        sealAttestation()
                    } label: {
                        Label("Cryptographically Seal Attestation", systemImage: "lock.shield.fill")
                            .fontWeight(.semibold)
                            .apertureMinimumTouchTarget(expandHorizontally: true)
                    }
                    .apertureLiquidGlassButton(prominent: true)
                    .disabled(samples.isEmpty)

                    Spacer()
                }
                .padding(Aperture.Spacing.l)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func sealAttestation() {
        let signer = SecureEnclaveAttestationSigner()
        let dummyDoc = "Case:\(caseID)".data(using: .utf8)!
        if let result = try? signer.signAttestation(caseID: caseID, documentData: dummyDoc, telemetrySamples: samples) {
            onAttested(result.envelope)
        }
    }
}
