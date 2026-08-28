import Foundation
import Testing
import ApertureDomain
@testable import ApertureAPI

/// T-62. Confirmed fields say nothing about whether the documents the agency
/// requires were ever collected, and a case's own state can forbid producing
/// filing output no matter how complete its data looks. These prove the gate
/// counts both, and that generating never rewrites a blocker to zero.
@Suite("Package generation gate")
struct PackageGenerationGateTests {

    private let seededCase = CaseID("c_ramirez_i130")

    private func makeClient() async -> StubAPIClient {
        let api = StubAPIClient()
        await api.setDelay(.zero)
        return api
    }

    /// Confirms every reviewable field, which is all the gate used to require.
    private func confirmEveryField(_ api: StubAPIClient, caseID: CaseID) async throws {
        let fields = try await api.reviewableFields(caseID: caseID)
        let confirmations = fields.map { field in
            ValueConfirmation(
                personID: field.subjectPersonID,
                canonicalPath: field.canonicalPath,
                value: field.displayValue ?? "Applicant response",
                resolvesDiscrepancyID: field.confirmed?.discrepancy?.id
            )
        }
        _ = try await api.confirmValues(
            caseID: caseID,
            confirmations: confirmations,
            idempotencyKey: "gate-confirm-\(caseID.rawValue)"
        )
    }

    private func linkBlockingEvidence(_ api: StubAPIClient, caseID: CaseID) async throws {
        let outstanding = try await api.missingItems(caseID: caseID).items
            .filter { $0.kind == .evidence && $0.severity == .blocking }
        for (offset, item) in outstanding.enumerated() {
            _ = try await api.linkEvidence(
                caseID: caseID,
                requirementCode: try #require(item.requirementCode),
                documentID: DocumentID("d_greencard"),
                idempotencyKey: "gate-link-\(caseID.rawValue)-\(offset)"
            )
        }
    }

    @Test("A fully confirmed case with documents outstanding cannot generate")
    func confirmedFieldsDoNotSubstituteForEvidence() async throws {
        let api = await makeClient()
        try await confirmEveryField(api, caseID: seededCase)

        let readiness = try await api.packageGenerationReadiness(caseID: seededCase)
        #expect(readiness.unconfirmedRequiredFields == 0)
        #expect(readiness.openProposals == 0)
        #expect(readiness.blockingDiscrepancies == 0)
        // The contradiction this task was raised for: everything a human could
        // confirm is confirmed, and the case still owes a mandatory document.
        #expect(readiness.outstandingBlockingEvidence > 0)
        #expect(!readiness.canGenerate)

        do {
            _ = try await api.requestPackageGeneration(
                caseID: seededCase,
                idempotencyKey: "evidence-outstanding"
            )
            Issue.record("Generation must refuse a case with mandatory evidence outstanding")
        } catch let problem as ProblemDetails {
            #expect(problem.status == 409)
            #expect(problem.type.hasSuffix("evidence-incomplete"))
            #expect(problem.errors?.first?.field == "outstandingBlockingEvidence")
            #expect(problem.errors?.first?.resolutionPath?.contains("missing-items") == true)
        }
    }

    @Test("Collecting the required document opens the gate")
    func linkingEvidenceOpensTheGate() async throws {
        let api = await makeClient()
        try await confirmEveryField(api, caseID: seededCase)
        try await linkBlockingEvidence(api, caseID: seededCase)

        let readiness = try await api.packageGenerationReadiness(caseID: seededCase)
        #expect(readiness.outstandingBlockingEvidence == 0)
        #expect(readiness.canGenerate)
        let package = try await api.requestPackageGeneration(
            caseID: seededCase,
            idempotencyKey: "evidence-satisfied"
        )
        #expect(package.verification.passed)
    }

