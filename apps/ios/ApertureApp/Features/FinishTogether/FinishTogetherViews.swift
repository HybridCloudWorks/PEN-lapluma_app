import SwiftUI
import UIKit
import PDFKit
import ApertureDomain
import ApertureAPI
import ApertureUI

// MARK: - Guided Finish

struct GuidedFinishSetupView: View {
    let caseID: CaseID
    @State private var minutes = 10

    var body: some View {
        List {
            Section {
                Label("Choose a short focus session", systemImage: "timer")
                    .font(Aperture.Typography.sectionTitle)
                Text("LaPluma will group the paperwork tasks that fit. Required items stay ahead of optional items.")
                    .font(Aperture.Typography.body)
                    .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
            }

            Section("Time available") {
                Picker("Time available", selection: $minutes) {
                    ForEach(GuidedFinishPolicy.supportedBudgets, id: \.self) { option in
                        Text(LaPlumaFormat("guided.minutes", option)).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("guided-finish-budget")
            }

            Section {
                NavigationLink {
                    GuidedFinishView(caseID: caseID, minutes: minutes)
                } label: {
                    Label("Start focused session", systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("guided-finish-start")
            } footer: {
                Text("This orders paperwork tasks only. It does not predict an agency decision or rank the strength of evidence.")
            }

            Section { DisclosureFooter() }
        }
        .navigationTitle("Guided Finish")
    }
}

struct GuidedFinishView: View {
    let caseID: CaseID
    let minutes: Int
    @Environment(AppSession.self) private var session
    @State private var model = GuidedFinishModel()
    @State private var destination: GuidedFinishDestination?

    var body: some View {
        List {
            switch model.state {
            case .idle, .loading:
                ApertureLoadingView()
            case .failed:
                ApertureMessageView(
                    .failed(messageKey: "guided.loadFailed"),
                    action: (ApertureString("common.retry"), { Task { await load() } })
                )
            case .empty:
                Label("Nothing in this focus session needs you.", systemImage: "tray")
                    .apertureStatusSurface(.positive)
                    .accessibilityIdentifier("guided-finish-empty")
            case .loaded(let plan):
                Section {
                    Label(
                        LaPlumaFormat("guided.sessionSummary", plan.estimatedMinutes, plan.steps.count),
                        systemImage: "timer"
                    )
                    .apertureStatusSurface(.information)
                }

                ForEach(Array(plan.steps.enumerated()), id: \.element.id) { index, step in
                    Section {
                        GuidedFinishStepCard(
                            step: step,
                            position: index + 1,
                            total: plan.steps.count
                        ) { action in
                            route(step: step, action: action)
                        }
                    }
                }
            }

            Section { DisclosureFooter() }
        }
        .navigationTitle("Guided Finish")
        .navigationDestination(item: $destination) { destination in
            destinationView(destination)
        }
        .task(id: session.dataRevision) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        await model.load(api: session.api, caseID: caseID, minutes: minutes)
    }

    private func route(step: GuidedFinishStep, action: GuidedFinishAction) {
        switch action {
        case .relayStatus:
            if let relayID = step.relayID {
                destination = .relayDetail(relayID)
            }
        case .path(let path):
            guard let item = step.itemIDs.compactMap({ model.items[$0] }).first else { return }
            destination = .resolution(item, path)
        }
    }

    @ViewBuilder
    private func destinationView(_ destination: GuidedFinishDestination) -> some View {
        switch destination {
        case .relayDetail(let relayID):
            PrivateRelayDetailView(caseID: caseID, relayID: relayID)
        case .resolution(let item, let path):
            switch path.kind {
            case .scan, .importFile:
                CaptureView()
            case .answer, .type:
                StructuredQuestionsView(
                    caseID: caseID,
                    batchID: item.batchID ?? BatchID("single_\(item.id.rawValue)"),
                    personID: item.assignedPersonID
                )
            case .cannotObtain:
                CannotObtainView(item: item)
            case .privateRelay:
                PrivateRelayCreateView(caseID: caseID, item: item)
            }
        }
    }
}

private enum GuidedFinishAction {
    case path(ResolutionPath)
    case relayStatus
}

private enum GuidedFinishDestination: Hashable, Identifiable {
    case resolution(MissingItem, ResolutionPath)
    case relayDetail(EvidenceRelayID)

    var id: String {
        switch self {
        case .resolution(let item, let path): "resolution:\(item.id.rawValue):\(path.kind.rawValue)"
        case .relayDetail(let relayID): "relay:\(relayID.rawValue)"
        }
    }
}

private struct GuidedFinishStepCard: View {
    let step: GuidedFinishStep
    let position: Int
    let total: Int
    let onSelect: (GuidedFinishAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Aperture.Spacing.s) {
            Text(LaPlumaFormat("guided.stepCount", position, total))
                .font(Aperture.Typography.caption)
                .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
            Text(step.title).font(Aperture.Typography.value)
            Label(step.assignedPersonLabel, systemImage: "person.crop.circle")
                .font(Aperture.Typography.caption)

            switch step.status {
            case .actionable:
                Label(LaPlumaFormat("guided.estimatedMinutes", step.estimatedMinutes), systemImage: "clock")
                    .font(Aperture.Typography.caption)
                    .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                ForEach(step.resolutionPaths) { path in
                    Button {
                        onSelect(.path(path))
                    } label: {
                        Label(path.label, systemImage: icon(path.kind))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .apertureMinimumTouchTarget(expandHorizontally: true)
                    .accessibilityIdentifier("guided-action-\(path.kind.rawValue.lowercased())")
                }
            case .waitingForRelay:
                relayButton("Waiting for a private upload", systemImage: "hourglass")
            case .relayLocked:
                relayButton("Private request locked", systemImage: "lock.trianglebadge.exclamationmark")
            case .relayNeedsReview:
                relayButton("Document received — review it", systemImage: "doc.badge.clock")
            }
        }
        .padding(.vertical, Aperture.Spacing.xs)
    }

    private func relayButton(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Button { onSelect(.relayStatus) } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("guided-relay-status")
    }

    private func icon(_ kind: ResolutionPath.Kind) -> String {
        switch kind {
        case .scan: "doc.viewfinder"
        case .importFile: "folder"
        case .answer: "bubble.left.and.bubble.right"
        case .type: "keyboard"
        case .cannotObtain: "questionmark.circle"
        case .privateRelay: "link.badge.plus"
        }
    }
}

// MARK: - Proof Map

struct ProofMapView: View {
    let caseID: CaseID
    var initialFieldID: String? = nil
    @Environment(AppSession.self) private var session
    @State private var state: ApertureLoadState<ProofMap> = .idle
    @State private var personLabels: [PersonID: String] = [:]

    var body: some View {
        ScrollViewReader { proxy in
            List {
                switch state {
                case .idle, .loading:
                    ApertureLoadingView()
                case .empty:
                    ApertureMessageView(.empty(messageKey: "proof.empty"))
                case .failed:
                    ApertureMessageView(
                        .failed(messageKey: "proof.loadFailed"),
                        action: (ApertureString("common.retry"), { Task { await load() } })
                    )
                case .loaded(let map):
                    Section {
                        Text("Each answer is shown with where it came from and every pinned official-form field it will fill.")
                            .font(Aperture.Typography.caption)
                    }
                    ForEach(grouped(map.entries)) { group in
                        Section(group.label) {
                            ForEach(group.entries) { proof in
                                NavigationLink {
                                    ProofMapDetailView(proof: proof)
                                } label: {
                                    VStack(alignment: .leading, spacing: Aperture.Spacing.xs) {
                                        BilingualLabel(primary: proof.localizedLabel, english: proof.englishFormLabel)
                                        Text(proof.value ?? "—").font(Aperture.Typography.value)
                                        Label(
                                            LaPlumaFormat("proof.destinationCount", proof.destinations.count),
                                            systemImage: "arrow.triangle.branch"
                                        )
                                        .font(Aperture.Typography.caption)
                                        .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                                        if proof.requiresHumanReview {
                                            Label("Needs your check", systemImage: "person.crop.circle.badge.questionmark")
                                                .font(Aperture.Typography.caption)
                                                .foregroundStyle(Aperture.Palette.warning)
                                        }
                                    }
                                    .padding(.vertical, Aperture.Spacing.xs)
                                }
                                .id(proof.id)
                                .accessibilityIdentifier("proof-map-field-\(proof.canonicalPath.rawValue)")
                                .accessibilityAddTraits(initialFieldID == proof.id ? .isSelected : [])
                            }
                        }
                    }
                }
                Section { DisclosureFooter() }
            }
            .navigationTitle("Proof Map")
            .task(id: session.dataRevision) {
                await load()
                if let initialFieldID { proxy.scrollTo(initialFieldID, anchor: .center) }
            }
            .refreshable { await load() }
        }
    }

    private func load() async {
        state = .loading
        do {
            async let proofRequest = session.api.proofMap(caseID: caseID)
            async let foldersRequest = session.api.folders()
            let (map, folders) = try await (proofRequest, foldersRequest)
            personLabels = Dictionary(uniqueKeysWithValues: folders.flatMap(\.persons).map { ($0.id, $0.displayLabel) })
            state = map.entries.isEmpty ? .empty : .loaded(map)
        } catch is CancellationError {
            return
        } catch {
            state = .failed
        }
    }

    private func grouped(_ entries: [FieldProof]) -> [ProofPersonGroup] {
        Dictionary(grouping: entries) { ProofGroupKey(personID: $0.subjectPersonID, needsReview: $0.requiresHumanReview) }
            .map { key, fields in
                let person = personLabels[key.personID] ?? LaPlumaString("Person")
                return ProofPersonGroup(
                    personID: key.personID,
                    needsReview: key.needsReview,
                    label: LaPlumaFormat(
                        key.needsReview ? "proof.personNeedsReview" : "proof.personConfirmed",
                        person
                    ),
                    entries: fields.sorted { $0.localizedLabel < $1.localizedLabel }
                )
            }
            .sorted {
                let left = personLabels[$0.personID] ?? ""
                let right = personLabels[$1.personID] ?? ""
                if left != right { return left < right }
                return $0.needsReview && !$1.needsReview
            }
    }
}

private struct ProofGroupKey: Hashable {
    let personID: PersonID
    let needsReview: Bool
}

private struct ProofPersonGroup: Identifiable {
    let personID: PersonID
    let needsReview: Bool
    let label: String
    let entries: [FieldProof]
    var id: String { "\(personID.rawValue)|\(needsReview)" }
}

private struct ProofMapDetailView: View {
    let proof: FieldProof
    @Environment(AppSession.self) private var session
    @State private var previewState: ApertureLoadState<DocumentPagePreview> = .idle

    var body: some View {
        List {
            Section("Answer") {
                BilingualLabel(primary: proof.localizedLabel, english: proof.englishFormLabel)
                Text(proof.value ?? "—").font(Aperture.Typography.value)
                if proof.requiresHumanReview {
                    Label("Needs your check", systemImage: "person.crop.circle.badge.questionmark")
                        .apertureStatusSurface(.attention)
                }
            }

            Section("Source") {
                source
            }

            Section("Official-form destinations") {
                ForEach(proof.destinations, id: \.self) { destination in
                    VStack(alignment: .leading, spacing: Aperture.Spacing.xs) {
                        Text(destination.formNumber).font(Aperture.Typography.value)
                        Text(LaPlumaFormat("proof.formDestination", destination.page, destination.fieldName))
                            .font(Aperture.Typography.caption)
                            .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("proof-destination-\(destination.formNumber.lowercased())")
                }
            }

            Section { DisclosureFooter() }
        }
        .navigationTitle("Answer proof")
        .task { await loadPreviewIfNeeded() }
    }

    @ViewBuilder
    private var source: some View {
        switch proof.provenance {
        case .document(let anchor):
            VStack(alignment: .leading, spacing: Aperture.Spacing.s) {
                Text(LaPlumaFormat("proof.documentSource", anchor.documentName, anchor.pageNumber))
                switch previewState {
                case .idle, .loading:
                    ProgressView()
                case .failed:
                    Button(ApertureString("common.retry")) { Task { await loadPreviewIfNeeded() } }
                case .empty:
                    Text("Preview unavailable")
                case .loaded(let preview):
                    ProofPagePreview(preview: preview, anchor: anchor)
                        .accessibilityLabel("Sanitized source page with the answer region highlighted")
                        .accessibilityIdentifier("proof-source-preview")
                }
                if let note = anchor.normalizationNote {
                    Text(note)
                        .font(Aperture.Typography.caption)
                        .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                }
            }
        case .manualEntry(let userID, let date):
            Label(
                LaPlumaFormat("proof.manualSource", actorLabel(userID), localized(date)),
                systemImage: "keyboard"
            )
        case .interview(_, let userID, let onBehalfOf, let date):
            Label(
                onBehalfOf == nil
                    ? LaPlumaFormat("proof.interviewSource", actorLabel(userID), localized(date))
                    : LaPlumaFormat(
                        "proof.interviewOnBehalfSource",
                        actorLabel(userID),
                        onBehalfOf?.rawValue ?? "",
                        localized(date)
                    ),
                systemImage: "bubble.left.and.bubble.right"
            )
        case nil:
            Label("No answer has been supplied yet", systemImage: "questionmark.circle")
        }
    }

    private func localized(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(AperturePreferredLocale()))
    }

    private func actorLabel(_ userID: UserID) -> String {
        session.currentUserID == userID ? LaPlumaString("You") : userID.rawValue
    }

    private func loadPreviewIfNeeded() async {
        guard case .document(let anchor) = proof.provenance else { return }
        previewState = .loading
        do {
            let preview = try await session.api.documentPagePreview(
                documentID: anchor.documentID,
                pageNumber: anchor.pageNumber
            )
            guard preview.contentSHA256 == CapturePayloadProcessor.sha256(of: preview.data) else {
                previewState = .failed
                return
            }
            previewState = .loaded(preview)
        } catch is CancellationError {
            return
        } catch {
            previewState = .failed
        }
    }
}

private struct ProofPagePreview: View {
    let preview: DocumentPagePreview
    let anchor: DocumentAnchor

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                if let image = UIImage(data: preview.data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if !anchor.isDegenerate {
                    let minX = anchor.boundingPolygon.map(\.x).min() ?? 0
                    let minY = anchor.boundingPolygon.map(\.y).min() ?? 0
                    let maxX = anchor.boundingPolygon.map(\.x).max() ?? 0
                    let maxY = anchor.boundingPolygon.map(\.y).max() ?? 0
                    Rectangle()
                        .strokeBorder(Aperture.Palette.accent, lineWidth: 3)
                        .background(Aperture.Palette.accent.opacity(0.12))
                        .frame(
                            width: max(8, (maxX - minX) * geometry.size.width),
                            height: max(8, (maxY - minY) * geometry.size.height)
                        )
                        .offset(x: minX * geometry.size.width, y: minY * geometry.size.height)
                }
            }
        }
        .aspectRatio(CGFloat(preview.pixelWidth) / CGFloat(preview.pixelHeight), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Aperture.Radius.card))
    }
}

// MARK: - Private Relay

struct PrivateRelayCreateView: View {
    let caseID: CaseID
    let item: MissingItem
    @Environment(AppSession.self) private var session
    @State private var isCreating = false
    @State private var result: CreateEvidenceRelayResult?
    @State private var existing: EvidenceRelay?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Label("Private document request", systemImage: "link.badge.plus")
                    .font(Aperture.Typography.sectionTitle)
                Text(item.title).font(Aperture.Typography.value)
                Text("The recipient cannot see your case, forms, people, progress, or other documents.")
                    .font(Aperture.Typography.caption)
            }

