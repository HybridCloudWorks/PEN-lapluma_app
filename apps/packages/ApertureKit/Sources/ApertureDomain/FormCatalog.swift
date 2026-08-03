import Foundation

/// Stable, non-personal taxonomy values supplied by catalog operations. They are
/// deliberately independent of a user, folder, or case (ADR-001).
public struct CatalogCategory: Identifiable, Codable, Sendable, Hashable {
    public var id: String { code }
    public let code: String
    public let title: String
    public let sortOrder: Int

    public init(code: String, title: String, sortOrder: Int) {
        self.code = code
        self.title = title
        self.sortOrder = sortOrder
    }

    public static let uncategorized = CatalogCategory(
        code: "UNCATEGORIZED", title: "Other forms", sortOrder: .max
    )
}

public struct CatalogSubcategory: Identifiable, Codable, Sendable, Hashable {
    public var id: String { "\(categoryCode)/\(code)" }
    public let code: String
    public let categoryCode: String
    public let title: String
    public let sortOrder: Int

    public init(code: String, categoryCode: String, title: String, sortOrder: Int) {
        self.code = code
        self.categoryCode = categoryCode
        self.title = title
        self.sortOrder = sortOrder
    }

    public static let uncategorized = CatalogSubcategory(
        code: "UNCATEGORIZED", categoryCode: CatalogCategory.uncategorized.code,
        title: "Other", sortOrder: .max
    )
}

/// The source artifact's shape is separate from whether Aperture can safely act on it.
public enum FormArtifactKind: String, Codable, Sendable, CaseIterable {
    case officialPDF = "OFFICIAL_PDF"
    case externalWorkflow = "EXTERNAL_WORKFLOW"
    case proprietaryForm = "PROPRIETARY_FORM"
    case authoredTemplate = "AUTHORED_TEMPLATE"
}

public enum FormFillCapability: String, Codable, Sendable, CaseIterable {
    case automaticFill = "AUTOMATIC_FILL"
    case assistedPreparation = "ASSISTED_PREPARATION"
    case referenceOnly = "REFERENCE_ONLY"
}

/// Catalog presence never implies operational availability. Activation is explicit,
/// version-specific, and can therefore fail closed when an edition changes.
public enum FormActivationState: String, Codable, Sendable, CaseIterable {
    case unavailable = "UNAVAILABLE"
    case catalogOnly = "CATALOG_ONLY"
    case assisted = "ASSISTED"
    case pilot = "PILOT"

    public var allowsCaseCreation: Bool { self == .assisted || self == .pilot }
}

/// Immutable identity used by schemas and cases. A later agency edition is a new
/// identity rather than a mutation of an in-progress form.
public struct FormEditionID: Identifiable, Codable, Sendable, Hashable {
    private enum CodingKeys: String, CodingKey { case authority, formID, editionDate }

    /// Length-prefixed components avoid collisions even when an authority or form ID
    /// contains punctuation used by a human-readable identifier.
    public var id: String {
        let milliseconds = Int64((editionDate.timeIntervalSince1970 * 1_000).rounded())
        return "\(authority.utf8.count):\(authority)\(formID.utf8.count):\(formID)\(milliseconds)"
    }
    public let authority: String
    public let formID: String
    public let editionDate: Date

    public init(authority: String = "", formID: String, editionDate: Date) {
        self.authority = authority
        self.formID = formID
        self.editionDate = editionDate
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        authority = try values.decodeIfPresent(String.self, forKey: .authority) ?? ""
        formID = try values.decode(String.self, forKey: .formID)
        editionDate = try values.decode(Date.self, forKey: .editionDate)
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(authority, forKey: .authority)
        try values.encode(formID, forKey: .formID)
        try values.encode(editionDate, forKey: .editionDate)
    }
}

public struct FormSourceMetadata: Codable, Sendable, Hashable {
    public let issuingAuthority: String
    public let sourcePageURL: URL
    public let artifactURL: URL?
    public let officialDomain: String
    public let sha256: String?
    public let lastVerified: Date

    public init(
        issuingAuthority: String,
        sourcePageURL: URL,
        artifactURL: URL?,
        officialDomain: String,
        sha256: String?,
        lastVerified: Date
    ) {
        self.issuingAuthority = issuingAuthority
        self.sourcePageURL = sourcePageURL
        self.artifactURL = artifactURL
        self.officialDomain = officialDomain
        self.sha256 = sha256
        self.lastVerified = lastVerified
    }
}

public struct ExtractedFormSchema: Identifiable, Codable, Sendable, Hashable {
    public var id: String { "\(edition.id)#\(schemaVersion)" }
    public let edition: FormEditionID
    public let schemaVersion: String
    public let fields: [ExtractedFieldManifest]

