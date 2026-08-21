import Foundation
import ApertureDomain

extension StubAPIClient {
    public func authenticatedContext() async throws -> AuthenticatedContext {
        await pause()
        return AuthenticatedContext(
            userID: currentUser,
            workspaceCode: fixtureProfile == .marketingSafe ? "DEMO-SYNTHETIC" : "LOCAL-WORKSPACE",
            personas: workspaceRoles == [.applicant] ? [.applicant] : [.applicant, .workforce],
            roles: workspaceRoles,
            capabilities: WorkflowPolicy.capabilities(for: workspaceRoles),
            isDemo: fixtureProfile == .marketingSafe
        )
    }

    public func clientDirectory(query: String?, cursor: String?) async throws -> ClientDirectoryPage {
        await pause()
        let normalized = query?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let entries = storage.folders.compactMap { folder -> ClientDirectoryEntry? in
            guard normalized.isEmpty || folder.name.lowercased().contains(normalized)
                    || folder.cases.contains(where: { $0.packageTitle.lowercased().contains(normalized) }) else { return nil }
            let primary = folder.cases.first(where: { $0.state != .closed }) ?? folder.cases.first
            return ClientDirectoryEntry(
                id: folder.id, displayLabel: folder.name, personCount: folder.persons.count,
                documentCount: folder.documentCount, primaryCase: primary,
                attentionCount: primary?.counters.blockingItems ?? 0
            )
        }
        return ClientDirectoryPage(items: entries, nextCursor: nil)
    }

    public func createClient(label: String, idempotencyKey: String) async throws -> ClientDirectoryEntry {
        let folder = try await createFolder(name: label, idempotencyKey: idempotencyKey)
        return ClientDirectoryEntry(id: folder.id, displayLabel: folder.name, personCount: 0, documentCount: 0, primaryCase: nil, attentionCount: 0)
    }

    public func caseWorkspace(caseID: CaseID) async throws -> CaseWorkspace {
        await pause()
        guard let summary = storage.allCases.first(where: { $0.id == caseID }),
              let folder = storage.folders.first(where: { $0.id == summary.folderID }) else { throw notFound() }
        let client = ClientDirectoryEntry(id: folder.id, displayLabel: folder.name, personCount: folder.persons.count, documentCount: folder.documentCount, primaryCase: summary, attentionCount: summary.counters.blockingItems)
        return CaseWorkspace(client: client, summary: summary, assignments: assignments(for: caseID), sections: sections(for: caseID, summary: summary), evidence: evidence(for: caseID, summary: summary))
    }

    public func setAssignments(caseID: CaseID, assignments: CaseAssignments, idempotencyKey: String) async throws -> CaseAssignments {
        await pause(); try requireKey(idempotencyKey); guard storage.allCases.contains(where: { $0.id == caseID }) else { throw notFound() }
        guard assignments.approverID == nil || WorkflowPolicy.canApprove(preparerID: assignments.preparerID, reviewerID: assignments.reviewerID, approverID: assignments.approverID!) else {
            throw ProblemDetails(type: "https://api.aperture.app/problems/separation-of-duties", title: "Three distinct actors are required", status: 422)
        }
        return try commit {
            if storage.assignments == nil { storage.assignments = [:] }
            storage.assignments?[caseID] = assignments
            appendHistory(caseID, actor: currentUser, kind: "ASSIGNMENT_CHANGED", summary: "Case assignments changed")
            return assignments
        }
    }

    public func transition(caseID: CaseID, to state: CaseState, idempotencyKey: String) async throws -> CaseSummary {
        await pause(); try requireKey(idempotencyKey)
        guard let existing = storage.allCases.first(where: { $0.id == caseID }) else { throw notFound() }
        guard WorkflowPolicy.allowedTransition(from: existing.state, to: state) else {
            throw ProblemDetails(type: "https://api.aperture.app/problems/invalid-case-transition", title: "Case transition is not allowed", status: 409)
        }
        return try commit {
            let updated = replacing(existing, state: state)
            replaceCase(updated)
            appendHistory(caseID, actor: currentUser, kind: "STATE_CHANGED", summary: "Case moved to \(state.rawValue)")
            return updated
        }
    }

