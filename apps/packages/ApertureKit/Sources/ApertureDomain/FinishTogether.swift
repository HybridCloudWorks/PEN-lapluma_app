import Foundation

public struct GuidedFinishPlan: Codable, Sendable, Hashable {
    public let caseID: CaseID
    public let minutesBudget: Int
    public let estimatedMinutes: Int
    public let steps: [GuidedFinishStep]

    public init(caseID: CaseID, minutesBudget: Int, estimatedMinutes: Int, steps: [GuidedFinishStep]) {
        self.caseID = caseID
        self.minutesBudget = minutesBudget
        self.estimatedMinutes = estimatedMinutes
        self.steps = steps
    }
}

public struct GuidedFinishStep: Identifiable, Codable, Sendable, Hashable {
    public enum Status: String, Codable, Sendable {
        case actionable = "ACTIONABLE"
        case waitingForRelay = "WAITING_FOR_RELAY"
        case relayLocked = "RELAY_LOCKED"
        case relayNeedsReview = "RELAY_NEEDS_REVIEW"
    }

    public let id: String
    public let itemIDs: [MissingItemID]
    public let title: String
    public let assignedPersonID: PersonID
    public let assignedPersonLabel: String
    public let severity: MissingItem.Severity
    public let estimatedMinutes: Int
    public let resolutionPaths: [ResolutionPath]
    public let batchID: BatchID?
    public let status: Status
    public let relayID: EvidenceRelayID?

    public init(
        id: String,
        itemIDs: [MissingItemID],
        title: String,
        assignedPersonID: PersonID,
        assignedPersonLabel: String,
        severity: MissingItem.Severity,
        estimatedMinutes: Int,
        resolutionPaths: [ResolutionPath],
        batchID: BatchID?,
        status: Status,
        relayID: EvidenceRelayID? = nil
    ) {
        self.id = id
        self.itemIDs = itemIDs
        self.title = title
        self.assignedPersonID = assignedPersonID
        self.assignedPersonLabel = assignedPersonLabel
        self.severity = severity
        self.estimatedMinutes = estimatedMinutes
        self.resolutionPaths = resolutionPaths
        self.batchID = batchID
        self.status = status
        self.relayID = relayID
    }
}

/// Deterministic prioritization of administrative work. This orders cited paperwork
/// tasks; it never ranks evidence strength or predicts an agency outcome.
public enum GuidedFinishPolicy {
    public static let supportedBudgets = [5, 10, 20]

