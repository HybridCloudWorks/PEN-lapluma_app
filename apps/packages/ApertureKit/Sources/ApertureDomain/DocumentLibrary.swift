import Foundation

/// Preparation capability disposition for a Document Blueprint.
/// Aligned with ADR-019 and backend preparation capabilities.
public enum PreparationMode: String, Codable, Sendable, CaseIterable {
    case fillablePdf = "FILLABLE_PDF"
    case staticAssisted = "STATIC_ASSISTED"
    case externalReference = "EXTERNAL_REFERENCE"

    public var supportsAutomaticFill: Bool { self == .fillablePdf }
    public var isInteractive: Bool { self != .externalReference }
}

/// Publication lifecycle state for Document Blueprints and Collections.
public enum PublicationState: String, Codable, Sendable, CaseIterable {
    case draft = "DRAFT"
    case validated = "VALIDATED"
    case inReview = "IN_REVIEW"
    case published = "PUBLISHED"
    case quarantined = "QUARANTINED"
    case withdrawn = "WITHDRAWN"
    case rolledBack = "ROLLED_BACK"

    public var isAvailable: Bool { self == .published }
}

/// Underlying form artifact type.
public enum BlueprintArtifactType: String, Codable, Sendable, CaseIterable {
    case officialPdf = "OFFICIAL_PDF"
    case xfa = "XFA"
    case flat = "FLAT"
    case externalLink = "EXTERNAL_LINK"
    case authoredTemplate = "AUTHORED_TEMPLATE"
}

/// Pinned member of a Document Collection.
public struct CollectionBlueprintMember: Identifiable, Codable, Sendable, Hashable {
    public var id: String { "\(namespace)/\(blueprintId)@r\(pinnedRevision)" }

    public let namespace: String
    public let blueprintId: String
    public let pinnedRevision: Int
    public let preparationMode: PreparationMode
    public let displayOrder: Int
    public let isRequired: Bool

    public init(
        namespace: String,
        blueprintId: String,
        pinnedRevision: Int,
        preparationMode: PreparationMode,
        displayOrder: Int,
        isRequired: Bool
    ) {
        self.namespace = namespace
        self.blueprintId = blueprintId
        self.pinnedRevision = pinnedRevision
        self.preparationMode = preparationMode
        self.displayOrder = displayOrder
        self.isRequired = isRequired
    }
}

/// Immutable, versioned Document Blueprint.
public struct DocumentBlueprint: Identifiable, Codable, Sendable, Hashable {
    public var id: String { "\(namespace)/\(blueprintId)@r\(revision)" }

    public let namespace: String
    public let blueprintId: String
    public let revision: Int
    public let title: String
    public let issuer: String
    public let officialEditionDate: Date?
    public let preparationMode: PreparationMode
    public let artifactType: BlueprintArtifactType
    public let sourceUrl: URL?
    public let sourceSha256: String?
    public let publicationState: PublicationState
    public let isLatest: Bool
    public let fieldCount: Int

    public init(
        namespace: String,
        blueprintId: String,
        revision: Int,
        title: String,
        issuer: String,
        officialEditionDate: Date? = nil,
        preparationMode: PreparationMode,
        artifactType: BlueprintArtifactType,
        sourceUrl: URL? = nil,
        sourceSha256: String? = nil,
        publicationState: PublicationState = .published,
        isLatest: Bool = true,
        fieldCount: Int = 0
    ) {
        self.namespace = namespace
        self.blueprintId = blueprintId
        self.revision = revision
        self.title = title
        self.issuer = issuer
        self.officialEditionDate = officialEditionDate
        self.preparationMode = preparationMode
        self.artifactType = artifactType
        self.sourceUrl = sourceUrl
        self.sourceSha256 = sourceSha256
        self.publicationState = publicationState
        self.isLatest = isLatest
        self.fieldCount = fieldCount
    }
}

