import Foundation

/// A candidate value awaiting a human decision. Zero-or-many may be open per field.
///
/// Separated from `FieldValue` (SME B-02) so a *new* proposal can coexist with an
/// *already-confirmed* value. Rev A collapsed the two behind a unique index, which made
/// "never silently overwrite a human" impossible to implement: a fresh extraction that
/// disagreed with a confirmed value had nowhere to live.
public struct ValueProposal: Identifiable, Codable, Sendable, Hashable {
    public enum Disposition: String, Codable, Sendable {
        case open = "OPEN"
        case accepted = "ACCEPTED"
        case rejected = "REJECTED"
        case superseded = "SUPERSEDED"
    }

    public enum Origin: String, Codable, Sendable {
        case extraction = "EXTRACTION"
        case interview = "INTERVIEW"
        case derived = "DERIVED"
    }

    public let id: ProposalID
    public let caseID: CaseID
    public let subjectPersonID: PersonID
    public let canonicalPath: CanonicalPath
    public let proposedValue: String?
    public let confidenceBand: ConfidenceBand
    public let origin: Origin
    public let provenance: Provenance
    public let disposition: Disposition
    public let createdAt: Date

    public init(
        id: ProposalID,
        caseID: CaseID,
        subjectPersonID: PersonID,
        canonicalPath: CanonicalPath,
        proposedValue: String?,
        confidenceBand: ConfidenceBand,
        origin: Origin,
        provenance: Provenance,
        disposition: Disposition = .open,
        createdAt: Date
    ) {
        self.id = id
        self.caseID = caseID
        self.subjectPersonID = subjectPersonID
        self.canonicalPath = canonicalPath
        self.proposedValue = proposedValue
        self.confidenceBand = confidenceBand
        self.origin = origin
        self.provenance = provenance
        self.disposition = disposition
        self.createdAt = createdAt
    }

    /// Whether this proposal is model-generated rather than engine-extracted.
    /// Model-generated values are always `.needsReview` — enforced in the database by
    /// `CK_EV_ModelNeedsReview` and mirrored here so the client cannot render otherwise.
    public var isAwaitingHuman: Bool { disposition == .open }
}

/// **The** authoritative value. The only thing a generated PDF may read.
///
/// `confirmedBy` and `confirmedAt` are non-optional by design: a `FieldValue` can only
/// exist because a human put it there. The server enforces the same invariant with a
/// NOT NULL foreign key to `UserAccount`, so there is no representable state in which a
/// model's output reaches a government form unattended (AI-1, US-06.03).
public struct FieldValue: Identifiable, Codable, Sendable, Hashable {
    public enum Origin: String, Codable, Sendable {
        case extraction = "EXTRACTION"
        case interview = "INTERVIEW"
        case manual = "MANUAL"
        case derived = "DERIVED"
    }

    public var id: String { "\(caseID)|\(subjectPersonID)|\(canonicalPath)" }

    public let caseID: CaseID
    public let subjectPersonID: PersonID
    public let canonicalPath: CanonicalPath
    public let value: String?
    public let confidenceBand: ConfidenceBand
    public let origin: Origin
    public let provenance: Provenance
    public let acceptedProposalID: ProposalID?
    /// Who confirmed it. Never nil — see the type's documentation.
    public let confirmedBy: UserID
    /// Set when a Helper answered on the applicant's behalf, so the audit trail records
    /// the human who actually gave the answer rather than whose case it is.
    public let confirmedOnBehalfOf: PersonID?
    public let confirmedAt: Date
    /// Populated when two sources disagree. The system never arbitrates (AP-7).
    public let discrepancy: Discrepancy?

    public init(
        caseID: CaseID,
        subjectPersonID: PersonID,
        canonicalPath: CanonicalPath,
        value: String?,
        confidenceBand: ConfidenceBand,
        origin: Origin,
        provenance: Provenance,
        acceptedProposalID: ProposalID? = nil,
        confirmedBy: UserID,
        confirmedOnBehalfOf: PersonID? = nil,
        confirmedAt: Date,
        discrepancy: Discrepancy? = nil
    ) {
        self.caseID = caseID
        self.subjectPersonID = subjectPersonID
        self.canonicalPath = canonicalPath
        self.value = value
        self.confidenceBand = confidenceBand
        self.origin = origin
        self.provenance = provenance
        self.acceptedProposalID = acceptedProposalID
        self.confirmedBy = confirmedBy
        self.confirmedOnBehalfOf = confirmedOnBehalfOf
        self.confirmedAt = confirmedAt
        self.discrepancy = discrepancy
    }
}

/// A recorded conflict between two sources for the same logical value.
/// Always resolved by a human; the platform presents both and stops.
public struct Discrepancy: Identifiable, Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
        case nameVariant = "NAME_VARIANT"
        case dateConflict = "DATE_CONFLICT"
        case numberConflict = "NUMBER_CONFLICT"
        case expiryRisk = "EXPIRY_RISK"
        case checksumFail = "CHECKSUM_FAIL"
    }

    public enum Severity: String, Codable, Sendable {
        case blocking = "BLOCKING"
        case advisory = "ADVISORY"
    }

    public let id: DiscrepancyID
    public let kind: Kind
    public let severity: Severity
    public let description: String
    public let alternativeValue: String?
    public let alternativeAnchor: DocumentAnchor?

    public init(
        id: DiscrepancyID,
        kind: Kind,
        severity: Severity,
        description: String,
        alternativeValue: String? = nil,
        alternativeAnchor: DocumentAnchor? = nil
    ) {
        self.id = id
        self.kind = kind
        self.severity = severity
        self.description = description
        self.alternativeValue = alternativeValue
        self.alternativeAnchor = alternativeAnchor
    }
}

/// One reviewable row on the Review Information screen: the authoritative value if a
/// human has confirmed one, plus any proposal still waiting on them.
public struct ReviewableField: Identifiable, Sendable, Hashable {
    public var id: String { "\(subjectPersonID)|\(canonicalPath)" }

    public let subjectPersonID: PersonID
    public let canonicalPath: CanonicalPath
    /// The user's-language label, with the authoritative English form label alongside.
    public let localizedLabel: String
    public let englishFormLabel: String
    public let formReference: String
    public let confirmed: FieldValue?
    public let openProposal: ValueProposal?

    public init(
        subjectPersonID: PersonID,
        canonicalPath: CanonicalPath,
        localizedLabel: String,
        englishFormLabel: String,
        formReference: String,
        confirmed: FieldValue?,
        openProposal: ValueProposal?
    ) {
        self.subjectPersonID = subjectPersonID
        self.canonicalPath = canonicalPath
        self.localizedLabel = localizedLabel
        self.englishFormLabel = englishFormLabel
        self.formReference = formReference
        self.confirmed = confirmed
        self.openProposal = openProposal
    }

    public var displayValue: String? { confirmed?.value ?? openProposal?.proposedValue }
    public var band: ConfidenceBand { confirmed?.confidenceBand ?? openProposal?.confidenceBand ?? .needsReview }
    public var needsHuman: Bool { confirmed == nil || openProposal?.isAwaitingHuman == true }
    public var provenance: Provenance? { confirmed?.provenance ?? openProposal?.provenance }
    public var isBlocked: Bool { confirmed?.discrepancy?.severity == .blocking }
}
