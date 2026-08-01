import Foundation
import ApertureDomain

/// An in-memory client with realistic fixture data, so every screen can be exercised
/// in the Simulator and in previews without a backend.
///
/// It is deliberately not a toy: it enforces the invariants the real server enforces,
/// so a screen that would be rejected in production is rejected here too. In
/// particular it refuses to confirm a value without a human actor, and it refuses to
/// report progress as anything other than counters.
public actor StubAPIClient: ApertureAPIClient {

    /// Simulated latency so loading states are visible during development rather than
    /// only appearing for the first time on a real device on a bad connection.
    public var artificialDelay: Duration = .milliseconds(320)

    private let currentUser = UserID("u_stub_maria")
    private var storage = StubStorage.seeded()

    public init() {}

    /// Tests run without the simulated latency that makes loading states visible
    /// during development.
    public func setDelay(_ duration: Duration) {
        artificialDelay = duration
    }

    private func pause() async {
        guard artificialDelay > .zero else { return }
        try? await Task.sleep(for: artificialDelay)
    }

    // MARK: Folders and cases

    public func folders() async throws -> [Folder] {
        await pause()
        return storage.folders
    }

    public func folder(id: FolderID) async throws -> Folder {
        await pause()
        guard let folder = storage.folders.first(where: { $0.id == id }) else {
            throw ProblemDetails(type: "https://api.aperture.app/problems/not-found",
                                 title: "Not found", status: 404)
        }
        return folder
    }

    public func createFolder(name: String, idempotencyKey: String) async throws -> Folder {
        await pause()
        let folder = Folder(
            id: FolderID("f_\(UUID().uuidString.prefix(8))"),
            name: name,
            ownerUserID: currentUser,
            persons: [],
            documentCount: 0,
            cases: []
        )
        storage.folders.append(folder)
        return folder
    }

    public func caseSummary(id: CaseID) async throws -> CaseSummary {
        await pause()
        guard let summary = storage.allCases.first(where: { $0.id == id }) else {
            throw ProblemDetails(type: "https://api.aperture.app/problems/not-found",
                                 title: "Not found", status: 404)
        }
        return summary
    }

    public func progress(caseID: CaseID) async throws -> ProgressCounters {
        await pause()
        return try await caseSummary(id: caseID).counters
    }

    // MARK: Catalog

    public func catalogPackages(query: String?) async throws -> [FormPackage] {
        await pause()
        // Ordering is deterministic and identical for every caller. No ranking,
        // no personalisation, no use of case data — the parameter list has none.
        let all = storage.catalog.sorted { $0.packageCode < $1.packageCode }
        guard let query, !query.trimmingCharacters(in: .whitespaces).isEmpty else { return all }
        let needle = query.lowercased()
        return all.filter {
            $0.title.lowercased().contains(needle)
                || $0.forms.contains { $0.formNumber.lowercased().contains(needle) }
                || ($0.agencyCategoryLabel?.lowercased().contains(needle) ?? false)
        }
    }

    public func requirements(packageCode: String) async throws -> RequirementSet {
        await pause()
        guard let set = storage.requirements[packageCode] else {
            throw ProblemDetails(type: "https://api.aperture.app/problems/not-found",
                                 title: "Not found", status: 404)
        }
        return set
    }

    public func createCase(
        folderID: FolderID,
        packageCode: String,
        roleAssignments: [PersonID: String],
        attestation: SelectionAttestation,
        idempotencyKey: String
    ) async throws -> CaseSummary {
        await pause()
        // A case cannot exist without a human attesting they chose the package.
        guard attestation.attested else {
            throw ProblemDetails(
                type: "https://api.aperture.app/problems/attestation-required",
                title: "You need to confirm you chose these forms",
                status: 422,
                detail: "Aperture cannot select a form package on your behalf."
            )
        }
        guard let package = storage.catalog.first(where: { $0.packageCode == packageCode }) else {
            throw ProblemDetails(type: "https://api.aperture.app/problems/not-found",
                                 title: "Not found", status: 404)
        }
        let summary = CaseSummary(
            id: CaseID("c_\(UUID().uuidString.prefix(8))"),
            folderID: folderID,
            packageCode: packageCode,
            packageTitle: package.title,
            state: .collecting,
            counters: ProgressCounters(
                fieldsFilled: 0,
                fieldsRequired: storage.requirements[packageCode]?.fieldCount ?? 0,
                documentsCollected: 0,
                documentsRequired: storage.requirements[packageCode]?.evidence.count ?? 0,
                blockingItems: storage.requirements[packageCode]?.evidence.count ?? 0,
                advisoryItems: 0
            ),
            pinnedForms: package.forms.map {
                PinnedForm(formNumber: $0.formNumber,
                           editionDate: $0.editionDate,
                           sourceSHA256: "stub",
                           encoding: $0.encoding)
            }
        )
        storage.allCases.append(summary)
        return summary
    }

    // MARK: Documents

    public func documents(folderID: FolderID) async throws -> [CaseDocument] {
        await pause()
        return storage.documents.filter { $0.folderID == folderID }
    }

    public func createUploadSession(
        folderID: FolderID,
        subjectPersonID: PersonID?,
        originalName: String,
        sizeBytes: Int64,
        source: DocumentSource,
        quality: CaptureQuality?,
        idempotencyKey: String
    ) async throws -> UploadSession {
        await pause()
        let documentID = DocumentID("d_\(UUID().uuidString.prefix(8))")
        storage.pendingUploads[documentID] = CaseDocument(
            id: documentID,
            folderID: folderID,
            subjectPersonID: subjectPersonID,
            originalName: originalName,
            // The real server derives this from magic bytes. The client's declared
            // type is recorded for forensics and ignored for processing.
            verifiedMimeType: "image/jpeg",
            sizeBytes: sizeBytes,
            documentClass: nil,
            documentSubtype: nil,
            processingState: .uploaded,
            detectedLanguage: nil,
            uploadedAt: Date(),
            captureQualityOverridden: quality.map { !$0.isAcceptable } ?? false
        )
        return UploadSession(
            sessionID: "us_\(UUID().uuidString.prefix(8))",
            documentID: documentID,
            uploadURL: URL(string: "https://stub.invalid/upload")!,
            expiresAt: Date().addingTimeInterval(900)
        )
    }

    public func completeUpload(sessionID: String, idempotencyKey: String) async throws -> CaseDocument {
        await pause()
        guard let (id, pending) = storage.pendingUploads.first else {
            throw ProblemDetails(type: "https://api.aperture.app/problems/not-found",
                                 title: "Upload session not found", status: 404)
        }
        storage.pendingUploads.removeValue(forKey: id)
        let classified = CaseDocument(
            id: pending.id,
            folderID: pending.folderID,
            subjectPersonID: pending.subjectPersonID,
            originalName: pending.originalName,
            verifiedMimeType: pending.verifiedMimeType,
            sizeBytes: pending.sizeBytes,
            documentClass: .identity,
            documentSubtype: "PASSPORT",
            processingState: .extracted,
            detectedLanguage: "es",
            uploadedAt: pending.uploadedAt,
            captureQualityOverridden: pending.captureQualityOverridden
        )
        storage.documents.append(classified)
        return classified
    }

    public func reclassify(documentID: DocumentID, to documentClass: DocumentClass) async throws -> CaseDocument {
        await pause()
        guard let index = storage.documents.firstIndex(where: { $0.id == documentID }) else {
            throw ProblemDetails(type: "https://api.aperture.app/problems/not-found",
                                 title: "Not found", status: 404)
        }
        let existing = storage.documents[index]
        // A human override is authoritative and permanent, and it can move a document
        // into the opaque class — after which nothing may read it.
        let updated = CaseDocument(
            id: existing.id,
            folderID: existing.folderID,
            subjectPersonID: existing.subjectPersonID,
            originalName: existing.originalName,
            verifiedMimeType: existing.verifiedMimeType,
            sizeBytes: existing.sizeBytes,
            documentClass: documentClass,
            documentSubtype: nil,
            processingState: documentClass.isOpaqueByPolicy ? .opaqueStored : existing.processingState,
            detectedLanguage: existing.detectedLanguage,
            uploadedAt: existing.uploadedAt,
            isOpaque: documentClass.isOpaqueByPolicy,
            captureQualityOverridden: existing.captureQualityOverridden
        )
        storage.documents[index] = updated
        return updated
    }

    public func deleteDocument(id: DocumentID) async throws {
        await pause()
        storage.documents.removeAll { $0.id == id }
    }

    // MARK: Review

    public func reviewableFields(caseID: CaseID) async throws -> [ReviewableField] {
        await pause()
        return storage.reviewable[caseID] ?? []
    }

    public func confirmValues(
        caseID: CaseID,
        confirmations: [ValueConfirmation],
        idempotencyKey: String
    ) async throws -> [FieldValue] {
        await pause()
        var confirmed: [FieldValue] = []
        for confirmation in confirmations {
            let now = Date()
            // Note the non-optional confirmedBy: this type cannot represent a value
            // that no human put there.
            let value = FieldValue(
                caseID: caseID,
                subjectPersonID: confirmation.personID,
                canonicalPath: confirmation.canonicalPath,
                value: confirmation.value,
                confidenceBand: .verified,
                origin: .manual,
                provenance: .manualEntry(by: currentUser, at: now),
                confirmedBy: currentUser,
                confirmedOnBehalfOf: confirmation.onBehalfOf,
                confirmedAt: now
            )
            confirmed.append(value)
            storage.applyConfirmation(caseID: caseID, value: value)
        }
        return confirmed
    }

    public func resolveDiscrepancy(
        caseID: CaseID,
        discrepancyID: DiscrepancyID,
        chosenValue: String,
        note: String?,
        idempotencyKey: String
    ) async throws {
        await pause()
        storage.clearDiscrepancy(caseID: caseID, discrepancyID: discrepancyID, chosen: chosenValue, by: currentUser)
    }

    // MARK: Missing items and interview

    public func missingItems(caseID: CaseID) async throws -> (items: [MissingItem], batches: [MissingItemBatch]) {
        await pause()
        return (storage.missingItems[caseID] ?? [], storage.batches[caseID] ?? [])
    }

    public func startInterview(
        caseID: CaseID,
        personID: PersonID,
        batchID: BatchID,
        modality: InterviewModality,
        consent: VoiceConsent?,
        idempotencyKey: String
    ) async throws -> InterviewSession {
        await pause()
        // Voice cannot start without recorded consent captured before any audio.
        if modality == .voice, consent == nil {
            throw ProblemDetails(
                type: "https://api.aperture.app/problems/consent-required",
                title: "We need your permission first",
                status: 422
            )
        }
        let session = InterviewSession(
            id: SessionID("is_\(UUID().uuidString.prefix(8))"),
            caseID: caseID,
            personID: personID,
            modality: modality,
            batchID: batchID,
            locale: Locale.current.identifier,
            turns: storage.openingTurns(for: personID),
            budget: modality == .voice ? VoiceBudget(secondsRemaining: 1800, targetSeconds: 420, isWaived: false) : nil,
            startedAt: Date()
        )
        storage.sessions[session.id] = session
        return session
    }

    public func sendInterviewMessage(
        sessionID: SessionID,
        text: String,
        idempotencyKey: String
    ) async throws -> [InterviewTurn] {
        await pause()
        guard var session = storage.sessions[sessionID] else {
            throw ProblemDetails(type: "https://api.aperture.app/problems/not-found",
                                 title: "Session not found", status: 404)
        }
        let userTurn = InterviewTurn(
            id: UUID().uuidString, role: .user, text: text, timestamp: Date()
        )
        session.turns.append(userTurn)

        // The guardrail chain runs on every candidate utterance before it is shown.
        // Here it is simulated, but the shape matters: a block substitutes a
        // deterministic refusal rather than generating one, because a generated
        // refusal could itself drift into advice.
        let reply: InterviewTurn
        if StubGuardrail.looksLikeAdviceRequest(text) {
            reply = InterviewTurn(
                id: UUID().uuidString,
                role: .assistant,
                text: StubGuardrail.deterministicRefusal,
                isDeterministic: true,
                guardrailBlocked: true,
                timestamp: Date()
            )
        } else {
            reply = InterviewTurn(
                id: UUID().uuidString,
                role: .assistant,
                text: storage.nextPrompt(for: session),
                question: storage.nextQuestion(for: session),
                timestamp: Date()
            )
        }
        session.turns.append(reply)
        storage.sessions[sessionID] = session
        return [userTurn, reply]
    }

    public func endInterview(sessionID: SessionID) async throws {
        await pause()
        storage.sessions.removeValue(forKey: sessionID)
    }

    // MARK: Package and export

    public func generatedPackage(caseID: CaseID) async throws -> GeneratedPackage? {
        await pause()
        return storage.packages[caseID]
    }

    public func export(
        packageID: PackageID,
        channel: ExportChannel,
        recipientEmail: String?,
        idempotencyKey: String
    ) async throws -> DeliveryLink? {
        await pause()
        guard channel == .secureLink else { return nil }
        return DeliveryLink(
            id: "ex_\(UUID().uuidString.prefix(8))",
            expiresAt: Date().addingTimeInterval(72 * 3600),
            maxDownloads: 3,
            downloadCount: 0,
            revoked: false
        )
    }

    // MARK: Inbox and consent

    public func inbox() async throws -> [InboxItem] {
        await pause()
        return storage.inbox.sorted { $0.createdAt > $1.createdAt }
    }

    public func markRead(notificationID: NotificationID) async throws {
        guard let index = storage.inbox.firstIndex(where: { $0.id == notificationID }) else { return }
        storage.inbox[index].readAt = Date()
    }

    public func consents() async throws -> [ConsentRecord] {
        await pause()
        return storage.consents
    }

    public func setConsent(purpose: ConsentRecord.Purpose, granted: Bool) async throws -> ConsentRecord {
        await pause()
        let record = ConsentRecord(
            purpose: purpose,
            granted: granted,
            noticeVersion: "2026.03",
            grantedAt: granted ? Date() : nil,
            withdrawnAt: granted ? nil : Date()
        )
        if let index = storage.consents.firstIndex(where: { $0.purpose == purpose }) {
            storage.consents[index] = record
        } else {
            storage.consents.append(record)
        }
        return record
    }
}

/// A stand-in for the Legal Advice Classifier's stage-1 deterministic screen.
///
/// The real chain is three stages, fails closed, and is gated on a held-out corpus the
/// engineering team never sees. This is only enough to exercise the UI path — it is
/// **not** a safety control and must never be mistaken for one.
enum StubGuardrail {
    static let triggers = [
        "qualify", "eligible", "approved", "denied", "chances", "should i file",
        "which form", "will i get", "my odds", "guarantee",
        "califico", "elegible", "aprobar", "aprobado", "qué formulario", "que formulario"
    ]

    static func looksLikeAdviceRequest(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return triggers.contains { lowered.contains($0) }
    }

    /// In the real system the refusal text is **served by the backend**: Agent 16
    /// substitutes a reviewed, localised, static string when it blocks an utterance.
    /// The client never composes a refusal, so this literal exists only so the stub
    /// can exercise the blocked-turn UI path.
    static let deterministicRefusal = """
        I can't tell you what a government agency will decide — nobody here can, and it \
        would be wrong to guess. What I can do is help you make sure your application is \
        complete and correct. If you'd like legal advice, here are nonprofit organisations \
        that offer free help.
        """
}