/// Versioned Document Collection composed of immutable Blueprint members.
public struct DocumentCollection: Identifiable, Codable, Sendable, Hashable {
    public var id: String { "\(namespace)/\(collectionId)@r\(revision)" }

    public let namespace: String
    public let collectionId: String
    public let revision: Int
    public let title: String
    public let descriptionText: String?
    public let authority: String
    public let publicationState: PublicationState
    public let isLatest: Bool
    public let members: [CollectionBlueprintMember]
    public let legacyPackageCode: String?
    public let isSupported: Bool
    public let unsupportedReason: String?

    public init(
        namespace: String,
        collectionId: String,
        revision: Int,
        title: String,
        descriptionText: String? = nil,
        authority: String,
        publicationState: PublicationState = .published,
        isLatest: Bool = true,
        members: [CollectionBlueprintMember],
        legacyPackageCode: String? = nil,
        isSupported: Bool = true,
        unsupportedReason: String? = nil
    ) {
        self.namespace = namespace
        self.collectionId = collectionId
        self.revision = revision
        self.title = title
        self.descriptionText = descriptionText
        self.authority = authority
        self.publicationState = publicationState
        self.isLatest = isLatest
        self.members = members
        self.legacyPackageCode = legacyPackageCode
        self.isSupported = isSupported
        self.unsupportedReason = unsupportedReason
    }

    public var supportsAutomaticFill: Bool {
        !members.isEmpty && members.allSatisfy { $0.preparationMode.supportsAutomaticFill }
    }

    public var allowsCaseCreation: Bool {
        publicationState == .published && isSupported
    }
}

/// Cross-repository legacy package compatibility mapping.
public struct LegacyPackageMapping: Identifiable, Codable, Sendable, Hashable {
    public var id: String { packageCode }

    public let packageCode: String
    public let collectionNamespace: String
    public let collectionId: String
    public let pinnedRevision: Int
    public let displayName: String
    public let authority: String
    public let formNumbers: [String]
    public let blueprintMembers: [CollectionBlueprintMember]

    public init(
        packageCode: String,
        collectionNamespace: String,
        collectionId: String,
        pinnedRevision: Int,
        displayName: String,
        authority: String,
        formNumbers: [String],
        blueprintMembers: [CollectionBlueprintMember]
    ) {
        self.packageCode = packageCode
        self.collectionNamespace = collectionNamespace
        self.collectionId = collectionId
        self.pinnedRevision = pinnedRevision
        self.displayName = displayName
        self.authority = authority
        self.formNumbers = formNumbers
        self.blueprintMembers = blueprintMembers
    }
}

/// Source-cited, revision-bound official document guidance and fee references (INF-09, APP-03).
public struct DocumentGuidance: Identifiable, Codable, Sendable, Hashable {
    public var id: String { formId }

    public let formId: String
    public let formNumber: String
    public let authority: String
    public let officialInstructionsUrl: URL?
    public let feeScheduleCitationUrl: URL?
    public let feeUsdCents: Int?
    public let feeNotes: String?
    public let evidenceChecklist: [String]
    public let institutionGuidanceNotes: String?

    public init(
        formId: String,
        formNumber: String,
        authority: String,
        officialInstructionsUrl: URL? = nil,
        feeScheduleCitationUrl: URL? = nil,
        feeUsdCents: Int? = nil,
        feeNotes: String? = nil,
        evidenceChecklist: [String] = [],
        institutionGuidanceNotes: String? = nil
    ) {
        self.formId = formId
        self.formNumber = formNumber
        self.authority = authority
        self.officialInstructionsUrl = officialInstructionsUrl
        self.feeScheduleCitationUrl = feeScheduleCitationUrl
        self.feeUsdCents = feeUsdCents
        self.feeNotes = feeNotes
        self.evidenceChecklist = evidenceChecklist
        self.institutionGuidanceNotes = institutionGuidanceNotes
    }
}
