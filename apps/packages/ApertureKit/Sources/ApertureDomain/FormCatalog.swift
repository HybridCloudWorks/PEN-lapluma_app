import Foundation

/// A curated set of forms filed together, e.g. `FAMILY_I130` = I-130 + I-130A.
///
/// Catalog browsing is the most compliance-sensitive surface in the product. The
/// catalog is **identical for every user**: results are ordered deterministically and
/// no ranking, personalisation or recommendation exists. The API accepts no case data,
/// so personalisation is not merely disallowed — it is impossible (ADR-001).
public struct FormPackage: Identifiable, Codable, Sendable, Hashable {
    public var id: String { packageCode }

    public let packageCode: String
    public let title: String
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
        self.agency = agency
        self.agencyCategoryLabel = agencyCategoryLabel
        self.forms = forms
        self.feeUSDCents = feeUSDCents
        self.feeCitationURL = feeCitationURL
        self.sourceURL = sourceURL
        self.lastVerified = lastVerified
    }

    /// True when every form in the package can be filled programmatically.
    /// A package containing an XFA or flat form is Assisted-Fill-Only and says so.
    public var supportsAutomaticFill: Bool {
        forms.allSatisfy { $0.encoding.supportsAutomaticFill }
    }
}

public struct CatalogForm: Identifiable, Codable, Sendable, Hashable {
    public var id: String { "\(formNumber)@\(editionDate.timeIntervalSince1970)" }

    public let formNumber: String
    public let title: String
    public let editionDate: Date
    public let encoding: FormEncoding
    public let pageCount: Int

    public init(
        formNumber: String,
        title: String,
        editionDate: Date,
        encoding: FormEncoding,
        pageCount: Int
    ) {
        self.formNumber = formNumber
        self.title = title
        self.editionDate = editionDate
        self.encoding = encoding
        self.pageCount = pageCount
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
