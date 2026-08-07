import Foundation
import ApertureDomain

/// Selects fixture copy without allowing screenshot tooling to reuse realistic
/// internal personas. The marketing profile is synthetic, non-persistent, and must
/// never be confused with a production API environment.
public enum StubFixtureProfile: Sendable {
    case realisticInternal
    case marketingSafe
}

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

    private let currentUser: UserID
    private let persistenceURL: URL?
    private let now: @Sendable () -> Date
    private var storage: StubStorage

    public init(
        persistenceURL: URL? = nil,
        fixtureProfile: StubFixtureProfile = .realisticInternal,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        currentUser = fixtureProfile == .marketingSafe ? UserID("u_sample") : UserID("u_stub_maria")
        self.persistenceURL = fixtureProfile == .marketingSafe ? nil : persistenceURL
        self.now = now
        if fixtureProfile == .realisticInternal,
           let persistenceURL,
           let data = try? Data(contentsOf: persistenceURL),
           var saved = try? JSONDecoder().decode(StubStorage.self, from: data) {
            // Public catalog data is versioned independently of applicant state. Do
            // not let an older persisted fixture silently hide a new edition or keep
            // an obsolete activation state after an app update.
            let currentPublicData = StubStorage.seeded(profile: fixtureProfile)
            saved.catalog = currentPublicData.catalog
            saved.requirements = currentPublicData.requirements
            storage = saved
        } else {
            storage = StubStorage.seeded(profile: fixtureProfile)
        }
    }

    /// The mobile-only build uses the same production-shaped client boundary as the
    /// future server client, but persists its local fixture state between launches.
    /// This keeps the complete applicant journey usable without deploying a backend.
    private func persist() {
        guard let persistenceURL,
              let data = try? JSONEncoder().encode(storage) else { return }
        try? FileManager.default.createDirectory(
            at: persistenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        #if os(iOS)
        try? data.write(to: persistenceURL, options: [.atomic, .completeFileProtection])
        #else
        try? data.write(to: persistenceURL, options: .atomic)
        #endif
    }

    /// Tests run without the simulated latency that makes loading states visible
    /// during development.
    public func setDelay(_ duration: Duration) {
        artificialDelay = duration
    }

    /// Mobile-only data-rights implementation. Catalog and published requirements are
    /// public reference data; every applicant-owned record is erased.
    public func deleteAllUserData() {
        storage.folders.removeAll()
        storage.allCases.removeAll()
        storage.documents.removeAll()
        storage.pendingUploads.removeAll()
        storage.uploadSessions = [:]
        storage.reviewable.removeAll()
        storage.valueHistory = [:]
        storage.missingItems.removeAll()
        storage.batches.removeAll()
        storage.sessions.removeAll()
        storage.packages.removeAll()
        storage.inbox.removeAll()
        storage.consents.removeAll()
        storage.idempotencyRecords?.removeAll()
        persist()
    }

    private func pause() async {
        guard artificialDelay > .zero else { return }
        try? await Task.sleep(for: artificialDelay)
    }

    /// Replays the first successful response for one endpoint/key/request tuple. A
    /// key is scoped to its endpoint so independent operations may safely use the
    /// same client-generated value. Reusing it for a different payload is a conflict,
    /// never a second mutation.
    private func idempotent<Request: Encodable, Response: Codable>(
        endpoint: String,
        key: String,
        request: Request,
        operation: () throws -> Response
    ) throws -> Response {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProblemDetails(
                type: "https://api.aperture.app/problems/idempotency-key-required",
                title: "Idempotency key required",
                status: 422
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let requestData = try encoder.encode(request)
        let recordKey = "\(endpoint.utf8.count):\(endpoint)\(key)"
        if let existing = storage.idempotencyRecords?[recordKey] {
            guard existing.request == requestData else {
                throw ProblemDetails(
                    type: "https://api.aperture.app/problems/idempotency-key-conflict",
                    title: "Idempotency key already used",
                    status: 409,
                    detail: "Use a new idempotency key when the request payload changes."
                )
            }
            return try JSONDecoder().decode(Response.self, from: existing.response)
        }

        let response = try operation()
        if storage.idempotencyRecords == nil { storage.idempotencyRecords = [:] }
        storage.idempotencyRecords?[recordKey] = StubIdempotencyRecord(
            request: requestData,
            response: try encoder.encode(response)
        )
        persist()
        return response
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
        return try idempotent(endpoint: "createFolder", key: idempotencyKey, request: name) {
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
                || $0.category.title.lowercased().contains(needle)
                || $0.subcategory.title.lowercased().contains(needle)
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
        let request = CreateCaseRequest(
            folderID: folderID,
            packageCode: packageCode,
            roleAssignments: roleAssignments,
            attestation: attestation
        )
        return try idempotent(endpoint: "createCase", key: idempotencyKey, request: request) {
        // A case cannot exist without a human attesting they chose the package.
        guard attestation.attested else {
            throw ProblemDetails(
                type: "https://api.aperture.app/problems/attestation-required",
                title: "You need to confirm you chose these forms",
                status: 422,
                detail: "LaPluma cannot select a form package on your behalf."
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
        if let folderIndex = storage.folders.firstIndex(where: { $0.id == folderID }) {
            let folder = storage.folders[folderIndex]
            storage.folders[folderIndex] = Folder(
                id: folder.id,
                name: folder.name,
                ownerUserID: folder.ownerUserID,
                persons: folder.persons,
                documentCount: folder.documentCount,
                cases: folder.cases + [summary]
            )
        }
        return summary
        }
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
        contentSHA256: String,
        idempotencyKey: String
    ) async throws -> UploadSession {
        await pause()
        let request = CreateUploadSessionRequest(
            folderID: folderID,
            subjectPersonID: subjectPersonID,
            originalName: originalName,
            sizeBytes: sizeBytes,
            source: source,
            quality: quality,
            contentSHA256: contentSHA256
        )
        return try idempotent(endpoint: "createUploadSession", key: idempotencyKey, request: request) {
        let documentID = DocumentID("d_\(UUID().uuidString.prefix(8))")
        let expiresAt = now().addingTimeInterval(900)
        let sessionID = "us_\(UUID().uuidString.prefix(8))"
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
            uploadedAt: now(),
            contentSHA256: contentSHA256,
            captureQualityOverridden: quality.map { !$0.isAcceptable } ?? false
        )
        if storage.uploadSessions == nil {
            storage.uploadSessions = [:]
        }
        storage.uploadSessions?[sessionID] = StubUploadSession(
            documentID: documentID,
            expiresAt: expiresAt
        )
        return UploadSession(
            sessionID: sessionID,
            documentID: documentID,
            uploadURL: URL(string: "https://stub.invalid/upload")!,
            expiresAt: expiresAt
        )
        }
    }

    public func completeUpload(sessionID: String, idempotencyKey: String) async throws -> CaseDocument {
        await pause()
        return try idempotent(endpoint: "completeUpload", key: idempotencyKey, request: sessionID) {
        guard let uploadSession = storage.uploadSessions?[sessionID],
              let pending = storage.pendingUploads[uploadSession.documentID] else {
            throw ProblemDetails(type: "https://api.aperture.app/problems/not-found",
                                 title: "Upload session not found", status: 404)
        }
        guard uploadSession.expiresAt > now() else {
            throw ProblemDetails(
                type: "https://api.aperture.app/problems/upload-session-expired",
                title: "Upload session expired",
                status: 410,
                detail: "Create a new upload session and try again."
            )
        }
        storage.pendingUploads.removeValue(forKey: uploadSession.documentID)
        storage.uploadSessions?.removeValue(forKey: sessionID)
        let classified = CaseDocument(
            id: pending.id,
            folderID: pending.folderID,
            subjectPersonID: pending.subjectPersonID,
            originalName: pending.originalName,
            verifiedMimeType: pending.verifiedMimeType,
            sizeBytes: pending.sizeBytes,
            documentClass: .identity,
            documentSubtype: "PASSPORT",
            classificationBand: .likelyMatch,
            processingState: .extracted,
            detectedLanguage: "es",
            uploadedAt: pending.uploadedAt,
            contentSHA256: pending.contentSHA256,
            captureQualityOverridden: pending.captureQualityOverridden
        )
        storage.documents.append(classified)
        if let folderIndex = storage.folders.firstIndex(where: { $0.id == classified.folderID }) {
            let folder = storage.folders[folderIndex]
            storage.folders[folderIndex] = Folder(
                id: folder.id,
                name: folder.name,
                ownerUserID: folder.ownerUserID,
                persons: folder.persons,
                documentCount: folder.documentCount + 1,
                cases: folder.cases
            )
        }
        return classified
        }
    }

    public func reclassify(documentID: DocumentID, to documentClass: DocumentClass) async throws -> CaseDocument {
        await pause()
        guard let index = storage.documents.firstIndex(where: { $0.id == documentID }) else {
            throw ProblemDetails(type: "https://api.aperture.app/problems/not-found",
                                 title: "Not found", status: 404)
        }
        let existing = storage.documents[index]
        guard !existing.isOpaque || documentClass == .sealedMedical else {
            throw ProblemDetails(
                type: "https://api.aperture.app/problems/sealed-document-immutable",
                title: "A sealed medical document cannot be reopened or reprocessed",
                status: 409
            )
        }
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
            classificationBand: .humanConfirmed,
            classificationOverride: DocumentClassificationOverride(
                previousClass: existing.documentClass,
                selectedClass: documentClass,
                recordedAt: Date()
            ),
            processingState: documentClass.isOpaqueByPolicy
                ? .opaqueStored
                : documentClass == .openedMedicalExam
                    ? .extractionFailed
                    : existing.processingState == .needsClassification ? .extracted : existing.processingState,
            detectedLanguage: existing.detectedLanguage,
            uploadedAt: existing.uploadedAt,
            contentSHA256: existing.contentSHA256,
            isOpaque: documentClass.isOpaqueByPolicy,
            captureQualityOverridden: existing.captureQualityOverridden
        )
        storage.documents[index] = updated
        persist()
        return updated
    }

    public func deleteDocument(id: DocumentID) async throws {
        await pause()
        let folderID = storage.documents.first(where: { $0.id == id })?.folderID
        storage.documents.removeAll { $0.id == id }
        if let folderID,
           let folderIndex = storage.folders.firstIndex(where: { $0.id == folderID }) {
            let folder = storage.folders[folderIndex]
            storage.folders[folderIndex] = Folder(
                id: folder.id,
                name: folder.name,
                ownerUserID: folder.ownerUserID,
                persons: folder.persons,
                documentCount: max(0, folder.documentCount - 1),
                cases: folder.cases
            )
        }
        persist()
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
        let request = ConfirmValuesRequest(caseID: caseID, confirmations: confirmations)
        return try idempotent(endpoint: "confirmValues", key: idempotencyKey, request: request) {
        var prepared: [(value: FieldValue, history: [ValueHistoryEntry])] = []
        var seenFields: Set<String> = []
        for confirmation in confirmations {
            let fieldKey = "\(confirmation.personID.rawValue.utf8.count):\(confirmation.personID.rawValue)\(confirmation.canonicalPath.rawValue)"
            guard seenFields.insert(fieldKey).inserted else {
                throw ProblemDetails(
                    type: "https://api.aperture.app/problems/duplicate-confirmation",
                    title: "Field confirmed more than once",
                    status: 422,
                    detail: "Each field may appear only once in a confirmation batch."
                )
            }
            guard let field = storage.reviewable[caseID]?.first(where: {
                $0.subjectPersonID == confirmation.personID
                    && $0.canonicalPath == confirmation.canonicalPath
            }) else {
                throw ProblemDetails(
                    type: "https://api.aperture.app/problems/not-found",
                    title: "Field not found",
                    status: 404
                )
            }

            let now = Date()
            let previousValue = field.confirmed?.value ?? field.openProposal?.proposedValue
            let isCorrection = previousValue != nil && previousValue != confirmation.value
            let acceptsProposal = !isCorrection && field.openProposal != nil
            let provenance = acceptsProposal
                ? field.openProposal!.provenance
                : Provenance.manualEntry(by: currentUser, at: now)
            let origin: FieldValue.Origin = acceptsProposal
                ? Self.fieldOrigin(for: field.openProposal!.origin)
                : .manual
            let existingDiscrepancy = field.confirmed?.discrepancy
            if let resolutionID = confirmation.resolvesDiscrepancyID,
               existingDiscrepancy?.id != resolutionID {
                throw ProblemDetails(
                    type: "https://api.aperture.app/problems/discrepancy-not-found",
                    title: "Discrepancy not found",
                    status: 422,
                    detail: "The discrepancy resolution does not match this field."
                )
            }
            let unresolvedDiscrepancy = confirmation.resolvesDiscrepancyID == nil
                ? existingDiscrepancy
                : nil
            // Note the non-optional confirmedBy: this type cannot represent a value
            // that no human put there.
            let value = FieldValue(
                caseID: caseID,
                subjectPersonID: confirmation.personID,
                canonicalPath: confirmation.canonicalPath,
                value: confirmation.value,
                confidenceBand: acceptsProposal ? field.openProposal!.confidenceBand : .verified,
                origin: origin,
                provenance: provenance,
                acceptedProposalID: acceptsProposal ? field.openProposal?.id : nil,
                confirmedBy: currentUser,
                confirmedOnBehalfOf: confirmation.onBehalfOf,
                confirmedAt: now,
                discrepancy: unresolvedDiscrepancy
            )
            var historyEntries: [ValueHistoryEntry] = []
            if let proposal = field.openProposal {
                historyEntries.append(ValueHistoryEntry(
                    caseID: caseID,
                    subjectPersonID: confirmation.personID,
                    canonicalPath: confirmation.canonicalPath,
                    action: .proposalSuperseded,
                    value: proposal.proposedValue,
                    provenance: proposal.provenance,
                    confidenceBand: proposal.confidenceBand,
                    actorUserID: currentUser,
                    actorOnBehalfOf: confirmation.onBehalfOf,
                    sourceProposalID: proposal.id,
                    recordedAt: now
                ))
            }
            historyEntries.append(ValueHistoryEntry(
                caseID: caseID,
                subjectPersonID: confirmation.personID,
                canonicalPath: confirmation.canonicalPath,
                action: confirmation.resolvesDiscrepancyID == nil
                    ? (isCorrection ? .humanCorrected : .humanConfirmed)
                    : .discrepancyResolved,
                value: confirmation.value,
                previousValue: isCorrection ? previousValue : nil,
                provenance: provenance,
                confidenceBand: value.confidenceBand,
                actorUserID: currentUser,
                actorOnBehalfOf: confirmation.onBehalfOf,
                sourceProposalID: field.openProposal?.id,
                recordedAt: now
            ))

            prepared.append((value, historyEntries))
        }

        // Nothing above mutates storage. Apply only after the entire batch has
        // validated, preventing an invalid later item from partially committing it.
        for item in prepared {
            storage.applyConfirmation(
                caseID: caseID,
                value: item.value,
                historyEntries: item.history
            )
        }
        return prepared.map(\.value)
        }
    }

    public func resolveDiscrepancy(
        caseID: CaseID,
        discrepancyID: DiscrepancyID,
        chosenValue: String,
        note: String?,
        idempotencyKey: String
    ) async throws {
        await pause()
        let request = ResolveDiscrepancyRequest(
            caseID: caseID,
            discrepancyID: discrepancyID,
            chosenValue: chosenValue,
            note: note
        )
        _ = try idempotent(endpoint: "resolveDiscrepancy", key: idempotencyKey, request: request) {
            storage.clearDiscrepancy(
                caseID: caseID,
                discrepancyID: discrepancyID,
                chosen: chosenValue,
                by: currentUser
            )
            return StubEmptyResponse()
        }
    }

    public func valueHistory(
        caseID: CaseID,
        personID: PersonID,
        canonicalPath: CanonicalPath
    ) async throws -> [ValueHistoryEntry] {
        await pause()
        storage.ensureValueHistory(caseID: caseID)
        persist()
        return (storage.valueHistory?[caseID] ?? [])
            .filter { $0.subjectPersonID == personID && $0.canonicalPath == canonicalPath }
            .sorted { $0.recordedAt > $1.recordedAt }
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
        accessibilityProfileEnabled: Bool,
        idempotencyKey: String
    ) async throws -> InterviewSession {
        await pause()
        let request = StartInterviewRequest(
            caseID: caseID,
            personID: personID,
            batchID: batchID,
            modality: modality,
            consent: consent,
            accessibilityProfileEnabled: accessibilityProfileEnabled
        )
        return try idempotent(endpoint: "startInterview", key: idempotencyKey, request: request) {
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
            budget: modality == .voice ? VoiceBudget(
                secondsRemaining: 1800,
                targetSeconds: 420,
                isWaived: accessibilityProfileEnabled
            ) : nil,
            startedAt: Date()
        )
        storage.sessions[session.id] = session
        return session
        }
    }

    public func sendInterviewMessage(
        sessionID: SessionID,
        text: String,
        idempotencyKey: String
    ) async throws -> [InterviewTurn] {
        await pause()
        let request = SendInterviewMessageRequest(sessionID: sessionID, text: text)
        return try idempotent(endpoint: "sendInterviewMessage", key: idempotencyKey, request: request) {
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
    }

    public func endInterview(sessionID: SessionID) async throws {
        await pause()
        storage.sessions.removeValue(forKey: sessionID)
        persist()
    }

    // MARK: Package and export

    public func packageGenerationReadiness(caseID: CaseID) async throws -> PackageGenerationReadiness {
        await pause()
        return PackageGenerationReadiness(requiredFields: storage.reviewable[caseID] ?? [])
    }

    public func requestPackageGeneration(
        caseID: CaseID,
        idempotencyKey: String
    ) async throws -> GeneratedPackage {
        await pause()
        return try idempotent(endpoint: "requestPackageGeneration", key: idempotencyKey, request: caseID) {
        let readiness = PackageGenerationReadiness(requiredFields: storage.reviewable[caseID] ?? [])
        guard readiness.canGenerate else {
            throw ProblemDetails(
                type: "https://api.aperture.app/problems/human-confirmation-required",
                title: "Review required before forms can be made",
                status: 409,
                detail: "Every required value must be confirmed by a human and every discrepancy resolved.",
                errors: [
                    FieldProblem(
                        field: "requiredFields",
                        reason: "\(readiness.unconfirmedRequiredFields) required fields are not confirmed",
                        resolutionPath: "aperture://cases/\(caseID)/review"
                    ),
                    FieldProblem(
                        field: "openProposals",
                        reason: "\(readiness.openProposals) proposals still need a human decision",
                        resolutionPath: "aperture://cases/\(caseID)/review"
                    ),
                    FieldProblem(
                        field: "blockingDiscrepancies",
                        reason: "\(readiness.blockingDiscrepancies) discrepancies are unresolved",
                        resolutionPath: "aperture://cases/\(caseID)/review"
                    )
                ]
            )
        }
        guard let package = storage.packages[caseID] else {
            throw ProblemDetails(
                type: "https://api.aperture.app/problems/generation-unavailable",
                title: "Package generation is not available in the local fixture",
                status: 501
            )
        }
        return package
        }
    }

    public func generatedPackage(caseID: CaseID) async throws -> GeneratedPackage? {
        await pause()
        return storage.packages[caseID]
    }

    private static func fieldOrigin(for proposalOrigin: ValueProposal.Origin) -> FieldValue.Origin {
        switch proposalOrigin {
        case .extraction: .extraction
        case .interview: .interview
        case .derived: .derived
        }
    }

    public func export(
        packageID: PackageID,
        channel: ExportChannel,
        recipientEmail: String?,
        idempotencyKey: String
    ) async throws -> DeliveryLink? {
        await pause()
        let request = ExportRequest(
            packageID: packageID,
            channel: channel,
            recipientEmail: recipientEmail
        )
        return try idempotent(endpoint: "export", key: idempotencyKey, request: request) {
            guard channel == .secureLink else { return nil }
            return DeliveryLink(
                id: "ex_\(UUID().uuidString.prefix(8))",
                expiresAt: Date().addingTimeInterval(72 * 3600),
                maxDownloads: 3,
                downloadCount: 0,
                revoked: false
            )
        }
    }

    // MARK: Inbox and consent

    public func inbox() async throws -> [InboxItem] {
        await pause()
        return storage.inbox.sorted { $0.createdAt > $1.createdAt }
    }

    public func markRead(notificationID: NotificationID) async throws {
        guard let index = storage.inbox.firstIndex(where: { $0.id == notificationID }) else { return }
        storage.inbox[index].readAt = Date()
        persist()
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
        persist()
        return record
    }
}

private struct CreateCaseRequest: Codable {
    struct RoleAssignment: Codable {
        let personID: PersonID
        let role: String
    }

    let folderID: FolderID
    let packageCode: String
    let roleAssignments: [RoleAssignment]
    let attestation: SelectionAttestation

    init(
        folderID: FolderID,
        packageCode: String,
        roleAssignments: [PersonID: String],
        attestation: SelectionAttestation
    ) {
        self.folderID = folderID
        self.packageCode = packageCode
        self.roleAssignments = roleAssignments
            .map { RoleAssignment(personID: $0.key, role: $0.value) }
            .sorted { $0.personID.rawValue < $1.personID.rawValue }
        self.attestation = attestation
    }
}

private struct CreateUploadSessionRequest: Codable {
    let folderID: FolderID
    let subjectPersonID: PersonID?
    let originalName: String
    let sizeBytes: Int64
    let source: DocumentSource
    let quality: CaptureQuality?
    let contentSHA256: String
}

private struct ConfirmValuesRequest: Codable {
    let caseID: CaseID
    let confirmations: [ValueConfirmation]
}

private struct ResolveDiscrepancyRequest: Codable {
    let caseID: CaseID
    let discrepancyID: DiscrepancyID
    let chosenValue: String
    let note: String?
}

private struct StartInterviewRequest: Codable {
    let caseID: CaseID
    let personID: PersonID
    let batchID: BatchID
    let modality: InterviewModality
    let consent: VoiceConsent?
    let accessibilityProfileEnabled: Bool
}

private struct SendInterviewMessageRequest: Codable {
    let sessionID: SessionID
    let text: String
}

private struct ExportRequest: Codable {
    let packageID: PackageID
    let channel: ExportChannel
    let recipientEmail: String?
}

private struct StubEmptyResponse: Codable {}

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
