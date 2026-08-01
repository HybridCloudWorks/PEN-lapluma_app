import Foundation

/// Two explicit mechanical counters. **There is deliberately no percentage.**
///
/// C-20: "Your application is 94% complete" is heard by an anxious applicant as
/// "you are 94% of the way to being approved." That is an implied outcome
/// representation the platform must never make.
///
/// A contract test asserts no API response contains a key matching
/// `/percent|complete(ness)?Score/i`, and this type is the client-side expression
/// of the same rule: it exposes numerators and denominators, and nothing that
/// divides them.
public struct ProgressCounters: Codable, Sendable, Hashable {
    public let fieldsFilled: Int
    public let fieldsRequired: Int
    public let documentsCollected: Int
    public let documentsRequired: Int
    public let blockingItems: Int
    public let advisoryItems: Int

    public init(
        fieldsFilled: Int,
        fieldsRequired: Int,
        documentsCollected: Int,
        documentsRequired: Int,
        blockingItems: Int,
        advisoryItems: Int
    ) {
        self.fieldsFilled = fieldsFilled
        self.fieldsRequired = fieldsRequired
        self.documentsCollected = documentsCollected
        self.documentsRequired = documentsRequired
        self.blockingItems = blockingItems
        self.advisoryItems = advisoryItems
    }

    /// Numerator/denominator pairs only. Formatting and localisation belong to the
    /// UI layer — the domain deliberately owns no presentation strings, so there is
    /// no place here for a ratio to creep in.
    public var fields: (filled: Int, required: Int) { (fieldsFilled, fieldsRequired) }
    public var documents: (collected: Int, required: Int) { (documentsCollected, documentsRequired) }

    /// Readiness is a statement about paperwork, never a prediction about an agency.
    public var isReadyToFile: Bool {
        fieldsFilled >= fieldsRequired
            && documentsCollected >= documentsRequired
            && blockingItems == 0
    }
}
