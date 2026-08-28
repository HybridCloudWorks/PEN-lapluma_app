import Foundation

public enum AppPersona: String, Codable, Sendable, CaseIterable {
    case applicant = "APPLICANT"
    case workforce = "WORKFORCE"
}

public enum WorkspaceRole: String, Codable, Sendable, CaseIterable {
    case applicant = "APPLICANT"
    case preparer = "PREPARER"
    case reviewer = "REVIEWER"
    case approver = "APPROVER"
    case tenantAdmin = "TENANT_ADMIN"
}

public enum WorkflowCapability: String, Codable, Sendable, CaseIterable {
    case viewApplicantFolder, viewClientDirectory, createClient, prepareCase
    case reviewCase, approveCase, generatePackage, exportPackage, administerWorkspace
    case viewProofMap, runGuidedFinish, manageEvidenceRelay
}

public struct AuthenticatedContext: Codable, Sendable, Hashable {
    public let userID: UserID
    public let workspaceCode: String
    public let personas: Set<AppPersona>
    public let roles: Set<WorkspaceRole>
    public let capabilities: Set<WorkflowCapability>
    public let isDemo: Bool

    public init(userID: UserID, workspaceCode: String, personas: Set<AppPersona>, roles: Set<WorkspaceRole>, capabilities: Set<WorkflowCapability>, isDemo: Bool) {
        self.userID = userID; self.workspaceCode = workspaceCode; self.personas = personas
        self.roles = roles; self.capabilities = capabilities; self.isDemo = isDemo
    }
}

public enum WorkflowPolicy {
    public static func capabilities(for roles: Set<WorkspaceRole>) -> Set<WorkflowCapability> {
        var result: Set<WorkflowCapability> = []
        if roles.contains(.applicant) {
            result.formUnion([.viewApplicantFolder, .viewProofMap, .runGuidedFinish, .manageEvidenceRelay])
        }
        if roles.contains(.preparer) {
            result.formUnion([.viewClientDirectory, .createClient, .prepareCase, .viewProofMap, .runGuidedFinish, .manageEvidenceRelay])
        }
        if roles.contains(.reviewer) { result.formUnion([.viewClientDirectory, .reviewCase, .viewProofMap]) }
        if roles.contains(.approver) {
            result.formUnion([.viewClientDirectory, .approveCase, .generatePackage, .exportPackage, .viewProofMap])
        }
        if roles.contains(.tenantAdmin) { result.formUnion([.viewClientDirectory, .administerWorkspace]) }
        return result
    }

    public static func canApprove(preparerID: UserID?, reviewerID: UserID?, approverID: UserID) -> Bool {
        preparerID != approverID && reviewerID != approverID && preparerID != reviewerID
    }

    public static func allowedTransition(from: CaseState, to: CaseState) -> Bool {
        switch (from, to) {
        case (.draft, .collecting), (.collecting, .validating), (.validating, .inReview),
             (.inReview, .changesRequested), (.inReview, .readyForApproval),
             (.changesRequested, .inReview), (.readyForApproval, .approved),
             (.approved, .generated), (.generated, .delivered), (.delivered, .closed): true
        // Form drift (T-77). Until this existed no edge led into
        // `quarantinedFormDrift`, so the state — and the protection it stands for —
        // was unreachable. A case can be frozen from any state that is still
        // preparing paperwork, and the way out is a human accepting the migration,
        // which returns the case to collecting because the new edition's fields
        // have to be reviewed again.
        case (.draft, .quarantinedFormDrift), (.collecting, .quarantinedFormDrift),
             (.interviewing, .quarantinedFormDrift), (.validating, .quarantinedFormDrift),
             (.inReview, .quarantinedFormDrift), (.changesRequested, .quarantinedFormDrift),
             (.readyForApproval, .quarantinedFormDrift), (.approved, .quarantinedFormDrift),
             (.quarantinedFormDrift, .collecting): true
        default: false
        }
    }
}