    public func commitSection(caseID: CaseID, sectionID: String, baseRevision: Int, values: [String: String], idempotencyKey: String) async throws -> SectionCommit {
        await pause(); try requireKey(idempotencyKey)
        guard let existing = storage.allCases.first(where: { $0.id == caseID }) else { throw notFound() }
        let revision = storage.sectionRevisions?[caseID]?[sectionID] ?? 1
        guard revision == baseRevision else {
            throw ProblemDetails(type: "https://api.aperture.app/problems/version-conflict", title: "This section changed on another device", status: 412, detail: "Reload to compare the saved version with your local draft.")
        }
        return try commit {
            if storage.sectionRevisions == nil { storage.sectionRevisions = [:] }
            if storage.sectionValues == nil { storage.sectionValues = [:] }
            var revisions = storage.sectionRevisions?[caseID] ?? [:]; revisions[sectionID] = revision + 1; storage.sectionRevisions?[caseID] = revisions
            var caseValues = storage.sectionValues?[caseID] ?? [:]; caseValues[sectionID] = values; storage.sectionValues?[caseID] = caseValues
            let reopen = [.inReview, .changesRequested, .readyForApproval].contains(existing.state)
            let invalidate = [.approved, .generated, .delivered].contains(existing.state)
            if reopen { replaceCase(replacing(existing, state: .validating)) }
            if invalidate {
                replaceCase(replacing(existing, state: .validating)); storage.approvals?[caseID] = nil; storage.packages[caseID] = nil
            }
            appendHistory(caseID, actor: currentUser, kind: "SECTION_COMMITTED", summary: "Canonical values committed from \(sectionID)")
            let current = storage.allCases.first(where: { $0.id == caseID }) ?? existing
            let section = sections(for: caseID, summary: current).first(where: { $0.id == sectionID }) ?? FormSection(id: sectionID, title: sectionID, formNumber: current.pinnedForms.first?.formNumber ?? "", revision: revision + 1, fields: [])
            return SectionCommit(section: section, reopenedReview: reopen, invalidatedApproval: invalidate)
        }
    }

    public func linkEvidence(caseID: CaseID, requirementCode: String, documentID: DocumentID, idempotencyKey: String) async throws -> EvidenceRequirementItem {
        await pause(); try requireKey(idempotencyKey)
        guard let summary = storage.allCases.first(where: { $0.id == caseID }), storage.documents.contains(where: { $0.id == documentID }) else { throw notFound() }
        return try commit {
            if storage.evidenceLinks == nil { storage.evidenceLinks = [:] }
            var links = storage.evidenceLinks?[caseID] ?? [:]
            var documents = links[requirementCode] ?? []; if !documents.contains(documentID) { documents.append(documentID) }
            links[requirementCode] = documents; storage.evidenceLinks?[caseID] = links
            storage.reconcileMissingItems(caseID: caseID)
            storage.bumpCounters(caseID: caseID, incrementsFilledCounter: false, incrementsDocumentsCounter: true)
            appendHistory(caseID, actor: currentUser, kind: "EVIDENCE_LINKED", summary: "Document linked to \(requirementCode)")
            guard let result = evidence(for: caseID, summary: summary).first(where: { $0.code == requirementCode }) else { throw notFound() }
            return result
        }
    }

    public func reviewQueue() async throws -> [ReviewQueueItem] {
        await pause()
        return storage.allCases.filter { [.validating, .inReview, .changesRequested, .readyForApproval].contains($0.state) }.map { summary in
            let label = storage.folders.first(where: { $0.id == summary.folderID })?.name ?? "Client"
            return ReviewQueueItem(clientLabel: label, caseSummary: summary, ageDays: 2, blockerCount: summary.counters.blockingItems)
        }
    }

    public func recordReviewDecision(caseID: CaseID, outcome: ReviewOutcome, note: String?, idempotencyKey: String) async throws -> ReviewDecision {
        await pause(); try requireKey(idempotencyKey)
        guard let existing = storage.allCases.first(where: { $0.id == caseID }), existing.state == .inReview else {
            throw ProblemDetails(type: "https://api.aperture.app/problems/review-state", title: "Case is not in review", status: 409)
        }
        let decision = ReviewDecision(caseID: caseID, reviewerID: UserID("u_stub_reviewer"), outcome: outcome, note: note, decidedAt: now())
        return try commit {
            if storage.reviewDecisions == nil { storage.reviewDecisions = [:] }
            storage.reviewDecisions?[caseID, default: []].append(decision)
            replaceCase(replacing(existing, state: outcome == .changesRequested ? .changesRequested : .readyForApproval))
            appendHistory(caseID, actor: decision.reviewerID, kind: "REVIEW_DECIDED", summary: outcome.rawValue)
            return decision
        }
    }

