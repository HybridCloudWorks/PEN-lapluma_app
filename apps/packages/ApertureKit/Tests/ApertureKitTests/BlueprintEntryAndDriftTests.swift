import XCTest
@testable import ApertureAPI
@testable import ApertureDomain

final class BlueprintEntryAndDriftTests: XCTestCase {

    func testSyntheticNonImmigrationBlueprintsRegistered() async throws {
        let client = StubAPIClient()

        // 1. Clinic Intake
        let clinic = try await client.libraryBlueprintDefinition(namespace: "clinic-legal-org", id: "intake")
        XCTAssertNotNil(clinic, "Clinic intake blueprint definition should be available")
        XCTAssertEqual(clinic?.namespace, "clinic-legal-org")
        XCTAssertEqual(clinic?.blueprintId, "intake")
        XCTAssertEqual(clinic?.preparationMode, .staticAssisted)

        // 2. Scholarship Application
        let scholarship = try await client.libraryBlueprintDefinition(namespace: "hope-heritage", id: "scholarship-app")
        XCTAssertNotNil(scholarship, "Scholarship blueprint definition should be available")
        XCTAssertEqual(scholarship?.namespace, "hope-heritage")
        XCTAssertEqual(scholarship?.blueprintId, "scholarship-app")
        XCTAssertEqual(scholarship?.accessScope, "INSTITUTION_PRIVATE")

        // 3. DS-11 Passport
        let ds11 = try await client.libraryBlueprintDefinition(namespace: "dos", id: "ds-11")
        XCTAssertNotNil(ds11, "DS-11 passport blueprint definition should be available")
        XCTAssertEqual(ds11?.namespace, "dos")
        XCTAssertEqual(ds11?.blueprintId, "ds-11")
        XCTAssertEqual(ds11?.preparationMode, .fillablePdf)

        // 4. FAFSA
        let fafsa = try await client.libraryBlueprintDefinition(namespace: "student-aid", id: "fafsa")
        XCTAssertNotNil(fafsa, "FAFSA blueprint definition should be available")
        XCTAssertEqual(fafsa?.namespace, "student-aid")
        XCTAssertEqual(fafsa?.blueprintId, "fafsa")
        XCTAssertEqual(fafsa?.preparationMode, .externalReference)
    }

    func testDeclarativeConditionEvaluation() {
        // equals
        let eq = BlueprintCondition(field: "has_sponsor", operator: .equals, value: "true")
        XCTAssertTrue(eq.evaluate(against: ["has_sponsor": "true"]))
        XCTAssertFalse(eq.evaluate(against: ["has_sponsor": "false"]))
        XCTAssertFalse(eq.evaluate(against: [:]))

        // notEquals
        let ne = BlueprintCondition(field: "status", operator: .notEquals, value: "closed")
        XCTAssertTrue(ne.evaluate(against: ["status": "open"]))
        XCTAssertFalse(ne.evaluate(against: ["status": "closed"]))

        // isSet / isNotSet
        let isSet = BlueprintCondition(field: "ssn", operator: .isSet)
        XCTAssertTrue(isSet.evaluate(against: ["ssn": "123-45-6789"]))
        XCTAssertFalse(isSet.evaluate(against: [:]))
        XCTAssertFalse(isSet.evaluate(against: ["ssn": "  "]))

        let isNotSet = BlueprintCondition(field: "alien_number", operator: .isNotSet)
        XCTAssertTrue(isNotSet.evaluate(against: [:]))
        XCTAssertFalse(isNotSet.evaluate(against: ["alien_number": "A123456789"]))

        // inValues
        let inCond = BlueprintCondition(field: "state", operator: .inValues, values: ["CA", "NY", "TX"])
        XCTAssertTrue(inCond.evaluate(against: ["state": "CA"]))
        XCTAssertFalse(inCond.evaluate(against: ["state": "FL"]))
    }

    func testRepeatedSectionBoundsAndOverflowStrategy() {
        let section = BlueprintSection(
            sectionId: "sec_academic_records",
            title: "Academic History",
            isRepeatable: true,
            maxOccurs: 5,
            overflowStrategy: .attachmentAddendum
        )
        XCTAssertTrue(section.isRepeatable)
        XCTAssertEqual(section.maxOccurs, 5)
        XCTAssertEqual(section.overflowStrategy, .attachmentAddendum)
        XCTAssertTrue(section.isVisible(against: [:]))
    }