public struct ClientDirectoryEntry: Identifiable, Codable, Sendable, Hashable {
    public let id: FolderID
    public let displayLabel: String
    public let personCount: Int
    public let documentCount: Int
    public let primaryCase: CaseSummary?
    public let attentionCount: Int
    public init(id: FolderID, displayLabel: String, personCount: Int, documentCount: Int, primaryCase: CaseSummary?, attentionCount: Int) {
        self.id = id; self.displayLabel = displayLabel; self.personCount = personCount
        self.documentCount = documentCount; self.primaryCase = primaryCase; self.attentionCount = attentionCount
    }
}

public struct ClientDirectoryPage: Codable, Sendable, Hashable {
    public let items: [ClientDirectoryEntry]
    public let nextCursor: String?
    public init(items: [ClientDirectoryEntry], nextCursor: String? = nil) { self.items = items; self.nextCursor = nextCursor }
}

public struct CaseAssignments: Codable, Sendable, Hashable {
    public let preparerID: UserID?
    public let reviewerID: UserID?
    public let approverID: UserID?
    public init(preparerID: UserID? = nil, reviewerID: UserID? = nil, approverID: UserID? = nil) {
        self.preparerID = preparerID; self.reviewerID = reviewerID; self.approverID = approverID
    }
}

public struct FormFieldReference: Codable, Sendable, Hashable {
    public let formNumber: String
    public let page: Int
    public let fieldName: String
    public init(formNumber: String, page: Int, fieldName: String) { self.formNumber = formNumber; self.page = page; self.fieldName = fieldName }
}

public struct CanonicalFormField: Identifiable, Codable, Sendable, Hashable {
    public var id: String { "\(personID.rawValue):\(path.rawValue)" }
    public let personID: PersonID
    public let path: CanonicalPath
    public let label: String
    public let value: String
    public let required: Bool
    public let references: [FormFieldReference]
    public init(personID: PersonID, path: CanonicalPath, label: String, value: String, required: Bool, references: [FormFieldReference]) {
        self.personID = personID; self.path = path; self.label = label; self.value = value; self.required = required; self.references = references
    }
}

public struct FormSection: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let title: String
    public let formNumber: String
    public let revision: Int
    public let fields: [CanonicalFormField]
    public init(id: String, title: String, formNumber: String, revision: Int, fields: [CanonicalFormField]) {
        self.id = id; self.title = title; self.formNumber = formNumber; self.revision = revision; self.fields = fields
    }
}

public struct SectionCommit: Codable, Sendable, Hashable {
    public let section: FormSection
    public let reopenedReview: Bool
    public let invalidatedApproval: Bool
    public init(section: FormSection, reopenedReview: Bool, invalidatedApproval: Bool) {
        self.section = section; self.reopenedReview = reopenedReview; self.invalidatedApproval = invalidatedApproval
    }
}

public struct EvidenceRequirementItem: Identifiable, Codable, Sendable, Hashable {
    public var id: String { code }
    public let code: String
    public let title: String
    public let personRole: String
    public let citation: Citation
    public let linkedDocumentIDs: [DocumentID]
    public init(code: String, title: String, personRole: String, citation: Citation, linkedDocumentIDs: [DocumentID]) {
        self.code = code; self.title = title; self.personRole = personRole; self.citation = citation; self.linkedDocumentIDs = linkedDocumentIDs
    }
}

public struct ReviewQueueItem: Identifiable, Codable, Sendable, Hashable {
    public var id: CaseID { caseSummary.id }
    public let clientLabel: String
    public let caseSummary: CaseSummary
    public let ageDays: Int
    public let blockerCount: Int
    public init(clientLabel: String, caseSummary: CaseSummary, ageDays: Int, blockerCount: Int) {
        self.clientLabel = clientLabel; self.caseSummary = caseSummary; self.ageDays = ageDays; self.blockerCount = blockerCount
    }
}

public enum ReviewOutcome: String, Codable, Sendable { case changesRequested = "CHANGES_REQUESTED", readyForApproval = "READY_FOR_APPROVAL" }

