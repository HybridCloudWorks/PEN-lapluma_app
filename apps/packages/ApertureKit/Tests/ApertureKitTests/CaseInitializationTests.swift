import Foundation
import Testing
import ApertureDomain
@testable import ApertureAPI

/// T-61: a newly created case must be born with the structure its form package
/// requires — reviewable fields, missing items, an interview batch — instead of
/// as a shell only the hand-seeded fixture could escape. The first test is the
/// task's own acceptance criterion: selection through generation with no
/// pre-seeded case anywhere in the path.
@Suite("Case initialization from the form package")
struct CaseInitializationTests {

    private func makeClient() async -> StubAPIClient {
        let api = StubAPIClient()
        await api.setDelay(.zero)
        return api
    }

    private func attestation() -> SelectionAttestation {
        SelectionAttestation(
            attested: true,
            attestationVersion: "2026.03",
            text: "I chose these forms."
        )
    }

    @Test("A new I-130 case travels from selection to generation without the seeded case")
    func newCaseTravelsSelectionThroughGeneration() async throws {
        let api = await makeClient()

        let created = try await api.createCase(
            folderID: FolderID("f_ramirez"),
            packageCode: "FAMILY_I130",
            roleAssignments: [:],
            attestation: attestation(),
            idempotencyKey: "t61-journey"
        )
        #expect(created.id != CaseID("c_ramirez_i130"))

        // Born with structure: fields to review, gaps to close, a batch to sit
        // down with — none of them borrowed from the seeded fixture.
        let fields = try await api.reviewableFields(caseID: created.id)
        try #require(!fields.isEmpty)
        #expect(fields.allSatisfy { $0.confirmed == nil && $0.openProposal == nil })

        let (items, batches) = try await api.missingItems(caseID: created.id)
        let fieldItems = items.filter { $0.kind == .field }
        #expect(fieldItems.count == fields.count)
        #expect(items.contains { $0.kind == .evidence })
        let batch = try #require(batches.first)
        #expect(batch.itemCount == fieldItems.count)
        #expect(fieldItems.allSatisfy { $0.batchID == batch.id })

        // A case with everything unconfirmed must not generate.
        let before = try await api.packageGenerationReadiness(caseID: created.id)
        #expect(!before.canGenerate)

        // A human confirms every required value — the only path the platform
        // permits — and the field-kind gaps reconcile away.
        for (offset, field) in fields.enumerated() {
            _ = try await api.confirmValues(
                caseID: created.id,
                confirmations: [ValueConfirmation(
                    personID: field.subjectPersonID,
                    canonicalPath: field.canonicalPath,
                    value: "answer-\(offset)"
                )],
                idempotencyKey: "t61-confirm-\(offset)"
            )
        }
        let (afterItems, _) = try await api.missingItems(caseID: created.id)
        #expect(afterItems.allSatisfy { $0.kind != .field })

        // Confirmed fields do not stand in for collected documents (T-62): the
        // package's mandatory evidence has to be satisfied before generation.
        let evidenceGate = try await api.packageGenerationReadiness(caseID: created.id)
        #expect(!evidenceGate.canGenerate)
        #expect(evidenceGate.outstandingBlockingEvidence > 0)
        for (offset, item) in afterItems.filter({ $0.severity == .blocking }).enumerated() {
            _ = try await api.linkEvidence(
                caseID: created.id,
                requirementCode: try #require(item.requirementCode),
                documentID: DocumentID("d_greencard"),
                idempotencyKey: "t61-link-\(offset)"
            )
        }

        let readiness = try await api.packageGenerationReadiness(caseID: created.id)
        #expect(readiness.canGenerate)
        let package = try await api.requestPackageGeneration(
            caseID: created.id,
            idempotencyKey: "t61-generate"
        )
        #expect(package.caseID == created.id)
        #expect(package.outputs.contains { $0.formNumber == "I-130" })
    }

