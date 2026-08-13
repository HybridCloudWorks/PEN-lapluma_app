import SwiftUI
import ApertureUI
import ApertureAPI
import ApertureDomain

/// S-04. People, documents, cases — and **who has access**.
///
/// The Access tab is a *safety* surface, not an admin surface. It is written for
/// someone checking whether another person can see their information, which in this
/// population is a question with real stakes (TA-2).
struct FolderView: View {
    let folderID: FolderID
    @Environment(AppSession.self) private var session
    @State private var loadState: ApertureLoadState<FolderContent> = .idle
    @State private var tab = Tab.people

    enum Tab: String, CaseIterable {
        case people, documents, cases, access

        var title: String {
            switch self {
            case .people: LaPlumaString("People")
            case .documents: LaPlumaString("Documents")
            case .cases: LaPlumaString("Cases")
            case .access: LaPlumaString("Access")
            }
        }
    }

    var body: some View {
        VStack {
            Picker("Section", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Aperture.Spacing.m)

            List {
                switch loadState {
                case .idle, .loading:
                    ApertureLoadingView()
                case .empty:
                    ApertureMessageView(.empty(messageKey: "folder.empty"))
                case .failed:
                    ApertureMessageView(
                        .failed(messageKey: "error.folderLoadFailed"),
                        action: (ApertureString("common.retry"), {
                            Task { await load() }
                        })
                    )
                    .accessibilityIdentifier("folder-load-failed")
                case .loaded(let content):
                    switch tab {
                    case .people: peopleSection(content.folder.persons)
                    case .documents: documentsSection(content.documents)
                    case .cases: casesSection(content.folder.cases)
                    case .access: accessSection
                    }
                }
            }
        }
        .navigationTitle(loadState.value?.folder.name ?? LaPlumaString("Folder"))
        .task(id: session.dataRevision) { await load() }
    }

