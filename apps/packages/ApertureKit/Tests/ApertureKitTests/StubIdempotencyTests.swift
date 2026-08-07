import Foundation
import Testing
import ApertureDomain
import ApertureAPI

@Suite("Stub idempotency")
struct StubIdempotencyTests {
    @Test("A successful retry replays its response without duplicating mutation")
    func createFolderRetryReplaysResponse() async throws {
        let api = StubAPIClient()
        await api.setDelay(.zero)
        let countBefore = try await api.folders().count

        let first = try await api.createFolder(name: "Retry safe", idempotencyKey: "folder-retry")
        let replay = try await api.createFolder(name: "Retry safe", idempotencyKey: "folder-retry")

        #expect(replay.id == first.id)
        #expect(try await api.folders().count == countBefore + 1)
    }

    @Test("A key cannot be reused with a conflicting request")
    func conflictingPayloadIsRejected() async throws {
        let api = StubAPIClient()
        await api.setDelay(.zero)
        let countBefore = try await api.folders().count
        _ = try await api.createFolder(name: "First", idempotencyKey: "folder-conflict")

        do {
            _ = try await api.createFolder(name: "Different", idempotencyKey: "folder-conflict")
            Issue.record("A changed payload must not reuse an idempotency key")
        } catch let problem as ProblemDetails {
            #expect(problem.status == 409)
        }
        #expect(try await api.folders().count == countBefore + 1)
    }

    @Test("Keys are scoped to an endpoint")
    func keyScopeIsPerEndpoint() async throws {
        let api = StubAPIClient()
        await api.setDelay(.zero)
        _ = try await api.createFolder(name: "Scoped", idempotencyKey: "shared-key")

        let upload = try await api.createUploadSession(
            folderID: FolderID("f_ramirez"),
            subjectPersonID: nil,
            originalName: "scope.jpg",
            sizeBytes: 10,
            source: .camera,
            quality: nil,
            contentSHA256: "scope-digest",
            idempotencyKey: "shared-key"
        )
        #expect(upload.sessionID.isEmpty == false)
    }

    @Test("A consumed upload session can replay its completion")
    func completedUploadReplays() async throws {
        let api = StubAPIClient()
        await api.setDelay(.zero)
        let session = try await api.createUploadSession(
            folderID: FolderID("f_ramirez"),
            subjectPersonID: nil,
            originalName: "retry.jpg",
            sizeBytes: 10,
            source: .camera,
            quality: nil,
            contentSHA256: "retry-digest",
            idempotencyKey: "upload-create-retry"
        )

        let first = try await api.completeUpload(
            sessionID: session.sessionID,
            idempotencyKey: "upload-complete-retry"
        )
        let replay = try await api.completeUpload(
            sessionID: session.sessionID,
            idempotencyKey: "upload-complete-retry"
        )

        #expect(replay == first)
        let matching = try await api.documents(folderID: FolderID("f_ramirez"))
            .filter { $0.id == first.id }
        #expect(matching.count == 1)
    }

    @Test("Confirmation validates the entire batch before mutation")
    func confirmationBatchIsAtomic() async throws {
        let api = StubAPIClient()
        await api.setDelay(.zero)
        let caseID = CaseID("c_ramirez_i130")
        let before = try await api.reviewableFields(caseID: caseID)

        do {
            _ = try await api.confirmValues(
                caseID: caseID,
                confirmations: [
                    ValueConfirmation(
                        personID: PersonID("p_carlos"),
                        canonicalPath: CanonicalPath("person.name.family"),
                        value: "Ramírez"
                    ),
                    ValueConfirmation(
                        personID: PersonID("p_carlos"),
                        canonicalPath: CanonicalPath("person.does.not.exist"),
                        value: "invalid"
                    )
                ],
                idempotencyKey: "atomic-confirmation"
            )
            Issue.record("An invalid batch member must reject the whole batch")
        } catch let problem as ProblemDetails {
            #expect(problem.status == 404)
        }

        #expect(try await api.reviewableFields(caseID: caseID) == before)
    }

    @Test("Confirmation retries replay without appending history")
    func confirmationRetryDoesNotMutate() async throws {
        let api = StubAPIClient()
        await api.setDelay(.zero)
        let caseID = CaseID("c_ramirez_i130")
        let confirmation = ValueConfirmation(
            personID: PersonID("p_carlos"),
            canonicalPath: CanonicalPath("person.name.family"),
            value: "Ramírez"
        )
        let first = try await api.confirmValues(
            caseID: caseID,
            confirmations: [confirmation],
            idempotencyKey: "confirm-retry"
        )
        let stateAfterFirst = try await api.reviewableFields(caseID: caseID)
        let replay = try await api.confirmValues(
            caseID: caseID,
            confirmations: [confirmation],
            idempotencyKey: "confirm-retry"
        )

        #expect(replay == first)
        #expect(try await api.reviewableFields(caseID: caseID) == stateAfterFirst)
    }

    @Test("Replay records survive a stub relaunch")
    func replayPersists() async throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "lapluma-idempotency-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let firstClient = StubAPIClient(persistenceURL: url)
        await firstClient.setDelay(.zero)
        let first = try await firstClient.createFolder(name: "Persisted", idempotencyKey: "persisted-key")

        let relaunched = StubAPIClient(persistenceURL: url)
        await relaunched.setDelay(.zero)
        let replay = try await relaunched.createFolder(name: "Persisted", idempotencyKey: "persisted-key")

        #expect(replay.id == first.id)
        #expect(try await relaunched.folders().filter { $0.id == first.id }.count == 1)
    }
}
