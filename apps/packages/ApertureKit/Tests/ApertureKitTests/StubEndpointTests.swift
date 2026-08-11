import Testing
import Foundation
import PDFKit
@testable import ApertureDomain
@testable import ApertureAPI

@Suite("PDF capture preparation")
struct PDFCapturePreparationTests {
    @Test("The PDF information dictionary is stripped before upload")
    func pdfInformationDictionaryIsStripped() throws {
        let document = PDFDocument()
        document.insert(PDFPage(), at: 0)
        document.documentAttributes = [
            PDFDocumentAttribute.authorAttribute: "Test Author",
            PDFDocumentAttribute.titleAttribute: "Secret Title"
        ]
        let input = try #require(document.dataRepresentation())

        let prepared = try CapturePayloadProcessor.prepare(input)
        #expect(prepared.verifiedMIMEType == "application/pdf")
        #expect(prepared.pageCount == 1)
        #expect(prepared.strippedImageMetadata)
        #expect(prepared.contentSHA256 == CapturePayloadProcessor.sha256(of: prepared.data))

        let reread = try #require(PDFDocument(data: prepared.data))
        #expect(reread.pageCount == 1)
        let attributeValues = (reread.documentAttributes ?? [:]).values.compactMap { $0 as? String }
        #expect(!attributeValues.contains("Test Author"))
        #expect(!attributeValues.contains("Secret Title"))
    }
}

@Suite("Extraction verification policy")
struct ExtractionVerificationTests {
    @Test("A checksum-valid, well-anchored structured identifier reaches VERIFIED")
    func structuredIdentifierCanBeVerified() {
        let anchor = DocumentAnchor(
            documentID: DocumentID("d1"), documentName: "Passport", pageNumber: 1,
            boundingPolygon: [
                CGPointCodable(x: 0.1, y: 0.1), CGPointCodable(x: 0.4, y: 0.1),
                CGPointCodable(x: 0.4, y: 0.2)
            ],
            engine: "engine", engineVersion: "1", rawConfidence: 0.95,
            checksumValid: true
        )
        let decision = ExtractionSafetyPolicy.assess(ExtractionCandidate(
            source: .extractionEngine,
            kind: .structuredIdentifier,
            anchor: anchor
        ))
        #expect(decision.disposition == .offerForHumanReview)
        #expect(decision.confidenceBand == .verified)
        #expect(decision.reviewReasons.isEmpty)
        #expect(!decision.raisesSecurityEvent)
    }

    @Test("Degeneracy is decided by distinct points, not point count")
    func degeneracyRequiresDistinctPoints() {
        let repeated = DocumentAnchor(
            documentID: DocumentID("d1"), documentName: "Passport", pageNumber: 1,
            boundingPolygon: [
                CGPointCodable(x: 0.2, y: 0.2), CGPointCodable(x: 0.2, y: 0.2),
                CGPointCodable(x: 0.2, y: 0.2)
            ],
            engine: "engine", engineVersion: "1", rawConfidence: 0.99
        )
        #expect(repeated.isDegenerate)

        let distinct = DocumentAnchor(
            documentID: DocumentID("d1"), documentName: "Passport", pageNumber: 1,
            boundingPolygon: [
                CGPointCodable(x: 0.2, y: 0.2), CGPointCodable(x: 0.5, y: 0.2),
                CGPointCodable(x: 0.5, y: 0.3)
            ],
            engine: "engine", engineVersion: "1", rawConfidence: 0.99
        )
        #expect(!distinct.isDegenerate)
    }
}

@Suite("Stub interview endpoints")
struct StubInterviewEndpointTests {
    @Test("An advice request is answered with the deterministic refusal")
    func guardrailBlocksAdviceRequests() async throws {
        let api = StubAPIClient(persistenceURL: nil)
        await api.setDelay(.zero)

        let session = try await api.startInterview(
            caseID: CaseID("c_ramirez_i130"), personID: PersonID("p_carlos"),
            batchID: BatchID("mi_batch_017"), modality: .chat,
            consent: nil, accessibilityProfileEnabled: false,
            idempotencyKey: "guardrail-start"
        )

        let turns = try await api.sendInterviewMessage(
            sessionID: session.id,
            text: "Will I get approved if I file this?",
            idempotencyKey: "guardrail-blocked"
        )
        let reply = try #require(turns.last)
        #expect(reply.role == .assistant)
        #expect(reply.guardrailBlocked)
        #expect(reply.isDeterministic)
        #expect(reply.question == nil)
        #expect(reply.text == StubGuardrail.deterministicRefusal)

        // A blocked reply carries no question, so it must not advance the script:
        // the next benign turn still gets the first scripted question.
        let resumed = try await api.sendInterviewMessage(
            sessionID: session.id,
            text: "Ready to continue",
            idempotencyKey: "guardrail-resume"
        )
        #expect(resumed.last?.question?.id == "q_birth_city")
    }

