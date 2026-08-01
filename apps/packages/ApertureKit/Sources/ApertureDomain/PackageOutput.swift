import Foundation

/// A generated package. Cannot exist unverified: round-trip verification re-parses the
/// output PDF, re-extracts every field and asserts equality with the source record.
/// Any mismatch fails generation — it does not warn (ADR-003).
public struct GeneratedPackage: Identifiable, Codable, Sendable {
    public let id: PackageID
    public let caseID: CaseID
    public let generatedAt: Date
    public let verification: VerificationReport
    public let preparer: PreparerAttribution
    public let outputs: [PDFOutput]
    public let filingChecklist: FilingChecklist

    public init(
        id: PackageID,
        caseID: CaseID,
        generatedAt: Date,
        verification: VerificationReport,
        preparer: PreparerAttribution,
        outputs: [PDFOutput],
        filingChecklist: FilingChecklist
    ) {
        self.id = id
        self.caseID = caseID
        self.generatedAt = generatedAt
        self.verification = verification
        self.preparer = preparer
        self.outputs = outputs
        self.filingChecklist = filingChecklist
    }
}

public struct VerificationReport: Codable, Sendable, Hashable {
    public let passed: Bool
    public let fieldsVerified: Int
    public let mismatches: Int

    public init(passed: Bool, fieldsVerified: Int, mismatches: Int) {
        self.passed = passed
        self.fieldsVerified = fieldsVerified
        self.mismatches = mismatches
    }
}

/// Stamped on every generated page. A tenant cannot suppress it.
public struct PreparerAttribution: Codable, Sendable, Hashable {
    public let organizationName: String
    public let verificationStatus: String
    public let verificationType: String?

    public init(organizationName: String, verificationStatus: String, verificationType: String?) {
        self.organizationName = organizationName
        self.verificationStatus = verificationStatus
        self.verificationType = verificationType
    }
}

public struct PDFOutput: Identifiable, Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
        case coverIndex = "COVER_INDEX"
        case filledForm = "FILLED_FORM"
        case addendum = "ADDENDUM"
        case checklist = "CHECKLIST"
        case exhibit = "EXHIBIT"
        /// Produced instead of a filled form when the encoding is XFA or flat.
        case dataSheet = "DATA_SHEET"
    }

    public enum FillMode: String, Codable, Sendable {
        case acroFormFilled = "ACROFORM_FILLED"
        case assistedOnly = "ASSISTED_ONLY"
    }

    public let id: String
    public let kind: Kind
    public let fillMode: FillMode
    public let formNumber: String?
    public let editionDate: Date?
    public let pageCount: Int
    public let sortOrder: Int
    /// Populated for `.addendum` — a field exceeded the form's character capacity.
    /// Overflow generates a conforming addendum; truncation is never acceptable.
    public let reason: String?

    public init(
        id: String,
        kind: Kind,
        fillMode: FillMode,
        formNumber: String?,
        editionDate: Date?,
        pageCount: Int,
        sortOrder: Int,
        reason: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.fillMode = fillMode
        self.formNumber = formNumber
        self.editionDate = editionDate
        self.pageCount = pageCount
        self.sortOrder = sortOrder
        self.reason = reason
    }
}

/// Where to file, what fee, which edition, what to sign in wet ink.
/// Every element is a cited transcription of published agency instructions —
/// transcription, not advice.
public struct FilingChecklist: Codable, Sendable {
    public let feeUSDCents: Int?
    public let filingAddress: String?
    public let wetInkSignaturePoints: [SignaturePoint]
    public let citation: Citation?

    public init(
        feeUSDCents: Int?,
        filingAddress: String?,
        wetInkSignaturePoints: [SignaturePoint],
        citation: Citation?
    ) {
        self.feeUSDCents = feeUSDCents
        self.filingAddress = filingAddress
        self.wetInkSignaturePoints = wetInkSignaturePoints
        self.citation = citation
    }
}

public struct SignaturePoint: Identifiable, Codable, Sendable, Hashable {
    public var id: String { "\(formNumber)|\(partLabel)" }
    public let formNumber: String
    public let partLabel: String

    public init(formNumber: String, partLabel: String) {
        self.formNumber = formNumber
        self.partLabel = partLabel
    }
}

/// How a package leaves the platform. Never as an email attachment.
public enum ExportChannel: String, Codable, Sendable, CaseIterable {
    case files = "FILES"
    case print = "PRINT"
    /// A link, not the documents. Single-recipient, expiring, download-capped, revocable.
    case secureLink = "SECURE_LINK"

    public var localizationKey: String { "export.\(rawValue)" }
}

public struct DeliveryLink: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let expiresAt: Date
    public let maxDownloads: Int
    public let downloadCount: Int
    public let revoked: Bool

    public init(id: String, expiresAt: Date, maxDownloads: Int, downloadCount: Int, revoked: Bool) {
        self.id = id
        self.expiresAt = expiresAt
        self.maxDownloads = maxDownloads
        self.downloadCount = downloadCount
        self.revoked = revoked
    }

    public var isLive: Bool { !revoked && expiresAt > Date() && downloadCount < maxDownloads }
}
