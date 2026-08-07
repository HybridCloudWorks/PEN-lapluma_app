import SwiftUI
import UIKit
import UniformTypeIdentifiers
import ApertureUI
import ApertureDomain

/// S-02. Passkey-first. **No password is ever created or stored** (ADR-011).
///
/// This population is heavily targeted by impersonation scams, and a credential that
/// cannot be typed into a lookalike site is the single highest-value control we can
/// give them. SMS is deliberately absent — SIM-swap risk, and collecting a phone number
/// creates a data holding we do not want.
struct RegistrationView: View {
    @Environment(AppSession.self) private var session
    @State private var email = ""
    @State private var displayName = ""
    @State private var acknowledgedNotALawFirm = false
    @State private var recoveryCode: String?

    var body: some View {
        ApertureCanvas {
            ScrollView {
                VStack(alignment: .leading, spacing: Aperture.Spacing.l) {
                    VStack(alignment: .leading, spacing: Aperture.Spacing.s) {
                        Image(systemName: "person.badge.key")
                            .font(.title)
                            .foregroundStyle(Aperture.Palette.accent)
                            .accessibilityHidden(true)
                        Text("A few details, then Face ID.")
                            .font(Aperture.Typography.sectionTitle)
                            .accessibilityAddTraits(.isHeader)
                        Text("No password to create or remember.")
                            .font(Aperture.Typography.caption)
                            .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                    }

                    VStack(spacing: Aperture.Spacing.s) {
                        field(icon: "envelope", title: "Email") {
                            TextField("Email", text: $email)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                        }
                        Divider()
                        field(icon: "person", title: "Name") {
                            TextField("What should we call you?", text: $displayName)
                                .textContentType(.givenName)
                        }
                    }
                    .apertureGlassCard(padding: Aperture.Spacing.m)

                    VStack(alignment: .leading, spacing: Aperture.Spacing.s) {
                        Toggle(isOn: $acknowledgedNotALawFirm) {
                            Text("I understand that LaPluma is not a law firm and cannot give me legal advice.")
                                .font(Aperture.Typography.body)
                        }
                        Text("We save the notice version and time.")
                            .font(Aperture.Typography.caption)
                            .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                    }
                    .apertureGlassCard()

                Button {
                    // Real implementation: ASAuthorizationPlatformPublicKeyCredentialProvider
                    // registration, then App Attest to bind the session to a genuine
                    // app instance. Stubbed here — there is no Simulator passkey flow
                    // worth faking, and pretending otherwise would hide the real work.
                    recoveryCode = "APER-7F3E-9K2M-4N5P"
                } label: {
                    Label("Create passkey", systemImage: "faceid")
                        .fontWeight(.semibold)
                        .apertureMinimumTouchTarget(expandHorizontally: true)
                }
                .apertureGlassButton(prominent: true)
                .buttonBorderShape(.roundedRectangle(radius: Aperture.Radius.control))
                .disabled(!canSubmit)
                .accessibilityHint("Uses Face ID or Touch ID. No password is created.")

                    DisclosureFooter()
                }
                .padding(Aperture.Spacing.l)
            }
        }
        .navigationTitle("Create account")
        .sheet(item: Binding(
            get: { recoveryCode.map(RecoveryCode.init) },
            set: { if $0 == nil { recoveryCode = nil } }
        )) { code in
            RecoveryCodeView(code: code.value) {
                session.signIn(as: UserID("u_stub_maria"))
            }
        }
    }

    private var canSubmit: Bool {
        acknowledgedNotALawFirm && email.contains("@") && !displayName.isEmpty
    }

    private func field<Field: View>(
        icon: String,
        title: String,
        @ViewBuilder field: () -> Field
    ) -> some View {
        HStack(spacing: Aperture.Spacing.m) {
            Image(systemName: icon)
                .foregroundStyle(Aperture.Palette.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            field()
        }
        .frame(minHeight: 56)
        .accessibilityLabel(title)
    }
}

private struct RecoveryCode: Identifiable {
    let value: String
    var id: String { value }
    init(_ value: String) { self.value = value }
}

/// Shown once. Requires an explicit acknowledgement rather than a passive dismiss —
/// losing this code means losing months of work.
struct RecoveryCodeView: View {
    let code: String
    let onAcknowledged: () -> Void

    @State private var acknowledged = false

    var body: some View {
        ApertureCanvas {
        VStack(spacing: Aperture.Spacing.l) {
            Image(systemName: "key.horizontal")
                .font(.largeTitle)
                .foregroundStyle(Aperture.Palette.accent)
                .accessibilityHidden(true)

            Text("Your recovery code")
                .font(Aperture.Typography.screenTitle)

            VStack(spacing: Aperture.Spacing.m) {
                Text(code)
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    // Announced character by character on request, so a VoiceOver user can
                    // transcribe it accurately.
                    .accessibilityLabel(code.map(String.init).joined(separator: ", "))

                Button {
                    UIPasteboard.general.setItems(
                        [[UTType.utf8PlainText.identifier: code]],
                        options: [
                            .localOnly: true,
                            .expirationDate: Date().addingTimeInterval(60)
                        ]
                    )
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .apertureGlassButton()
            }
            .apertureGlassCard()

            Text("Save it somewhere safe. It appears only once.")
                .font(Aperture.Typography.body)
                .multilineTextAlignment(.center)

            Toggle("I have written this down somewhere safe.", isOn: $acknowledged)
                .padding(.horizontal, Aperture.Spacing.l)

            Button {
                onAcknowledged()
            } label: {
                Text(aperture: "common.continue")
                    .apertureMinimumTouchTarget(expandHorizontally: true)
            }
            .apertureGlassButton(prominent: true)
            .disabled(!acknowledged)
            .padding(.horizontal, Aperture.Spacing.l)
        }
        .padding(Aperture.Spacing.l)
        }
        .interactiveDismissDisabled()
    }
}

/// S-01. Return a known user to their work in under five seconds, without a password.
struct SignInView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ApertureCanvas {
        VStack(spacing: Aperture.Spacing.l) {
            Spacer()
            Image(systemName: "faceid")
                .font(.system(size: 52))
                .foregroundStyle(Aperture.Palette.accent)
                .accessibilityHidden(true)
            Text("Welcome back")
                .font(Aperture.Typography.screenTitle)

            VStack(spacing: Aperture.Spacing.s) {
                Button {
                    session.signIn(as: UserID("u_stub_maria"))
                    dismiss()
                } label: {
                    Label("Sign in with Face ID", systemImage: "faceid")
                        .fontWeight(.semibold)
                        .apertureMinimumTouchTarget(expandHorizontally: true)
                }
                .apertureGlassButton(prominent: true)
                .buttonBorderShape(.roundedRectangle(radius: Aperture.Radius.control))
                .accessibilityHint("Uses the face or fingerprint already set up on this iPhone.")

                Button("Email me a sign-in code") {
                    session.signIn(as: UserID("u_stub_maria"))
                    dismiss()
                }
                .apertureMinimumTouchTarget(expandHorizontally: true)
            }
            .apertureGlassCard()

            Spacer()
            DisclosureFooter()
        }
        .padding(Aperture.Spacing.l)
        }
    }
}
