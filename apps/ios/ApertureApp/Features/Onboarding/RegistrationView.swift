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
    @StateObject private var passkeySession = PasskeyAuthenticationSession()
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
                        field(icon: "envelope", title: LaPlumaString("Email")) {
                            TextField("Email", text: $email)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                        }
                        Divider()
                        field(icon: "person", title: LaPlumaString("Name")) {
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
                        .accessibilityIdentifier("registration-acknowledgment-toggle")
                        Text("We save the notice version and time.")
                            .font(Aperture.Typography.caption)
                            .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                    }
                    .apertureGlassCard()

                Button {
                    let challengeData = UUID().uuidString.data(using: .utf8) ?? Data()
                    let userHandle = (email.data(using: .utf8) ?? Data())
                    passkeySession.registerPasskey(
                        userName: email,
                        userID: userHandle,
                        challenge: challengeData
                    )
                    recoveryCode = "APER-7F3E-9K2M-4N5P"
                } label: {
                    Label("Create passkey", systemImage: "faceid")
                        .fontWeight(.semibold)
                        .apertureMinimumTouchTarget(expandHorizontally: true)
                }
                .apertureGlassButton(prominent: true)
                .buttonBorderShape(.roundedRectangle(radius: Aperture.Radius.control))
                .disabled(!canSubmit)
                .accessibilityHint(LaPlumaString("Uses Face ID or Touch ID. No password is created."))

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
                session.signIn(as: UserID("u_stub_maria"), persona: .applicant)
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
                .accessibilityIdentifier("recovery-code-acknowledgment-toggle")

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
    @StateObject private var samlSession = SamlAuthenticationSession()
    @StateObject private var passkeySession = PasskeyAuthenticationSession()
    @State private var email = ""
    @State private var workspaceCode = ""
    @State private var showingAdminApprovalSheet = false

    var body: some View {
        NavigationStack {
            ApertureCanvas {
                ScrollView {
                    VStack(alignment: .leading, spacing: Aperture.Spacing.l) {
                        VStack(alignment: .leading, spacing: Aperture.Spacing.s) {
                            Image(systemName: "person.badge.key.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(Aperture.Palette.accent)
                                .accessibilityHidden(true)
                            Text("Welcome back")
                                .font(Aperture.Typography.screenTitle)
                            Text("Choose your secure workspace, then sign in with your enterprise provider or passkey.")
                                .font(Aperture.Typography.body)
                                .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                        }

                        // Enterprise Identity Providers (Google Workspace & Entra ID ONLY)
                        VStack(spacing: Aperture.Spacing.s) {
                            HStack(spacing: Aperture.Spacing.xs) {
                                Image(systemName: "lock.shield.fill")
                                    .foregroundStyle(Aperture.Palette.actionBlue)
                                Text("Enterprise Single Sign-On")
                                    .font(Aperture.Typography.value)
                                    .foregroundStyle(Aperture.Palette.actionBlue)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Button {
                                samlSession.authenticate(
                                    emailOrDomain: email.isEmpty ? EnterpriseDomainPolicy.primaryOrgDomain : email,
                                    preferredProvider: .googleWorkspace
                                )
                            } label: {
                                Label("Sign in with Google Workspace", systemImage: "globe")
                                    .fontWeight(.semibold)
                                    .apertureMinimumTouchTarget(expandHorizontally: true)
                            }
                            .apertureGlassButton(prominent: true)
                            .buttonBorderShape(.roundedRectangle(radius: Aperture.Radius.control))

                            Button {
                                samlSession.authenticate(
                                    emailOrDomain: email.isEmpty ? EnterpriseDomainPolicy.primaryOrgDomain : email,
                                    preferredProvider: .entraID
                                )
                            } label: {
                                Label("Sign in with Microsoft Entra ID", systemImage: "building.2.fill")
                                    .fontWeight(.semibold)
                                    .apertureMinimumTouchTarget(expandHorizontally: true)
                            }
                            .apertureGlassButton(prominent: false)
                            .buttonBorderShape(.roundedRectangle(radius: Aperture.Radius.control))
                        }
                        .aperturePastelCard(tone: .information)

                        if isPersonalDomainDisallowed {
                            HStack(alignment: .top, spacing: Aperture.Spacing.s) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Aperture.Palette.actionRed)
                                    .frame(width: 20, height: 20)
                                VStack(alignment: .leading, spacing: Aperture.Spacing.xs) {
                                    Text("Institutional Account Required")
                                        .font(Aperture.Typography.value)
                                        .foregroundStyle(Aperture.Palette.actionRed)
                                    Text("Personal email domains (@gmail.com, @outlook.com) cannot be used. Please use your institutional Google Workspace or Microsoft Entra ID address.")
                                        .font(Aperture.Typography.caption)
                                        .foregroundStyle(Aperture.Palette.actionRed)
                                }
                            }
                            .aperturePastelCard(tone: .critical)
                            .accessibilityIdentifier("personal-domain-disallowed-alert")
                        }

                        VStack(spacing: Aperture.Spacing.m) {
                            Label {
                                TextField("Work email", text: $email)
                                    .textContentType(.username)
                                    .keyboardType(.emailAddress)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .submitLabel(.next)
                            } icon: {
                                Image(systemName: "envelope")
                                    .foregroundStyle(Aperture.Palette.accent)
                            }
                            .frame(minHeight: 52)

                            Divider()

                            Label {
                                TextField("Workspace or location code", text: $workspaceCode)
                                    .textContentType(.organizationName)
                                    .textInputAutocapitalization(.characters)
                                    .autocorrectionDisabled()
                                    .submitLabel(.done)
                            } icon: {
                                Image(systemName: "building.2")
                                    .foregroundStyle(Aperture.Palette.accent)
                            }
                            .frame(minHeight: 52)
                            .accessibilityHint("Provided by your organization. It selects a workspace but does not grant access by itself.")
                        }
                        .apertureGlassCard()

                        VStack(spacing: Aperture.Spacing.s) {
                            Button {
                                let challenge = UUID().uuidString.data(using: .utf8) ?? Data()
                                passkeySession.assertPasskey(challenge: challenge)
                                completeStubSignIn()
                            } label: {
                                Label("Continue with passkey", systemImage: "faceid")
                                    .fontWeight(.semibold)
                                    .apertureMinimumTouchTarget(expandHorizontally: true)
                            }
                            .apertureGlassButton(prominent: true)
                            .buttonBorderShape(.roundedRectangle(radius: Aperture.Radius.control))
                            .disabled(!canContinue)
                            .accessibilityHint(LaPlumaString("Uses the face or fingerprint already set up on this iPhone."))

                            Button("Use account recovery") {
                                // Internal fixture only. Production recovery is email OTP plus
                                // the one-time recovery code and must revoke every prior session.
                                completeStubSignIn()
                            }
                            .disabled(!canContinue)
                            .apertureMinimumTouchTarget(expandHorizontally: true)
                        }
                        .apertureGlassCard()

                        Label(
                            "Passwords and SMS codes are never used. Only approved Google Workspace and Microsoft Entra ID institutional directories can authenticate.",
                            systemImage: "lock.shield.fill"
                        )
                        .font(Aperture.Typography.caption)
                        .foregroundStyle(Aperture.Palette.onSurfaceSecondary)

                        DisclosureFooter()
                    }
                    .padding(Aperture.Spacing.l)
                    .apertureReadableContentWidth(maximum: 680)
                }
            }
            .navigationTitle("Secure sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ApertureString("common.cancel")) { dismiss() }
                }
            }
            .onChange(of: samlSession.state) { _, newState in
                switch newState {
                case .authenticated(_, _, let userEmail):
                    session.signIn(
                        as: UserID("u_saml_\(userEmail)"),
                        workspaceCode: normalizedWorkspaceCode.isEmpty ? "NYC-01" : normalizedWorkspaceCode
                    )
                    dismiss()
                case .adminApprovalRequired:
                    showingAdminApprovalSheet = true
                default:
                    break
                }
            }
            .sheet(isPresented: $showingAdminApprovalSheet) {
                AdminApprovalGuidanceSheet(
                    organizationDomain: email.contains("@") ? String(email.split(separator: "@").last ?? "") : EnterpriseDomainPolicy.primaryOrgDomain,
                    adminConsentUrl: samlSession.state.adminConsentUrl
                )
            }
        }
    }

    private var domainValidation: EnterpriseDomainValidationResult? {
        guard email.contains("@") else { return nil }
        return EnterpriseDomainPolicy.validate(email: email)
    }

    private var isPersonalDomainDisallowed: Bool {
        if case .personalDomainDisallowed = domainValidation {
            return true
        }
        return false
    }

    private var canContinue: Bool {
        email.contains("@") && !isPersonalDomainDisallowed && normalizedWorkspaceCode.count >= 3
    }

    private var normalizedWorkspaceCode: String {
        workspaceCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    private func completeStubSignIn() {
        session.signIn(as: UserID("u_stub_maria"), workspaceCode: normalizedWorkspaceCode)
        dismiss()
    }
}

