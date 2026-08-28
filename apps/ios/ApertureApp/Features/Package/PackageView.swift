import SwiftUI
import ApertureUI
import ApertureAPI
import ApertureDomain
import PDFKit
import UIKit

/// S-14/S-15. Preview the actual filled government form, then get it out safely.
struct PackageView: View {
    let caseID: CaseID
    @Environment(AppSession.self) private var session
    @State private var model = PackageModel()
    @State private var fileExportURL: URL?
    @State private var printArtifact: PackageArtifact?
    @State private var exportError: String?
    @State private var exportingChannel: ExportChannel?
    @State private var exportIdempotencyKeys: [ExportChannel: String] = [:]
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
            get: { fileExportURL != nil },
            set: {
                if !$0 {
                    ExportScratch.discard(fileExportURL)
                    fileExportURL = nil
                }
            }
        )) {
            if let fileExportURL { DocumentExportPicker(url: fileExportURL) }
        }
        .sheet(isPresented: Binding(
            get: { securePackageID != nil },
            set: { if !$0 { securePackageID = nil } }
        )) {
            if let securePackageID { SecureLinkView(packageID: securePackageID) }
        }
        .sheet(item: $printArtifact) { artifact in
            PackagePrintSheet(artifact: artifact)
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
                            Task { await export(generated, through: channel) }
                        case .secureLink:
                            if !session.isDemoWorkspace { securePackageID = generated.id }
                        }
                    }
                    .disabled(exportingChannel != nil || (session.isDemoWorkspace && channel == .secureLink))
                    .accessibilityIdentifier("package-export-\(channel.rawValue.lowercased())")
                }
                if let exportingChannel {
                    ProgressView(
                        LaPlumaFormat(
                            "package.exportPreparing",
                            ApertureString(String.LocalizationValue(exportingChannel.localizationKey))
                        )
                    )
                }
                if session.isDemoWorkspace {
                    Text("Secure delivery is disabled in the synthetic demo workspace.")
                        .font(Aperture.Typography.caption)
                }
                if let exportError {
                    Label(exportError, systemImage: "exclamationmark.octagon.fill")
                        .apertureStatusSurface(.critical)
                        .accessibilityIdentifier("package-export-error")
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
        } else if content.readiness.canGenerate {
            Section {
                Label(ApertureString("generation.ready"), systemImage: "doc.badge.plus")
                    .font(Aperture.Typography.sectionTitle)
                    .accessibilityIdentifier("package-generation-ready")
                Text(aperture: "generation.ready.detail")
                Button {
                    Task {
                        if await model.generate(api: session.api, caseID: caseID) {
                            session.dataDidChange()
                        }
                    }
                } label: {
                    if model.isGenerating {
                        ProgressView(ApertureString("generation.generating"))
                    } else {
                        Label(ApertureString("generation.generateAction"), systemImage: "doc.badge.plus")
                    }
                }
                .disabled(model.isGenerating)
                .accessibilityIdentifier("package-generate")

                if model.generationFailed {
                    Label(ApertureString("generation.failed"), systemImage: "exclamationmark.octagon.fill")
                        .apertureStatusSurface(.critical)
                        .accessibilityIdentifier("package-generation-failed")
                }
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
                // Without this row a case blocked only by missing documents showed
                // three zeros under "Still blocking forms" and no reason at all.
                blockerRow(
                    ApertureString("generation.evidence"),
                    value: content.readiness.outstandingBlockingEvidence,
                    systemImage: "doc.badge.plus",
                    tone: .attention
                )
                blockerRow(
                    ApertureString("generation.formDrift"),
                    value: content.readiness.formsWithEditionDrift,
                    systemImage: "arrow.triangle.2.circlepath",
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

    @MainActor
    private func export(_ package: GeneratedPackage, through channel: ExportChannel) async {
        guard exportingChannel == nil, channel != .secureLink else { return }
        exportingChannel = channel
        exportError = nil
        let key = exportIdempotencyKeys[channel] ?? IdempotencyKey.make()
        exportIdempotencyKeys[channel] = key
        defer { exportingChannel = nil }

        do {
            let result = try await session.api.export(
                packageID: package.id,
                channel: channel,
                recipientEmail: nil,
                idempotencyKey: key
            )
            guard case .artifact(let artifact) = result,
                  artifact.mimeType == "application/pdf",
                  artifact.data.starts(with: [0x25, 0x50, 0x44, 0x46]),
                  CapturePayloadProcessor.sha256(of: artifact.data) == artifact.contentSHA256,
                  let document = PDFDocument(data: artifact.data),
                  document.pageCount == artifact.pageCount else {
                throw ProblemDetails(
                    type: "https://api.aperture.app/problems/invalid-package-artifact",
                    title: "The package artifact failed integrity validation",
                    status: 502
                )
            }

            switch channel {
            case .files:
                let url = try ExportScratch.makeURL(named: artifact.fileName)
                try artifact.data.write(to: url, options: [.atomic, .completeFileProtection])
                fileExportURL = url
            case .print:
                printArtifact = artifact
            case .secureLink:
                break
            }
            exportIdempotencyKeys[channel] = IdempotencyKey.make()
        } catch is CancellationError {
            return
        } catch {
            exportError = LaPlumaString("package.exportFailed")
        }
    }
}

private struct DocumentExportPicker: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        UIDocumentPickerViewController(forExporting: [url], asCopy: true)
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {}
}

private struct PackagePrintSheet: View {
    let artifact: PackageArtifact
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PrintPresenter(artifact: artifact) { dismiss() }
    }
}

private struct PrintPresenter: UIViewControllerRepresentable {
    let artifact: PackageArtifact
    let onFinished: () -> Void

    final class Controller: UIViewController {
        var artifact: PackageArtifact?
        var onFinished: (() -> Void)?
        var didPresent = false

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !didPresent, let artifact else { return }
            didPresent = true

            let printController = UIPrintInteractionController.shared
            let info = UIPrintInfo(dictionary: nil)
            info.jobName = artifact.fileName
            info.outputType = .general
            printController.printInfo = info
            printController.printingItem = artifact.data
            let completion: UIPrintInteractionController.CompletionHandler = { [weak self] _, _, _ in
                self?.onFinished?()
            }
            if traitCollection.userInterfaceIdiom == .pad {
                printController.present(
                    from: view.bounds,
                    in: view,
                    animated: true,
                    completionHandler: completion
                )
            } else {
                printController.present(animated: true, completionHandler: completion)
            }
        }
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = Controller()
        controller.artifact = artifact
        controller.onFinished = onFinished
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        if let controller = controller as? Controller {
            controller.artifact = artifact
            controller.onFinished = onFinished
        }
    }
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
            let result = try await session.api.export(
                packageID: packageID,
                channel: .secureLink,
                recipientEmail: email,
                idempotencyKey: IdempotencyKey.make()
            )
            guard case .deliveryLink(let createdLink) = result else {
                throw ProblemDetails(
                    type: "https://api.aperture.app/problems/invalid-export-result",
                    title: "Secure delivery did not return a link",
                    status: 502
                )
            }
            link = createdLink
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
