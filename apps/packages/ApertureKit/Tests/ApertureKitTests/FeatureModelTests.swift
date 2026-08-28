import Foundation
import Testing
import ApertureDomain
import ApertureAPI
import ApertureUI

/// Every method fails the same way, so a test can hand a screen model exactly the
/// error class it is about: a transport failure, or the cancellation SwiftUI's
/// `.task` delivers when a screen disappears mid-request.
private struct ThrowingAPIClient: ApertureAPIClient {
    enum Mode: Sendable { case transport, cancellation }
    let mode: Mode

    private func fail<T>() throws -> T {
        switch mode {
        case .transport: throw URLError(.notConnectedToInternet)
        case .cancellation: throw CancellationError()
        }
    }

    func authenticatedContext() async throws -> AuthenticatedContext { try fail() }
    func clientDirectory(query: String?, cursor: String?) async throws -> ClientDirectoryPage { try fail() }
    func createClient(label: String, idempotencyKey: String) async throws -> ClientDirectoryEntry { try fail() }
    func folders() async throws -> [Folder] { try fail() }
    func folder(id: FolderID) async throws -> Folder { try fail() }
    func createFolder(name: String, idempotencyKey: String) async throws -> Folder { try fail() }
    func createPerson(folderID: FolderID, displayLabel: String, isMinor: Bool, relationships: [Relationship], idempotencyKey: String) async throws -> Person { try fail() }
    func caseSummary(id: CaseID) async throws -> CaseSummary { try fail() }
    func progress(caseID: CaseID) async throws -> ProgressCounters { try fail() }
    func catalogPackages(query: String?) async throws -> [FormPackage] { try fail() }
    func requirements(packageCode: String) async throws -> RequirementSet { try fail() }
    func createCase(folderID: FolderID, packageCode: String, roleAssignments: [PersonID: String], attestation: SelectionAttestation, idempotencyKey: String) async throws -> CaseSummary { try fail() }
    func documents(folderID: FolderID) async throws -> [CaseDocument] { try fail() }
    func createUploadSession(folderID: FolderID, subjectPersonID: PersonID?, originalName: String, sizeBytes: Int64, source: DocumentSource, quality: CaptureQuality?, contentSHA256: String, idempotencyKey: String) async throws -> UploadSession { try fail() }
    func completeUpload(sessionID: String, idempotencyKey: String) async throws -> CaseDocument { try fail() }
    func reclassify(documentID: DocumentID, to documentClass: DocumentClass) async throws -> CaseDocument { try fail() }
    func deleteDocument(id: DocumentID) async throws { try fail() as Void }
    func reviewableFields(caseID: CaseID) async throws -> [ReviewableField] { try fail() }
    func confirmValues(caseID: CaseID, confirmations: [ValueConfirmation], idempotencyKey: String) async throws -> [FieldValue] { try fail() }
    func resolveDiscrepancy(caseID: CaseID, discrepancyID: DiscrepancyID, chosenValue: String, note: String?, idempotencyKey: String) async throws { try fail() as Void }
    func valueHistory(caseID: CaseID, personID: PersonID, canonicalPath: CanonicalPath) async throws -> [ValueHistoryEntry] { try fail() }
    func missingItems(caseID: CaseID) async throws -> (items: [MissingItem], batches: [MissingItemBatch]) { try fail() }
    func guidedFinishPlan(caseID: CaseID, minutes: Int) async throws -> GuidedFinishPlan { try fail() }
    func proofMap(caseID: CaseID) async throws -> ProofMap { try fail() }
    func documentPagePreview(documentID: DocumentID, pageNumber: Int) async throws -> DocumentPagePreview { try fail() }
    func evidenceRelays(caseID: CaseID) async throws -> [EvidenceRelay] { try fail() }
    func createEvidenceRelay(caseID: CaseID, missingItemID: MissingItemID, idempotencyKey: String) async throws -> CreateEvidenceRelayResult { try fail() }
    func revokeEvidenceRelay(relayID: EvidenceRelayID, idempotencyKey: String) async throws -> EvidenceRelay { try fail() }
    func acceptEvidenceRelay(relayID: EvidenceRelayID, idempotencyKey: String) async throws -> EvidenceRelay { try fail() }
    func rejectEvidenceRelay(relayID: EvidenceRelayID, idempotencyKey: String) async throws -> EvidenceRelay { try fail() }
    func startInterview(caseID: CaseID, personID: PersonID, batchID: BatchID, modality: InterviewModality, consent: VoiceConsent?, accessibilityProfileEnabled: Bool, idempotencyKey: String) async throws -> InterviewSession { try fail() }
    func sendInterviewMessage(sessionID: SessionID, text: String, idempotencyKey: String) async throws -> [InterviewTurn] { try fail() }
    func endInterview(sessionID: SessionID) async throws { try fail() as Void }
    func packageGenerationReadiness(caseID: CaseID) async throws -> PackageGenerationReadiness { try fail() }
    func requestPackageGeneration(caseID: CaseID, idempotencyKey: String) async throws -> GeneratedPackage { try fail() }
    func generatedPackage(caseID: CaseID) async throws -> GeneratedPackage? { try fail() }
    func export(packageID: PackageID, channel: ExportChannel, recipientEmail: String?, idempotencyKey: String) async throws -> PackageExportResult { try fail() }
    func inbox() async throws -> [InboxItem] { try fail() }
    func markRead(notificationID: NotificationID) async throws { try fail() as Void }
    func consents() async throws -> [ConsentRecord] { try fail() }
    func setConsent(purpose: ConsentRecord.Purpose, granted: Bool) async throws -> ConsentRecord { try fail() }
    func caseWorkspace(caseID: CaseID) async throws -> CaseWorkspace { try fail() }
    func setAssignments(caseID: CaseID, assignments: CaseAssignments, idempotencyKey: String) async throws -> CaseAssignments { try fail() }
    func transition(caseID: CaseID, to state: CaseState, idempotencyKey: String) async throws -> CaseSummary { try fail() }
    func commitSection(caseID: CaseID, sectionID: String, baseRevision: Int, values: [String: String], idempotencyKey: String) async throws -> SectionCommit { try fail() }
    func linkEvidence(caseID: CaseID, requirementCode: String, documentID: DocumentID, idempotencyKey: String) async throws -> EvidenceRequirementItem { try fail() }
    func reviewQueue() async throws -> [ReviewQueueItem] { try fail() }
    func recordReviewDecision(caseID: CaseID, outcome: ReviewOutcome, note: String?, idempotencyKey: String) async throws -> ReviewDecision { try fail() }
    func draftPreview(caseID: CaseID) async throws -> DraftFormPreview { try fail() }
    func approve(caseID: CaseID, preview: DraftFormPreview, stepUpChallenge: String, attested: Bool, idempotencyKey: String) async throws -> ApprovalRecord { try fail() }
    func caseHistory(caseID: CaseID) async throws -> [CaseHistoryEvent] { try fail() }
    func adminMembers() async throws -> [AdminMember] { try fail() }
    func activeWorkspaceSessions() async throws -> [ActiveWorkspaceSession] { try fail() }
    func auditSummary() async throws -> AuditSummary { try fail() }
    func demoWorkspaceState() async throws -> DemoWorkspaceState { try fail() }
    func resetDemoWorkspace(idempotencyKey: String) async throws -> DemoWorkspaceState { try fail() }
}

