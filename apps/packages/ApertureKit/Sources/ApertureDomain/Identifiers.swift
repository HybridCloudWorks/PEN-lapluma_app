import Foundation

/// Typed identifiers. Distinct concrete types rather than a generic phantom so that
/// a `PersonID` can never be passed where a `CaseID` is expected — the household
/// trust boundary (ADR-007) depends on not confusing one person for another.
public protocol ApertureIdentifier: RawRepresentable, Hashable, Codable, Sendable,
                                    CustomStringConvertible where RawValue == String {
    init(_ value: String)
}

extension ApertureIdentifier {
    public var description: String { rawValue }
}

public struct TenantID: ApertureIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ value: String) { self.rawValue = value }
}

public struct UserID: ApertureIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ value: String) { self.rawValue = value }
}

public struct FolderID: ApertureIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ value: String) { self.rawValue = value }
}

public struct PersonID: ApertureIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ value: String) { self.rawValue = value }
}

public struct CaseID: ApertureIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ value: String) { self.rawValue = value }
}

public struct DocumentID: ApertureIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ value: String) { self.rawValue = value }
}

public struct ProposalID: ApertureIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ value: String) { self.rawValue = value }
}

public struct DiscrepancyID: ApertureIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ value: String) { self.rawValue = value }
}

public struct MissingItemID: ApertureIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ value: String) { self.rawValue = value }
}

public struct BatchID: ApertureIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ value: String) { self.rawValue = value }
}

public struct SessionID: ApertureIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ value: String) { self.rawValue = value }
}

public struct PackageID: ApertureIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ value: String) { self.rawValue = value }
}

public struct NotificationID: ApertureIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ value: String) { self.rawValue = value }
}

/// A logical field in the canonical model, e.g. `person.birth.date`.
/// Edition-independent: a value is *of* a canonical field, not of a form field.
public struct CanonicalPath: ApertureIdentifier {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ value: String) { self.rawValue = value }
}
