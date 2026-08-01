import SwiftUI
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
        Form {
            Section {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                TextField("What should we call you?", text: $displayName)
                    .textContentType(.givenName)
            }

            Section {
                Toggle(isOn: $acknowledgedNotALawFirm) {
                    Text("I understand that Aperture is not a law firm and cannot give me legal advice.")
                        .font(Aperture.Typography.body)
                }
            } footer: {
                Text("We record which version of this notice you saw and when.")
            }

            Section {
                Button {
                    // Real implementation: ASAuthorizationPlatformPublicKeyCredentialProvider
                    // registration, then App Attest to bind the session to a genuine
                    // app instance. Stubbed here — there is no Simulator passkey flow
                    // worth faking, and pretending otherwise would hide the real work.
                    recoveryCode = "APER-7F3E-9K2M-4N5P"
                } label: {
                    Label("Create passkey", systemImage: "faceid")
                        .frame(maxWidth: .infinity, minHeight: Aperture.Spacing.minimumTarget)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)
            } footer: {
                Text("A passkey uses the face or fingerprint already set up on this iPhone. There is no password to forget or to be tricked into typing somewhere else.")
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
        VStack(spacing: Aperture.Spacing.l) {
            Text("Your recovery code")
                .font(Aperture.Typography.screenTitle)

            Text(code)
                .font(.system(.title2, design: .monospaced))
                .padding(Aperture.Spacing.m)
                .background(Aperture.Palette.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Aperture.Radius.card))
                // Announced character by character on request, so a VoiceOver user can
                // transcribe it accurately.
                .accessibilityLabel(code.map(String.init).joined(separator: ", "))

            Text("Write this down. We cannot show it to you again.")
                .font(Aperture.Typography.body)
                .multilineTextAlignment(.center)

            Button {
                UIPasteboard.general.string = code
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            Toggle("I have written this down somewhere safe.", isOn: $acknowledged)
                .padding(.horizontal, Aperture.Spacing.l)

            Button {
                onAcknowledged()
            } label: {
                Text(aperture: "common.continue")
                    .frame(maxWidth: .infinity, minHeight: Aperture.Spacing.minimumTarget)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!acknowledged)
            .padding(.horizontal, Aperture.Spacing.l)
        }
        .padding(Aperture.Spacing.l)
        .interactiveDismissDisabled()
    }
}

/// S-01. Return a known user to their work in under five seconds, without a password.
struct SignInView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Aperture.Spacing.l) {
            Spacer()
            Text("Welcome back").font(Aperture.Typography.screenTitle)

            Button {
                session.signIn(as: UserID("u_stub_maria"))
                dismiss()
            } label: {
                Label("Sign in with Face ID", systemImage: "faceid")
                    .frame(maxWidth: .infinity, minHeight: Aperture.Spacing.minimumTarget)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Uses the face or fingerprint already set up on this iPhone.")

            Button("Use a code sent to my email") {
                session.signIn(as: UserID("u_stub_maria"))
                dismiss()
            }

            Spacer()
            DisclosureFooter()
        }
        .padding(Aperture.Spacing.l)
    }
}
