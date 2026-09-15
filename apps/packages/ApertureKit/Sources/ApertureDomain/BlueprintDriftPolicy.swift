import Foundation

/// Reason why a pinned Document Blueprint or Collection is in drift.
public enum BlueprintDriftReason: String, Codable, Sendable, CaseIterable {
    case revisionReplaced = "REVISION_REPLACED"
    case quarantined = "QUARANTINED"
    case withdrawn = "WITHDRAWN"
    case rolledBack = "ROLLED_BACK"
    case missingFromCatalog = "MISSING_FROM_CATALOG"
}

/// Represents edition drift between a case's pinned Blueprint/Collection and the active library catalog (APP-06).
public struct BlueprintDrift: Identifiable, Codable, Sendable, Hashable {
    public var id: String { "\(namespace)/\(blueprintId)@r\(pinnedRevision)->\(currentRevision.map(String.init) ?? "none")" }

    public let namespace: String
    public let blueprintId: String
    public let pinnedRevision: Int
    public let currentRevision: Int?
    public let publicationState: PublicationState?
    public let reason: BlueprintDriftReason

    public init(
        namespace: String,
        blueprintId: String,
        pinnedRevision: Int,
        currentRevision: Int?,
        publicationState: PublicationState?,
        reason: BlueprintDriftReason
    ) {
        self.namespace = namespace
        self.blueprintId = blueprintId
        self.pinnedRevision = pinnedRevision
        self.currentRevision = currentRevision
        self.publicationState = publicationState
        self.reason = reason
    }

    public var isWithdrawn: Bool {
        reason == .withdrawn || reason == .missingFromCatalog
    }

    public var isQuarantined: Bool {
        reason == .quarantined
    }
}

/// Policy for evaluating Document Blueprint and Collection revision drift (T-77, APP-06).
///
/// Drift is strictly derived on read and never silently written back. Migrating
/// a case to a new Blueprint revision is an explicit human decision.
public enum BlueprintDriftPolicy {

    /// Evaluates drift between pinned collection members and the current library catalog.
    public static func evaluateDrift(
        pinnedMembers: [CollectionBlueprintMember],
        currentBlueprints: [DocumentBlueprint]
    ) -> [BlueprintDrift] {
        pinnedMembers.compactMap { pinned in
            guard let current = currentBlueprints.first(where: {
                $0.namespace.caseInsensitiveCompare(pinned.namespace) == .orderedSame &&
                $0.blueprintId.caseInsensitiveCompare(pinned.blueprintId) == .orderedSame &&
                $0.isLatest
            }) else {
                return BlueprintDrift(
                    namespace: pinned.namespace,
                    blueprintId: pinned.blueprintId,
                    pinnedRevision: pinned.pinnedRevision,
                    currentRevision: nil,
                    publicationState: nil,
                    reason: .missingFromCatalog
                )
            }

            // Check publication state of the blueprint
            switch current.publicationState {
            case .quarantined:
                return BlueprintDrift(
                    namespace: pinned.namespace,
                    blueprintId: pinned.blueprintId,
                    pinnedRevision: pinned.pinnedRevision,
                    currentRevision: current.revision,
                    publicationState: .quarantined,
                    reason: .quarantined
                )
            case .withdrawn:
                return BlueprintDrift(
                    namespace: pinned.namespace,
                    blueprintId: pinned.blueprintId,
                    pinnedRevision: pinned.pinnedRevision,
                    currentRevision: current.revision,
                    publicationState: .withdrawn,
                    reason: .withdrawn
                )
            case .rolledBack:
                return BlueprintDrift(
                    namespace: pinned.namespace,
                    blueprintId: pinned.blueprintId,
                    pinnedRevision: pinned.pinnedRevision,
                    currentRevision: current.revision,
                    publicationState: .rolledBack,
                    reason: .rolledBack
                )
            default:
                break
            }

            // Check revision mismatch (a newer published revision has replaced the pinned revision)
            if current.revision > pinned.pinnedRevision {
                return BlueprintDrift(
                    namespace: pinned.namespace,
                    blueprintId: pinned.blueprintId,
                    pinnedRevision: pinned.pinnedRevision,
                    currentRevision: current.revision,
                    publicationState: current.publicationState,
                    reason: .revisionReplaced
                )
            }

            return nil
        }
    }

    /// Evaluates drift for a collection's revision pin.
    public static func evaluateCollectionDrift(
        namespace: String,
        collectionId: String,
        pinnedRevision: Int,
        currentCollections: [DocumentCollection]
    ) -> BlueprintDrift? {
        guard let current = currentCollections.first(where: {
            $0.namespace.caseInsensitiveCompare(namespace) == .orderedSame &&
            $0.collectionId.caseInsensitiveCompare(collectionId) == .orderedSame &&
            $0.isLatest
        }) else {
            return BlueprintDrift(
                namespace: namespace,
                blueprintId: collectionId,
                pinnedRevision: pinnedRevision,
                currentRevision: nil,
                publicationState: nil,
                reason: .missingFromCatalog
            )
        }

        if current.publicationState == .quarantined {
            return BlueprintDrift(
                namespace: namespace,
                blueprintId: collectionId,
                pinnedRevision: pinnedRevision,
                currentRevision: current.revision,
                publicationState: .quarantined,
                reason: .quarantined
            )
        }

        if current.publicationState == .withdrawn {
            return BlueprintDrift(
                namespace: namespace,
                blueprintId: collectionId,
                pinnedRevision: pinnedRevision,
                currentRevision: current.revision,
                publicationState: .withdrawn,
                reason: .withdrawn
            )
        }

        if current.revision > pinnedRevision {
            return BlueprintDrift(
                namespace: namespace,
                blueprintId: collectionId,
                pinnedRevision: pinnedRevision,
                currentRevision: current.revision,
                publicationState: current.publicationState,
                reason: .revisionReplaced
            )
        }

        return nil
    }

    /// Whether any detected drift strictly blocks official package generation/export (APP-06).
    public static func blocksPackageGeneration(drifts: [BlueprintDrift]) -> Bool {
        !drifts.isEmpty
    }
}