    func testDeclarativeSafetyRejectsExecutableConfiguration() {
        let unsafeBp = BlueprintDefinition(
            namespace: "malicious",
            blueprintId: "exploit",
            revision: 1,
            title: "<script>alert('xss')</script>",
            issuer: "Attacker",
            preparationMode: .staticAssisted,
            artifactType: .authoredTemplate
        )
        XCTAssertThrowsError(try BlueprintDefinition.validateDeclarativeSafety(unsafeBp)) { error in
            guard let problem = error as? ProblemDetails else {
                XCTFail("Expected ProblemDetails error")
                return
            }
            XCTAssertEqual(problem.status, 422)
            XCTAssertTrue(problem.title.contains("Executable"))
        }

        let safeBp = BlueprintDefinition(
            namespace: "clinic",
            blueprintId: "intake",
            revision: 1,
            title: "Safe Intake Form",
            issuer: "Legal Clinic",
            preparationMode: .staticAssisted,
            artifactType: .authoredTemplate
        )
        XCTAssertNoThrow(try BlueprintDefinition.validateDeclarativeSafety(safeBp))
    }

    func testBlueprintDriftDetectionPolicy() {
        let pinnedMember = CollectionBlueprintMember(
            namespace: "uscis",
            blueprintId: "i-130",
            pinnedRevision: 1,
            preparationMode: .fillablePdf,
            displayOrder: 1,
            isRequired: true
        )

        // 1. Current revision is 2 -> Revision Replaced
        let currentBpReplaced = DocumentBlueprint(
            namespace: "uscis",
            blueprintId: "i-130",
            revision: 2,
            title: "Petition for Alien Relative",
            issuer: "USCIS",
            preparationMode: .fillablePdf,
            artifactType: .officialPdf,
            publicationState: .published,
            isLatest: true
        )
        let driftsReplaced = BlueprintDriftPolicy.evaluateDrift(
            pinnedMembers: [pinnedMember],
            currentBlueprints: [currentBpReplaced]
        )
        XCTAssertEqual(driftsReplaced.count, 1)
        XCTAssertEqual(driftsReplaced.first?.reason, .revisionReplaced)
        XCTAssertTrue(BlueprintDriftPolicy.blocksPackageGeneration(drifts: driftsReplaced))

        // 2. Blueprint is Quarantined
        let currentBpQuarantined = DocumentBlueprint(
            namespace: "uscis",
            blueprintId: "i-130",
            revision: 1,
            title: "Petition for Alien Relative",
            issuer: "USCIS",
            preparationMode: .fillablePdf,
            artifactType: .officialPdf,
            publicationState: .quarantined,
            isLatest: true
        )
        let driftsQuarantined = BlueprintDriftPolicy.evaluateDrift(
            pinnedMembers: [pinnedMember],
            currentBlueprints: [currentBpQuarantined]
        )
        XCTAssertEqual(driftsQuarantined.count, 1)
        XCTAssertEqual(driftsQuarantined.first?.reason, .quarantined)
        XCTAssertTrue(driftsQuarantined.first?.isQuarantined == true)

        // 3. Blueprint is Withdrawn
        let currentBpWithdrawn = DocumentBlueprint(
            namespace: "uscis",
            blueprintId: "i-130",
            revision: 1,
            title: "Petition for Alien Relative",
            issuer: "USCIS",
            preparationMode: .fillablePdf,
            artifactType: .officialPdf,
            publicationState: .withdrawn,
            isLatest: true
        )
        let driftsWithdrawn = BlueprintDriftPolicy.evaluateDrift(
            pinnedMembers: [pinnedMember],
            currentBlueprints: [currentBpWithdrawn]
        )
        XCTAssertEqual(driftsWithdrawn.count, 1)
        XCTAssertEqual(driftsWithdrawn.first?.reason, .withdrawn)
        XCTAssertTrue(driftsWithdrawn.first?.isWithdrawn == true)

        // 4. Missing from catalog
        let driftsMissing = BlueprintDriftPolicy.evaluateDrift(
            pinnedMembers: [pinnedMember],
            currentBlueprints: []
        )
        XCTAssertEqual(driftsMissing.count, 1)
        XCTAssertEqual(driftsMissing.first?.reason, .missingFromCatalog)

        // 5. No drift when pinned matches current published
        let currentBpMatching = DocumentBlueprint(
            namespace: "uscis",
            blueprintId: "i-130",
            revision: 1,
            title: "Petition for Alien Relative",
            issuer: "USCIS",
            preparationMode: .fillablePdf,
            artifactType: .officialPdf,
            publicationState: .published,
            isLatest: true
        )
        let driftsNone = BlueprintDriftPolicy.evaluateDrift(
            pinnedMembers: [pinnedMember],
            currentBlueprints: [currentBpMatching]
        )
        XCTAssertTrue(driftsNone.isEmpty)
        XCTAssertFalse(BlueprintDriftPolicy.blocksPackageGeneration(drifts: driftsNone))
    }

