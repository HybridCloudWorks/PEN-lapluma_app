import Foundation

/// One pinned form whose edition no longer matches what the agency publishes.
public struct FormEditionDrift: Codable, Sendable, Hashable {
    public let formNumber: String
    /// The edition this case was prepared against.
    public let pinnedEdition: Date
    /// The edition the catalog carries now. Nil when the package no longer
    /// publishes this form at all, which is drift of a more serious kind: there
    /// is no current edition to migrate to.
    public let currentEdition: Date?

    public init(formNumber: String, pinnedEdition: Date, currentEdition: Date?) {
        self.formNumber = formNumber
        self.pinnedEdition = pinnedEdition
        self.currentEdition = currentEdition
    }

    public var isWithdrawn: Bool { currentEdition == nil }
}

/// Detects that a case is pinned to a form edition the agency has replaced (T-77).
///
/// `CaseState.quarantinedFormDrift` and `PinnedForm.driftDetected` have existed
/// since the aggregate was written, and `FolderView` has always been ready to warn
/// about a drifted form — but nothing ever computed the condition, so no case could
/// enter that state and the warning never once appeared. Editions are the whole
/// point of pinning: filling a form the agency withdrew produces paperwork that is
/// rejected on arrival, and the applicant is the one who pays for that.
///
/// Comparison is by edition date rather than by hash: the pinned `sourceSHA256`
/// records the exact artifact this case was prepared from, but the stub cannot
/// re-hash the agency's current PDF, and an edition date is what the agency itself
/// publishes and what the instructions cite. A real implementation should compare
/// both and treat either mismatch as drift.
public enum FormDriftPolicy {

    public static func drift(
        pinnedForms: [PinnedForm],
        against catalogForms: [CatalogForm]
    ) -> [FormEditionDrift] {
        pinnedForms.compactMap { pinned in
            guard let current = catalogForms.first(where: { $0.formNumber == pinned.formNumber }) else {
                return FormEditionDrift(
                    formNumber: pinned.formNumber,
                    pinnedEdition: pinned.editionDate,
                    currentEdition: nil
                )
            }
            guard current.editionDate != pinned.editionDate else { return nil }
            return FormEditionDrift(
                formNumber: pinned.formNumber,
                pinnedEdition: pinned.editionDate,
                currentEdition: current.editionDate
            )
        }
    }

    /// The pinned set with `driftDetected` derived against the current catalog.
    /// A derivation, never a write: the pin itself is what the case was prepared
    /// from and must not be silently rewritten to the new edition — migrating is a
    /// human decision, which is what the quarantine state exists to hold.
    public static func annotated(
        pinnedForms: [PinnedForm],
        against catalogForms: [CatalogForm]
    ) -> [PinnedForm] {
        let drifted = Set(drift(pinnedForms: pinnedForms, against: catalogForms).map(\.formNumber))
        return pinnedForms.map { pinned in
            let hasDrifted = drifted.contains(pinned.formNumber)
            guard hasDrifted != pinned.driftDetected else { return pinned }
            return PinnedForm(
                formNumber: pinned.formNumber,
                editionDate: pinned.editionDate,
                sourceSHA256: pinned.sourceSHA256,
                encoding: pinned.encoding,
                driftDetected: hasDrifted
            )
        }
    }
}