    public static func makePlan(
        caseID: CaseID,
        minutesBudget: Int,
        items: [MissingItem],
        batches: [MissingItemBatch],
        relays: [EvidenceRelay]
    ) -> GuidedFinishPlan {
        let budget = supportedBudgets.contains(minutesBudget) ? minutesBudget : 10
        let activeRelays = Dictionary(uniqueKeysWithValues: relays.compactMap { relay in
            [.active, .locked, .received].contains(relay.status) ? (relay.missingItemID, relay) : nil
        })
        let batchByID = Dictionary(uniqueKeysWithValues: batches.map { ($0.id, $0) })
        let grouped = Dictionary(grouping: items.filter { $0.batchID != nil }, by: { $0.batchID! })
        var candidates: [(step: GuidedFinishStep, age: Int)] = []
        var batchedItemIDs: Set<MissingItemID> = []

        for (batchID, batchItems) in grouped {
            guard let batch = batchByID[batchID], let first = batchItems.first else { continue }
            batchedItemIDs.formUnion(batchItems.map(\.id))
            candidates.append((GuidedFinishStep(
                id: "batch:\(batchID.rawValue)",
                itemIDs: batchItems.map(\.id).sorted { $0.rawValue < $1.rawValue },
                title: "\(batch.itemCount) quick questions",
                assignedPersonID: first.assignedPersonID,
                assignedPersonLabel: first.assignedPersonLabel,
                severity: batchItems.contains { $0.severity == .blocking } ? .blocking : .advisory,
                estimatedMinutes: batch.estimatedMinutes,
                resolutionPaths: first.resolutionPaths,
                batchID: batchID,
                status: .actionable
            ), batchItems.map(\.ageDays).max() ?? 0))
        }

        for item in items where !batchedItemIDs.contains(item.id) {
            let relay = activeRelays[item.id]
            let estimate = item.minimumEstimatedMinutes
                ?? item.resolutionPaths.compactMap(\.estimatedMinutes).min()
                ?? (item.kind == .field ? 2 : 4)
            let status: GuidedFinishStep.Status
            switch relay?.status {
            case .active: status = .waitingForRelay
            case .locked: status = .relayLocked
            case .received: status = .relayNeedsReview
            default: status = .actionable
            }
            candidates.append((GuidedFinishStep(
                id: "item:\(item.id.rawValue)",
                itemIDs: [item.id],
                title: item.title,
                assignedPersonID: item.assignedPersonID,
                assignedPersonLabel: item.assignedPersonLabel,
                severity: item.severity,
                estimatedMinutes: status == .actionable ? estimate : 0,
                resolutionPaths: item.resolutionPaths,
                batchID: nil,
                status: status,
                relayID: relay?.id
            ), item.ageDays))
        }

        candidates.sort { lhs, rhs in
            let leftSeverity = lhs.step.severity == .blocking ? 0 : 1
            let rightSeverity = rhs.step.severity == .blocking ? 0 : 1
            if leftSeverity != rightSeverity { return leftSeverity < rightSeverity }
            let leftWaiting = lhs.step.status == .actionable ? 0 : 1
            let rightWaiting = rhs.step.status == .actionable ? 0 : 1
            if leftWaiting != rightWaiting { return leftWaiting < rightWaiting }
            if lhs.age != rhs.age { return lhs.age > rhs.age }
            return lhs.step.id < rhs.step.id
        }

        var selected: [GuidedFinishStep] = []
        var spent = 0
        for candidate in candidates where candidate.step.status == .actionable {
            let fits = spent + candidate.step.estimatedMinutes <= budget
            if fits || selected.isEmpty {
                selected.append(candidate.step)
                spent += candidate.step.estimatedMinutes
            }
        }
        let selectedIDs = Set(selected.map(\.id))
        let ordered = candidates.map(\.step).filter {
            $0.status != .actionable || selectedIDs.contains($0.id)
        }
        return GuidedFinishPlan(caseID: caseID, minutesBudget: budget, estimatedMinutes: spent, steps: ordered)
    }
}

public struct ProofMap: Codable, Sendable, Hashable {
    public let caseID: CaseID
    public let entries: [FieldProof]
    public init(caseID: CaseID, entries: [FieldProof]) { self.caseID = caseID; self.entries = entries }
}

public struct FieldProof: Identifiable, Codable, Sendable, Hashable {
    public var id: String { "\(subjectPersonID.rawValue)|\(canonicalPath.rawValue)" }
    public let subjectPersonID: PersonID
    public let localizedLabel: String
    public let englishFormLabel: String
    public let canonicalPath: CanonicalPath
    public let value: String?
    public let requiresHumanReview: Bool
    public let provenance: Provenance?
    public let destinations: [FormFieldReference]

    public init(subjectPersonID: PersonID, localizedLabel: String, englishFormLabel: String, canonicalPath: CanonicalPath, value: String?, requiresHumanReview: Bool, provenance: Provenance?, destinations: [FormFieldReference]) {
        self.subjectPersonID = subjectPersonID
        self.localizedLabel = localizedLabel
        self.englishFormLabel = englishFormLabel
        self.canonicalPath = canonicalPath
        self.value = value
        self.requiresHumanReview = requiresHumanReview
        self.provenance = provenance
        self.destinations = destinations
    }
}

public struct DocumentPagePreview: Codable, Sendable, Hashable {
    public let documentID: DocumentID
    public let pageNumber: Int
    public let mimeType: String
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let contentSHA256: String
    public let data: Data