    @Test("Generating records output; it never rewrites a blocker to zero")
    func generationDoesNotFalsifyCounters() async throws {
        let api = await makeClient()
        try await confirmEveryField(api, caseID: seededCase)
        try await linkBlockingEvidence(api, caseID: seededCase)
        _ = try await api.requestPackageGeneration(
            caseID: seededCase,
            idempotencyKey: "counter-truthfulness"
        )

        let summary = try await api.caseSummary(id: seededCase)
        #expect(summary.state == .generated)
        // Previously this wrote fieldsFilled == fieldsRequired and blockingItems
        // == 0 unconditionally, so a generated case claimed completeness its own
        // document counters contradicted.
        let (items, _) = try await api.missingItems(caseID: seededCase)
        #expect(summary.counters.blockingItems == items.filter { $0.severity == .blocking }.count)
        #expect(summary.counters.advisoryItems == items.filter { $0.severity == .advisory }.count)
        #expect(summary.counters.fieldsFilled <= summary.counters.fieldsRequired)
        #expect(summary.counters.documentsCollected <= summary.counters.documentsRequired)
        // The folder's copy of the case must tell the same story as the case.
        let folderCopy = try #require(
            try await api.folder(id: summary.folderID).cases.first { $0.id == seededCase }
        )
        #expect(folderCopy.counters == summary.counters)
        #expect(folderCopy.state == .generated)
    }

    @Test("A reviewer's open change request forbids generating over it")
    func caseStateForbidsGeneration() async throws {
        let api = await makeClient()
        try await confirmEveryField(api, caseID: seededCase)
        try await linkBlockingEvidence(api, caseID: seededCase)
        #expect(try await api.packageGenerationReadiness(caseID: seededCase).canGenerate)

        for (offset, state) in [CaseState.validating, .inReview, .changesRequested].enumerated() {
            _ = try await api.transition(
                caseID: seededCase,
                to: state,
                idempotencyKey: "gate-state-\(offset)"
            )
        }

        let readiness = try await api.packageGenerationReadiness(caseID: seededCase)
        #expect(!readiness.caseStateAllowsGeneration)
        #expect(!readiness.canGenerate)
        do {
            _ = try await api.requestPackageGeneration(
                caseID: seededCase,
                idempotencyKey: "state-forbidden"
            )
            Issue.record("Generation must refuse while a reviewer's change request is open")
        } catch let problem as ProblemDetails {
            #expect(problem.status == 409)
            #expect(problem.type.hasSuffix("case-state-forbids-generation"))
        }
    }

    @Test("Only real blockers are reported as problems")
    func refusalNamesOnlyActualBlockers() async throws {
        let api = await makeClient()
        // Untouched, the seeded case owes confirmations, a decision, and an
        // adjudication — all three are real, so all three are named.
        do {
            _ = try await api.requestPackageGeneration(
                caseID: seededCase,
                idempotencyKey: "all-three"
            )
            Issue.record("Expected the untouched seeded case to be refused")
        } catch let problem as ProblemDetails {
            #expect(problem.errors?.count == 3)
        }

        // With the fields settled, the refusal must not still claim zero
        // discrepancies are unresolved as though it were a failure.
        try await confirmEveryField(api, caseID: seededCase)
        do {
            _ = try await api.requestPackageGeneration(
                caseID: seededCase,
                idempotencyKey: "evidence-only"
            )
            Issue.record("Expected an evidence refusal")
        } catch let problem as ProblemDetails {
            #expect(problem.errors?.count == 1)
            #expect(problem.errors?.first?.field == "outstandingBlockingEvidence")
        }
    }

    @Test("Every state that forbids generation says so")
    func statePolicyIsExplicit() {
        // Form drift is the load-bearing one: the pinned edition is known stale,
        // so no amount of confirmed data makes filling it legitimate.
        #expect(!CaseState.quarantinedFormDrift.allowsPackageGeneration)
        #expect(!CaseState.onHold.allowsPackageGeneration)
        #expect(!CaseState.abandoned.allowsPackageGeneration)
        #expect(!CaseState.closed.allowsPackageGeneration)
        #expect(!CaseState.changesRequested.allowsPackageGeneration)
        #expect(CaseState.collecting.allowsPackageGeneration)
        #expect(CaseState.approved.allowsPackageGeneration)
    }

    @Test("An unprepared case is not vacuously ready")
    func absentFieldSetIsNotReady() async throws {
        let api = await makeClient()
        let folder = try await api.createFolder(name: "Empty", idempotencyKey: "gate-folder")
        let created = try await api.createCase(
            folderID: folder.id,
            packageCode: "ADJUSTMENT_I485_I864",
            roleAssignments: [:],
            attestation: SelectionAttestation(
                attested: true, attestationVersion: "2026.03", text: "I chose these forms."
            ),
            idempotencyKey: "gate-shell"
        )
        let readiness = try await api.packageGenerationReadiness(caseID: created.id)
        #expect(readiness.unconfirmedRequiredFields == created.counters.fieldsRequired)
        #expect(!readiness.canGenerate)
    }
}