            if let result {
                credentials(result)
            } else if let existing {
                Section {
                    NavigationLink {
                        PrivateRelayDetailView(caseID: caseID, relayID: existing.id)
                    } label: {
                        RelayStatusLabel(status: existing.status)
                    }
                } header: {
                    Text("Request status")
                } footer: {
                    Text("For safety, the access code is shown only when a request is created. Revoke this request and create another if the code was lost.")
                }
            } else {
                Section {
                    Button {
                        Task { await create() }
                    } label: {
                        Label("Create private request", systemImage: "link.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isCreating || !session.connectivity.isOnline)
                    .accessibilityIdentifier("private-relay-create")
                } footer: {
                    Text("The link lasts 72 hours. Send the six-digit code separately. Five incorrect codes lock the request.")
                }
            }

            if !session.connectivity.isOnline {
                Section {
                    Label("A connection is required to create or manage a private request.", systemImage: "wifi.slash")
                        .apertureStatusSurface(.attention)
                }
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(Aperture.Palette.critical) }
            }
            Section { DisclosureFooter() }
        }
        .navigationTitle("Private Relay")
        .task { await load() }
    }

    @ViewBuilder
    private func credentials(_ result: CreateEvidenceRelayResult) -> some View {
        Section("Share the link") {
            ShareLink(
                item: result.shareURL,
                subject: Text("Private LaPluma document request"),
                message: Text("Open this private upload link. I will send the access code separately.")
            ) {
                Label("Share link", systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("private-relay-share-link")
            Text(result.shareURL.absoluteString)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }

        Section {
            Text(result.accessCode)
                .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                .accessibilityIdentifier("private-relay-access-code")
            Button {
                UIPasteboard.general.string = result.accessCode
            } label: {
                Label("Copy code", systemImage: "doc.on.doc")
            }
            .accessibilityIdentifier("private-relay-copy-code")
        } header: {
            Text("Send this code separately")
        } footer: {
            Text("Do not put the code in the same message as the link.")
        }

        #if DEBUG
        if let token = result.shareURL.pathComponents.last {
            Section {
                NavigationLink {
                    RelayRecipientHarnessView(token: token, suggestedCode: result.accessCode)
                } label: {
                    Label("Preview recipient upload", systemImage: "testtube.2")
                }
                .accessibilityIdentifier("private-relay-preview-recipient")
            } header: {
                Text("Simulator testing")
            } footer: {
                Text("Debug only. This recipient harness is not compiled into Release builds.")
            }
        }
        #endif
    }

    private func load() async {
        existing = (try? await session.api.evidenceRelays(caseID: caseID))?
            .first { $0.missingItemID == item.id && [.active, .locked, .received].contains($0.status) }
    }

    private func create() async {
        isCreating = true; errorMessage = nil
        defer { isCreating = false }
        do {
            result = try await session.api.createEvidenceRelay(
                caseID: caseID,
                missingItemID: item.id,
                idempotencyKey: IdempotencyKey.make()
            )
            session.dataDidChange()
        } catch let problem as ProblemDetails {
            errorMessage = problem.title
            await load()
        } catch {
            errorMessage = LaPlumaString("relay.createFailed")
        }
    }
}

struct PrivateRelayDetailView: View {
    let caseID: CaseID
    let relayID: EvidenceRelayID
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var relay: EvidenceRelay?
    @State private var document: CaseDocument?
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        List {
            if let relay {
                Section("Request status") {
                    RelayStatusLabel(status: relay.status)
                    Text(relay.requestedTitle).font(Aperture.Typography.value)
                    LabeledContent("Expires", value: localized(relay.expiresAt))
                }

                if relay.status == .received, let document {
                    Section("Received document") {
                        NavigationLink {
                            DocumentDetailView(document: document)
                        } label: {
                            Label(document.originalName, systemImage: "doc.badge.clock")
                        }
                        if document.documentClass == nil {
                            Label("Review the document type before using it.", systemImage: "person.crop.circle.badge.questionmark")
                                .apertureStatusSurface(.attention)
                        }
                    }
                    Section {
                        Button("Use for this request") { Task { await accept() } }
                            .buttonStyle(.borderedProminent)
                            .disabled(document.documentClass == nil || isSaving)
                            .accessibilityIdentifier("private-relay-accept")
                        Button("Reject this upload", role: .destructive) { Task { await reject() } }
                            .disabled(isSaving)
                    } footer: {
                        Text("Receiving a file does not satisfy a requirement. An authorized person must review and accept it.")
                    }
                } else if [.active, .locked].contains(relay.status) {
                    Section {
                        Button("Revoke request", role: .destructive) { Task { await revoke() } }
                            .disabled(isSaving)
                            .accessibilityIdentifier("private-relay-revoke")
                    }
                }
            } else {
                ApertureLoadingView()
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(Aperture.Palette.critical) }
            }
            Section { DisclosureFooter() }
        }
        .navigationTitle("Private Relay")
        .task(id: session.dataRevision) { await load() }
    }

    private func load() async {
        do {
            relay = try await session.api.evidenceRelays(caseID: caseID).first { $0.id == relayID }
            guard let documentID = relay?.submittedDocumentID else { document = nil; return }
            let folderID = try await session.api.caseSummary(id: caseID).folderID
            document = try await session.api.documents(folderID: folderID).first { $0.id == documentID }
        } catch {
            errorMessage = LaPlumaString("relay.loadFailed")
        }
    }

    private func accept() async { await mutate { try await session.api.acceptEvidenceRelay(relayID: relayID, idempotencyKey: IdempotencyKey.make()) } }
    private func reject() async { await mutate { try await session.api.rejectEvidenceRelay(relayID: relayID, idempotencyKey: IdempotencyKey.make()) } }
    private func revoke() async { await mutate { try await session.api.revokeEvidenceRelay(relayID: relayID, idempotencyKey: IdempotencyKey.make()) } }

    private func mutate(_ operation: () async throws -> EvidenceRelay) async {
        isSaving = true; errorMessage = nil
        defer { isSaving = false }
        do {
            relay = try await operation()
            session.dataDidChange()
            if relay?.status == .accepted || relay?.status == .rejected || relay?.status == .revoked { dismiss() }
        } catch let problem as ProblemDetails {
            errorMessage = problem.title
        } catch {
            errorMessage = LaPlumaString("relay.updateFailed")
        }
    }

    private func localized(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(AperturePreferredLocale()))
    }
}

