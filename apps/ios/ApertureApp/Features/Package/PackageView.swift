import SwiftUI
import ApertureUI
import ApertureAPI
import ApertureDomain
import UIKit

@Observable
@MainActor
final class PackageModel {
    /// Readiness always exists; a generated package exists only once every gate is
    /// clear. Keeping them in one loaded value means the screen can never present
    /// the compliance verdict from a request that did not arrive.
    struct Content {
        let generated: GeneratedPackage?
        let readiness: PackageGenerationReadiness
    }

    var state: ApertureLoadState<Content> = .idle

    func load(api: any ApertureAPIClient, caseID: CaseID) async {
        state = .loading
        do {
            async let packageRequest = api.generatedPackage(caseID: caseID)
            async let readinessRequest = api.packageGenerationReadiness(caseID: caseID)
            let (generated, readiness) = try await (packageRequest, readinessRequest)
            state = .loaded(Content(generated: generated, readiness: readiness))
        } catch is CancellationError {
            return
        } catch {
            state = .failed
        }
    }
}

/// S-14/S-15. Preview the actual filled government form, then get it out safely.
struct PackageView: View {
    let caseID: CaseID
    @Environment(AppSession.self) private var session
    @State private var model = PackageModel()
    @State private var shareURL: URL?
    /// Captured when the applicant taps the action, not re-derived from the load
    /// state. A background capture drain bumps `dataRevision` (`ApertureApp.swift`),
    /// which re-fires the `.task` below and returns `state` to `.loading`; reading the
    /// package out of `state` here would blank an open sheet and discard whatever the
    /// applicant had already typed into it.
    @State private var securePackageID: PackageID?

    var body: some View {
        List {
            switch model.state {
            case .idle, .loading:
                ApertureLoadingView()
            case .failed:
                // A request that failed is not a compliance verdict. Saying "not
                // ready" here would blame the applicant's case for a transport error.
                ApertureMessageView(
                    .failed(messageKey: "error.packageLoadFailed"),
                    action: (ApertureString("common.retry"), {
                        Task { await model.load(api: session.api, caseID: caseID) }
                    })
                )
                .accessibilityIdentifier("package-load-failed")
            case .empty:
                ApertureMessageView(.attention(messageKey: "generation.notReady"))
            case .loaded(let content):
                loadedSections(content)
            }
        }
        .apertureReadableContentWidth()
        .navigationTitle("Forms")
        .task(id: session.dataRevision) { await model.load(api: session.api, caseID: caseID) }
        .sheet(isPresented: Binding(
            get: { shareURL != nil },
            set: {
                if !$0 {
                    ExportScratch.discard(shareURL)
                    shareURL = nil
                }
            }
        )) {
            if let shareURL { ShareSheet(items: [shareURL]) }
        }
        .sheet(isPresented: Binding(
            get: { securePackageID != nil },
            set: { if !$0 { securePackageID = nil } }
        )) {
            if let securePackageID { SecureLinkView(packageID: securePackageID) }
        }
    }

    @ViewBuilder
    private func loadedSections(_ content: PackageModel.Content) -> some View {
        if let generated = content.generated {
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

            Section(LaPlumaString("Filing checklist")) {
                if let fee = generated.filingChecklist.feeUSDCents {
                    LabeledContent(LaPlumaString("Fee"), value: Decimal(fee) / 100, format: .currency(code: "USD"))
                }
                if let address = generated.filingChecklist.filingAddress {
                    LabeledContent(LaPlumaString("Where to file"), value: address)
                }
                ForEach(generated.filingChecklist.wetInkSignaturePoints) { point in
                    Label(LaPlumaFormat("package.signByHand", point.formNumber, point.partLabel),
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
                            securePackageID = generated.id
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
        } else {
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
                    value: content.readiness.unconfirmedRequiredFields,
                    systemImage: "questionmark.circle.fill",
                    tone: .attention
                )
                blockerRow(
                    ApertureString("generation.proposals"),
                    value: content.readiness.openProposals,
                    systemImage: "bubble.left.and.exclamationmark.bubble.right.fill",
                    tone: .information
                )
                blockerRow(
                    ApertureString("generation.discrepancies"),
                    value: content.readiness.blockingDiscrepancies,
                    systemImage: "exclamationmark.octagon.fill",
                    tone: .critical
                )
            }

            Section {
                NavigationLink(ApertureString("generation.reviewAction")) {
                    ReviewView(caseID: caseID)
                }
            }
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
        let locale = laPlumaPreferredLocale()
        let generatedDate = package.generatedAt.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)
        )
        let lines = [
            LaPlumaString("package.manifestTitle"),
            LaPlumaFormat("package.manifestGenerated", generatedDate),
            LaPlumaFormat(
                "package.manifestVerification",
                package.verification.fieldsVerified,
                package.verification.mismatches
            ),
            "",
            LaPlumaString("package.manifestIncludedOutputs")
        ] + package.outputs.sorted(by: { $0.sortOrder < $1.sortOrder }).map {
            LaPlumaFormat(
                "package.manifestOutput",
                $0.formNumber ?? $0.kind.localizedTitle,
                $0.pageCount
            )
        } + [
            "",
            LaPlumaString("package.manifestNotFiled")
        ]
        do {
            let url = try ExportScratch.makeURL(named: "LaPluma-Package-Manifest.txt")
            guard let data = lines.joined(separator: "\n").data(using: .utf8) else { return nil }
            // This lists the forms, the fee and the filing address — the same class of
            // record as every other write in the app, and protected the same way.
            try data.write(to: url, options: [.atomic, .completeFileProtection])
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
                        LabeledContent(
                            "Expires",
                            value: link.expiresAt.formatted(
                                Date.FormatStyle(date: .abbreviated, time: .shortened)
                                    .locale(session.preferredLocale)
                            )
                        )
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
                    Button(
                        link == nil ? LaPlumaString("Cancel") : LaPlumaString("Done")
                    ) { dismiss() }
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
            errorMessage = LaPlumaString("The secure link could not be created. Try again.")
        }
    }
}

struct OutputRow: View {
    let output: PDFOutput

    var body: some View {
        VStack(alignment: .leading, spacing: Aperture.Spacing.xs) {
            Text(output.formNumber ?? output.kind.localizedTitle)
                .font(Aperture.Typography.value)
            Text(LaPlumaFormat("package.pageCount", output.pageCount))
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

private extension PDFOutput.Kind {
    var localizedTitle: String {
        LaPlumaString(String.LocalizationValue("package.outputKind.\(rawValue)"))
    }
}
