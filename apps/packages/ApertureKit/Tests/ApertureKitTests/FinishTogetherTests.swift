import Foundation
import PDFKit
import Testing
import ApertureDomain
@testable import ApertureAPI

@Suite("Finish Together MVP")
struct FinishTogetherTests {
    private let caseID = CaseID("c_ramirez_i130")

    @Test("Guided Finish is deterministic, budgeted, and does not duplicate a batch")
    func guidedFinishPlanning() async throws {
        let api = StubAPIClient(); await api.setDelay(.zero)
        let short = try await api.guidedFinishPlan(caseID: caseID, minutes: 5)
        #expect(short.minutesBudget == 5)
        #expect(short.steps.first?.batchID == BatchID("mi_batch_017"))
        #expect(short.estimatedMinutes == 6, "The first blocking step remains visible even when it exceeds the budget")
        #expect(Set(short.steps.flatMap(\.itemIDs)).count == short.steps.flatMap(\.itemIDs).count)

        let first = try await api.guidedFinishPlan(caseID: caseID, minutes: 10)
        let second = try await api.guidedFinishPlan(caseID: caseID, minutes: 10)
        #expect(first == second)
        #expect(first.estimatedMinutes <= 10)
        #expect(first.steps.first?.severity == .blocking)
    }

    @Test("Proof Map binds one canonical value to both pinned family forms")
    func proofMapUsesPinnedDestinations() async throws {
        let api = StubAPIClient(); await api.setDelay(.zero)
        let map = try await api.proofMap(caseID: caseID)
        let familyName = try #require(map.entries.first {
            $0.canonicalPath == CanonicalPath("person.name.family")
        })
        #expect(Set(familyName.destinations.map(\.formNumber)) == ["I-130", "I-130A"])
        guard case .document(let anchor) = familyName.provenance else {
            Issue.record("The seeded family name should retain document provenance")
            return
        }
        let preview = try await api.documentPagePreview(
            documentID: anchor.documentID,
            pageNumber: anchor.pageNumber
        )
        #expect(preview.mimeType == "image/png")
        #expect(preview.contentSHA256 == CapturePayloadProcessor.sha256(of: preview.data))
        #expect(!preview.data.isEmpty)
    }

    @Test("Private Relay requires both factors, receives one document, and clears only after acceptance")
    func relayLifecycle() async throws {
        let api = StubAPIClient(); await api.setDelay(.zero)
        let created = try await api.createEvidenceRelay(
            caseID: caseID,
            missingItemID: MissingItemID("mi_0141"),
            idempotencyKey: "relay-lifecycle"
        )
        let token = try #require(created.shareURL.pathComponents.last)
        #expect(created.accessCode.count == 6)
        #expect(try await api.relayChallenge(token: token).isAvailable)

        await #expect(throws: ProblemDetails.self) {
            _ = try await api.unlockRelay(token: token, accessCode: "000000", idempotencyKey: "wrong-code")
        }
        let grant = try await api.unlockRelay(token: token, accessCode: created.accessCode, idempotencyKey: "correct-code")
        #expect(grant.requestedTitle == created.relay.requestedTitle)

        let pdf = PDFDocument()
        pdf.insert(PDFPage(), at: 0)
        let data = try #require(pdf.dataRepresentation())
        let prepared = try CapturePayloadProcessor.prepare(data)
        let upload = try await api.createRelayUploadSession(
            grantID: grant.id,
            originalName: "requested-document.pdf",
            sizeBytes: Int64(prepared.data.count),
            contentSHA256: prepared.contentSHA256,
            idempotencyKey: "relay-upload"
        )
        let receipt = try await api.completeRelayUpload(
            sessionID: upload.id,
            uploadedData: prepared.data,
            idempotencyKey: "relay-complete"
        )
        #expect(receipt.status == .received)
        #expect(try await api.missingItems(caseID: caseID).items.contains { $0.id == MissingItemID("mi_0141") })
        let pendingPlan = try await api.guidedFinishPlan(caseID: caseID, minutes: 10)
        #expect(pendingPlan.steps.contains { $0.status == .relayNeedsReview })

        _ = try await api.reclassify(documentID: receipt.documentID, to: .civil)
        let accepted = try await api.acceptEvidenceRelay(
            relayID: created.relay.id,
            idempotencyKey: "relay-accept"
        )
        #expect(accepted.status == .accepted)
        #expect(try await api.acceptEvidenceRelay(
            relayID: created.relay.id,
            idempotencyKey: "relay-accept"
        ) == accepted)
        #expect(!(try await api.missingItems(caseID: caseID).items.contains { $0.id == MissingItemID("mi_0141") }))
    }

    @Test("Five incorrect relay codes lock the request")
    func relayLockout() async throws {
        let api = StubAPIClient(); await api.setDelay(.zero)
        let created = try await api.createEvidenceRelay(
            caseID: caseID,
            missingItemID: MissingItemID("mi_0141"),
            idempotencyKey: "relay-lockout"
        )
        let token = try #require(created.shareURL.pathComponents.last)
        for attempt in 1...5 {
            do {
                _ = try await api.unlockRelay(token: token, accessCode: "999999", idempotencyKey: "wrong-\(attempt)")
                Issue.record("Attempt \(attempt) unexpectedly unlocked the relay")
            } catch let problem as ProblemDetails {
                #expect(problem.status == (attempt == 5 ? 423 : 401))
            }
        }
        #expect(!(try await api.relayChallenge(token: token).isAvailable))
        #expect(try await api.evidenceRelays(caseID: caseID).first?.status == .locked)
    }

    @Test("Relay credentials are not written to persisted fixture JSON")
    func relaySecretsAreHashedAtRest() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "relay-secret-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = directory.appending(path: "stub.json")
        let api = StubAPIClient(persistenceURL: store); await api.setDelay(.zero)
        let created = try await api.createEvidenceRelay(
            caseID: caseID,
            missingItemID: MissingItemID("mi_0141"),
            idempotencyKey: "relay-persistence"
        )
        let token = try #require(created.shareURL.pathComponents.last)
        let grant = try await api.unlockRelay(token: token, accessCode: created.accessCode, idempotencyKey: "credential-unlock")
        let pdf = PDFDocument(); pdf.insert(PDFPage(), at: 0)
        let prepared = try CapturePayloadProcessor.prepare(try #require(pdf.dataRepresentation()))
        let upload = try await api.createRelayUploadSession(
            grantID: grant.id,
            originalName: "credential-check.pdf",
            sizeBytes: Int64(prepared.data.count),
            contentSHA256: prepared.contentSHA256,
            idempotencyKey: "relay-session-persistence"
        )
        let persisted = String(decoding: try Data(contentsOf: store), as: UTF8.self)
        #expect(!persisted.contains(created.accessCode))
        #expect(!persisted.contains(created.shareURL.pathComponents.last ?? "missing-token"))
        #expect(!persisted.contains(grant.id))
        #expect(!persisted.contains(upload.id))
        #expect(!persisted.contains(upload.uploadURL.absoluteString))
    }

    @Test("Expired relays stop challenging without exposing their request")
    func relayExpiry() async throws {
        final class Clock: @unchecked Sendable { var value = Date(timeIntervalSince1970: 10_000) }
        let clock = Clock()
        let api = StubAPIClient(now: { clock.value }); await api.setDelay(.zero)
        let created = try await api.createEvidenceRelay(
            caseID: caseID,
            missingItemID: MissingItemID("mi_0141"),
            idempotencyKey: "relay-expiry"
        )
        let token = try #require(created.shareURL.pathComponents.last)
        clock.value = created.relay.expiresAt
        #expect(!(try await api.relayChallenge(token: token).isAvailable))
        #expect(try await api.evidenceRelays(caseID: caseID).first?.status == .expired)
    }

    @Test("Reviewer and admin capabilities keep Finish Together mutations separated")
    func capabilityEnforcement() async throws {
        let reviewer = StubAPIClient(
            userID: UserID("u_stub_reviewer"),
            roles: [.reviewer]
        )
        await reviewer.setDelay(.zero)
        #expect(!(try await reviewer.proofMap(caseID: caseID).entries.isEmpty))
        await #expect(throws: ProblemDetails.self) {
            _ = try await reviewer.guidedFinishPlan(caseID: caseID, minutes: 10)
        }
        await #expect(throws: ProblemDetails.self) {
            _ = try await reviewer.createEvidenceRelay(
                caseID: caseID,
                missingItemID: MissingItemID("mi_0141"),
                idempotencyKey: "reviewer-cannot-relay"
            )
        }

        let admin = StubAPIClient(userID: UserID("u_stub_admin"), roles: [.tenantAdmin])
        await admin.setDelay(.zero)
        do {
            _ = try await admin.proofMap(caseID: caseID)
            Issue.record("Tenant admin unexpectedly received case proof")
        } catch let problem as ProblemDetails {
            #expect(problem.status == 404)
        }
    }

    @Test("Proof previews honor person scope and opaque-document denial")
    func proofPreviewScope() async throws {
        let api = StubAPIClient(personScope: [PersonID("p_carlos")])
        await api.setDelay(.zero)
        let map = try await api.proofMap(caseID: caseID)
        #expect(map.entries.allSatisfy { $0.subjectPersonID == PersonID("p_carlos") })

        for inaccessible in [DocumentID("d_greencard"), DocumentID("d_sealed")] {
            do {
                _ = try await api.documentPagePreview(documentID: inaccessible, pageNumber: 1)
                Issue.record("Inaccessible document unexpectedly returned a preview")
            } catch let problem as ProblemDetails {
                #expect(problem.status == 404)
            }
        }
    }
}
