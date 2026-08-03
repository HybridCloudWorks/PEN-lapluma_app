import SwiftUI
import ApertureUI
import ApertureAPI
import ApertureDomain
import UIKit

/// S-14/S-15. Preview the actual filled government form, then get it out safely.
struct PackageView: View {
    let caseID: CaseID
    @Environment(AppSession.self) private var session
    @State private var generated: GeneratedPackage?
    @State private var readiness: PackageGenerationReadiness?
    @State private var loaded = false
    @State private var shareURL: URL?
    @State private var showsSecureLink = false

    var body: some View {
        List {
            if let generated {
                Section("Verification") {
                    // A package cannot exist unverified: round-trip verification
                    // re-parses the output and asserts equality with the source record.
                    // A mismatch fails generation — it does not warn (ADR-003).
                    LabeledContent("Fields checked", value: "\(generated.verification.fieldsVerified)")
                    LabeledContent("Mismatches", value: "\(generated.verification.mismatches)")
                }

                Section("Documents") {
                    ForEach(generated.outputs.sorted { $0.sortOrder < $1.sortOrder }) { output in
                        OutputRow(output: output)
                    }
                }

                Section("Filing checklist") {
                    if let fee = generated.filingChecklist.feeUSDCents {
                        LabeledContent("Fee", value: Decimal(fee) / 100, format: .currency(code: "USD"))
                    }
                    if let address = generated.filingChecklist.filingAddress {
                        LabeledContent("Where to file", value: address)
                    }
                    ForEach(generated.filingChecklist.wetInkSignaturePoints) { point in
                        Label("Sign by hand: \(point.formNumber) \(point.partLabel)",
                              systemImage: "signature")
                            .font(Aperture.Typography.caption)
                    }
                }

                Section("Export") {
                    ForEach(ExportChannel.allCases, id: \.self) { channel in
                        Button(ApertureString(String.LocalizationValue(channel.localizationKey))) {
                            switch channel {
                            case .files, .print:
                                shareURL = makeExportManifest(for: generated)
                            case .secureLink:
                                showsSecureLink = true
                            }
                        }
                    }
                    Text(aperture: "export.linkNotAttachment")
                        .font(Aperture.Typography.caption)
                        .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                }

                Section {
                    Text(aperture: "disclosure.notFiled")
                        .font(Aperture.Typography.body.weight(.semibold))
                    DisclosureFooter(emphasis: .prominent)
                }
            } else if loaded, let readiness {
                Section {
                    Label(ApertureString("generation.reviewRequired"), systemImage: "person.crop.circle.badge.exclamationmark")
                        .font(Aperture.Typography.sectionTitle)
                        .foregroundStyle(Aperture.Palette.warning)
                        .accessibilityIdentifier("package-generation-blocked")
                    Text(aperture: "generation.reviewRequired.detail")
                        .font(Aperture.Typography.body)
                }

                Section(ApertureString("generation.blockers")) {
                    blockerRow(
                        ApertureString("generation.unconfirmed"),
                        value: readiness.unconfirmedRequiredFields,
                        systemImage: "questionmark.circle.fill",
                        tone: .attention
                    )
                    blockerRow(
                        ApertureString("generation.proposals"),
                        value: readiness.openProposals,
                        systemImage: "bubble.left.and.exclamationmark.bubble.right.fill",
                        tone: .information
                    )
                    blockerRow(
                        ApertureString("generation.discrepancies"),
                        value: readiness.blockingDiscrepancies,
                        systemImage: "exclamationmark.octagon.fill",
                        tone: .critical
                    )
                }

                Section {
                    NavigationLink(ApertureString("generation.reviewAction")) {
                        ReviewView(caseID: caseID)
                    }
                }
            } else if loaded {
                ApertureMessageView(.attention(messageKey: "progress.itemsNeedAttention"))
            } else {
                ApertureLoadingView()
            }
        }
        .apertureReadableContentWidth()
        .navigationTitle("Forms")
        .task {
            async let packageRequest = session.api.generatedPackage(caseID: caseID)
            async let readinessRequest = session.api.packageGenerationReadiness(caseID: caseID)
            generated = try? await packageRequest
            readiness = try? await readinessRequest
            loaded = true
        }
        .sheet(isPresented: Binding(
            get: { shareURL != nil },
            set: { if !$0 { shareURL = nil } }
        )) {
            if let shareURL { ShareSheet(items: [shareURL]) }
        }
        .sheet(isPresented: $showsSecureLink) {
            if let generated { SecureLinkView(packageID: generated.id) }
        }
    }