    public init(edition: FormEditionID, schemaVersion: String, fields: [ExtractedFieldManifest]) {
        self.edition = edition
        self.schemaVersion = schemaVersion
        self.fields = fields
    }
}

public struct ExtractedFieldManifest: Identifiable, Codable, Sendable, Hashable {
    public enum ValueType: String, Codable, Sendable {
        case text = "TEXT"
        case date = "DATE"
        case boolean = "BOOLEAN"
        case choice = "CHOICE"
        case signature = "SIGNATURE"
    }

    public var id: String { fieldName }
    public let fieldName: String
    public let label: String
    public let valueType: ValueType
    public let required: Bool
    public let confidence: Double
    public let bounds: FieldBounds?

    public init(
        fieldName: String,
        label: String,
        valueType: ValueType,
        required: Bool,
        confidence: Double,
        bounds: FieldBounds?
    ) {
        self.fieldName = fieldName
        self.label = label
        self.valueType = valueType
        self.required = required
        self.confidence = confidence
        self.bounds = bounds
    }
}

public struct FieldBounds: Codable, Sendable, Hashable {
    public let page: Int
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(page: Int, x: Double, y: Double, width: Double, height: Double) {
        self.page = page
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// A curated set of forms filed together, e.g. `FAMILY_I130` = I-130 + I-130A.
///
/// Catalog browsing is the most compliance-sensitive surface in the product. The
/// catalog is **identical for every user**: results are ordered deterministically and
/// no ranking, personalisation or recommendation exists. The API accepts no case data,
/// so personalisation is not merely disallowed — it is impossible (ADR-001).
public struct FormPackage: Identifiable, Codable, Sendable, Hashable {
    private enum CodingKeys: String, CodingKey {
        case packageCode, title, category, subcategory, agency, agencyCategoryLabel
        case forms, feeUSDCents, feeCitationURL, sourceURL, lastVerified
    }
    public var id: String { packageCode }

    public let packageCode: String
    public let title: String
    public let category: CatalogCategory
    public let subcategory: CatalogSubcategory
    public let agency: String
    /// The agency's own category label. Never ours.
    public let agencyCategoryLabel: String?
    public let forms: [CatalogForm]
    public let feeUSDCents: Int?
    public let feeCitationURL: URL?
    public let sourceURL: URL
    public let lastVerified: Date

    public init(
        packageCode: String,
        title: String,
        category: CatalogCategory = .uncategorized,
        subcategory: CatalogSubcategory = .uncategorized,
        agency: String,
        agencyCategoryLabel: String?,
        forms: [CatalogForm],
        feeUSDCents: Int?,
        feeCitationURL: URL?,
        sourceURL: URL,
        lastVerified: Date
    ) {
        self.packageCode = packageCode
        self.title = title
        self.category = category
        self.subcategory = subcategory
        self.agency = agency
        self.agencyCategoryLabel = agencyCategoryLabel
        self.forms = forms
        self.feeUSDCents = feeUSDCents
        self.feeCitationURL = feeCitationURL
        self.sourceURL = sourceURL
        self.lastVerified = lastVerified
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        packageCode = try values.decode(String.self, forKey: .packageCode)
        title = try values.decode(String.self, forKey: .title)
        category = try values.decodeIfPresent(CatalogCategory.self, forKey: .category) ?? .uncategorized
        subcategory = try values.decodeIfPresent(CatalogSubcategory.self, forKey: .subcategory) ?? .uncategorized
        agency = try values.decode(String.self, forKey: .agency)
        agencyCategoryLabel = try values.decodeIfPresent(String.self, forKey: .agencyCategoryLabel)
        forms = try values.decode([CatalogForm].self, forKey: .forms)
        feeUSDCents = try values.decodeIfPresent(Int.self, forKey: .feeUSDCents)
        feeCitationURL = try values.decodeIfPresent(URL.self, forKey: .feeCitationURL)
        sourceURL = try values.decode(URL.self, forKey: .sourceURL)
        lastVerified = try values.decode(Date.self, forKey: .lastVerified)
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(packageCode, forKey: .packageCode)
        try values.encode(title, forKey: .title)
        try values.encode(category, forKey: .category)
        try values.encode(subcategory, forKey: .subcategory)
        try values.encode(agency, forKey: .agency)
        try values.encodeIfPresent(agencyCategoryLabel, forKey: .agencyCategoryLabel)
        try values.encode(forms, forKey: .forms)
        try values.encodeIfPresent(feeUSDCents, forKey: .feeUSDCents)
        try values.encodeIfPresent(feeCitationURL, forKey: .feeCitationURL)
        try values.encode(sourceURL, forKey: .sourceURL)
        try values.encode(lastVerified, forKey: .lastVerified)
    }

    /// True when every form in the package can be filled programmatically.
    /// A package containing an XFA or flat form is Assisted-Fill-Only and says so.
    public var supportsAutomaticFill: Bool {
        forms.allSatisfy { $0.fillCapability == .automaticFill }
    }

    public var activationState: FormActivationState {
        if forms.contains(where: { $0.activationState == .unavailable }) { return .unavailable }
        if forms.contains(where: { $0.activationState == .catalogOnly }) { return .catalogOnly }
        if forms.contains(where: { $0.activationState == .assisted }) { return .assisted }
        return .pilot
    }
}

public struct CatalogForm: Identifiable, Codable, Sendable, Hashable {
    private enum CodingKeys: String, CodingKey {
        case formNumber, title, editionDate, encoding, pageCount
        case artifactKind, fillCapability, activationState, source
    }
    public var id: String { edition.id }
    public var edition: FormEditionID {
        FormEditionID(
            authority: source?.issuingAuthority ?? "",
            formID: formNumber,
            editionDate: editionDate
        )
    }

    public let formNumber: String
    public let title: String
    public let editionDate: Date
    public let encoding: FormEncoding
    public let pageCount: Int
    public let artifactKind: FormArtifactKind
    public let fillCapability: FormFillCapability
    public let activationState: FormActivationState
    public let source: FormSourceMetadata?

    public init(
        formNumber: String,
        title: String,
        editionDate: Date,
        encoding: FormEncoding,
        pageCount: Int,
        artifactKind: FormArtifactKind = .officialPDF,
        fillCapability: FormFillCapability? = nil,
        activationState: FormActivationState = .catalogOnly,
        source: FormSourceMetadata? = nil
    ) {
        self.formNumber = formNumber
        self.title = title
        self.editionDate = editionDate
        self.encoding = encoding
        self.pageCount = pageCount
        self.artifactKind = artifactKind
        self.fillCapability = fillCapability ?? (encoding.supportsAutomaticFill ? .automaticFill : .assistedPreparation)
        self.activationState = activationState
        self.source = source
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        formNumber = try values.decode(String.self, forKey: .formNumber)
        title = try values.decode(String.self, forKey: .title)
        editionDate = try values.decode(Date.self, forKey: .editionDate)
        encoding = try values.decode(FormEncoding.self, forKey: .encoding)
        pageCount = try values.decode(Int.self, forKey: .pageCount)
        artifactKind = try values.decodeIfPresent(FormArtifactKind.self, forKey: .artifactKind) ?? .officialPDF
        fillCapability = try values.decodeIfPresent(FormFillCapability.self, forKey: .fillCapability)
            ?? (encoding.supportsAutomaticFill ? .automaticFill : .assistedPreparation)
        activationState = try values.decodeIfPresent(FormActivationState.self, forKey: .activationState)
            ?? .catalogOnly
        source = try values.decodeIfPresent(FormSourceMetadata.self, forKey: .source)
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(formNumber, forKey: .formNumber)
        try values.encode(title, forKey: .title)
        try values.encode(editionDate, forKey: .editionDate)
        try values.encode(encoding, forKey: .encoding)
        try values.encode(pageCount, forKey: .pageCount)
        try values.encode(artifactKind, forKey: .artifactKind)
        try values.encode(fillCapability, forKey: .fillCapability)
        try values.encode(activationState, forKey: .activationState)
        try values.encodeIfPresent(source, forKey: .source)
    }
}

/// What a selected package requires, derived from the pinned edition's field map and
/// the agency's published instructions — never from a model's memory of a form.
public struct RequirementSet: Codable, Sendable {
    public let packageCode: String
    public let fieldCount: Int
    public let evidence: [EvidenceRequirement]

    public init(packageCode: String, fieldCount: Int, evidence: [EvidenceRequirement]) {
        self.packageCode = packageCode
        self.fieldCount = fieldCount
        self.evidence = evidence
    }
}

public struct EvidenceRequirement: Identifiable, Codable, Sendable, Hashable {
    public var id: String { code }

    public let code: String
    public let personRole: String
    public let requirementDescription: String
    public let isConditional: Bool
    /// The agency's own conditional language, verbatim. We do not resolve the
    /// condition for the user and we do not paraphrase it.
    public let conditionText: String?
    public let citation: Citation

    public init(
        code: String,
        personRole: String,
        requirementDescription: String,
        isConditional: Bool,
        conditionText: String?,
        citation: Citation
    ) {
        self.code = code
        self.personRole = personRole
        self.requirementDescription = requirementDescription
        self.isConditional = isConditional
        self.conditionText = conditionText
        self.citation = citation
    }
}

/// The user's recorded confirmation that *they* chose the package.
/// A case cannot be created without it.
public struct SelectionAttestation: Codable, Sendable, Hashable {
    public let attested: Bool
    public let attestationVersion: String
    public let text: String

    public init(attested: Bool, attestationVersion: String, text: String) {
        self.attested = attested
        self.attestationVersion = attestationVersion
        self.text = text
    }
}
