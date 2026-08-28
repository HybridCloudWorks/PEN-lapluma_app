import Foundation
import Testing
import ApertureDomain
@testable import ApertureAPI

/// T-75. A folder created in the app held nobody, and nothing in the app could ever
/// put a person in one, so a form package's required roles had no one to attach to
/// and the application could not be created. The first test is the acceptance
/// criterion: a folder made from scratch reaches a created I-130 case.
@Suite("Folder people and relationships")
struct FolderPeopleTests {

    private func makeClient() async -> StubAPIClient {
        let api = StubAPIClient()
        await api.setDelay(.zero)
        return api
    }

    @Test("A folder built from scratch can create the case its package requires")
    func newFolderReachesCaseCreation() async throws {
        let api = await makeClient()
        let folder = try await api.createFolder(name: "My application", idempotencyKey: "t75-folder")

        // Before anyone is in it, the folder cannot produce an I-130 case at all.
        await #expect(throws: ProblemDetails.self) {
            _ = try await api.createCase(
                folderID: folder.id,
                packageCode: "FAMILY_I130",
                roleAssignments: [:],
                attestation: SelectionAttestation(
                    attested: true, attestationVersion: "2026.03", text: "I chose these forms."
                ),
                idempotencyKey: "t75-too-early"
            )
        }

        let petitioner = try await api.createPerson(
            folderID: folder.id,
            displayLabel: "Me",
            isMinor: false,
            relationships: [],
            idempotencyKey: "t75-petitioner"
        )
        let beneficiary = try await api.createPerson(
            folderID: folder.id,
            displayLabel: "My husband",
            isMinor: false,
            relationships: [Relationship(kind: .beneficiaryOf, objectPersonID: petitioner.id)],
            idempotencyKey: "t75-beneficiary"
        )

        let created = try await api.createCase(
            folderID: folder.id,
            packageCode: "FAMILY_I130",
            roleAssignments: [:],
            attestation: SelectionAttestation(
                attested: true, attestationVersion: "2026.03", text: "I chose these forms."
            ),
            idempotencyKey: "t75-create"
        )
        // And the case is born with real structure attributed to these two people,
        // not to the seeded fixture's.
        let fields = try await api.reviewableFields(caseID: created.id)
        #expect(!fields.isEmpty)
        let subjects = Set(fields.map(\.subjectPersonID))
        #expect(subjects == [petitioner.id, beneficiary.id])
    }

    @Test("The other side of a relationship is recorded too")
    func inverseRelationshipIsRecorded() async throws {
        let api = await makeClient()
        let folder = try await api.createFolder(name: "Household", idempotencyKey: "t75-inv-folder")
        let first = try await api.createPerson(
            folderID: folder.id, displayLabel: "First", isMinor: false,
            relationships: [], idempotencyKey: "t75-inv-first"
        )
        let second = try await api.createPerson(
            folderID: folder.id, displayLabel: "Second", isMinor: false,
            relationships: [Relationship(kind: .beneficiaryOf, objectPersonID: first.id)],
            idempotencyKey: "t75-inv-second"
        )

        // Recording only one direction would leave the petitioner looking
        // unrelated, which is exactly what role resolution reads.
        let stored = try await api.folder(id: folder.id)
        let storedFirst = try #require(stored.persons.first { $0.id == first.id })
        #expect(storedFirst.relationships.contains(
            Relationship(kind: .petitionerFor, objectPersonID: second.id)
        ))
        let storedSecond = try #require(stored.persons.first { $0.id == second.id })
        #expect(storedSecond.relationships.contains(
            Relationship(kind: .beneficiaryOf, objectPersonID: first.id)
        ))
    }

    @Test("Every offered relationship kind has an inverse, and the rest say so")
    func inverseTableIsHonest() {
        #expect(Relationship.Kind.petitionerFor.inverse == .beneficiaryOf)
        #expect(Relationship.Kind.beneficiaryOf.inverse == .petitionerFor)
        #expect(Relationship.Kind.parentOf.inverse == .childOf)
        #expect(Relationship.Kind.childOf.inverse == .parentOf)
        #expect(Relationship.Kind.spouseOf.inverse == .spouseOf)
        #expect(Relationship.Kind.siblingOf.inverse == .siblingOf)
        // No term exists for these on the other side; inventing one would record a
        // relationship the model cannot represent.
        #expect(Relationship.Kind.guardianOf.inverse == nil)
        #expect(Relationship.Kind.sponsorFor.inverse == nil)
        #expect(Relationship.Kind.derivativeOf.inverse == nil)
    }

    @Test("A person recorded by someone else never holds a credential")
    func addedPersonHoldsNoCredential() async throws {
        let api = await makeClient()
        let folder = try await api.createFolder(name: "Family", idempotencyKey: "t75-cred-folder")
        // A minor especially: CK_Person_MinorNoLogin holds by construction here
        // because this endpoint cannot create a credential at all (ADR-007).
        let child = try await api.createPerson(
            folderID: folder.id, displayLabel: "My daughter", isMinor: true,
            relationships: [], idempotencyKey: "t75-child"
        )
        #expect(child.isMinor)
        #expect(!child.holdsOwnCredential)
        #expect(child.participation == .active)
    }

    @Test("A relationship cannot name someone outside the folder")
    func relationshipMustStayInsideTheFolder() async throws {
        let api = await makeClient()
        let folder = try await api.createFolder(name: "Scoped", idempotencyKey: "t75-scope-folder")
        do {
            _ = try await api.createPerson(
                folderID: folder.id,
                displayLabel: "Someone",
                isMinor: false,
                // A person from the seeded folder: real, but not this folder's to name.
                relationships: [Relationship(kind: .spouseOf, objectPersonID: PersonID("p_carlos"))],
                idempotencyKey: "t75-outside"
            )
            Issue.record("Expected a relationship outside the folder to be refused")
        } catch let problem as ProblemDetails {
            #expect(problem.status == 422)
            #expect(problem.type.hasSuffix("relationship-person-not-in-folder"))
        }
    }

    @Test("A person needs a name, and a repeated request adds one person")
    func labelRequiredAndCreationIsIdempotent() async throws {
        let api = await makeClient()
        let folder = try await api.createFolder(name: "Names", idempotencyKey: "t75-name-folder")

        do {
            _ = try await api.createPerson(
                folderID: folder.id, displayLabel: "   ", isMinor: false,
                relationships: [], idempotencyKey: "t75-blank"
            )
            Issue.record("Expected a blank label to be refused")
        } catch let problem as ProblemDetails {
            #expect(problem.status == 422)
            #expect(problem.type.hasSuffix("person-label-required"))
        }

        let first = try await api.createPerson(
            folderID: folder.id, displayLabel: "Once", isMinor: false,
            relationships: [], idempotencyKey: "t75-once"
        )
        let replay = try await api.createPerson(
            folderID: folder.id, displayLabel: "Once", isMinor: false,
            relationships: [], idempotencyKey: "t75-once"
        )
        #expect(first.id == replay.id)
        #expect(try await api.folder(id: folder.id).persons.count == 1)
    }

    @Test("Adding a person to a folder that does not exist is refused")
    func unknownFolderRefused() async throws {
        let api = await makeClient()
        await #expect(throws: ProblemDetails.self) {
            _ = try await api.createPerson(
                folderID: FolderID("f_nope"), displayLabel: "Ghost", isMinor: false,
                relationships: [], idempotencyKey: "t75-ghost"
            )
        }
    }
}
