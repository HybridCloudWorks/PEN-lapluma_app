import Foundation
import ApertureDomain

/// Production HTTP client conforming to `ApertureAPIClient`.
///
/// Connects to Google Cloud API Gateway / Cloud Run microservices (Core API and Workflow API),
/// enforces RFC 9457 Problem Details error decoding, injects dynamic OIDC/Bearer tokens,
/// and delegates unmigrated endpoints to an underlying fallback client (e.g. `StubAPIClient`).
public actor NetworkAPIClient: ApertureAPIClient {

    public let coreBaseURL: URL
    public let workflowBaseURL: URL
    public let session: URLSession
    private var tokenProvider: (@Sendable () async -> String?)?
    private var activeTenantID: String?
    private let fallbackClient: (any ApertureAPIClient)?

    private let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateStr = try container.decode(String.self)
            if let date = ISO8601DateFormatter().date(from: dateStr) {
                return date
            }
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .iso8601)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSSZZZZZ"
            if let date = formatter.date(from: dateStr) {
                return date
            }
            formatter.dateFormat = "yyyy-MM-dd"
            if let date = formatter.date(from: dateStr) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format: \(dateStr)")
        }
        return decoder
    }()

    private let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    public init(
        coreBaseURL: URL = URL(string: ApertureEnvironment.current.coreApiBaseUrl)!,
        workflowBaseURL: URL = URL(string: ApertureEnvironment.current.workflowApiBaseUrl)!,
        session: URLSession = .shared,
        tokenProvider: (@Sendable () async -> String?)? = nil,
        activeTenantID: String? = nil,
        fallbackClient: (any ApertureAPIClient)? = nil
    ) {
        self.coreBaseURL = coreBaseURL
        self.workflowBaseURL = workflowBaseURL
        self.session = session
        self.tokenProvider = tokenProvider
        self.activeTenantID = activeTenantID
        self.fallbackClient = fallbackClient
    }

    public func setTokenProvider(_ provider: (@Sendable () async -> String?)?) {
        self.tokenProvider = provider
    }

    public func setActiveTenantID(_ tenantID: String?) {
        self.activeTenantID = tenantID
    }

    // MARK: - HTTP Pipeline & Request Building

    public func buildRequest(
        baseURL: URL,
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem]? = nil,
        body: Data? = nil,
        idempotencyKey: String? = nil
    ) async -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: true)
        if let queryItems, !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        let finalURL = components?.url ?? baseURL.appendingPathComponent(path)
        var request = URLRequest(url: finalURL)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/problem+json", forHTTPHeaderField: "Accept")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")

        if let token = await tokenProvider?() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let tenantID = activeTenantID {
            request.setValue(tenantID, forHTTPHeaderField: "X-Tenant-ID")
        }

        if let idempotencyKey {
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }

        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return request
    }

    private struct DataEnvelope<T: Decodable>: Decodable {
        let data: T
    }

    public func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost:
                throw TransportError.offline
            case .timedOut:
                throw TransportError.timedOut
            case .cancelled:
                throw TransportError.cancelled
            default:
                throw error
            }
        }

        guard let http = response as? HTTPURLResponse else {
            throw TransportError.decodingFailed("Non-HTTP response")
        }

        guard (200..<300).contains(http.statusCode) else {
            if let problem = try? jsonDecoder.decode(ProblemDetails.self, from: data) {
                throw problem
            }
            let message = HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw ProblemDetails(
                type: "urn:problem:http-\(http.statusCode)",
                title: message,
                status: http.statusCode,
                detail: String(data: data, encoding: .utf8)
            )
        }

        if let direct = try? jsonDecoder.decode(T.self, from: data) {
            return direct
        }

        if let wrapped = try? jsonDecoder.decode(DataEnvelope<T>.self, from: data) {
            return wrapped.data
        }

        do {
            return try jsonDecoder.decode(T.self, from: data)
        } catch {
            throw TransportError.decodingFailed(error.localizedDescription)
        }
    }

    // MARK: - Core API Endpoints

    public func catalogPackages(query: String?) async throws -> [FormPackage] {
        var queryItems: [URLQueryItem] = []
        if let query, !query.trimmingCharacters(in: .whitespaces).isEmpty {
            queryItems.append(URLQueryItem(name: "query", value: query))
        }
        let request = await buildRequest(
            baseURL: coreBaseURL,
            path: "v1/catalog/packages",
            method: "GET",
            queryItems: queryItems.isEmpty ? nil : queryItems
        )

        do {
            return try await execute(request)
        } catch {
            if let fallbackClient {
                return try await fallbackClient.catalogPackages(query: query)
            }
            throw error
        }
    }

    public func requirements(packageCode: String) async throws -> RequirementSet {
        let request = await buildRequest(
            baseURL: coreBaseURL,
            path: "v1/catalog/packages/\(packageCode)",
            method: "GET"
        )
        do {
            return try await execute(request)
        } catch {
            if let fallbackClient {
                return try await fallbackClient.requirements(packageCode: packageCode)
            }
            throw error
        }
    }

    public func libraryCollections(tenantID: String?) async throws -> [DocumentCollection] {
        var queryItems: [URLQueryItem] = []
        if let tenantID {
            queryItems.append(URLQueryItem(name: "tenantId", value: tenantID))
        }
        let request = await buildRequest(
            baseURL: coreBaseURL,
            path: "v1/library/collections",
            method: "GET",
            queryItems: queryItems.isEmpty ? nil : queryItems
        )
        do {
            return try await execute(request)
        } catch {
            if let fallbackClient {
                return try await fallbackClient.libraryCollections(tenantID: tenantID)
            }
            throw error
        }
    }

    public func libraryCollection(namespace: String, id: String, revision: Int?) async throws -> DocumentCollection? {
        var queryItems: [URLQueryItem] = []
        if let revision {
            queryItems.append(URLQueryItem(name: "revision", value: String(revision)))
        }
        let request = await buildRequest(
            baseURL: coreBaseURL,
            path: "v1/library/collections/\(namespace)/\(id)",
            method: "GET",
            queryItems: queryItems.isEmpty ? nil : queryItems
        )
        do {
            return try await execute(request)
        } catch {
            if let fallbackClient {
                return try await fallbackClient.libraryCollection(namespace: namespace, id: id, revision: revision)
            }
            throw error
        }
    }

    // MARK: - Workflow API Endpoints

    public func authenticatedContext() async throws -> AuthenticatedContext {
        let request = await buildRequest(
            baseURL: workflowBaseURL,
            path: "v1/session",
            method: "GET"
        )
        do {
            return try await execute(request)
        } catch {
            if let fallbackClient {
                return try await fallbackClient.authenticatedContext()
            }
            throw error
        }
    }

    public func clientDirectory(query: String?, cursor: String?) async throws -> ClientDirectoryPage {
        var queryItems: [URLQueryItem] = []
        if let query, !query.isEmpty {
            queryItems.append(URLQueryItem(name: "query", value: query))
        }
        if let cursor, !cursor.isEmpty {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        let request = await buildRequest(
            baseURL: workflowBaseURL,
            path: "v1/clients",
            method: "GET",
            queryItems: queryItems.isEmpty ? nil : queryItems
        )
        do {
            return try await execute(request)
        } catch {
            if let fallbackClient {
                return try await fallbackClient.clientDirectory(query: query, cursor: cursor)
            }
            throw error
        }
    }

    public func createClient(label: String, idempotencyKey: String) async throws -> ClientDirectoryEntry {
        if let fallbackClient {
            return try await fallbackClient.createClient(label: label, idempotencyKey: idempotencyKey)
        }
        throw TransportError.offline
    }

    // MARK: - Document Upload Sessions (ADR-019 / INT-05)

    private struct CreateUploadSessionPayload: Codable {
        let folderId: String
        let subjectPersonId: String?
        let originalName: String
        let sizeBytes: Int64
        let contentSha256: String
        let sourceChannel: String?
    }

    public func createUploadSession(
        folderID: FolderID,
        subjectPersonID: PersonID?,
        originalName: String,
        sizeBytes: Int64,
        source: DocumentSource,
        quality: CaptureQuality?,
        contentSHA256: String,
        idempotencyKey: String
    ) async throws -> UploadSession {
        let payload = CreateUploadSessionPayload(
            folderId: folderID.rawValue,
            subjectPersonId: subjectPersonID?.rawValue,
            originalName: originalName,
            sizeBytes: sizeBytes,
            contentSha256: contentSHA256,
            sourceChannel: source.rawValue
        )
        let body = try jsonEncoder.encode(payload)
        let request = await buildRequest(
            baseURL: workflowBaseURL,
            path: "v1/documents/upload-sessions",
            method: "POST",
            body: body,
            idempotencyKey: idempotencyKey
        )

        do {
            return try await execute(request)
        } catch {
            if let fallbackClient {
                return try await fallbackClient.createUploadSession(
                    folderID: folderID,
                    subjectPersonID: subjectPersonID,
                    originalName: originalName,
                    sizeBytes: sizeBytes,
                    source: source,
                    quality: quality,
                    contentSHA256: contentSHA256,
                    idempotencyKey: idempotencyKey
                )
            }
            throw error
        }
    }

    public func completeUpload(sessionID: String, idempotencyKey: String) async throws -> CaseDocument {
        let request = await buildRequest(
            baseURL: workflowBaseURL,
            path: "v1/documents/upload-sessions/\(sessionID)/complete",
            method: "POST",
            idempotencyKey: idempotencyKey
        )
        do {
            return try await execute(request)
        } catch {
            if let fallbackClient {
                return try await fallbackClient.completeUpload(sessionID: sessionID, idempotencyKey: idempotencyKey)
            }
            throw error
        }
    }

    // MARK: - Delegated / Fallback Operations

    public func folders() async throws -> [Folder] {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.folders()
    }

    public func folder(id: FolderID) async throws -> Folder {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.folder(id: id)
    }

    public func createFolder(name: String, idempotencyKey: String) async throws -> Folder {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.createFolder(name: name, idempotencyKey: idempotencyKey)
    }

    public func createPerson(
        folderID: FolderID,
        displayLabel: String,
        isMinor: Bool,
        relationships: [Relationship],
        idempotencyKey: String
    ) async throws -> Person {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.createPerson(
            folderID: folderID,
            displayLabel: displayLabel,
            isMinor: isMinor,
            relationships: relationships,
            idempotencyKey: idempotencyKey
        )
    }

    public func caseSummary(id: CaseID) async throws -> CaseSummary {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.caseSummary(id: id)
    }

    public func progress(caseID: CaseID) async throws -> ProgressCounters {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.progress(caseID: caseID)
    }

    public func createCase(
        folderID: FolderID,
        packageCode: String,
        roleAssignments: [PersonID: String],
        attestation: SelectionAttestation,
        idempotencyKey: String
    ) async throws -> CaseSummary {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.createCase(
            folderID: folderID,
            packageCode: packageCode,
            roleAssignments: roleAssignments,
            attestation: attestation,
            idempotencyKey: idempotencyKey
        )
    }

    public func libraryBlueprints(tenantID: String?) async throws -> [DocumentBlueprint] {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.libraryBlueprints(tenantID: tenantID)
    }

    public func libraryBlueprints(tenantID: String?, query: String?) async throws -> [DocumentBlueprint] {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.libraryBlueprints(tenantID: tenantID, query: query)
    }

    public func libraryBlueprint(namespace: String, id: String, revision: Int?) async throws -> DocumentBlueprint? {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.libraryBlueprint(namespace: namespace, id: id, revision: revision)
    }

    public func libraryBlueprintDefinition(namespace: String, id: String, revision: Int?) async throws -> BlueprintDefinition? {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.libraryBlueprintDefinition(namespace: namespace, id: id, revision: revision)
    }

    public func documentGuidance(namespace: String, id: String) async throws -> DocumentGuidance? {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.documentGuidance(namespace: namespace, id: id)
    }

    public func packageMappings() async throws -> [LegacyPackageMapping] {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.packageMappings()
    }

    public func documents(folderID: FolderID) async throws -> [CaseDocument] {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.documents(folderID: folderID)
    }

    public func reclassify(documentID: DocumentID, to documentClass: DocumentClass) async throws -> CaseDocument {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.reclassify(documentID: documentID, to: documentClass)
    }

    public func deleteDocument(id: DocumentID) async throws {
        guard let fallbackClient else { throw TransportError.offline }
        try await fallbackClient.deleteDocument(id: id)
    }

    public func reviewableFields(caseID: CaseID) async throws -> [ReviewableField] {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.reviewableFields(caseID: caseID)
    }

    public func confirmValues(
        caseID: CaseID,
        confirmations: [ValueConfirmation],
        idempotencyKey: String
    ) async throws -> [FieldValue] {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.confirmValues(
            caseID: caseID,
            confirmations: confirmations,
            idempotencyKey: idempotencyKey
        )
    }

    public func resolveDiscrepancy(
        caseID: CaseID,
        discrepancyID: DiscrepancyID,
        chosenValue: String,
        note: String?,
        idempotencyKey: String
    ) async throws {
        guard let fallbackClient else { throw TransportError.offline }
        try await fallbackClient.resolveDiscrepancy(
            caseID: caseID,
            discrepancyID: discrepancyID,
            chosenValue: chosenValue,
            note: note,
            idempotencyKey: idempotencyKey
        )
    }

    public func valueHistory(
        caseID: CaseID,
        personID: PersonID,
        canonicalPath: CanonicalPath
    ) async throws -> [ValueHistoryEntry] {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.valueHistory(caseID: caseID, personID: personID, canonicalPath: canonicalPath)
    }

    public func missingItems(caseID: CaseID) async throws -> (items: [MissingItem], batches: [MissingItemBatch]) {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.missingItems(caseID: caseID)
    }

    public func guidedFinishPlan(caseID: CaseID, minutes: Int) async throws -> GuidedFinishPlan {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.guidedFinishPlan(caseID: caseID, minutes: minutes)
    }

    public func proofMap(caseID: CaseID) async throws -> ProofMap {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.proofMap(caseID: caseID)
    }

    public func documentPagePreview(documentID: DocumentID, pageNumber: Int) async throws -> DocumentPagePreview {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.documentPagePreview(documentID: documentID, pageNumber: pageNumber)
    }

    public func evidenceRelays(caseID: CaseID) async throws -> [EvidenceRelay] {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.evidenceRelays(caseID: caseID)
    }

    public func createEvidenceRelay(caseID: CaseID, missingItemID: MissingItemID, idempotencyKey: String) async throws -> CreateEvidenceRelayResult {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.createEvidenceRelay(caseID: caseID, missingItemID: missingItemID, idempotencyKey: idempotencyKey)
    }

    public func revokeEvidenceRelay(relayID: EvidenceRelayID, idempotencyKey: String) async throws -> EvidenceRelay {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.revokeEvidenceRelay(relayID: relayID, idempotencyKey: idempotencyKey)
    }

    public func acceptEvidenceRelay(relayID: EvidenceRelayID, idempotencyKey: String) async throws -> EvidenceRelay {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.acceptEvidenceRelay(relayID: relayID, idempotencyKey: idempotencyKey)
    }

    public func rejectEvidenceRelay(relayID: EvidenceRelayID, idempotencyKey: String) async throws -> EvidenceRelay {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.rejectEvidenceRelay(relayID: relayID, idempotencyKey: idempotencyKey)
    }

    public func startInterview(
        caseID: CaseID,
        personID: PersonID,
        batchID: BatchID,
        modality: InterviewModality,
        consent: VoiceConsent?,
        accessibilityProfileEnabled: Bool,
        idempotencyKey: String
    ) async throws -> InterviewSession {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.startInterview(
            caseID: caseID,
            personID: personID,
            batchID: batchID,
            modality: modality,
            consent: consent,
            accessibilityProfileEnabled: accessibilityProfileEnabled,
            idempotencyKey: idempotencyKey
        )
    }

    public func sendInterviewMessage(
        sessionID: SessionID,
        text: String,
        idempotencyKey: String
    ) async throws -> [InterviewTurn] {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.sendInterviewMessage(sessionID: sessionID, text: text, idempotencyKey: idempotencyKey)
    }

    public func endInterview(sessionID: SessionID) async throws {
        guard let fallbackClient else { throw TransportError.offline }
        try await fallbackClient.endInterview(sessionID: sessionID)
    }

    public func packageGenerationReadiness(caseID: CaseID) async throws -> PackageGenerationReadiness {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.packageGenerationReadiness(caseID: caseID)
    }

    public func requestPackageGeneration(caseID: CaseID, idempotencyKey: String) async throws -> GeneratedPackage {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.requestPackageGeneration(caseID: caseID, idempotencyKey: idempotencyKey)
    }

    public func generatedPackage(caseID: CaseID) async throws -> GeneratedPackage? {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.generatedPackage(caseID: caseID)
    }

    public func export(
        packageID: PackageID,
        channel: ExportChannel,
        recipientEmail: String?,
        idempotencyKey: String
    ) async throws -> PackageExportResult {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.export(
            packageID: packageID,
            channel: channel,
            recipientEmail: recipientEmail,
            idempotencyKey: idempotencyKey
        )
    }

    public func inbox() async throws -> [InboxItem] {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.inbox()
    }

    public func markRead(notificationID: NotificationID) async throws {
        guard let fallbackClient else { throw TransportError.offline }
        try await fallbackClient.markRead(notificationID: notificationID)
    }

    public func consents() async throws -> [ConsentRecord] {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.consents()
    }

    public func setConsent(purpose: ConsentRecord.Purpose, granted: Bool) async throws -> ConsentRecord {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.setConsent(purpose: purpose, granted: granted)
    }

    public func caseWorkspace(caseID: CaseID) async throws -> CaseWorkspace {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.caseWorkspace(caseID: caseID)
    }

    public func setAssignments(caseID: CaseID, assignments: CaseAssignments, idempotencyKey: String) async throws -> CaseAssignments {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.setAssignments(caseID: caseID, assignments: assignments, idempotencyKey: idempotencyKey)
    }

    public func transition(caseID: CaseID, to state: CaseState, idempotencyKey: String) async throws -> CaseSummary {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.transition(caseID: caseID, to: state, idempotencyKey: idempotencyKey)
    }

    public func commitSection(
        caseID: CaseID,
        sectionID: String,
        baseRevision: Int,
        values: [String: String],
        idempotencyKey: String
    ) async throws -> SectionCommit {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.commitSection(
            caseID: caseID,
            sectionID: sectionID,
            baseRevision: baseRevision,
            values: values,
            idempotencyKey: idempotencyKey
        )
    }

    public func linkEvidence(
        caseID: CaseID,
        requirementCode: String,
        documentID: DocumentID,
        idempotencyKey: String
    ) async throws -> EvidenceRequirementItem {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.linkEvidence(
            caseID: caseID,
            requirementCode: requirementCode,
            documentID: documentID,
            idempotencyKey: idempotencyKey
        )
    }

    public func reviewQueue() async throws -> [ReviewQueueItem] {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.reviewQueue()
    }

    public func recordReviewDecision(
        caseID: CaseID,
        outcome: ReviewOutcome,
        note: String?,
        idempotencyKey: String
    ) async throws -> ReviewDecision {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.recordReviewDecision(
            caseID: caseID,
            outcome: outcome,
            note: note,
            idempotencyKey: idempotencyKey
        )
    }

    public func draftPreview(caseID: CaseID) async throws -> DraftFormPreview {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.draftPreview(caseID: caseID)
    }

    public func stepUpChallenge(caseID: CaseID, idempotencyKey: String) async throws -> StepUpChallenge {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.stepUpChallenge(caseID: caseID, idempotencyKey: idempotencyKey)
    }

    public func approve(
        caseID: CaseID,
        preview: DraftFormPreview,
        stepUpChallenge: String,
        attested: Bool,
        idempotencyKey: String
    ) async throws -> ApprovalRecord {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.approve(
            caseID: caseID,
            preview: preview,
            stepUpChallenge: stepUpChallenge,
            attested: attested,
            idempotencyKey: idempotencyKey
        )
    }

    public func packageDownload(caseID: CaseID, packageID: PackageID, idempotencyKey: String) async throws -> ScopedDownloadGrant {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.packageDownload(caseID: caseID, packageID: packageID, idempotencyKey: idempotencyKey)
    }

    public func caseHistory(caseID: CaseID) async throws -> [CaseHistoryEvent] {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.caseHistory(caseID: caseID)
    }

    public func adminMembers() async throws -> [AdminMember] {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.adminMembers()
    }

    public func activeWorkspaceSessions() async throws -> [ActiveWorkspaceSession] {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.activeWorkspaceSessions()
    }

    public func auditSummary() async throws -> AuditSummary {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.auditSummary()
    }

    public func demoWorkspaceState() async throws -> DemoWorkspaceState {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.demoWorkspaceState()
    }

    public func resetDemoWorkspace(idempotencyKey: String) async throws -> DemoWorkspaceState {
        guard let fallbackClient else { throw TransportError.offline }
        return try await fallbackClient.resetDemoWorkspace(idempotencyKey: idempotencyKey)
    }
}