private struct RelayStatusLabel: View {
    let status: EvidenceRelayStatus

    var body: some View {
        Label(title, systemImage: icon)
            .apertureStatusSurface(tone)
            .accessibilityIdentifier("private-relay-status-\(status.rawValue.lowercased())")
    }

    private var title: String {
        switch status {
        case .active: LaPlumaString("Waiting for upload")
        case .locked: LaPlumaString("Locked after incorrect codes")
        case .received: LaPlumaString("Received — needs review")
        case .accepted: LaPlumaString("Accepted for this request")
        case .rejected: LaPlumaString("Upload rejected")
        case .revoked: LaPlumaString("Request revoked")
        case .expired: LaPlumaString("Request expired")
        }
    }

    private var icon: String {
        switch status {
        case .active: "hourglass"
        case .locked: "lock.trianglebadge.exclamationmark"
        case .received: "doc.badge.clock"
        case .accepted: "person.crop.circle.badge.checkmark"
        case .rejected: "xmark.octagon"
        case .revoked: "link.badge.minus"
        case .expired: "clock.badge.exclamationmark"
        }
    }

    private var tone: Aperture.StatusTone {
        switch status {
        case .accepted: .positive
        case .active, .received: .information
        case .locked, .expired: .attention
        case .rejected, .revoked: .critical
        }
    }
}

