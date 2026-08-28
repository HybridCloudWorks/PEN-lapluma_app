import Foundation

/// The Virtual Applicant Folder. A container for people, documents and cases.
/// Holds no personal data itself — every datum belongs to a `Person` (DP-4).
public struct Folder: Identifiable, Codable, Sendable, Hashable {
    public let id: FolderID
    public let name: String
    public let ownerUserID: UserID
    public let persons: [Person]
    public let documentCount: Int
    public let cases: [CaseSummary]

    public init(
        id: FolderID,
        name: String,
        ownerUserID: UserID,
        persons: [Person],
        documentCount: Int,
        cases: [CaseSummary]
    ) {
        self.id = id
        self.name = name
        self.ownerUserID = ownerUserID
        self.persons = persons
        self.documentCount = documentCount
        self.cases = cases
    }
}

/// A human the case is about. **The unit of privacy.**
///
/// `displayLabel` is a navigation label only. It is *not* the person's name and is
/// never written to a form — the authoritative name is a `FieldValue` with provenance,
/// like every other attribute (SME M-01).
public struct Person: Identifiable, Codable, Sendable, Hashable {
    public enum Participation: String, Codable, Sendable {
        case active = "ACTIVE"
        case invited = "INVITED"
        /// Set by Quiet Exit. Shown to others with no reason and no precise date.
        case inactive = "INACTIVE"
    }

    public let id: PersonID
    public let displayLabel: String
    public let isMinor: Bool
    public let participation: Participation
    public let holdsOwnCredential: Bool
    public let relationships: [Relationship]

    public init(
        id: PersonID,
        displayLabel: String,
        isMinor: Bool,
        participation: Participation,
        holdsOwnCredential: Bool,
        relationships: [Relationship] = []
    ) {
        self.id = id
        self.displayLabel = displayLabel
        self.isMinor = isMinor
        self.participation = participation
        self.holdsOwnCredential = holdsOwnCredential
        self.relationships = relationships
    }

    /// A minor may never hold their own credential — mirrored from the database
    /// constraint `CK_Person_MinorNoLogin`.
    public var canBeInvited: Bool { !isMinor && !holdsOwnCredential && participation == .active }
}

public struct Relationship: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case spouseOf = "SPOUSE_OF"
        case parentOf = "PARENT_OF"
        case childOf = "CHILD_OF"
        case siblingOf = "SIBLING_OF"
        case guardianOf = "GUARDIAN_OF"
        case petitionerFor = "PETITIONER_FOR"
        case beneficiaryOf = "BENEFICIARY_OF"
        case sponsorFor = "SPONSOR_FOR"
        case derivativeOf = "DERIVATIVE_OF"
    }

    public let kind: Kind
    public let objectPersonID: PersonID

    public init(kind: Kind, objectPersonID: PersonID) {
        self.kind = kind
        self.objectPersonID = objectPersonID
    }
}

extension Relationship.Kind {
    public var localizationKey: String { "relationship.\(rawValue)" }

    /// The same relationship read from the other person's side, where the model can
    /// express it. Recording only one direction leaves the counterpart looking
    /// unrelated, which is what package role resolution reads (T-75): a beneficiary
    /// added against a petitioner must make that petitioner a petitioner.
    ///
    /// Nil where no inverse kind exists — a guardian's ward, a sponsor's sponsee and
    /// a derivative's principal have no term here. Inventing one would put a
    /// relationship on a person that the model cannot actually represent.
    public var inverse: Relationship.Kind? {
        switch self {
        case .spouseOf: .spouseOf
        case .siblingOf: .siblingOf
        case .parentOf: .childOf
        case .childOf: .parentOf
        case .petitionerFor: .beneficiaryOf
        case .beneficiaryOf: .petitionerFor
        case .guardianOf, .sponsorFor, .derivativeOf: nil
        }
    }
}

/// One folder + one form package + one pinned edition set.
public struct CaseSummary: Identifiable, Codable, Sendable, Hashable {
    public let id: CaseID
    public let folderID: FolderID
    public let packageCode: String
    public let packageTitle: String
    public let state: CaseState
    public let counters: ProgressCounters
    public let pinnedForms: [PinnedForm]