    public func draftPreview(caseID: CaseID) async throws -> DraftFormPreview {
        await pause(); guard let summary = storage.allCases.first(where: { $0.id == caseID }) else { throw notFound() }
        guard [.inReview, .readyForApproval, .approved].contains(summary.state) else {
            throw ProblemDetails(type: "https://api.aperture.app/problems/preview-state", title: "Preview is not available at this stage", status: 409)
        }
        let revision = (storage.sectionRevisions?[caseID]?.values.reduce(0, +) ?? 0)
        return DraftFormPreview(caseID: caseID, watermark: "DRAFT — NOT FOR FILING", pageCount: summary.pinnedForms.count * 8, valueSetHash: "stub-values-\(caseID.rawValue)-\(revision)", editionSetHash: summary.pinnedForms.map(\.sourceSHA256).joined(separator: ":"), expiresAt: now().addingTimeInterval(600))
    }

    public func approve(caseID: CaseID, preview: DraftFormPreview, stepUpChallenge: String, attested: Bool, idempotencyKey: String) async throws -> ApprovalRecord {
        await pause(); try requireKey(idempotencyKey)
        guard attested, !stepUpChallenge.isEmpty else { throw ProblemDetails(type: "https://api.aperture.app/problems/step-up-required", title: "Step-up authentication and attestation are required", status: 401) }
        guard let existing = storage.allCases.first(where: { $0.id == caseID }), existing.state == .readyForApproval else { throw ProblemDetails(type: "https://api.aperture.app/problems/approval-state", title: "Case is not ready for approval", status: 409) }
        let assignment = assignments(for: caseID); let approver = assignment.approverID ?? UserID("u_stub_approver")
        guard WorkflowPolicy.canApprove(preparerID: assignment.preparerID, reviewerID: assignment.reviewerID, approverID: approver) else { throw ProblemDetails(type: "https://api.aperture.app/problems/separation-of-duties", title: "Approver must be distinct", status: 403) }
        let currentPreview = try await draftPreview(caseID: caseID)
        guard preview.valueSetHash == currentPreview.valueSetHash, preview.editionSetHash == currentPreview.editionSetHash else { throw ProblemDetails(type: "https://api.aperture.app/problems/stale-preview", title: "Preview is no longer current", status: 409) }
        let record = ApprovalRecord(caseID: caseID, approverID: approver, valueSetHash: preview.valueSetHash, editionSetHash: preview.editionSetHash, attestedAt: now())
        return try commit { if storage.approvals == nil { storage.approvals = [:] }; storage.approvals?[caseID] = record; replaceCase(replacing(existing, state: .approved)); appendHistory(caseID, actor: approver, kind: "APPROVED", summary: "Step-up approval recorded"); return record }
    }

    public func caseHistory(caseID: CaseID) async throws -> [CaseHistoryEvent] { await pause(); return (storage.history?[caseID] ?? []).sorted { $0.occurredAt > $1.occurredAt } }