#if DEBUG
private struct RelayRecipientHarnessView: View {
    let token: String
    let suggestedCode: String
    @Environment(AppSession.self) private var session
    @State private var code = ""
    @State private var grant: RelayUploadGrant?
    @State private var message: String?
    @State private var isAvailable = false

    var body: some View {
        List {
            Section {
                Text("A LaPluma user asked you to send one document.")
                Text("Enter the code they sent separately. No request details are shown before the code is accepted.")
                    .font(Aperture.Typography.caption)
            }

            if let grant {
                Section("Requested document") {
                    Text(grant.requestedTitle).font(Aperture.Typography.value)
                    Button("Submit synthetic document") { Task { await submit(grant) } }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("relay-harness-submit")
                }
            } else if isAvailable {
                Section("Access code") {
                    TextField("Six-digit code", text: $code)
                        .keyboardType(.numberPad)
                        .accessibilityIdentifier("relay-harness-code")
                    Button("Unlock upload") { Task { await unlock() } }
                        .disabled(code.count != 6)
                        .accessibilityIdentifier("relay-harness-unlock")
                    Button("Use suggested Debug code") { code = suggestedCode }
                        .accessibilityIdentifier("relay-harness-use-code")
                }
            } else {
                Label("This request is unavailable.", systemImage: "link.badge.minus")
            }

            if let message { Section { Text(message) } }
        }
        .navigationTitle("Private upload")
        .task { await challenge() }
    }