    func testOfflineCaseStorePartitioning() async {
        let store = OfflineCaseStore()
        let pin = CaseRevisionPin(
            collectionNamespace: "official",
            collectionId: "family-reunification-i130",
            collectionRevision: 1,
            pinnedMembers: []
        )

        let caseIdA = CaseID("case_alpha")
        let draftA = OfflineCaseDraft(tenantId: "tenant_alpha", caseId: caseIdA, revisionPin: pin)
        await store.saveDraft(draftA)

        let caseIdB = CaseID("case_beta")
        let draftB = OfflineCaseDraft(tenantId: "tenant_beta", caseId: caseIdB, revisionPin: pin)
        await store.saveDraft(draftB)

        // Verify tenant partition isolation
        let fetchedA = await store.draft(tenantId: "tenant_alpha", caseId: caseIdA)
        XCTAssertNotNil(fetchedA)
        XCTAssertEqual(fetchedA?.caseId, caseIdA)

        let fetchedWrongTenant = await store.draft(tenantId: "tenant_alpha", caseId: caseIdB)
        XCTAssertNil(fetchedWrongTenant, "Tenant alpha must not see tenant beta's case draft")

        // Clear tenant alpha
        await store.clearTenant(tenantId: "tenant_alpha")
        XCTAssertNil(await store.draft(tenantId: "tenant_alpha", caseId: caseIdA))
        XCTAssertNotNil(await store.draft(tenantId: "tenant_beta", caseId: caseIdB))
    }

    func testOfflineSectionConflictPreservation() async {
        let store = OfflineCaseStore()
        let pin = CaseRevisionPin(
            collectionNamespace: "official",
            collectionId: "family-reunification-i130",
            collectionRevision: 1,
            pinnedMembers: []
        )
        let caseId = CaseID("case_conflict_test")
        let initialDraft = OfflineCaseDraft(tenantId: "tenant_1", caseId: caseId, revisionPin: pin)
        await store.saveDraft(initialDraft)

        // Record conflict from HTTP 412
        await store.recordConflict(
            tenantId: "tenant_1",
            caseId: caseId,
            sectionId: "sec_identity",
            localValues: ["name": "Alice Local"],
            baseRevision: 1,
            serverRevision: 2,
            serverValues: ["name": "Alice Server"]
        )

        let conflictDraft = await store.draft(tenantId: "tenant_1", caseId: caseId)
        let secDraft = conflictDraft?.sectionDrafts["sec_identity"]
        XCTAssertNotNil(secDraft)
        XCTAssertTrue(secDraft?.hasConflict == true)
        XCTAssertEqual(secDraft?.localValues["name"], "Alice Local")
        XCTAssertEqual(secDraft?.conflictServerValues?["name"], "Alice Server")
        XCTAssertEqual(secDraft?.conflictServerRevision, 2)

        // Resolve conflict
        await store.resolveConflict(
            tenantId: "tenant_1",
            caseId: caseId,
            sectionId: "sec_identity",
            resolvedValues: ["name": "Alice Resolved"],
            newBaseRevision: 2
        )
        let resolvedDraft = await store.draft(tenantId: "tenant_1", caseId: caseId)
        let resolvedSec = resolvedDraft?.sectionDrafts["sec_identity"]
        XCTAssertFalse(resolvedSec?.hasConflict == true)
        XCTAssertEqual(resolvedSec?.localValues["name"], "Alice Resolved")
        XCTAssertEqual(resolvedSec?.baseRevision, 2)
    }

    func testApprovalInvalidationOnSectionCommit() async throws {
        let client = StubAPIClient()
        let summary = try await client.createCase(
            folderID: FolderID("f_demo"),
            packageCode: "FAMILY_I130",
            roleAssignments: [PersonID("p_petitioner"): "PETITIONER", PersonID("p_beneficiary"): "BENEFICIARY"],
            attestation: SelectionAttestation(attested: true, signature: "Sig", timestamp: Date()),
            idempotencyKey: IdempotencyKey.make()
        )

        // Move to inReview then readyForApproval
        _ = try await client.transition(caseID: summary.id, to: .inReview, idempotencyKey: IdempotencyKey.make())
        _ = try await client.transition(caseID: summary.id, to: .readyForApproval, idempotencyKey: IdempotencyKey.make())

        // Approve case
        let preview = try await client.draftPreview(caseID: summary.id)
        let challenge = try await client.stepUpChallenge(caseID: summary.id, idempotencyKey: IdempotencyKey.make())
        _ = try await client.approve(caseID: summary.id, preview: preview, stepUpChallenge: challenge.challengeToken, attested: true, idempotencyKey: IdempotencyKey.make())

        // Now commit a section edit: must invalidate approval!
        let commitResult = try await client.commitSection(
            caseID: summary.id,
            sectionID: "identity",
            baseRevision: 1,
            values: ["petitioner.name.given": "NewName"],
            idempotencyKey: IdempotencyKey.make()
        )
        XCTAssertTrue(commitResult.invalidatedApproval, "Editing fields on an approved case must invalidate approval")
    }
}