/// The screen models the app's feature views drive. Each test exercises the same
/// transitions the view triggers from `.task`, `.refreshable`, or a button, against
/// either the seeded stub fixture or a client that fails deterministically — so the
/// state a view renders from is proven at package speed instead of only through a
/// scheduled simulator journey.
@MainActor
@Suite("Feature screen models")
struct FeatureModelTests {
    private let seededCase = CaseID("c_ramirez_i130")
    private let readyCase = CaseID("c_demo_ready")

    private func stub() async -> StubAPIClient {
        let api = StubAPIClient()
        await api.setDelay(.zero)
        return api
    }

    // MARK: Home

    @Test("Home surfaces exactly the cases with blocking items, in folder order")
    func homeSurfacesOnlyBlockedCases() async throws {
        let api = await stub()
        let model = HomeModel()
        await model.load(api: api)

        #expect(model.phase == .loaded)
        let expected = model.folders.flatMap { folder in
            folder.cases.filter { $0.counters.blockingItems > 0 }
        }
        // The seeded fixture must contain at least one blocked case, or this test
        // proves nothing about the filter.
        #expect(!expected.isEmpty)
        #expect(model.attentionItems.map(\.id) == expected.map(\.id.rawValue))
        for (item, summary) in zip(model.attentionItems, expected) {
            #expect(item.blockingCount == summary.counters.blockingItems)
            #expect(item.title == summary.packageTitle)
        }
    }