    private var recipientAPI: (any EvidenceRelayRecipientClient)? {
        session.api as? any EvidenceRelayRecipientClient
    }

    private func challenge() async {
        guard let recipientAPI else { isAvailable = false; return }
        isAvailable = (try? await recipientAPI.relayChallenge(token: token).isAvailable) ?? false
    }

    private func unlock() async {
        do {
            guard let recipientAPI else { throw RelayHarnessError.unavailable }
            grant = try await recipientAPI.unlockRelay(
                token: token,
                accessCode: code,
                idempotencyKey: IdempotencyKey.make()
            )
            message = nil
        } catch let problem as ProblemDetails {
            message = problem.title
        } catch {
            message = LaPlumaString("That code could not be checked.")
        }
    }

    private func submit(_ grant: RelayUploadGrant) async {
        let pdf = PDFDocument(); pdf.insert(PDFPage(), at: 0)
        guard let data = pdf.dataRepresentation(),
              let prepared = try? CapturePayloadProcessor.prepare(data) else { return }
        do {
            guard let recipientAPI else { throw RelayHarnessError.unavailable }
            let upload = try await recipientAPI.createRelayUploadSession(
                grantID: grant.id,
                originalName: "requested-document.pdf",
                sizeBytes: Int64(prepared.data.count),
                contentSHA256: prepared.contentSHA256,
                idempotencyKey: IdempotencyKey.make()
            )
            _ = try await recipientAPI.completeRelayUpload(
                sessionID: upload.id,
                uploadedData: prepared.data,
                idempotencyKey: IdempotencyKey.make()
            )
            message = LaPlumaString("Upload received. The requester must review it before it is used.")
            session.dataDidChange()
        } catch let problem as ProblemDetails {
            message = problem.title
        } catch {
            message = LaPlumaString("The upload could not be completed.")
        }
    }
}

private enum RelayHarnessError: Error { case unavailable }
#endif
