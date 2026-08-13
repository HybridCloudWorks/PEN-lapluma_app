import Testing
import ApertureAPI
import ApertureDomain

@Suite("Workforce vertical slice")
struct WorkflowVerticalSliceTests {
    @Test("Capabilities do not collapse the three human stages")
    func capabilitiesAndSeparation() {
        #expect(WorkflowPolicy.capabilities(for: [.preparer]).contains(.prepareCase))
        #expect(!WorkflowPolicy.capabilities(for: [.preparer]).contains(.reviewCase))
        #expect(!WorkflowPolicy.capabilities(for: [.reviewer]).contains(.approveCase))
        #expect(WorkflowPolicy.canApprove(preparerID: UserID("p"), reviewerID: UserID("r"), approverID: UserID("a")))
        #expect(!WorkflowPolicy.canApprove(preparerID: UserID("same"), reviewerID: UserID("r"), approverID: UserID("same")))
    }

    @Test("Primary workflow transitions are explicit")
    func transitions() {
        #expect(WorkflowPolicy.allowedTransition(from: .inReview, to: .changesRequested))
        #expect(WorkflowPolicy.allowedTransition(from: .inReview, to: .readyForApproval))
        #expect(!WorkflowPolicy.allowedTransition(from: .collecting, to: .approved))
        #expect(!WorkflowPolicy.allowedTransition(from: .readyForApproval, to: .generated))
    }

    @Test("Canonical commits use optimistic concurrency and invalidate approval")
    func concurrencyAndInvalidation() async throws {
        let api = StubAPIClient(); await api.setDelay(.zero)
        let folder = try #require(try await api.folders().first)
        let caseID = try #require(folder.cases.first(where: { $0.state == .collecting })?.id)
        _ = try await api.transition(caseID: caseID, to: .validating, idempotencyKey: "to-validating")
        _ = try await api.transition(caseID: caseID, to: .inReview, idempotencyKey: "to-review")
        _ = try await api.recordReviewDecision(caseID: caseID, outcome: .readyForApproval, note: nil, idempotencyKey: "review")
        let preview = try await api.draftPreview(caseID: caseID)
        _ = try await api.approve(caseID: caseID, preview: preview, stepUpChallenge: "assertion", attested: true, idempotencyKey: "approve")
        let workspace = try await api.caseWorkspace(caseID: caseID)
        let section = try #require(workspace.sections.first)
        let result = try await api.commitSection(caseID: caseID, sectionID: section.id, baseRevision: section.revision, values: ["person.birth.date": "1980-01-01"], idempotencyKey: "commit")
        #expect(result.invalidatedApproval)
        #expect(try await api.caseSummary(id: caseID).state == .validating)
        await #expect(throws: ProblemDetails.self) {
            _ = try await api.commitSection(caseID: caseID, sectionID: section.id, baseRevision: section.revision, values: [:], idempotencyKey: "stale")
        }
    }

    @Test("One document can satisfy multiple cited requirements")
    func evidenceManyToMany() async throws {
        let api = StubAPIClient(); await api.setDelay(.zero)
        let folder = try #require(try await api.folders().first)
        let caseID = try #require(folder.cases.first?.id)
        let document = try #require(try await api.documents(folderID: folder.id).first)
        let workspace = try await api.caseWorkspace(caseID: caseID)
        let codes = Array(workspace.evidence.prefix(2).map(\.code))
        #expect(codes.count == 2)
        for code in codes { _ = try await api.linkEvidence(caseID: caseID, requirementCode: code, documentID: document.id, idempotencyKey: "link-\(code)") }
        let refreshed = try await api.caseWorkspace(caseID: caseID)
        #expect(refreshed.evidence.filter { codes.contains($0.code) }.allSatisfy { $0.linkedDocumentIDs.contains(document.id) })
    }

    @Test("Live fixtures cannot use demo reset")
    func demoRestriction() async {
        let api = StubAPIClient(); await api.setDelay(.zero)
        await #expect(throws: ProblemDetails.self) { _ = try await api.resetDemoWorkspace(idempotencyKey: "reset") }
    }
}
