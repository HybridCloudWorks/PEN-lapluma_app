import Foundation

/// An uploaded artifact. Documents are immutable — corrections create a new version.
public struct CaseDocument: Identifiable, Codable, Sendable, Hashable {
    public let id: DocumentID
    public let folderID: FolderID
    public let subjectPersonID: PersonID?
    public let originalName: String
    /// Determined server-side from magic bytes. The client's declared type is recorded
    /// for forensics and ignored for processing.
    public let verifiedMimeType: String
    public let sizeBytes: Int64
    public let documentClass: DocumentClass?
    public let documentSubtype: String?
    /// Applicant-safe classification band. Raw engine scores remain server/reviewer data.
    public let classificationBand: DocumentClassificationBand?
    /// Present when a human replaced the machine's proposed class. This decision is
    /// authoritative and survives later processing runs.
    public let classificationOverride: DocumentClassificationOverride?
    public let processingState: DocumentProcessingState
    public let detectedLanguage: String?
    public let uploadedAt: Date
    /// Server-computed digest returned after upload and compared with the client's
    /// pre-upload digest before protected local bytes are released.
    public let contentSHA256: String?
    /// True for `SEALED_MEDICAL`. Stored encrypted, never opened.
    public let isOpaque: Bool
    public let captureQualityOverridden: Bool

    public init(
        id: DocumentID,
        folderID: FolderID,
        subjectPersonID: PersonID?,
        originalName: String,
        verifiedMimeType: String,
        sizeBytes: Int64,
        documentClass: DocumentClass?,
        documentSubtype: String?,
        classificationBand: DocumentClassificationBand? = nil,
        classificationOverride: DocumentClassificationOverride? = nil,
        processingState: DocumentProcessingState,
        detectedLanguage: String?,
        uploadedAt: Date,
        contentSHA256: String? = nil,
        isOpaque: Bool = false,
        captureQualityOverridden: Bool = false
    ) {
        self.id = id
        self.folderID = folderID
        self.subjectPersonID = subjectPersonID
        self.originalName = originalName
        self.verifiedMimeType = verifiedMimeType
        self.sizeBytes = sizeBytes
        self.documentClass = documentClass
        self.documentSubtype = documentSubtype
        self.classificationBand = classificationBand
        self.classificationOverride = classificationOverride
        self.processingState = processingState
        self.detectedLanguage = detectedLanguage
        self.uploadedAt = uploadedAt
        self.contentSHA256 = contentSHA256
        self.isOpaque = isOpaque
        self.captureQualityOverridden = captureQualityOverridden
    }

    /// Sealed medical documents are never previewed, never OCR'd, never sent to a model.
    /// The checklist records possession only.
    public var allowsPreview: Bool { !isOpaque }
    public var allowsExtraction: Bool { !isOpaque && documentClass != .openedMedicalExam }
}

public enum DocumentClassificationBand: String, Codable, Sendable, CaseIterable {
    case likelyMatch = "LIKELY_MATCH"
    case needsReview = "NEEDS_REVIEW"
    case humanConfirmed = "HUMAN_CONFIRMED"

    public var localizationKey: String { "documentClassificationBand.\(rawValue)" }
}

public struct DocumentClassificationOverride: Codable, Sendable, Hashable {
    public let previousClass: DocumentClass?
    public let selectedClass: DocumentClass
    public let recordedAt: Date

    public init(previousClass: DocumentClass?, selectedClass: DocumentClass, recordedAt: Date) {
        self.previousClass = previousClass
        self.selectedClass = selectedClass
        self.recordedAt = recordedAt
    }
}

public enum DocumentClass: String, Codable, Sendable, CaseIterable {
    case identity = "IDENTITY"
    case civil = "CIVIL"
    case financial = "FINANCIAL"
    case immigrationIssued = "IMMIGRATION_ISSUED"
    case employment = "EMPLOYMENT"
    case medical = "MEDICAL"
    /// An opened I-693 is visible only to explain the problem; OCR/extraction is refused.
    case openedMedicalExam = "OPENED_MEDICAL_EXAM"
    /// Form I-693 arrives in a sealed envelope; opening it invalidates it (C-06).
    case sealedMedical = "SEALED_MEDICAL"
    case translation = "TRANSLATION"
    case correspondence = "CORRESPONDENCE"
    case other = "OTHER"

    public var isOpaqueByPolicy: Bool { self == .sealedMedical }
    public var refusesExtractionByPolicy: Bool {
        self == .sealedMedical || self == .openedMedicalExam
    }
    public var localizationKey: String { "documentClass.\(rawValue)" }
}

public enum DocumentProcessingState: String, Codable, Sendable {
    case uploaded = "UPLOADED"
    case scanning = "SCANNING"
    case quarantined = "QUARANTINED"
    case sanitized = "SANITIZED"
    case classifying = "CLASSIFYING"
    case needsClassification = "NEEDS_CLASSIFICATION"
    case extracting = "EXTRACTING"
    case extracted = "EXTRACTED"
    case extractionFailed = "EXTRACTION_FAILED"
    case opaqueStored = "OPAQUE_STORED"
    case deleted = "DELETED"

    public var isTerminal: Bool {
        switch self {
        case .extracted, .extractionFailed, .opaqueStored, .deleted, .needsClassification: true
        default: false
        }
    }

    public var isInFlight: Bool { !isTerminal && self != .quarantined }
    public var localizationKey: String { "documentState.\(rawValue)" }
}

/// On-device capture assessment, computed before upload.
///
/// The single highest-leverage quality intervention in the product: a bad photo is
/// corrected while the document is still in the user's hand, not discovered as a
/// failure hours later. Target: a verdict within 800 ms (NFR-PERF-004).
public struct CaptureQuality: Codable, Sendable, Hashable {
    public let blurScore: Double
    public let glareScore: Double
    public let estimatedDPI: Int
    public let edgesComplete: Bool
    public let textDetected: Bool

    public init(
        blurScore: Double,
        glareScore: Double,
        estimatedDPI: Int,
        edgesComplete: Bool,
        textDetected: Bool
    ) {
        self.blurScore = blurScore
        self.glareScore = glareScore
        self.estimatedDPI = estimatedDPI
        self.edgesComplete = edgesComplete
        self.textDetected = textDetected
    }

    /// A specific, actionable reason — never a generic "poor quality".
    /// Ordered by what a user can most easily fix.
    public var issue: Issue? {
        if !edgesComplete { return .edgesIncomplete }
        if !textDetected { return .noTextDetected }
        if blurScore > 0.25 { return .blurry }
        if glareScore > 0.20 { return .glare }
        if estimatedDPI < 300 { return .tooFarAway }
        return nil
    }

    public var isAcceptable: Bool { issue == nil }

    public enum Issue: String, Sendable, CaseIterable {
        case edgesIncomplete
        case blurry
        case glare
        case tooFarAway
        case noTextDetected

        /// Hints are specific because "try again" teaches nothing.
        public var hintKey: String { "capture.hint.\(rawValue)" }
    }
}

/// How a document entered the system.
public enum DocumentSource: String, Codable, Sendable {
    case camera = "CAMERA"
    case photoLibrary = "LIBRARY"
    case files = "FILES"
    case shareSheet = "SHARE"
}
