import Foundation

/// Pinned collection and blueprint revisions associated with a case (APP-06).
public struct CaseRevisionPin: Codable, Sendable, Hashable {
    public let collectionNamespace: String
    public let collectionId: String
    public let collectionRevision: Int
    public let pinnedMembers: [CollectionBlueprintMember]

    public init(
        collectionNamespace: String,
        collectionId: String,
        collectionRevision: Int,
        pinnedMembers: [CollectionBlueprintMember]
    ) {
        self.collectionNamespace = collectionNamespace
        self.collectionId = collectionId
        self.collectionRevision = collectionRevision
        self.pinnedMembers = pinnedMembers
    }
}

/// Local uncommitted section draft preserving optimistic concurrency base revision (APP-06).
public struct OfflineSectionDraft: Codable, Sendable, Hashable {
    public let sectionId: String
    public let baseRevision: Int
    public let localValues: [String: String]
    public let updatedAt: Date
    public let hasConflict: Bool
    public let conflictServerValues: [String: String]?
    public let conflictServerRevision: Int?

    public init(
        sectionId: String,
        baseRevision: Int,
        localValues: [String: String],
        updatedAt: Date = Date(),
        hasConflict: Bool = false,
        conflictServerValues: [String: String]? = nil,
        conflictServerRevision: Int? = nil
    ) {
        self.sectionId = sectionId
        self.baseRevision = baseRevision
        self.localValues = localValues
        self.updatedAt = updatedAt
        self.hasConflict = hasConflict
        self.conflictServerValues = conflictServerValues
        self.conflictServerRevision = conflictServerRevision
    }
}

/// Offline case aggregate preserving pinned revisions and uncommitted work across reconnect/relaunch.
public struct OfflineCaseDraft: Identifiable, Codable, Sendable, Hashable {
    public var id: String { "\(tenantId):\(caseId.rawValue)" }

    public let tenantId: String
    public let caseId: CaseID
    public let revisionPin: CaseRevisionPin
    public var sectionDrafts: [String: OfflineSectionDraft]
    public var lastSyncedAt: Date?

    public init(
        tenantId: String,
        caseId: CaseID,
        revisionPin: CaseRevisionPin,
        sectionDrafts: [String: OfflineSectionDraft] = [:],
        lastSyncedAt: Date? = nil
    ) {
        self.tenantId = tenantId
        self.caseId = caseId
        self.revisionPin = revisionPin
        self.sectionDrafts = sectionDrafts
        self.lastSyncedAt = lastSyncedAt
    }
}

/// Thread-safe client store for offline case drafts, strictly partitioned by tenant ID (APP-06).
public actor OfflineCaseStore {
    public static let shared = OfflineCaseStore()

    private var draftsByTenant: [String: [CaseID: OfflineCaseDraft]] = [:]

    public init() {}

    /// Saves or updates an offline case draft.
    public func saveDraft(_ draft: OfflineCaseDraft) {
        var tenantMap = draftsByTenant[draft.tenantId] ?? [:]
        tenantMap[draft.caseId] = draft
        draftsByTenant[draft.tenantId] = tenantMap
    }

    /// Retrieves an offline case draft scoped to the active tenant.
    public func draft(tenantId: String, caseId: CaseID) -> OfflineCaseDraft? {
        draftsByTenant[tenantId]?[caseId]
    }

    /// Records an uncommitted local section draft.
    public func setSectionDraft(
        tenantId: String,
        caseId: CaseID,
        revisionPin: CaseRevisionPin,
        sectionId: String,
        baseRevision: Int,
        values: [String: String]
    ) {
        var existing = draft(tenantId: tenantId, caseId: caseId) ?? OfflineCaseDraft(
            tenantId: tenantId,
            caseId: caseId,
            revisionPin: revisionPin
        )
        existing.sectionDrafts[sectionId] = OfflineSectionDraft(
            sectionId: sectionId,
            baseRevision: baseRevision,
            localValues: values,
            updatedAt: Date()
        )
        saveDraft(existing)
    }

    /// Records an HTTP 412 version conflict, preserving local values alongside server values.
    public func recordConflict(
        tenantId: String,
        caseId: CaseID,
        sectionId: String,
        localValues: [String: String],
        baseRevision: Int,
        serverRevision: Int,
        serverValues: [String: String]
    ) {
        guard var existing = draft(tenantId: tenantId, caseId: caseId) else { return }
        existing.sectionDrafts[sectionId] = OfflineSectionDraft(
            sectionId: sectionId,
            baseRevision: baseRevision,
            localValues: localValues,
            updatedAt: Date(),
            hasConflict: true,
            conflictServerValues: serverValues,
            conflictServerRevision: serverRevision
        )
        saveDraft(existing)
    }

    /// Resolves a conflict with agreed values and advances base revision.
    public func resolveConflict(
        tenantId: String,
        caseId: CaseID,
        sectionId: String,
        resolvedValues: [String: String],
        newBaseRevision: Int
    ) {
        guard var existing = draft(tenantId: tenantId, caseId: caseId) else { return }
        existing.sectionDrafts[sectionId] = OfflineSectionDraft(
            sectionId: sectionId,
            baseRevision: newBaseRevision,
            localValues: resolvedValues,
            updatedAt: Date(),
            hasConflict: false,
            conflictServerValues: nil,
            conflictServerRevision: nil
        )
        saveDraft(existing)
    }

    /// Clears local data for a tenant (customer switching partitions local data cleanly).
    public func clearTenant(tenantId: String) {
        draftsByTenant.removeValue(forKey: tenantId)
    }

    /// Returns all drafts for a tenant.
    public func allDrafts(tenantId: String) -> [OfflineCaseDraft] {
        guard let map = draftsByTenant[tenantId] else { return [] }
        return Array(map.values)
    }
}