    @Test("A home load failure reads as failed, not as an empty dashboard")
    func homeLoadFailureReadsAsFailed() async {
        let model = HomeModel()
        await model.load(api: ThrowingAPIClient(mode: .transport))
        #expect(model.phase == .failed)
        #expect(model.folders.isEmpty)
        #expect(model.attentionItems.isEmpty)
    }

    // MARK: Catalog

    @Test("Catalog groups sort by category order and preserve every package")
    func catalogGroupsDeterministically() async throws {
        let api = await stub()
        let model = CatalogModel()
        await model.load(api: api, query: "")

        let packages = try #require(model.state.value)
        let groups = model.categoryGroups
        #expect(!groups.isEmpty)
        #expect(groups.reduce(0) { $0 + $1.packages.count } == packages.count)
        let orders = groups.map { ($0.category.sortOrder, $0.category.title, $0.category.code) }
        #expect(zip(orders, orders.sorted(by: <)).allSatisfy { $0 == $1 })
    }

    @Test("A search with no matches is empty, never failed")
    func catalogNoMatchesReadsAsEmpty() async {
        let api = await stub()
        let model = CatalogModel()
        await model.load(api: api, query: "zzzz-no-such-package")
        #expect(model.state == .empty)
        #expect(!model.isStale)
    }

    @Test("A refresh failure keeps the last result on screen and marks it stale")
    func catalogKeepsStaleResultOnRefreshFailure() async throws {
        let api = await stub()
        let model = CatalogModel()
        await model.load(api: api, query: "")
        let loadedCount = try #require(model.state.value?.count)

        await model.load(api: ThrowingAPIClient(mode: .transport), query: "")
        #expect(model.isStale)
        #expect(model.state.value?.count == loadedCount)

        await model.load(api: api, query: "")
        #expect(!model.isStale)
        #expect(model.state.value?.count == loadedCount)
    }

    @Test("A first-load failure is failed; a cancelled first load stays loading for the next task")
    func catalogFirstLoadFailureAndCancellation() async {
        let failed = CatalogModel()
        await failed.load(api: ThrowingAPIClient(mode: .transport), query: "")
        #expect(failed.state == .failed)

        // `.task(id: query)` cancels the in-flight load on every keystroke; the
        // replacement task owns the next transition, so cancellation changes nothing.
        let cancelled = CatalogModel()
        await cancelled.load(api: ThrowingAPIClient(mode: .cancellation), query: "")
        #expect(cancelled.state == .loading)
        #expect(!cancelled.isStale)
    }

    // MARK: Review

    @Test("Review groups fields by their subject person, labeled and sorted")
    func reviewGroupsFieldsByPerson() async throws {
        let api = await stub()
        let model = ReviewModel()
        await model.load(api: api, caseID: seededCase)

        let fields = try #require(model.state.value)
        let groups = model.groupedByPerson
        #expect(groups.reduce(0) { $0 + $1.fields.count } == fields.count)
        #expect(groups.map(\.person) == groups.map(\.person).sorted())
        for group in groups {
            let subjectIDs = Set(group.fields.map(\.subjectPersonID))
            #expect(subjectIDs.count == 1)
            if let subject = subjectIDs.first {
                #expect(model.personLabels[subject] == group.person)
            }
        }
    }