    public init(
        id: CaseID,
        folderID: FolderID,
        packageCode: String,
        packageTitle: String,
        state: CaseState,
        counters: ProgressCounters,
        pinnedForms: [PinnedForm]
    ) {
        self.id = id
        self.folderID = folderID
        self.packageCode = packageCode
        self.packageTitle = packageTitle
        self.state = state
        self.counters = counters
        self.pinnedForms = pinnedForms
    }
}

/// The exact form edition a case is being prepared against. Pinned at case creation and
/// again at generation; both are recorded. Agencies reject packages on superseded
/// editions, and an edition can change without notice (ADR-003).
public struct PinnedForm: Codable, Sendable, Hashable {
    public let formNumber: String
    public let editionDate: Date
    public let sourceSHA256: String
    public let encoding: FormEncoding
    public let driftDetected: Bool

    public init(
        formNumber: String,
        editionDate: Date,
        sourceSHA256: String,
        encoding: FormEncoding,
        driftDetected: Bool = false
    ) {
        self.formNumber = formNumber
        self.editionDate = editionDate
        self.sourceSHA256 = sourceSHA256
        self.encoding = encoding
        self.driftDetected = driftDetected
    }
}

public enum FormEncoding: String, Codable, Sendable {
    /// Fillable programmatically. The only encoding in MVP scope.
    case acroForm = "ACROFORM"
    /// Dynamic XFA — cannot be filled reliably. Assisted-Fill-Only.
    case xfa = "XFA"
    /// Flattened, no form fields. Assisted-Fill-Only.
    case flat = "FLAT"

    public var supportsAutomaticFill: Bool { self == .acroForm }
}

/// The case state machine. Transitions are server-owned and audited; the client
/// mirrors it to drive navigation and to refuse actions that the server would reject.
public enum CaseState: String, Codable, Sendable, CaseIterable {
    case draft = "DRAFT"
    case collecting = "COLLECTING"
    case interviewing = "INTERVIEWING"
    case validating = "VALIDATING"
    case inReview = "IN_REVIEW"
    case changesRequested = "CHANGES_REQUESTED"
    case readyForApproval = "READY_FOR_APPROVAL"
    case approved = "APPROVED"
    case generated = "GENERATED"
    case delivered = "DELIVERED"
    case closed = "CLOSED"
    /// The agency republished a form this case is pinned to.
    case quarantinedFormDrift = "QUARANTINED_FORM_DRIFT"
    case onHold = "ON_HOLD"
    case abandoned = "ABANDONED"
}

extension CaseState {
    /// Whether the applicant can still add or change information.
    public var acceptsApplicantInput: Bool {
        switch self {
        case .draft, .collecting, .interviewing, .validating: true
        case .inReview, .changesRequested, .readyForApproval, .approved, .generated, .delivered, .closed,
             .quarantinedFormDrift, .onHold, .abandoned: false
        }
    }

    /// Quarantined cases are frozen until a human accepts the edition migration.
    public var isBlockedPendingHuman: Bool {
        self == .quarantinedFormDrift || self == .onHold
    }

    /// Whether producing filing output is legitimate from this state (T-62).
    ///
    /// `quarantinedFormDrift` is the load-bearing case: the agency republished a
    /// form this case is pinned to, so generating would fill an edition we know is
    /// stale. `changesRequested` is excluded because generating over a reviewer's
    /// open request routes around the review that produced it, and the terminal
    /// states cannot gain new output. Generation from `generated`/`delivered` is
    /// answered by returning the existing package, never by producing a second one.
    public var allowsPackageGeneration: Bool {
        switch self {
        case .draft, .collecting, .interviewing, .validating, .inReview, .readyForApproval, .approved: true
        case .changesRequested, .generated, .delivered, .closed,
             .quarantinedFormDrift, .onHold, .abandoned: false
        }
    }

    public var localizationKey: String { "caseState.\(rawValue)" }
}
