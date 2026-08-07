import Foundation

/// Where a value came from. Inseparable from the value itself (DP-3).
///
/// A value without provenance is a defect, not a value. This is why the type is
/// non-optional on `FieldValue` and `ValueProposal`.
public enum Provenance: Codable, Sendable, Hashable {
    /// Read from a document, anchored to a region on a page.
    case document(DocumentAnchor)
    /// Typed by a human directly.
    case manualEntry(by: UserID, at: Date)
    /// Given in an interview, attributed to the human who actually spoke or typed.
    case interview(sessionID: SessionID, by: UserID, onBehalfOf: PersonID?, at: Date)
}

/// The page and region a value was read from, plus which engine read it.
///
/// `boundingPolygon` is required and must be non-degenerate. A value the model produced
/// without a locatable source region is not extraction — it is invention — and is banded
/// `.needsReview` by rule.
public struct DocumentAnchor: Codable, Sendable, Hashable {
    public let documentID: DocumentID
    public let documentName: String
    public let pageNumber: Int
    /// Normalised [0,1] coordinates, clockwise from top-left.
    public let boundingPolygon: [CGPointCodable]
    public let engine: String
    public let engineVersion: String
    public let rawConfidence: Double
    public let checksumValid: Bool?
    public let normalizationNote: String?

    public init(
        documentID: DocumentID,
        documentName: String,
        pageNumber: Int,
        boundingPolygon: [CGPointCodable],
        engine: String,
        engineVersion: String,
        rawConfidence: Double,
        checksumValid: Bool? = nil,
        normalizationNote: String? = nil
    ) {
        self.documentID = documentID
        self.documentName = documentName
        self.pageNumber = pageNumber
        self.boundingPolygon = boundingPolygon
        self.engine = engine
        self.engineVersion = engineVersion
        self.rawConfidence = rawConfidence
        self.checksumValid = checksumValid
        self.normalizationNote = normalizationNote
    }

    /// A polygon with fewer than three distinct points cannot locate anything:
    /// repeated coordinates collapse to a line or a point, so an engine claim
    /// anchored by one is treated as unanchored.
    public var isDegenerate: Bool { Set(boundingPolygon).count < 3 }
}

/// `CGPoint` is not `Codable` on all platforms in the shape we want, and the domain
/// layer deliberately does not import CoreGraphics semantics beyond this.
public struct CGPointCodable: Codable, Sendable, Hashable {
    public let x: Double
    public let y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}