    @Test("A review load failure clears person labels instead of showing stale names")
    func reviewLoadFailureClearsLabels() async throws {
        let api = await stub()
        let model = ReviewModel()
        await model.load(api: api, caseID: seededCase)
        #expect(!model.personLabels.isEmpty)

        await model.load(api: ThrowingAPIClient(mode: .transport), caseID: seededCase)
        #expect(model.state == .failed)
        #expect(model.personLabels.isEmpty)
    }

    // MARK: Package

    @Test("A blocked case cannot generate through the model, and refusing is not a failure")
    func packageBlockedCaseCannotGenerate() async throws {
        let api = await stub()
        let model = PackageModel()
        await model.load(api: api, caseID: seededCase)

        let content = try #require(model.state.value)
        #expect(content.generated == nil)
        #expect(!content.readiness.canGenerate)

        let generated = await model.generate(api: api, caseID: seededCase)
        #expect(!generated)
        #expect(!model.generationFailed)
        #expect(model.state.value?.generated == nil)
    }

    @Test("Generation succeeds exactly once through the model and existing output is surfaced")
    func packageGeneratesOnceAndSurfacesExistingOutput() async throws {
        let api = await stub()
        let model = PackageModel()
        // `c_demo_ready` ships pre-generated: the load path must surface the existing
        // package rather than offer generation again.
        await model.load(api: api, caseID: readyCase)
        let loaded = try #require(model.state.value)
        #expect(loaded.generated != nil)
        // With output already on screen, generate must refuse without touching state.
        #expect(await model.generate(api: api, caseID: readyCase) == false)
        #expect(!model.generationFailed)

        // The model's own success path, from a ready state with no output yet. The
        // stub accepts generation for this case, so this proves the model stores the
        // result, reports success, and then refuses a second request.
        let clean = PackageGenerationReadiness(
            unconfirmedRequiredFields: 0,
            openProposals: 0,
            blockingDiscrepancies: 0
        )
        model.state = .loaded(PackageModel.Content(generated: nil, readiness: clean))
        #expect(await model.generate(api: api, caseID: readyCase))
        #expect(model.state.value?.generated != nil)
        #expect(!model.generationFailed)
        #expect(await model.generate(api: api, caseID: readyCase) == false)
    }

    @Test("A generation transport failure keeps the readiness verdict on screen")
    func packageGenerationFailureKeepsReadiness() async throws {
        let model = PackageModel()
        let readiness = PackageGenerationReadiness(
            unconfirmedRequiredFields: 0,
            openProposals: 0,
            blockingDiscrepancies: 0
        )
        model.state = .loaded(PackageModel.Content(generated: nil, readiness: readiness))

        let generated = await model.generate(
            api: ThrowingAPIClient(mode: .transport),
            caseID: readyCase
        )
        #expect(!generated)
        #expect(model.generationFailed)
        // A transport failure is not evidence that review became incomplete: the
        // last readiness result must survive so the screen never claims "not ready".
        let content = try #require(model.state.value)
        #expect(content.generated == nil)
        #expect(content.readiness.canGenerate)
    }

    // MARK: Missing items

    @Test("Missing items split by severity and a batch resolves to its subject person")
    func missingItemsSplitAndBatchSubject() async throws {
        let api = await stub()
        let model = MissingItemsModel()
        await model.load(api: api, caseID: seededCase)

        #expect(model.hasLoaded)
        #expect(!model.loadFailed)
        #expect(model.required.allSatisfy { $0.severity == .blocking })
        #expect(model.advisory.allSatisfy { $0.severity == .advisory })

        let (items, batches) = try await api.missingItems(caseID: seededCase)
        #expect(model.required.count + model.advisory.count == items.count)

        // The batch subject comes from the batch's own items (ADR-007) — the T-42
        // regression was exactly this resolution hard-coding a fixture person.
        let batch = try #require(batches.first)
        let expectedSubject = try #require(items.first { $0.batchID == batch.id }?.assignedPersonID)
        #expect(model.personID(forBatch: batch.id) == expectedSubject)
        #expect(model.personID(forBatch: BatchID("mi_batch_nonexistent")) == nil)
    }

