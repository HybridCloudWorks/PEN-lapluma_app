import Foundation

/// RFC 9457 Problem Details. Errors are actionable and safe: a stable machine-readable
/// `type`, a localized `title`, and never a stack trace, a SQL fragment, or another
/// user's data.
public struct ProblemDetails: Error, Codable, Sendable {
    public let type: String
    public let title: String
    public let status: Int
    public let detail: String?
    public let correlationID: String?
    public let errors: [FieldProblem]?
    public let budget: BudgetContext?

    public init(
        type: String,
        title: String,
        status: Int,
        detail: String? = nil,
        correlationID: String? = nil,
        errors: [FieldProblem]? = nil,
        budget: BudgetContext? = nil
    ) {
        self.type = type
        self.title = title
        self.status = status
        self.detail = detail
        self.correlationID = correlationID
        self.errors = errors
        self.budget = budget
    }

    enum CodingKeys: String, CodingKey {
        case type, title, status, detail, errors, budget
        case correlationID = "correlationId"
    }
}

public struct FieldProblem: Codable, Sendable {
    public let field: String
    public let reason: String
    public let resolutionPath: String?

    public init(field: String, reason: String, resolutionPath: String? = nil) {
        self.field = field
        self.reason = reason
        self.resolutionPath = resolutionPath
    }
}

/// Returned with 429 when a budget is exhausted. The message preserves the user's work
/// and points at a free alternative rather than simply refusing (C-11).
public struct BudgetContext: Codable, Sendable {
    public let kind: String
    public let used: Int
    public let limit: Int
    public let alternatives: [String]
    public let topUpAvailable: Bool

    public init(kind: String, used: Int, limit: Int, alternatives: [String], topUpAvailable: Bool) {
        self.kind = kind
        self.used = used
        self.limit = limit
        self.alternatives = alternatives
        self.topUpAvailable = topUpAvailable
    }
}

extension ProblemDetails {
    /// Existence is itself information: an unentitled resource returns 404 rather than
    /// 403, because 403 would confirm that a folder exists. In the intimate-partner
    /// threat model (TA-2) that confirmation is a disclosure.
    public var isNotFoundOrUnentitled: Bool { status == 404 }
    public var isBudgetExhausted: Bool { status == 429 }
    public var isStateConflict: Bool { status == 409 }
    /// The case is frozen by form-edition drift and needs a human to accept migration.
    public var isQuarantined: Bool { status == 423 }
}

/// Transport-level failures distinct from server-returned problems.
public enum TransportError: Error, Sendable {
    case offline
    case timedOut
    case cancelled
    case decodingFailed(String)
    case attestationFailed
}
