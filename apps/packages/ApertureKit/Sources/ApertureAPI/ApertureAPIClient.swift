import Foundation
import ApertureDomain

/// The client contract. Generated from the OpenAPI document in `contracts/openapi`
/// in the real build — hand-written clients are not permitted (API-2), so this
/// protocol exists to keep the app testable and to make the stub swap trivial.
///
/// Every mutating call takes an idempotency key: the target population uses metered
/// mobile data in areas with poor coverage, so a retry that silently duplicates a case
/// is a real failure mode, not a theoretical one.
public protocol ApertureAPIClient: Sendable {

    // MARK: Folders and cases
    func folders() async throws -> [Folder]
    func folder(id: FolderID) async throws -> Folder
    func createFolder(name: String, idempotencyKey: String) async throws -> Folder
    func caseSummary(id: CaseID) async throws -> CaseSummary
    func progress(caseID: CaseID) async throws -> ProgressCounters

    // MARK: Catalog
    /// Takes no principal-specific input beyond locale. The response is independent of
    /// any case data — that is what makes personalisation impossible rather than merely
    /// forbidden (ADR-001).
    func catalogPackages(query: String?) async throws -> [FormPackage]
    func requirements(packageCode: String) async throws -> RequirementSet
    func createCase(
        folderID: FolderID,
        packageCode: String,
        roleAssignments: [PersonID: String],
        attestation: SelectionAttestation,
        idempotencyKey: String
    ) async throws -> CaseSummary

    // MARK: Documents
    func documents(folderID: FolderID) async throws -> [CaseDocument]
    /// Returns an upload session. The bytes go directly to blob storage via a
    /// write-only, single-blob, 15-minute SAS — never through the API.
    func createUploadSession(
        folderID: FolderID,
        subjectPersonID: PersonID?,
        originalName: String,
        sizeBytes: Int64,
        source: DocumentSource,
        quality: CaptureQuality?,
        contentSHA256: String,
        idempotencyKey: String
    ) async throws -> UploadSession
    func completeUpload(sessionID: String, idempotencyKey: String) async throws -> CaseDocument
    /// Records an authoritative human override. A sealed opaque document cannot later
    /// be moved back into a readable class.
    func reclassify(documentID: DocumentID, to documentClass: DocumentClass) async throws -> CaseDocument
    func deleteDocument(id: DocumentID) async throws

    // MARK: Review
    func reviewableFields(caseID: CaseID) async throws -> [ReviewableField]
    /// The human-in-the-loop endpoint. Nothing reaches a form without passing through it.
    func confirmValues(
        caseID: CaseID,
        confirmations: [ValueConfirmation],
        idempotencyKey: String
    ) async throws -> [FieldValue]
    func resolveDiscrepancy(
        caseID: CaseID,
        discrepancyID: DiscrepancyID,
        chosenValue: String,
        note: String?,
        idempotencyKey: String
    ) async throws
    /// Append-only history for one logical form field, newest first.
    func valueHistory(
        caseID: CaseID,
        personID: PersonID,
        canonicalPath: CanonicalPath
    ) async throws -> [ValueHistoryEntry]

    // MARK: Missing items and interview
    func missingItems(caseID: CaseID) async throws -> (items: [MissingItem], batches: [MissingItemBatch])
    func startInterview(
        caseID: CaseID,
        personID: PersonID,
        batchID: BatchID,
        modality: InterviewModality,
        consent: VoiceConsent?,
        accessibilityProfileEnabled: Bool,
        idempotencyKey: String
    ) async throws -> InterviewSession
    func sendInterviewMessage(
        sessionID: SessionID,
        text: String,
        idempotencyKey: String
    ) async throws -> [InterviewTurn]
    func endInterview(sessionID: SessionID) async throws

    // MARK: Package and export
    func packageGenerationReadiness(caseID: CaseID) async throws -> PackageGenerationReadiness
    /// The generation endpoint fails closed while any required field is proposed,
    /// unconfirmed, or blocked by an unresolved discrepancy.
    func requestPackageGeneration(
        caseID: CaseID,
        idempotencyKey: String
    ) async throws -> GeneratedPackage
    func generatedPackage(caseID: CaseID) async throws -> GeneratedPackage?
    func export(
        packageID: PackageID,
        channel: ExportChannel,
        recipientEmail: String?,
        idempotencyKey: String
    ) async throws -> DeliveryLink?

    // MARK: Inbox and consent
    func inbox() async throws -> [InboxItem]
    func markRead(notificationID: NotificationID) async throws
    func consents() async throws -> [ConsentRecord]
    func setConsent(purpose: ConsentRecord.Purpose, granted: Bool) async throws -> ConsentRecord
}

public struct UploadSession: Codable, Sendable {
    public let sessionID: String
    public let documentID: DocumentID
    public let uploadURL: URL
    public let expiresAt: Date

    public init(sessionID: String, documentID: DocumentID, uploadURL: URL, expiresAt: Date) {
        self.sessionID = sessionID
        self.documentID = documentID
        self.uploadURL = uploadURL
        self.expiresAt = expiresAt
    }
}

public struct ValueConfirmation: Codable, Sendable {
    public let personID: PersonID
    public let canonicalPath: CanonicalPath
    public let value: String
    public let resolvesDiscrepancyID: DiscrepancyID?
    /// Set when a Helper answers for the applicant, so attribution survives.
    public let onBehalfOf: PersonID?

    public init(
        personID: PersonID,
        canonicalPath: CanonicalPath,
        value: String,
        resolvesDiscrepancyID: DiscrepancyID? = nil,
        onBehalfOf: PersonID? = nil
    ) {
        self.personID = personID
        self.canonicalPath = canonicalPath
        self.value = value
        self.resolvesDiscrepancyID = resolvesDiscrepancyID
        self.onBehalfOf = onBehalfOf
    }
}

public enum IdempotencyKey {
    /// Client-generated and stable across retries of the same logical operation.
    public static func make() -> String { UUID().uuidString }
}