    @Test("A missing-items load failure is recoverable by a successful retry")
    func missingItemsFailureThenRetryRecovers() async {
        let model = MissingItemsModel()
        await model.load(api: ThrowingAPIClient(mode: .transport), caseID: seededCase)
        #expect(model.loadFailed)
        #expect(!model.hasLoaded)

        let api = await stub()
        await model.load(api: api, caseID: seededCase)
        #expect(!model.loadFailed)
        #expect(model.hasLoaded)
    }

    // MARK: Interview

    @Test("An interview starts, carries the scripted turns, and sends without a phantom failure")
    func interviewStartsAndSends() async throws {
        let api = await stub()
        let model = InterviewModel()
        await model.start(
            api: api,
            caseID: seededCase,
            personID: PersonID("p_carlos"),
            batchID: BatchID("mi_batch_017"),
            modality: .form,
            consent: nil
        )
        #expect(model.session != nil)
        #expect(model.failure == nil)
        #expect(!model.budgetExhausted)

        let turnsBefore = model.turns.count
        #expect(await model.send(api: api, text: "Begin structured questions"))
        #expect(model.turns.count > turnsBefore)
        #expect(model.failure == nil)
    }

    @Test("Start and send failures are reported distinctly and never as budget exhaustion")
    func interviewFailuresAreDistinct() async throws {
        let failing = ThrowingAPIClient(mode: .transport)
        let model = InterviewModel()
        await model.start(
            api: failing,
            caseID: seededCase,
            personID: PersonID("p_carlos"),
            batchID: BatchID("mi_batch_017"),
            modality: .form,
            consent: nil
        )
        #expect(model.session == nil)
        #expect(model.failure == .startFailed)
        #expect(!model.budgetExhausted)

        // A send with no session is a start problem, not a send problem.
        let sessionless = InterviewModel()
        #expect(await sessionless.send(api: failing, text: "hello") == false)
        #expect(sessionless.failure == .startFailed)

        // A transport failure after a healthy start reads as a send failure, and a
        // retry of the same text against a healthy client recovers.
        let api = await stub()
        let retrying = InterviewModel()
        await retrying.start(
            api: api,
            caseID: seededCase,
            personID: PersonID("p_carlos"),
            batchID: BatchID("mi_batch_017"),
            modality: .form,
            consent: nil
        )
        #expect(await retrying.send(api: failing, text: "Begin structured questions") == false)
        #expect(retrying.failure == .sendFailed)
        #expect(await retrying.send(api: api, text: "Begin structured questions"))
        #expect(retrying.failure == nil)
    }

    // MARK: Client dashboard

    @Test("The client dashboard loads folders and reads a failure as failed")
    func clientDashboardLoadsAndFails() async throws {
        let api = await stub()
        let model = ClientDashboardModel()
        await model.load(api: api)
        #expect(model.phase == .loaded)
        #expect(!model.folders.isEmpty)

        let failed = ClientDashboardModel()
        await failed.load(api: ThrowingAPIClient(mode: .transport))
        #expect(failed.phase == .failed)
        #expect(failed.folders.isEmpty)
    }

    // MARK: Guided Finish

    @Test("Guided Finish loads the plan with every cited item resolvable")
    func guidedFinishLoadsPlanAndItems() async throws {
        let api = await stub()
        let model = GuidedFinishModel()
        await model.load(api: api, caseID: seededCase, minutes: 10)

        let plan = try #require(model.state.value)
        #expect(plan.minutesBudget == 10)
        for step in plan.steps where step.batchID == nil {
            for itemID in step.itemIDs {
                #expect(model.items[itemID] != nil)
            }
        }

        let failed = GuidedFinishModel()
        await failed.load(api: ThrowingAPIClient(mode: .transport), caseID: seededCase, minutes: 10)
        #expect(failed.state == .failed)
    }
}
