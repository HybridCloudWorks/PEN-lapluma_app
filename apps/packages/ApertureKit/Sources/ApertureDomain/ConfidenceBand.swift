import Foundation

/// Three bands derived from *measurable* signals. Never from a model's self-report.
///
/// ADR-010. A raw numeric score exists in the ledger for calibration analysis and is
/// shown in the reviewer workbench, but it is never surfaced as a percentage to an
/// applicant — a fluent number beside someone's date of birth manufactures assurance
/// exactly where verification matters most.
public enum ConfidenceBand: String, Codable, Sendable, CaseIterable {
    /// Two independent sources agree, or a checksum validates, and engine confidence is high.
    case verified = "VERIFIED"
    /// A single anchored source above threshold.
    case extracted = "EXTRACTED"
    /// Below threshold, conflicting, unanchored, model-generated, or capture quality overridden.
    case needsReview = "NEEDS_REVIEW"
}

extension ConfidenceBand {
    /// Deliberately not a checkmark for `.verified` — a checkmark reads as endorsement,
    /// which UX-2 forbids. (SME m-01.)
    public var symbolName: String {
        switch self {
        case .verified: "circle.circle"
        case .extracted: "circle"
        case .needsReview: "exclamationmark.circle"
        }
    }

    /// Short chip label shown beside a value.
    public var chipKey: String {
        switch self {
        case .verified: "confidence.verified.chip"
        case .extracted: "confidence.extracted.chip"
        case .needsReview: "confidence.needsReview.chip"
        }
    }

    /// Plain-language meaning revealed on tap. Never a percentage.
    public var explanationKey: String {
        switch self {
        case .verified: "confidence.verified.explanation"
        case .extracted: "confidence.extracted.explanation"
        case .needsReview: "confidence.needsReview.explanation"
        }
    }

    /// Whether this band alone may be bulk-accepted by a reviewer.
    /// Bulk accept is a reviewer-only affordance and is capped per action;
    /// it is intentionally unavailable on iPhone.
    public var isBulkAcceptable: Bool { self == .verified }
}
