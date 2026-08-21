import Foundation

/// An actionable gap, assigned to exactly one `Person` so a household can divide work.
///
/// Items belonging to another participant surface only as "waiting on someone else",
/// with no further detail — the per-person boundary holds even inside a shared folder.
public struct MissingItem: Identifiable, Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
        case field = "FIELD"
        case evidence = "EVIDENCE"
    }

    public enum Severity: String, Codable, Sendable {
        /// Required by the agency's own instructions.
        case blocking = "BLOCKING"
        /// Listed in the instructions but not required.
        case advisory = "ADVISORY"
    }

    public let id: MissingItemID
    public let kind: Kind
    public let severity: Severity
    public let assignedPersonID: PersonID
    public let assignedPersonLabel: String
    public let title: String
    /// Why it is required — always the agency's own words, cited.
    public let whyRequired: String
    public let citation: Citation?
    public let resolutionPaths: [ResolutionPath]
    public let batchID: BatchID?
    public let ageDays: Int
    /// Exact canonical field resolved by a field item. Optional so persisted Alpha
    /// fixtures remain decodable and evidence items do not invent a field binding.
    public let canonicalPath: CanonicalPath?
    /// Catalog-owned evidence requirement resolved by an evidence item.
    public let requirementCode: String?
    /// Curated minimum time for focused-session planning. Never model-generated.
    public let minimumEstimatedMinutes: Int?

    public init(
        id: MissingItemID,
        kind: Kind,
        severity: Severity,
        assignedPersonID: PersonID,
        assignedPersonLabel: String,
        title: String,
        whyRequired: String,
        citation: Citation?,
        resolutionPaths: [ResolutionPath],
        batchID: BatchID?,
        ageDays: Int,
        canonicalPath: CanonicalPath? = nil,
        requirementCode: String? = nil,
        minimumEstimatedMinutes: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.severity = severity
        self.assignedPersonID = assignedPersonID
        self.assignedPersonLabel = assignedPersonLabel
        self.title = title
        self.whyRequired = whyRequired
        self.citation = citation
        self.resolutionPaths = resolutionPaths
        self.batchID = batchID
        self.ageDays = ageDays
        self.canonicalPath = canonicalPath
        self.requirementCode = requirementCode
        self.minimumEstimatedMinutes = minimumEstimatedMinutes
    }
}

public struct ResolutionPath: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case scan = "SCAN"
        case importFile = "IMPORT"
        case answer = "ANSWER"
        case type = "TYPE"
        /// Routes to human review rather than leaving the user stuck.
        case cannotObtain = "CANNOT_OBTAIN"
        /// Creates an upload-only request; it never grants folder access.
        case privateRelay = "PRIVATE_RELAY"
    }

    public var id: String { kind.rawValue }
    public let kind: Kind
    public let label: String
    public let estimatedMinutes: Int?

    public init(kind: Kind, label: String, estimatedMinutes: Int? = nil) {
        self.kind = kind
        self.label = label
        self.estimatedMinutes = estimatedMinutes
    }
}

/// A group of missing items sized for a single sitting.
public struct MissingItemBatch: Identifiable, Codable, Sendable, Hashable {
    public let id: BatchID
    public let itemCount: Int
    public let estimatedMinutes: Int
    public let supportedModalities: [InterviewModality]

    public init(
        id: BatchID,
        itemCount: Int,
        estimatedMinutes: Int,
        supportedModalities: [InterviewModality]
    ) {
        self.id = id
        self.itemCount = itemCount
        self.estimatedMinutes = estimatedMinutes
        self.supportedModalities = supportedModalities
    }
}

/// A pointer into the agency's own published instructions. Every requirement the
/// platform states carries one; an item without a citation is dropped, not shown (AP-5).
public struct Citation: Codable, Sendable, Hashable {
    public let sourceURL: URL
    public let documentTitle: String
    public let sectionRef: String?
    public let revisionDate: Date?
    public let quotedText: String?

    public init(
        sourceURL: URL,
        documentTitle: String,
        sectionRef: String? = nil,
        revisionDate: Date? = nil,
        quotedText: String? = nil
    ) {
        self.sourceURL = sourceURL
        self.documentTitle = documentTitle
        self.sectionRef = sectionRef
        self.revisionDate = revisionDate
        self.quotedText = quotedText
    }
}