    @ViewBuilder private func peopleSection(_ people: [Person]) -> some View {
        if people.isEmpty {
            ApertureMessageView(.empty(messageKey: "folder.peopleEmpty"))
        }
        ForEach(people) { person in
            VStack(alignment: .leading, spacing: Aperture.Spacing.xs) {
                Text(person.displayLabel).font(Aperture.Typography.value)
                if person.participation == .inactive {
                    // Quiet Exit: no reason, no precise date, and no notification was
                    // ever generated to anyone (ADR-007).
                    Text("Participant no longer active")
                        .font(Aperture.Typography.caption)
                        .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                } else if person.holdsOwnCredential {
                    Label("Has their own sign-in", systemImage: "person.badge.key")
                        .font(Aperture.Typography.caption)
                        .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private func documentsSection(_ documents: [CaseDocument]) -> some View {
        if documents.isEmpty {
            ApertureMessageView(.empty(messageKey: "folder.documentsEmpty"))
        }
        ForEach(documents) { document in
            NavigationLink { DocumentDetailView(document: document) } label: {
                HStack {
                    Image(systemName: document.isOpaque ? "lock.doc" : "doc.text")
                        .foregroundStyle(document.isOpaque ? Aperture.Palette.warning
                                                           : Aperture.Palette.accent)
                    VStack(alignment: .leading, spacing: Aperture.Spacing.xs) {
                        Text(document.originalName).font(Aperture.Typography.body)
                        if let documentClass = document.documentClass {
                            Text(ApertureString(String.LocalizationValue(documentClass.localizationKey)))
                                .font(Aperture.Typography.caption)
                                .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                        }
                        if document.isOpaque {
                            Text(aperture: "document.sealed.badge")
                                .font(Aperture.Typography.caption)
                                .foregroundStyle(Aperture.Palette.warning)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder private func casesSection(_ cases: [CaseSummary]) -> some View {
        if cases.isEmpty {
            ApertureMessageView(.empty(messageKey: "folder.casesEmpty"))
        }
        ForEach(cases) { summary in
            NavigationLink { CaseWorkspaceView(caseID: summary.id) } label: {
                VStack(alignment: .leading, spacing: Aperture.Spacing.s) {
                    Text(summary.packageTitle).font(Aperture.Typography.value)
                    ProgressCountersView(summary.counters, showsCaveat: false)
                }
            }
        }
    }

    @ViewBuilder private var accessSection: some View {
        Section {
            Text("This is everyone who can see anything in this folder, and exactly what they can see.")
                .font(Aperture.Typography.caption)
        }
        // In the real client this is populated from FolderMembership, showing scoped
        // persons and sections per member, plus a Revoke action that propagates within
        // 60 seconds. Private Annex items belonging to other people are not listed —
        // and not counted — because their *existence* must not be visible.
        Text("You — full access to this folder")
        Text("Casa Legal (reviewer) — can review, cannot approve")
    }

    @MainActor
    private func load() async {
        loadState = .loading
        do {
            async let folderRequest = session.api.folder(id: folderID)
            async let documentsRequest = session.api.documents(folderID: folderID)
            let (folder, documents) = try await (folderRequest, documentsRequest)
            loadState = .loaded(FolderContent(folder: folder, documents: documents))
        } catch is CancellationError {
            return
        } catch {
            loadState = .failed
        }
    }
}

private struct FolderContent: Equatable {
    let folder: Folder
    let documents: [CaseDocument]
}

struct DocumentDetailView: View {
    @State private var document: CaseDocument

    init(document: CaseDocument) {
        _document = State(initialValue: document)
    }

    var body: some View {
        List {
            if document.isOpaque {
                Section {
                    Label(ApertureString("document.sealed.notice"), systemImage: "lock.doc")
                        .font(Aperture.Typography.body)
                        .foregroundStyle(Aperture.Palette.warning)
                }
            } else if document.documentClass == .openedMedicalExam {
                Section {
                    Label("This appears to be an opened I-693. We will not read or extract it. Ask the civil surgeon what to do next.", systemImage: "exclamationmark.triangle")
                        .font(Aperture.Typography.body)
                        .foregroundStyle(Aperture.Palette.critical)
                }
            } else {
                Section("Preview") {
                    // Previews are rasterised server-side; the client never parses an
                    // unsanitised original (C-15).
                    RoundedRectangle(cornerRadius: Aperture.Radius.card)
                        .fill(Aperture.Palette.surfaceSecondary)
                        .frame(height: 220)
                        .overlay { Text("Server-rasterised preview").font(Aperture.Typography.caption) }
                }
            }

            Section("Details") {
                LabeledContent(
                    "Type",
                    value: document.documentClass.map {
                        ApertureString(String.LocalizationValue($0.localizationKey))
                    } ?? LaPlumaString("Not yet classified")
                )
                if let band = document.classificationBand {
                    Label(
                        ApertureString(String.LocalizationValue(band.localizationKey)),
                        systemImage: band.statusIcon
                    )
                    .font(Aperture.Typography.caption)
                    .apertureStatusSurface(band.statusTone)
                }
                if document.classificationOverride != nil {
                    Label("You chose this type", systemImage: "person.crop.circle.badge.checkmark")
                        .foregroundStyle(Aperture.Palette.accent)
                        .accessibilityIdentifier("classification-human-override")
                }
                Label(
                    ApertureString(String.LocalizationValue(document.processingState.localizationKey)),
                    systemImage: document.processingState.statusIcon
                )
                .font(Aperture.Typography.caption)
                .apertureStatusSurface(document.processingState.statusTone)
                LabeledContent("Added", value: document.uploadedAt.formatted(
                    Date.FormatStyle(date: .abbreviated, time: .omitted)
                        .locale(AperturePreferredLocale())
                ))
            }

            Section {
                NavigationLink("Review document type") {
                    DocumentClassificationView(document: document) { updated in
                        document = updated
                    }
                }
            } footer: {
                Text("You can always correct the suggested type. Your choice is recorded and will not be replaced automatically.")
            }
        }
        .navigationTitle(document.originalName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension DocumentProcessingState {
    var statusIcon: String {
        switch self {
        case .uploaded: "checkmark.circle.fill"
        case .scanning: "shield.lefthalf.filled"
        case .quarantined: "exclamationmark.octagon.fill"
        case .sanitized: "shield.checkered"
        case .classifying: "sparkle.magnifyingglass"
        case .needsClassification: "questionmark.circle.fill"
        case .extracting: "text.viewfinder"
        case .extracted: "checkmark.circle.fill"
        case .extractionFailed: "xmark.octagon.fill"
        case .opaqueStored: "lock.doc.fill"
        case .deleted: "trash.slash.fill"
        }
    }

    var statusTone: Aperture.StatusTone {
        switch self {
        case .uploaded, .sanitized, .extracted: .positive
        case .scanning, .classifying, .extracting: .information
        case .needsClassification, .opaqueStored: .attention
        case .quarantined, .extractionFailed: .critical
        case .deleted: .neutral
        }
    }
}

private extension DocumentClassificationBand {
    var statusIcon: String {
        switch self {
        case .likelyMatch: "sparkle.magnifyingglass"
        case .needsReview: "questionmark.circle.fill"
        case .humanConfirmed: "person.crop.circle.badge.checkmark"
        }
    }

    var statusTone: Aperture.StatusTone {
        switch self {
        case .likelyMatch: .information
        case .needsReview: .attention
        case .humanConfirmed: .neutral
        }
    }
}

private struct DocumentClassificationView: View {
    let document: CaseDocument
    let onUpdated: (CaseDocument) -> Void

    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var pendingSealedSelection = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                if let band = document.classificationBand {
                    LabeledContent(
                        "Current assessment",
                        value: ApertureString(String.LocalizationValue(band.localizationKey))
                    )
                }
                Text("Choose the type that best describes this document. This does not decide what forms you should file.")
                    .font(Aperture.Typography.caption)
                    .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
            }

            Section("Document type") {
                ForEach(DocumentClass.allCases, id: \.self) { documentClass in
                    Button {
                        if documentClass == .sealedMedical {
                            pendingSealedSelection = true
                        } else {
                            save(documentClass)
                        }
                    } label: {
                        HStack {
                            Text(ApertureString(String.LocalizationValue(documentClass.localizationKey)))
                            Spacer()
                            if document.documentClass == documentClass {
                                Image(systemName: "circle.inset.filled")
                            }
                        }
                    }
                    .disabled(isSaving || document.isOpaque)
                    .accessibilityIdentifier("classification-option-\(documentClass.rawValue)")
                }
            }

            if document.isOpaque {
                Section {
                    Text("A document stored as sealed medical cannot be made readable later.")
                        .foregroundStyle(Aperture.Palette.warning)
                }
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(Aperture.Palette.critical) }
            }
        }
        .navigationTitle("Document type")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Keep this document sealed?", isPresented: $pendingSealedSelection) {
            Button("Cancel", role: .cancel) {}
            Button("Keep sealed", role: .destructive) { save(.sealedMedical) }
        } message: {
            Text("We will store possession only. LaPluma will never preview, read, or extract this document, and this cannot be undone.")
        }
    }

    private func save(_ documentClass: DocumentClass) {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                let updated = try await session.api.reclassify(documentID: document.id, to: documentClass)
                onUpdated(updated)
                session.dataDidChange()
                dismiss()
            } catch let problem as ProblemDetails {
                errorMessage = problem.title
                isSaving = false
            } catch {
                errorMessage = LaPlumaString("We couldn't save that document type. Try again.")
                isSaving = false
            }
        }
    }
}

struct CaseOverviewView: View {
    let summary: CaseSummary

    var body: some View {
        List {
            Section { ProgressCountersView(summary.counters) }

            Section("Forms") {
                ForEach(summary.pinnedForms, id: \.formNumber) { form in
                    VStack(alignment: .leading, spacing: Aperture.Spacing.xs) {
                        Text(form.formNumber).font(Aperture.Typography.value)
                        Text(ApertureFormat(
                            "catalog.editionDate",
                            form.editionDate.formatted(
                                Date.FormatStyle(date: .abbreviated, time: .omitted)
                                    .locale(AperturePreferredLocale())
                            )
                        ))
                            .font(Aperture.Typography.caption)
                            .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                        if form.driftDetected {
                            Label(ApertureString("error.formDrift"), systemImage: "arrow.triangle.2.circlepath")
                                .font(Aperture.Typography.caption)
                                .foregroundStyle(Aperture.Palette.warning)
                        }
                    }
                }
            }

            Section {
                NavigationLink("What's missing") { MissingItemsView(caseID: summary.id) }
                NavigationLink("Review information") { ReviewView(caseID: summary.id) }
                NavigationLink("Forms and export") { PackageView(caseID: summary.id) }
            }

            Section { DisclosureFooter().listRowBackground(Color.clear) }
        }
        .navigationTitle(summary.packageTitle)
    }
}
