import Foundation

/// The mobile mirror of the server's extraction admission rules. It never runs OCR;
/// it determines whether a returned candidate is safe to show and how prominently a
/// human must review it.
public struct ExtractionCandidate: Sendable, Hashable {
    public enum Source: Sendable, Hashable { case extractionEngine, modelSuggestion }
    public enum Kind: Sendable, Hashable { case text, date, structuredIdentifier, name }

    public let source: Source
    public let kind: Kind
    public let anchor: DocumentAnchor?
    public let dateInterpretations: [String]
    public let instructionLikeTextDetected: Bool
    public let extractedName: ExtractedName?

    public init(
        source: Source,
        kind: Kind,
        anchor: DocumentAnchor?,
        dateInterpretations: [String] = [],
        instructionLikeTextDetected: Bool = false,
        extractedName: ExtractedName? = nil
    ) {
        self.source = source
        self.kind = kind
        self.anchor = anchor
        self.dateInterpretations = dateInterpretations
        self.instructionLikeTextDetected = instructionLikeTextDetected
        self.extractedName = extractedName
    }
}

public struct ExtractionSafetyDecision: Sendable, Hashable {
    public enum Disposition: Sendable, Hashable {
        /// Engine output without a real page anchor is not extraction and is omitted.
        case dropUnanchoredClaim
        case offerForHumanReview
    }

    public let disposition: Disposition
    public let confidenceBand: ConfidenceBand
    public let reviewReasons: [ExtractionReviewReason]
    public let raisesSecurityEvent: Bool
}

public enum ExtractionSafetyPolicy {
    public static func assess(_ candidate: ExtractionCandidate) -> ExtractionSafetyDecision {
        if candidate.source == .extractionEngine,
           candidate.anchor == nil || candidate.anchor?.isDegenerate == true {
            return ExtractionSafetyDecision(
                disposition: .dropUnanchoredClaim,
                confidenceBand: .needsReview,
                reviewReasons: [],
                raisesSecurityEvent: false
            )
        }

        var reasons: [ExtractionReviewReason] = []
        if candidate.source == .modelSuggestion { reasons.append(.modelSuggestion) }
        if candidate.kind == .date, Set(candidate.dateInterpretations).count > 1 {
            reasons.append(.ambiguousDate)
        }
        if candidate.anchor?.checksumValid == false { reasons.append(.failedChecksum) }
        if candidate.instructionLikeTextDetected { reasons.append(.instructionLikeText) }

        let canBeVerified = candidate.kind == .structuredIdentifier
            && candidate.anchor?.checksumValid == true
            && (candidate.anchor?.rawConfidence ?? 0) >= 0.9
        let baseBand: ConfidenceBand = canBeVerified ? .verified : .extracted

        return ExtractionSafetyDecision(
            disposition: .offerForHumanReview,
            confidenceBand: reasons.isEmpty ? baseBand : .needsReview,
            reviewReasons: reasons,
            raisesSecurityEvent: candidate.instructionLikeTextDetected
        )
    }
}