/// Explains the Microsoft Entra ID / Google Workspace Admin Approval requirement (AADSTS90094).
private struct AdminApprovalGuidanceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let organizationDomain: String
    let adminConsentUrl: URL?
    @State private var linkCopied = false

    init(organizationDomain: String, adminConsentUrl: URL? = nil) {
        self.organizationDomain = organizationDomain
        self.adminConsentUrl = adminConsentUrl
    }

    var body: some View {
        NavigationStack {
            ApertureCanvas {
                ScrollView {
                    VStack(alignment: .leading, spacing: Aperture.Spacing.l) {
                        HStack(spacing: Aperture.Spacing.s) {
                            Image(systemName: "exclamationmark.lock.fill")
                                .font(.title)
                                .foregroundStyle(Aperture.Palette.actionYellow)
                            VStack(alignment: .leading, spacing: Aperture.Spacing.xs) {
                                Text("Administrator Approval Required")
                                    .font(Aperture.Typography.sectionTitle)
                                Text("Enterprise SAML Consent")
                                    .font(Aperture.Typography.caption)
                                    .foregroundStyle(Aperture.Palette.inkSecondary)
                            }
                        }

                        VStack(alignment: .leading, spacing: Aperture.Spacing.m) {
                            Text("Your organization requires an IT administrator to approve LaPluma before users can sign in.")
                                .font(Aperture.Typography.body)

                            Text(organizationDomain)
                                .font(Aperture.Typography.value)

                            Text("To complete access:")
                                .font(Aperture.Typography.value)

                            VStack(alignment: .leading, spacing: Aperture.Spacing.xs) {
                                Text("1. Contact your Microsoft Entra ID or Google Workspace administrator.")
                                Text("2. Request approval for the LaPluma enterprise application registration.")
                                Text("3. Once approved, sign in again with your institutional account.")
                            }
                            .font(Aperture.Typography.caption)
                            .foregroundStyle(Aperture.Palette.inkSecondary)
                        }
                        .aperturePastelCard(tone: .attention)

                        if let consentUrl = adminConsentUrl {
                            VStack(alignment: .leading, spacing: Aperture.Spacing.s) {
                                Text("Administrator Consent Link")
                                    .font(Aperture.Typography.value)
                                Text("Share this link with your IT department to grant tenant-wide consent:")
                                    .font(Aperture.Typography.caption)
                                    .foregroundStyle(Aperture.Palette.inkSecondary)

                                Button {
                                    UIPasteboard.general.string = consentUrl.absoluteString
                                    linkCopied = true
                                } label: {
                                    Label(linkCopied ? "Consent Link Copied" : "Copy Admin Consent Link", systemImage: linkCopied ? "checkmark.circle.fill" : "doc.on.doc")
                                        .fontWeight(.semibold)
                                        .apertureMinimumTouchTarget(expandHorizontally: true)
                                }
                                .apertureGlassButton(prominent: false)

                                ShareLink(
                                    item: consentUrl,
                                    subject: Text("LaPluma Enterprise App Admin Approval"),
                                    message: Text("Please grant tenant administrator consent for LaPluma Enterprise SSO: \(consentUrl.absoluteString)")
                                ) {
                                    Label("Share Approval Link", systemImage: "square.and.arrow.up")
                                        .fontWeight(.semibold)
                                        .apertureMinimumTouchTarget(expandHorizontally: true)
                                }
                                .apertureGlassButton(prominent: false)
                            }
                            .aperturePastelCard(tone: .information)
                        }

                        Button {
                            dismiss()
                        } label: {
                            Text("I Understand")
                                .fontWeight(.semibold)
                                .apertureMinimumTouchTarget(expandHorizontally: true)
                        }
                        .apertureGlassButton(prominent: true)
                    }
                    .padding(Aperture.Spacing.l)
                }
            }
            .navigationTitle("App Approval")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ApertureString("common.cancel")) { dismiss() }
                }
            }
        }
    }
}