    public init(documentID: DocumentID, pageNumber: Int, mimeType: String, pixelWidth: Int, pixelHeight: Int, contentSHA256: String, data: Data) {
        self.documentID = documentID; self.pageNumber = pageNumber; self.mimeType = mimeType
        self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight
        self.contentSHA256 = contentSHA256; self.data = data
    }
}

public enum EvidenceRelayStatus: String, Codable, Sendable, Hashable {
    case active = "ACTIVE"
    case locked = "LOCKED"
    case received = "RECEIVED"
    case accepted = "ACCEPTED"
    case rejected = "REJECTED"
    case revoked = "REVOKED"
    case expired = "EXPIRED"
}

public struct EvidenceRelay: Identifiable, Codable, Sendable, Hashable {
    public let id: EvidenceRelayID
    public let caseID: CaseID
    public let missingItemID: MissingItemID
    public let requirementCode: String
    public let requestedTitle: String
    public let subjectPersonID: PersonID
    public let createdBy: UserID
    public let createdAt: Date
    public let expiresAt: Date
    public let status: EvidenceRelayStatus
    public let failedCodeAttempts: Int
    public let submittedDocumentID: DocumentID?

    public init(id: EvidenceRelayID, caseID: CaseID, missingItemID: MissingItemID, requirementCode: String, requestedTitle: String, subjectPersonID: PersonID, createdBy: UserID, createdAt: Date, expiresAt: Date, status: EvidenceRelayStatus, failedCodeAttempts: Int = 0, submittedDocumentID: DocumentID? = nil) {
        self.id = id; self.caseID = caseID; self.missingItemID = missingItemID
        self.requirementCode = requirementCode; self.requestedTitle = requestedTitle
        self.subjectPersonID = subjectPersonID; self.createdBy = createdBy
        self.createdAt = createdAt; self.expiresAt = expiresAt; self.status = status
        self.failedCodeAttempts = failedCodeAttempts; self.submittedDocumentID = submittedDocumentID
    }
}

public struct CreateEvidenceRelayResult: Codable, Sendable, Hashable {
    public let relay: EvidenceRelay
    public let shareURL: URL
    public let accessCode: String
    public init(relay: EvidenceRelay, shareURL: URL, accessCode: String) {
        self.relay = relay; self.shareURL = shareURL; self.accessCode = accessCode
    }
}

/// Generic until the second factor succeeds; it intentionally contains no request title.
public struct RelayChallenge: Codable, Sendable, Hashable {
    public let isAvailable: Bool
    public let expiresAt: Date?
    public init(isAvailable: Bool, expiresAt: Date? = nil) { self.isAvailable = isAvailable; self.expiresAt = expiresAt }
}

public struct RelayUploadGrant: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let relayID: EvidenceRelayID
    public let requestedTitle: String
    public let expiresAt: Date
    public init(id: String, relayID: EvidenceRelayID, requestedTitle: String, expiresAt: Date) {
        self.id = id; self.relayID = relayID; self.requestedTitle = requestedTitle; self.expiresAt = expiresAt
    }
}

/// One write-only upload slot minted from a successful relay challenge. Its URL is
/// scoped to one object and expires quickly; it carries no case read capability.
public struct RelayUploadSession: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let uploadURL: URL
    public let expiresAt: Date
    public let expectedContentSHA256: String

    public init(id: String, uploadURL: URL, expiresAt: Date, expectedContentSHA256: String) {
        self.id = id
        self.uploadURL = uploadURL
        self.expiresAt = expiresAt
        self.expectedContentSHA256 = expectedContentSHA256
    }
}

public struct RelaySubmissionReceipt: Codable, Sendable, Hashable {
    public let relayID: EvidenceRelayID
    public let documentID: DocumentID
    public let status: EvidenceRelayStatus
    public init(relayID: EvidenceRelayID, documentID: DocumentID, status: EvidenceRelayStatus) {
        self.relayID = relayID; self.documentID = documentID; self.status = status
    }
}