    public func adminMembers() async throws -> [AdminMember] {
        await pause(); return [AdminMember(id: UserID("u_stub_preparer"), displayLabel: "Demo Preparer", roles: [.preparer]), AdminMember(id: UserID("u_stub_reviewer"), displayLabel: "Demo Reviewer", roles: [.reviewer]), AdminMember(id: UserID("u_stub_approver"), displayLabel: "Demo Approver", roles: [.approver]), AdminMember(id: UserID("u_stub_admin"), displayLabel: "Workspace Admin", roles: [.tenantAdmin])]
    }
    public func activeWorkspaceSessions() async throws -> [ActiveWorkspaceSession] { await pause(); return [ActiveWorkspaceSession(id: "session-current", memberID: currentUser, deviceLabel: "This device", lastSeenAt: now())] }
    public func auditSummary() async throws -> AuditSummary { await pause(); return AuditSummary(eventCount: storage.history?.values.reduce(0) { $0 + $1.count } ?? 0, securityEventCount: 0, lastExportAt: nil) }
    public func demoWorkspaceState() async throws -> DemoWorkspaceState { await pause(); return DemoWorkspaceState(enabled: fixtureProfile == .marketingSafe, workspaceCode: "DEMO-SYNTHETIC", lastResetAt: storage.demoLastResetAt) }
    public func resetDemoWorkspace(idempotencyKey: String) async throws -> DemoWorkspaceState {
        await pause(); try requireKey(idempotencyKey); guard fixtureProfile == .marketingSafe else { throw ProblemDetails(type: "https://api.aperture.app/problems/demo-only", title: "Only the demo workspace can be reset", status: 403) }
        let resetAt = now(); try commit { storage = StubStorage.seeded(profile: .marketingSafe); storage.demoLastResetAt = resetAt }
        return DemoWorkspaceState(enabled: true, workspaceCode: "DEMO-SYNTHETIC", lastResetAt: resetAt)
    }

    private func assignments(for caseID: CaseID) -> CaseAssignments {
        storage.assignments?[caseID] ?? CaseAssignments(preparerID: UserID("u_stub_preparer"), reviewerID: UserID("u_stub_reviewer"), approverID: UserID("u_stub_approver"))
    }
    private func sections(for caseID: CaseID, summary: CaseSummary) -> [FormSection] {
        let fields = storage.reviewable[caseID] ?? []
        let form = summary.pinnedForms.first?.formNumber ?? "Form"
        let sectionID = "identity"
        let overlay = storage.sectionValues?[caseID]?[sectionID] ?? [:]
        return [FormSection(id: sectionID, title: "Identity and contact information", formNumber: form, revision: storage.sectionRevisions?[caseID]?[sectionID] ?? 1, fields: fields.map { field in
            CanonicalFormField(personID: field.subjectPersonID, path: field.canonicalPath, label: field.localizedLabel, value: overlay[field.canonicalPath.rawValue] ?? field.displayValue ?? "", required: true, references: [FormFieldReference(formNumber: form, page: 1, fieldName: field.englishFormLabel)])
        })]
    }
    private func evidence(for caseID: CaseID, summary: CaseSummary) -> [EvidenceRequirementItem] {
        (storage.requirements[summary.packageCode]?.evidence ?? []).map { requirement in EvidenceRequirementItem(code: requirement.code, title: requirement.requirementDescription, personRole: requirement.personRole, citation: requirement.citation, linkedDocumentIDs: storage.evidenceLinks?[caseID]?[requirement.code] ?? []) }
    }
    private func replacing(_ summary: CaseSummary, state: CaseState) -> CaseSummary { CaseSummary(id: summary.id, folderID: summary.folderID, packageCode: summary.packageCode, packageTitle: summary.packageTitle, state: state, counters: summary.counters, pinnedForms: summary.pinnedForms) }
    private func replaceCase(_ updated: CaseSummary) {
        if let index = storage.allCases.firstIndex(where: { $0.id == updated.id }) { storage.allCases[index] = updated }
        if let index = storage.folders.firstIndex(where: { $0.id == updated.folderID }) { let folder = storage.folders[index]; storage.folders[index] = Folder(id: folder.id, name: folder.name, ownerUserID: folder.ownerUserID, persons: folder.persons, documentCount: folder.documentCount, cases: folder.cases.map { $0.id == updated.id ? updated : $0 }) }
    }
    private func appendHistory(_ caseID: CaseID, actor: UserID, kind: String, summary: String) { if storage.history == nil { storage.history = [:] }; storage.history?[caseID, default: []].append(CaseHistoryEvent(occurredAt: now(), actorID: actor, kind: kind, summary: summary)) }
    private func requireKey(_ key: String) throws { if key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw ProblemDetails(type: "https://api.aperture.app/problems/idempotency-key-required", title: "Idempotency key required", status: 422) } }
    private func notFound() -> ProblemDetails { ProblemDetails(type: "https://api.aperture.app/problems/not-found", title: "Not found", status: 404) }
}