    @Test("Explicit role assignments override relationship inference")
    func explicitAssignmentsOverrideInference() async throws {
        let api = await makeClient()
        // Deliberately swapped relative to the folder's recorded relationships.
        let created = try await api.createCase(
            folderID: FolderID("f_ramirez"),
            packageCode: "FAMILY_I130",
            roleAssignments: [
                PersonID("p_maria"): "BENEFICIARY",
                PersonID("p_carlos"): "PETITIONER"
            ],
            attestation: attestation(),
            idempotencyKey: "t61-swapped"
        )
        let fields = try await api.reviewableFields(caseID: created.id)
        let birthCity = try #require(fields.first {
            $0.canonicalPath == CanonicalPath("person.birth.city")
        })
        #expect(birthCity.subjectPersonID == PersonID("p_maria"))
    }

    @Test("An interview can start against the new case's batch")
    func interviewStartsOnTheNewBatch() async throws {
        let api = await makeClient()
        let created = try await api.createCase(
            folderID: FolderID("f_ramirez"),
            packageCode: "FAMILY_I130",
            roleAssignments: [:],
            attestation: attestation(),
            idempotencyKey: "t61-interview"
        )
        let (_, batches) = try await api.missingItems(caseID: created.id)
        let batch = try #require(batches.first)
        let session = try await api.startInterview(
            caseID: created.id,
            personID: PersonID("p_carlos"),
            batchID: batch.id,
            modality: .chat,
            consent: nil,
            accessibilityProfileEnabled: false,
            idempotencyKey: "t61-session"
        )
        #expect(session.caseID == created.id)
    }

    @Test("A folder with nobody to fill the roles cannot create the case")
    func emptyFolderFailsClosed() async throws {
        let api = await makeClient()
        let folder = try await api.createFolder(name: "New folder", idempotencyKey: "t61-folder")
        do {
            _ = try await api.createCase(
                folderID: folder.id,
                packageCode: "FAMILY_I130",
                roleAssignments: [:],
                attestation: attestation(),
                idempotencyKey: "t61-empty"
            )
            Issue.record("Expected creation without resolvable roles to fail closed")
        } catch let problem as ProblemDetails {
            #expect(problem.status == 422)
            #expect(problem.type.hasSuffix("role-assignments-incomplete"))
            let missingRoles = Set(problem.errors?.map(\.field) ?? [])
            #expect(missingRoles == ["PETITIONER", "BENEFICIARY"])
        }
    }

    @Test("A role assignment naming a stranger to the folder is refused")
    func strangerAssignmentRefused() async throws {
        let api = await makeClient()
        await #expect(throws: ProblemDetails.self) {
            _ = try await api.createCase(
                folderID: FolderID("f_ramirez"),
                packageCode: "FAMILY_I130",
                roleAssignments: [PersonID("p_stranger"): "PETITIONER"],
                attestation: attestation(),
                idempotencyKey: "t61-stranger"
            )
        }
    }

    @Test("Two people assigned the same role is a conflict, not a coin toss")
    func duplicateRoleRefused() async throws {
        let api = await makeClient()
        do {
            _ = try await api.createCase(
                folderID: FolderID("f_ramirez"),
                packageCode: "FAMILY_I130",
                roleAssignments: [
                    PersonID("p_maria"): "PETITIONER",
                    PersonID("p_carlos"): "PETITIONER"
                ],
                attestation: attestation(),
                idempotencyKey: "t61-duplicate"
            )
            Issue.record("Expected a duplicated role to fail closed")
        } catch let problem as ProblemDetails {
            #expect(problem.status == 422)
            #expect(problem.type.hasSuffix("role-duplicated"))
        }
    }

    @Test("Conditional evidence arrives advisory; unconditional arrives blocking")
    func evidenceSeverityFollowsConditionality() async throws {
        let api = await makeClient()
        let created = try await api.createCase(
            folderID: FolderID("f_ramirez"),
            packageCode: "FAMILY_I130",
            roleAssignments: [:],
            attestation: attestation(),
            idempotencyKey: "t61-evidence"
        )
        let (items, _) = try await api.missingItems(caseID: created.id)
        let prior = try #require(items.first { $0.requirementCode == "PRIOR_MARRIAGE_TERMINATION" })
        #expect(prior.severity == .advisory)
        let marriage = try #require(items.first { $0.requirementCode == "MARRIAGE_CERTIFICATE" })
        #expect(marriage.severity == .blocking)
        // Counters describe the same state the collections do.
        #expect(created.counters.blockingItems
            == items.filter { $0.severity == .blocking }.count)
        #expect(created.counters.advisoryItems
            == items.filter { $0.severity == .advisory }.count)
    }

    @Test("A package without a template keeps the previous shell behaviour")
    func templatelessPackageKeepsShellBehaviour() async throws {
        let api = await makeClient()
        let created = try await api.createCase(
            folderID: FolderID("f_ramirez"),
            packageCode: "ADJUSTMENT_I485_I864",
            roleAssignments: [:],
            attestation: attestation(),
            idempotencyKey: "t61-shell"
        )
        let fields = try await api.reviewableFields(caseID: created.id)
        #expect(fields.isEmpty)
        // The generation gate still fails closed for the shell (T-62 tracks
        // widening that gate; this only pins the current contract).
        do {
            _ = try await api.requestPackageGeneration(
                caseID: created.id,
                idempotencyKey: "t61-shell-generate"
            )
            Issue.record("Expected an uninitialized case to be refused generation")
        } catch let problem as ProblemDetails {
            #expect(problem.status == 409)
            #expect(problem.type.hasSuffix("generation-data-not-ready"))
        }
    }
}