    private func blockerRow(
        _ title: String,
        value: Int,
        systemImage: String,
        tone: Aperture.StatusTone
    ) -> some View {
        HStack(spacing: Aperture.Spacing.s) {
            Image(systemName: systemImage)
                .foregroundStyle(tone.foreground)
                .accessibilityHidden(true)
            Text(title)
            Spacer()
            Text("\(value)")
                .fontWeight(.semibold)
                .foregroundStyle(tone.foreground)
        }
        .accessibilityElement(children: .combine)
    }

    private func makeExportManifest(for package: GeneratedPackage) -> URL? {
        let lines = [
            "LaPluma application package",
            "Generated: \(package.generatedAt.formatted())",
            "Verification: \(package.verification.fieldsVerified) fields checked; \(package.verification.mismatches) mismatches",
            "",
            "Included outputs:"
        ] + package.outputs.sorted(by: { $0.sortOrder < $1.sortOrder }).map {
            "- \($0.formNumber ?? $0.kind.rawValue): \($0.pageCount) pages"
        } + [
            "",
            "LaPluma is not a law firm. This package has not been filed with any agency."
        ]
        let url = FileManager.default.temporaryDirectory
            .appending(path: "LaPluma-Package-Manifest.txt")
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct SecureLinkView: View {
    let packageID: PackageID
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var link: DeliveryLink?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if let link {
                    Section("Secure link created") {
                        Label("Ready to share securely", systemImage: "checkmark.circle.fill")
                            .apertureStatusSurface(.positive)
                        LabeledContent("Expires", value: link.expiresAt.formatted())
                        LabeledContent("Download limit", value: "\(link.maxDownloads)")
                        Text("Only the recipient receives the link. Documents are never email attachments.")
                    }
                } else {
                    Section("Recipient") {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                    }
                    Section {
                        Button("Create secure link") { Task { await createLink() } }
                            .disabled(!email.contains("@"))
                    }
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.octagon.fill")
                        .apertureStatusSurface(.critical)
                }
                Section { DisclosureFooter() }
            }
            .navigationTitle("Secure delivery")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(link == nil ? "Cancel" : "Done") { dismiss() }
                }
            }
        }
    }

    @MainActor private func createLink() async {
        do {
            link = try await session.api.export(
                packageID: packageID,
                channel: .secureLink,
                recipientEmail: email,
                idempotencyKey: IdempotencyKey.make()
            )
        } catch {
            errorMessage = "The secure link could not be created. Try again."
        }
    }
}

struct OutputRow: View {
    let output: PDFOutput

    var body: some View {
        VStack(alignment: .leading, spacing: Aperture.Spacing.xs) {
            Text(output.formNumber ?? output.kind.rawValue)
                .font(Aperture.Typography.value)
            Text("\(output.pageCount) pages")
                .font(Aperture.Typography.caption)
                .foregroundStyle(Aperture.Palette.onSurfaceSecondary)

            // XFA and flat forms cannot be filled. Say so prominently rather than
            // shipping something that looks like a filled form and is not.
            if output.fillMode == .assistedOnly {
                Label(ApertureString("catalog.assistedFillOnly"), systemImage: "exclamationmark.triangle")
                    .font(Aperture.Typography.caption)
                    .foregroundStyle(Aperture.Palette.warning)
            }

            // Overflow generates a conforming addendum. Truncating a name or an address
            // is a defect that reaches an adjudicator.
            if let reason = output.reason {
                Text(reason)
                    .font(Aperture.Typography.caption)
                    .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
