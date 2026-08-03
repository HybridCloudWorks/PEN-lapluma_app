import Foundation

/// An append-only applicant-facing record of how a form value changed.
///
/// The current `FieldValue` is authoritative, but it never erases the evidence that
/// preceded it. Automated proposals have no human actor. Every event that changes the
/// authoritative value carries the human who performed it.
public struct ValueHistoryEntry: Identifiable, Codable, Sendable, Hashable {
    public enum Action: String, Codable, Sendable {
        case proposalRecorded = "PROPOSAL_RECORDED"
        case proposalSuperseded = "PROPOSAL_SUPERSEDED"
        case humanConfirmed = "HUMAN_CONFIRMED"
        case humanCorrected = "HUMAN_CORRECTED"
        case discrepancyResolved = "DISCREPANCY_RESOLVED"

        public var requiresHumanActor: Bool { self != .proposalRecorded }
    }

    public let id: String
    public let caseID: CaseID
    public let subjectPersonID: PersonID
    public let canonicalPath: CanonicalPath
    public let action: Action
    public let value: String?
    public let previousValue: String?
    public let provenance: Provenance
    public let confidenceBand: ConfidenceBand
    public let actorUserID: UserID?
    public let actorOnBehalfOf: PersonID?
    public let sourceProposalID: ProposalID?
    public let recordedAt: Date

    public init(
        id: String = UUID().uuidString,
        caseID: CaseID,
        subjectPersonID: PersonID,
        canonicalPath: CanonicalPath,
        action: Action,
        value: String?,
        previousValue: String? = nil,
        provenance: Provenance,
        confidenceBand: ConfidenceBand,
        actorUserID: UserID?,
        actorOnBehalfOf: PersonID? = nil,
        sourceProposalID: ProposalID? = nil,
        recordedAt: Date
    ) {
        self.id = id
        self.caseID = caseID
        self.subjectPersonID = subjectPersonID
        self.canonicalPath = canonicalPath
        self.action = action
        self.value = value
        self.previousValue = previousValue
        self.provenance = provenance
        self.confidenceBand = confidenceBand
        self.actorUserID = actorUserID
        self.actorOnBehalfOf = actorOnBehalfOf
        self.sourceProposalID = sourceProposalID
        self.recordedAt = recordedAt
    }

    /// A persisted ledger is invalid if an authoritative mutation has no human actor.
    public var hasRequiredAttribution: Bool {
        !action.requiresHumanActor || actorUserID != nil
    }
}

/// The mechanical gate evaluated before package generation. It contains counts, not
/// a prediction or completion score, and it never treats an open proposal as a value.
public struct PackageGenerationReadiness: Codable, Sendable, Hashable {
    public let unconfirmedRequiredFields: Int
    public let openProposals: Int
    public let blockingDiscrepancies: Int

    public init(
        unconfirmedRequiredFields: Int,
        openProposals: Int,
        blockingDiscrepancies: Int
    ) {
        self.unconfirmedRequiredFields = unconfirmedRequiredFields
        self.openProposals = openProposals
        self.blockingDiscrepancies = blockingDiscrepancies
    }

    public init(requiredFields: [ReviewableField]) {
        unconfirmedRequiredFields = requiredFields.filter { $0.confirmed == nil }.count
        openProposals = requiredFields.filter { $0.openProposal?.isAwaitingHuman == true }.count
        blockingDiscrepancies = requiredFields.filter(\.isBlocked).count
    }

    public var canGenerate: Bool {
        unconfirmedRequiredFields == 0 && openProposals == 0 && blockingDiscrepancies == 0
    }
}