public struct ReviewDecision: Codable, Sendable, Hashable {
    public let caseID: CaseID
    public let reviewerID: UserID
    public let outcome: ReviewOutcome
    public let note: String?
    public let decidedAt: Date
    public init(caseID: CaseID, reviewerID: UserID, outcome: ReviewOutcome, note: String?, decidedAt: Date) {
        self.caseID = caseID; self.reviewerID = reviewerID; self.outcome = outcome; self.note = note; self.decidedAt = decidedAt
    }
}

public struct DraftFormPreview: Codable, Sendable, Hashable {
    public let caseID: CaseID
    public let watermark: String
    public let pageCount: Int
    public let valueSetHash: String
    public let editionSetHash: String
    public let expiresAt: Date
    public init(caseID: CaseID, watermark: String, pageCount: Int, valueSetHash: String, editionSetHash: String, expiresAt: Date) {
        self.caseID = caseID; self.watermark = watermark; self.pageCount = pageCount
        self.valueSetHash = valueSetHash; self.editionSetHash = editionSetHash; self.expiresAt = expiresAt
    }
}

public struct ApprovalRecord: Codable, Sendable, Hashable {
    public let caseID: CaseID
    public let approverID: UserID
    public let valueSetHash: String
    public let editionSetHash: String
    public let attestedAt: Date
    public let valid: Bool
    public init(caseID: CaseID, approverID: UserID, valueSetHash: String, editionSetHash: String, attestedAt: Date, valid: Bool = true) {
        self.caseID = caseID; self.approverID = approverID; self.valueSetHash = valueSetHash
        self.editionSetHash = editionSetHash; self.attestedAt = attestedAt; self.valid = valid
    }
}

public struct CaseHistoryEvent: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let occurredAt: Date
    public let actorID: UserID
    public let kind: String
    public let summary: String
    public init(id: UUID = UUID(), occurredAt: Date, actorID: UserID, kind: String, summary: String) {
        self.id = id; self.occurredAt = occurredAt; self.actorID = actorID; self.kind = kind; self.summary = summary
    }
}

public struct CaseWorkspace: Codable, Sendable, Hashable {
    public let client: ClientDirectoryEntry
    public let summary: CaseSummary
    public let assignments: CaseAssignments
    public let sections: [FormSection]
    public let evidence: [EvidenceRequirementItem]
    public init(client: ClientDirectoryEntry, summary: CaseSummary, assignments: CaseAssignments, sections: [FormSection], evidence: [EvidenceRequirementItem]) {
        self.client = client; self.summary = summary; self.assignments = assignments; self.sections = sections; self.evidence = evidence
    }
}

public struct AdminMember: Identifiable, Codable, Sendable, Hashable {
    public let id: UserID
    public let displayLabel: String
    public let roles: Set<WorkspaceRole>
    public init(id: UserID, displayLabel: String, roles: Set<WorkspaceRole>) { self.id = id; self.displayLabel = displayLabel; self.roles = roles }
}

public struct ActiveWorkspaceSession: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let memberID: UserID
    public let deviceLabel: String
    public let lastSeenAt: Date
    public init(id: String, memberID: UserID, deviceLabel: String, lastSeenAt: Date) { self.id = id; self.memberID = memberID; self.deviceLabel = deviceLabel; self.lastSeenAt = lastSeenAt }
}

public struct AuditSummary: Codable, Sendable, Hashable {
    public let eventCount: Int
    public let securityEventCount: Int
    public let lastExportAt: Date?
    public init(eventCount: Int, securityEventCount: Int, lastExportAt: Date?) { self.eventCount = eventCount; self.securityEventCount = securityEventCount; self.lastExportAt = lastExportAt }
}

public struct DemoWorkspaceState: Codable, Sendable, Hashable {
    public let enabled: Bool
    public let workspaceCode: String
    public let lastResetAt: Date?
    public init(enabled: Bool, workspaceCode: String, lastResetAt: Date?) { self.enabled = enabled; self.workspaceCode = workspaceCode; self.lastResetAt = lastResetAt }
}