    @Test("The scripted questions advance in order and the session ends cleanly")
    func interviewScriptAdvancesAndEnds() async throws {
        let api = StubAPIClient(persistenceURL: nil)
        await api.setDelay(.zero)

        let session = try await api.startInterview(
            caseID: CaseID("c_ramirez_i130"), personID: PersonID("p_carlos"),
            batchID: BatchID("mi_batch_017"), modality: .form,
            consent: nil, accessibilityProfileEnabled: false,
            idempotencyKey: "script-start"
        )

        let first = try await api.sendInterviewMessage(
            sessionID: session.id, text: "Begin structured questions",
            idempotencyKey: "script-1"
        )
        #expect(first.last?.question?.id == "q_birth_city")
        #expect(first.last?.question?.canonicalPath == CanonicalPath("person.birth.city"))

        let second = try await api.sendInterviewMessage(
            sessionID: session.id, text: "Quetzaltenango",
            idempotencyKey: "script-2"
        )
        #expect(second.last?.question?.id == "q_family_name")

        let third = try await api.sendInterviewMessage(
            sessionID: session.id, text: "Ramírez",
            idempotencyKey: "script-3"
        )
        #expect(third.last?.question?.id == "q_last_entry_date")

        let fourth = try await api.sendInterviewMessage(
            sessionID: session.id, text: "2020-03-04",
            idempotencyKey: "script-4"
        )
        #expect(fourth.last?.question == nil)
        #expect(fourth.last?.text == "Thanks — that's everything for now.")

        try await api.endInterview(sessionID: session.id)
        do {
            _ = try await api.sendInterviewMessage(
                sessionID: session.id, text: "One more thing",
                idempotencyKey: "script-after-end"
            )
            Issue.record("A message to an ended session must be rejected")
        } catch let problem as ProblemDetails {
            #expect(problem.status == 404)
        }
    }
}

@Suite("Stub export, consent and document endpoints")
struct StubEndpointTests {
    @Test("Secure-link export returns a capped, expiring, unrevoked link")
    func exportSecureLink() async throws {
        let api = StubAPIClient(persistenceURL: nil)
        await api.setDelay(.zero)

        let secureResult = try await api.export(
            packageID: PackageID("pkg_demo_ready"),
            channel: .secureLink,
            recipientEmail: "recipient@example.test",
            idempotencyKey: "export-secure"
        )
        guard case .deliveryLink(let link) = secureResult else {
            Issue.record("Secure delivery must return a link, not local bytes")
            return
        }
        #expect(!link.id.isEmpty)
        #expect(link.maxDownloads == 3)
        #expect(link.downloadCount == 0)
        #expect(!link.revoked)
        #expect(link.expiresAt > Date())
        #expect(link.isLive)

        let filesResult = try await api.export(
            packageID: PackageID("pkg_demo_ready"),
            channel: .files,
            recipientEmail: nil,
            idempotencyKey: "export-files"
        )
        guard case .artifact(let artifact) = filesResult else {
            Issue.record("Files export must return the generated package bytes")
            return
        }
        #expect(artifact.fileName.hasSuffix(".pdf"))
        #expect(artifact.mimeType == "application/pdf")
        #expect(artifact.pageCount == 24)
        #expect(artifact.contentSHA256 == CapturePayloadProcessor.sha256(of: artifact.data))
        let prepared = try CapturePayloadProcessor.prepare(artifact.data)
        #expect(prepared.pageCount == artifact.pageCount)
        #expect(prepared.verifiedMIMEType == "application/pdf")

        let printResult = try await api.export(
            packageID: PackageID("pkg_demo_ready"),
            channel: .print,
            recipientEmail: nil,
            idempotencyKey: "export-print"
        )
        guard case .artifact(let printArtifact) = printResult else {
            Issue.record("Print export must return printable package bytes")
            return
        }
        #expect(printArtifact.data == artifact.data)
        #expect(printArtifact.contentSHA256 == artifact.contentSHA256)
    }

    @Test("Consent changes record grant and withdrawal timestamps")
    func consentLifecycleIsRecorded() async throws {
        let api = StubAPIClient(persistenceURL: nil)
        await api.setDelay(.zero)

        let granted = try await api.setConsent(purpose: .analytics, granted: true)
        #expect(granted.granted)
        #expect(granted.grantedAt != nil)
        #expect(granted.withdrawnAt == nil)
        let afterGrant = try await api.consents()
        #expect(afterGrant.first { $0.purpose == .analytics }?.granted == true)

        let withdrawn = try await api.setConsent(purpose: .analytics, granted: false)
        #expect(!withdrawn.granted)
        #expect(withdrawn.grantedAt == nil)
        #expect(withdrawn.withdrawnAt != nil)
        let afterWithdrawal = try await api.consents()
        #expect(afterWithdrawal.first { $0.purpose == .analytics }?.granted == false)
    }

    @Test("Deleting a document decrements its folder count exactly once")
    func deleteDocumentCounterMath() async throws {
        let api = StubAPIClient(persistenceURL: nil)
        await api.setDelay(.zero)
        let folderID = FolderID("f_ramirez")

        let before = try #require(
            try await api.folders().first { $0.id == folderID }
        )
        try await api.deleteDocument(id: DocumentID("d_passport"))

        let after = try #require(
            try await api.folders().first { $0.id == folderID }
        )
        #expect(after.documentCount == before.documentCount - 1)
        #expect(after.documentCount >= 0)
        let documents = try await api.documents(folderID: folderID)
        #expect(!documents.contains { $0.id == DocumentID("d_passport") })

        // Repeating the deletion is a no-op in the stub: the counter must not
        // decrement again for a document that is already gone.
        try await api.deleteDocument(id: DocumentID("d_passport"))
        let repeated = try #require(
            try await api.folders().first { $0.id == folderID }
        )
        #expect(repeated.documentCount == after.documentCount)
    }
}
