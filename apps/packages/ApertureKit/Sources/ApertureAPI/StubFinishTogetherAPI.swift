import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import ApertureDomain

struct StubRelaySecret: Codable, Sendable, Hashable {
    let tokenSHA256: String
    let codeSHA256: String
}

struct StubRelayGrant: Codable, Sendable, Hashable {
    let relayID: EvidenceRelayID
    let expiresAt: Date
}

struct StubRelayAttempt: Codable, Sendable, Hashable {
    let relayID: EvidenceRelayID
    let codeSHA256: String
    let failureStatus: Int?
    let grantExpiresAt: Date?
}

struct StubRelayUploadSession: Codable, Sendable, Hashable {
    let relayID: EvidenceRelayID
    let originalName: String
    let sizeBytes: Int64
    let contentSHA256: String
    let expiresAt: Date
}

private struct CompleteRelayUploadRequest: Codable {
    let sessionSHA256: String
    let contentSHA256: String
}
private struct RelayMutationRequest: Codable { let relayID: EvidenceRelayID }

extension StubAPIClient: EvidenceRelayRecipientClient {
    public func guidedFinishPlan(caseID: CaseID, minutes: Int) async throws -> GuidedFinishPlan {
        await pause()
        try requireFinishCapability(.runGuidedFinish, caseID: caseID)
        try expireRelays()
        return GuidedFinishPolicy.makePlan(
            caseID: caseID,
            minutesBudget: minutes,
            items: scoped(storage.missingItems[caseID] ?? [], by: \.assignedPersonID),
            batches: storage.batches[caseID] ?? [],
            relays: currentRelays(caseID: caseID)
        )
    }

    public func proofMap(caseID: CaseID) async throws -> ProofMap {
        await pause()
        try requireFinishCapability(.viewProofMap, caseID: caseID)
        guard let summary = storage.allCases.first(where: { $0.id == caseID }) else { throw finishNotFound() }
        let entries = scoped(storage.reviewable[caseID] ?? [], by: \.subjectPersonID).map { field in
            FieldProof(
                subjectPersonID: field.subjectPersonID,
                localizedLabel: field.localizedLabel,
                englishFormLabel: field.englishFormLabel,
                canonicalPath: field.canonicalPath,
                value: field.displayValue,
                requiresHumanReview: field.needsHuman || field.isBlocked,
                provenance: field.provenance,
                destinations: proofDestinations(for: field, summary: summary)
            )
        }.sorted {
            if $0.subjectPersonID != $1.subjectPersonID {
                return $0.subjectPersonID.rawValue < $1.subjectPersonID.rawValue
            }
            return $0.localizedLabel < $1.localizedLabel
        }
        return ProofMap(caseID: caseID, entries: entries)
    }

    public func documentPagePreview(documentID: DocumentID, pageNumber: Int) async throws -> DocumentPagePreview {
        await pause()
        guard pageNumber > 0,
              let document = storage.documents.first(where: { $0.id == documentID }),
              document.allowsPreview,
              personScope.map({ scope in document.subjectPersonID.map(scope.contains) ?? false }) ?? true,
              let summary = storage.allCases.first(where: { $0.folderID == document.folderID }) else { throw finishNotFound() }
        try requireFinishCapability(.viewProofMap, caseID: summary.id)
        let data = try syntheticPagePNG()
        return DocumentPagePreview(
            documentID: documentID,
            pageNumber: pageNumber,
            mimeType: "image/png",
            pixelWidth: 600,
            pixelHeight: 780,
            contentSHA256: CapturePayloadProcessor.sha256(of: data),
            data: data
        )
    }

    public func evidenceRelays(caseID: CaseID) async throws -> [EvidenceRelay] {
        await pause()
        try requireFinishCapability(.manageEvidenceRelay, caseID: caseID)
        try expireRelays()
        return currentRelays(caseID: caseID)
            .filter { personScope?.contains($0.subjectPersonID) ?? true }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func createEvidenceRelay(
        caseID: CaseID,
        missingItemID: MissingItemID,
        idempotencyKey: String
    ) async throws -> CreateEvidenceRelayResult {
        await pause()
        try requireRelayKey(idempotencyKey)
        try requireFinishCapability(.manageEvidenceRelay, caseID: caseID)
        guard let item = storage.missingItems[caseID]?.first(where: { $0.id == missingItemID }),
              item.kind == .evidence,
              let requirementCode = item.requirementCode,
              personScope?.contains(item.assignedPersonID) ?? true else {
            throw ProblemDetails(
                type: "https://api.aperture.app/problems/relay-item-ineligible",
                title: "Only a cited evidence request can be shared",
                status: 422
            )
        }

        let relayID = EvidenceRelayID("relay_\(Self.digest("\(caseID.rawValue)|\(missingItemID.rawValue)|\(idempotencyKey)").prefix(16))")
        let token = Self.digest("stub-relay-token|\(relayID.rawValue)|\(idempotencyKey)")
        let codeSeed = Self.digest("stub-relay-code|\(relayID.rawValue)|\(idempotencyKey)")
        let numeric = UInt64(codeSeed.prefix(12), radix: 16) ?? 0
        let code = String(format: "%06llu", numeric % 1_000_000)

        if let existing = storage.evidenceRelays?[relayID] {
            return CreateEvidenceRelayResult(
                relay: currentRelay(existing),
                shareURL: Self.shareURL(token: token),
                accessCode: code
            )
        }
        if currentRelays(caseID: caseID).contains(where: {
            $0.missingItemID == missingItemID && [.active, .locked, .received].contains($0.status)
        }) {
            throw ProblemDetails(
                type: "https://api.aperture.app/problems/relay-already-active",
                title: "A request is already active for this item",
                status: 409
            )
        }

        let created = now()
        let relay = EvidenceRelay(
            id: relayID,
            caseID: caseID,
            missingItemID: missingItemID,
            requirementCode: requirementCode,
            requestedTitle: item.title,
            subjectPersonID: item.assignedPersonID,
            createdBy: currentUser,
            createdAt: created,
            expiresAt: created.addingTimeInterval(72 * 60 * 60),
            status: .active
        )
        try commit {
            if storage.evidenceRelays == nil { storage.evidenceRelays = [:] }
            if storage.relaySecrets == nil { storage.relaySecrets = [:] }
            storage.evidenceRelays?[relayID] = relay
            storage.relaySecrets?[relayID] = StubRelaySecret(
                tokenSHA256: Self.digest(token),
                codeSHA256: Self.digest("\(token)|\(code)")
            )
        }
        return CreateEvidenceRelayResult(
            relay: relay,
            shareURL: Self.shareURL(token: token),
            accessCode: code
        )
    }

    public func revokeEvidenceRelay(relayID: EvidenceRelayID, idempotencyKey: String) async throws -> EvidenceRelay {
        await pause()
        guard let relay = storage.evidenceRelays?[relayID] else { throw finishNotFound() }
        try requireFinishCapability(.manageEvidenceRelay, caseID: relay.caseID)
        guard personScope?.contains(relay.subjectPersonID) ?? true else { throw finishNotFound() }
        try expireRelays()
        return try idempotent(
            endpoint: "revokeEvidenceRelay",
            key: idempotencyKey,
            request: RelayMutationRequest(relayID: relayID)
        ) {
            guard let current = storage.evidenceRelays?[relayID], [.active, .locked].contains(current.status) else {
                throw finishNotFound()
            }
            let updated = replacing(current, status: .revoked)
            storage.evidenceRelays?[relayID] = updated
            storage.relaySecrets?[relayID] = nil
            storage.relayGrants = storage.relayGrants?.filter { $0.value.relayID != relayID }
            storage.relayUploadSessions = storage.relayUploadSessions?.filter { $0.value.relayID != relayID }
            storage.relayAttempts = storage.relayAttempts?.filter { $0.value.relayID != relayID }
            return updated
        }
    }

    public func acceptEvidenceRelay(relayID: EvidenceRelayID, idempotencyKey: String) async throws -> EvidenceRelay {
        await pause()
        guard let relay = storage.evidenceRelays?[relayID] else { throw finishNotFound() }
        try requireFinishCapability(.manageEvidenceRelay, caseID: relay.caseID)
        guard personScope?.contains(relay.subjectPersonID) ?? true else { throw finishNotFound() }
        return try idempotent(
            endpoint: "acceptEvidenceRelay",
            key: idempotencyKey,
            request: RelayMutationRequest(relayID: relayID)
        ) {
            guard let current = storage.evidenceRelays?[relayID], current.status == .received,
                  let documentID = current.submittedDocumentID,
                  let document = storage.documents.first(where: { $0.id == documentID }),
                  document.processingState == .extracted,
                  document.documentClass != nil else { throw finishNotFound() }
            let updated = replacing(current, status: .accepted)
            storage.evidenceRelays?[relayID] = updated
            if storage.evidenceLinks == nil { storage.evidenceLinks = [:] }
            var links = storage.evidenceLinks?[current.caseID] ?? [:]
            var documents = links[current.requirementCode] ?? []
            if !documents.contains(documentID) { documents.append(documentID) }
            links[current.requirementCode] = documents
            storage.evidenceLinks?[current.caseID] = links
            storage.reconcileMissingItems(caseID: current.caseID)
            storage.bumpCounters(caseID: current.caseID, incrementsFilledCounter: false, incrementsDocumentsCounter: true)
            storage.relayUploadSessions = storage.relayUploadSessions?.filter { $0.value.relayID != current.id }
            return updated
        }
    }

    public func rejectEvidenceRelay(relayID: EvidenceRelayID, idempotencyKey: String) async throws -> EvidenceRelay {
        await pause()
        guard let relay = storage.evidenceRelays?[relayID] else { throw finishNotFound() }
        try requireFinishCapability(.manageEvidenceRelay, caseID: relay.caseID)
        guard personScope?.contains(relay.subjectPersonID) ?? true else { throw finishNotFound() }
        return try idempotent(
            endpoint: "rejectEvidenceRelay",
            key: idempotencyKey,
            request: RelayMutationRequest(relayID: relayID)
        ) {
            guard let current = storage.evidenceRelays?[relayID], current.status == .received else {
                throw finishNotFound()
            }
            let updated = replacing(current, status: .rejected)
            if let documentID = current.submittedDocumentID,
               let document = storage.documents.first(where: { $0.id == documentID }) {
                storage.documents.removeAll { $0.id == documentID }
                if let index = storage.folders.firstIndex(where: { $0.id == document.folderID }) {
                    let folder = storage.folders[index]
                    storage.folders[index] = Folder(
                        id: folder.id, name: folder.name, ownerUserID: folder.ownerUserID,
                        persons: folder.persons, documentCount: max(0, folder.documentCount - 1),
                        cases: folder.cases
                    )
                }
            }
            storage.evidenceRelays?[relayID] = updated
            storage.relayUploadSessions = storage.relayUploadSessions?.filter { $0.value.relayID != current.id }
            return updated
        }
    }

    public func relayChallenge(token: String) async throws -> RelayChallenge {
        await pause()
        try expireRelays()
        guard let relay = relay(forToken: token), currentRelay(relay).status == .active else {
            return RelayChallenge(isAvailable: false)
        }
        return RelayChallenge(isAvailable: true, expiresAt: relay.expiresAt)
    }

    public func unlockRelay(token: String, accessCode: String, idempotencyKey: String) async throws -> RelayUploadGrant {
        await pause()
        try requireRelayKey(idempotencyKey)
        try expireRelays()
        let attemptKey = Self.digest("\(token)|\(idempotencyKey)")
        let presentedCodeHash = Self.digest("\(token)|\(accessCode)")
        let grantID = "grant_\(Self.digest("grant|\(token)|\(idempotencyKey)").prefix(32))"
        if let replay = storage.relayAttempts?[attemptKey] {
            guard replay.codeSHA256 == presentedCodeHash,
                  let relay = storage.evidenceRelays?[replay.relayID] else {
                throw ProblemDetails(
                    type: "https://api.aperture.app/problems/idempotency-key-conflict",
                    title: "Idempotency key already used",
                    status: 409
                )
            }
            if let status = replay.failureStatus {
                throw ProblemDetails(
                    type: status == 423 ? "https://api.aperture.app/problems/relay-locked" : "https://api.aperture.app/problems/relay-code",
                    title: status == 423 ? "This request is locked" : "That code did not match",
                    status: status
                )
            }
            guard let expiresAt = replay.grantExpiresAt else { throw finishNotFound() }
            return RelayUploadGrant(id: grantID, relayID: relay.id, requestedTitle: relay.requestedTitle, expiresAt: expiresAt)
        }
        guard let relay = relay(forToken: token), currentRelay(relay).status == .active,
              let secret = storage.relaySecrets?[relay.id] else {
            throw ProblemDetails(type: "https://api.aperture.app/problems/relay-unavailable", title: "This request is unavailable", status: 404)
        }
        guard secret.codeSHA256 == Self.digest("\(token)|\(accessCode)") else {
            let attempts = relay.failedCodeAttempts + 1
            let status: EvidenceRelayStatus = attempts >= 5 ? .locked : .active
            let updated = replacing(relay, status: status, failedCodeAttempts: attempts)
            try commit {
                storage.evidenceRelays?[relay.id] = updated
                if storage.relayAttempts == nil { storage.relayAttempts = [:] }
                storage.relayAttempts?[attemptKey] = StubRelayAttempt(
                    relayID: relay.id,
                    codeSHA256: presentedCodeHash,
                    failureStatus: attempts >= 5 ? 423 : 401,
                    grantExpiresAt: nil
                )
            }
            throw ProblemDetails(
                type: attempts >= 5 ? "https://api.aperture.app/problems/relay-locked" : "https://api.aperture.app/problems/relay-code",
                title: attempts >= 5 ? "This request is locked" : "That code did not match",
                status: attempts >= 5 ? 423 : 401
            )
        }
        let grant = RelayUploadGrant(
            id: grantID,
            relayID: relay.id,
            requestedTitle: relay.requestedTitle,
            expiresAt: now().addingTimeInterval(10 * 60)
        )
        try commit {
            if storage.relayGrants == nil { storage.relayGrants = [:] }
            storage.relayGrants?[Self.digest(grant.id)] = StubRelayGrant(relayID: relay.id, expiresAt: grant.expiresAt)
            if storage.relayAttempts == nil { storage.relayAttempts = [:] }
            storage.relayAttempts?[attemptKey] = StubRelayAttempt(
                relayID: relay.id,
                codeSHA256: presentedCodeHash,
                failureStatus: nil,
                grantExpiresAt: grant.expiresAt
            )
        }
        return grant
    }

    public func createRelayUploadSession(
        grantID: String,
        originalName: String,
        sizeBytes: Int64,
        contentSHA256: String,
        idempotencyKey: String
    ) async throws -> RelayUploadSession {
        await pause()
        try requireRelayKey(idempotencyKey)
        guard sizeBytes > 0, sizeBytes <= Int64(CapturePayloadProcessor.maximumBytes),
              contentSHA256.count == 64,
              contentSHA256.allSatisfy({ $0.isHexDigit }),
              !originalName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw finishNotFound()
        }
        let normalizedDigest = contentSHA256.lowercased()
        let sessionID = "relay_upload_\(Self.digest("\(grantID)|\(idempotencyKey)").prefix(32))"
        let sessionHash = Self.digest(sessionID)
        if let existing = storage.relayUploadSessions?[sessionHash] {
            guard existing.originalName == originalName,
                  existing.sizeBytes == sizeBytes,
                  existing.contentSHA256 == normalizedDigest else {
                throw ProblemDetails(
                    type: "https://api.aperture.app/problems/idempotency-key-conflict",
                    title: "Idempotency key already used",
                    status: 409
                )
            }
            return relayUploadSession(id: sessionID, metadata: existing)
        }
        guard let grant = storage.relayGrants?[Self.digest(grantID)], grant.expiresAt > now(),
              let relay = storage.evidenceRelays?[grant.relayID], currentRelay(relay).status == .active else {
            throw finishNotFound()
        }
        let expiresAt = min(grant.expiresAt, now().addingTimeInterval(10 * 60))
        let metadata = StubRelayUploadSession(
            relayID: relay.id,
            originalName: originalName,
            sizeBytes: sizeBytes,
            contentSHA256: normalizedDigest,
            expiresAt: expiresAt
        )
        try commit {
            if storage.relayUploadSessions == nil { storage.relayUploadSessions = [:] }
            storage.relayUploadSessions?[sessionHash] = metadata
        }
        return relayUploadSession(id: sessionID, metadata: metadata)
    }

    public func completeRelayUpload(
        sessionID: String,
        uploadedData: Data,
        idempotencyKey: String
    ) async throws -> RelaySubmissionReceipt {
        await pause()
        let prepared: PreparedCapturePayload
        do { prepared = try CapturePayloadProcessor.prepare(uploadedData) }
        catch {
            throw ProblemDetails(type: "https://api.aperture.app/problems/invalid-relay-document", title: "The document could not be accepted", status: 422)
        }
        let sessionHash = Self.digest(sessionID)
        let uploadedDigest = CapturePayloadProcessor.sha256(of: uploadedData)
        let request = CompleteRelayUploadRequest(sessionSHA256: sessionHash, contentSHA256: uploadedDigest)
        return try idempotent(endpoint: "completeRelayUpload", key: idempotencyKey, request: request) {
            guard let upload = storage.relayUploadSessions?[sessionHash], upload.expiresAt > now(),
                  upload.contentSHA256 == uploadedDigest,
                  upload.sizeBytes == Int64(uploadedData.count),
                  let relay = storage.evidenceRelays?[upload.relayID], currentRelay(relay).status == .active,
                  let summary = storage.allCases.first(where: { $0.id == relay.caseID }) else { throw finishNotFound() }
            let documentID = DocumentID("d_relay_\(UUID().uuidString.prefix(8))")
            let document = CaseDocument(
                id: documentID,
                folderID: summary.folderID,
                subjectPersonID: relay.subjectPersonID,
                originalName: upload.originalName,
                verifiedMimeType: prepared.verifiedMIMEType,
                sizeBytes: Int64(prepared.data.count),
                documentClass: nil,
                documentSubtype: nil,
                classificationBand: .needsReview,
                processingState: .needsClassification,
                detectedLanguage: nil,
                uploadedAt: now(),
                contentSHA256: prepared.contentSHA256
            )
            storage.documents.append(document)
            if let index = storage.folders.firstIndex(where: { $0.id == summary.folderID }) {
                let folder = storage.folders[index]
                storage.folders[index] = Folder(
                    id: folder.id, name: folder.name, ownerUserID: folder.ownerUserID,
                    persons: folder.persons, documentCount: folder.documentCount + 1, cases: folder.cases
                )
            }
            storage.evidenceRelays?[relay.id] = replacing(relay, status: .received, submittedDocumentID: documentID)
            storage.relaySecrets?[relay.id] = nil
            storage.relayGrants = storage.relayGrants?.filter { $0.value.relayID != relay.id }
            storage.relayAttempts = storage.relayAttempts?.filter { $0.value.relayID != relay.id }
            storage.inbox.append(InboxItem(
                id: NotificationID("n_relay_\(relay.id.rawValue)"),
                category: .documentProcessed,
                title: "A requested document arrived",
                body: "Review it before using it for your paperwork.",
                deepLink: URL(string: "aperture://cases/\(relay.caseID)/relays"),
                createdAt: now()
            ))
            return RelaySubmissionReceipt(relayID: relay.id, documentID: documentID, status: .received)
        }
    }

    private func currentRelays(caseID: CaseID) -> [EvidenceRelay] {
        (storage.evidenceRelays ?? [:]).values.filter { $0.caseID == caseID }.map(currentRelay)
    }

    private func relayUploadSession(id: String, metadata: StubRelayUploadSession) -> RelayUploadSession {
        RelayUploadSession(
            id: id,
            uploadURL: URL(string: "https://upload.lapluma.example/relay/\(Self.digest("upload|\(id)"))")!,
            expiresAt: metadata.expiresAt,
            expectedContentSHA256: metadata.contentSHA256
        )
    }

    private func currentRelay(_ relay: EvidenceRelay) -> EvidenceRelay {
        guard relay.status == .active, relay.expiresAt <= now() else { return relay }
        return replacing(relay, status: .expired)
    }

    private func expireRelays() throws {
        let expiredIDs = (storage.evidenceRelays ?? [:]).compactMap { id, relay in
            relay.status == .active && relay.expiresAt <= now() ? id : nil
        }
        guard !expiredIDs.isEmpty else { return }
        try commit {
            for relayID in expiredIDs {
                guard let relay = storage.evidenceRelays?[relayID] else { continue }
                storage.evidenceRelays?[relayID] = replacing(relay, status: .expired)
                storage.relaySecrets?[relayID] = nil
            }
            storage.relayGrants = storage.relayGrants?.filter { !expiredIDs.contains($0.value.relayID) }
            storage.relayUploadSessions = storage.relayUploadSessions?.filter { !expiredIDs.contains($0.value.relayID) }
            storage.relayAttempts = storage.relayAttempts?.filter { !expiredIDs.contains($0.value.relayID) }
        }
    }

    private func relay(forToken token: String) -> EvidenceRelay? {
        guard !token.isEmpty else { return nil }
        let digest = Self.digest(token)
        guard let relayID = storage.relaySecrets?.first(where: { $0.value.tokenSHA256 == digest })?.key,
              let relay = storage.evidenceRelays?[relayID] else { return nil }
        return relay
    }

    private func replacing(
        _ relay: EvidenceRelay,
        status: EvidenceRelayStatus,
        failedCodeAttempts: Int? = nil,
        submittedDocumentID: DocumentID? = nil
    ) -> EvidenceRelay {
        EvidenceRelay(
            id: relay.id, caseID: relay.caseID, missingItemID: relay.missingItemID,
            requirementCode: relay.requirementCode, requestedTitle: relay.requestedTitle,
            subjectPersonID: relay.subjectPersonID, createdBy: relay.createdBy,
            createdAt: relay.createdAt, expiresAt: relay.expiresAt, status: status,
            failedCodeAttempts: failedCodeAttempts ?? relay.failedCodeAttempts,
            submittedDocumentID: submittedDocumentID ?? relay.submittedDocumentID
        )
    }

    private func proofDestinations(for field: ReviewableField, summary: CaseSummary) -> [FormFieldReference] {
        let primary = FormFieldReference(
            formNumber: summary.pinnedForms.first?.formNumber ?? "Form",
            page: 1,
            fieldName: field.englishFormLabel
        )
        guard summary.packageCode == "FAMILY_I130",
              summary.pinnedForms.contains(where: { $0.formNumber == "I-130A" }),
              ["person.name.family", "person.birth.date", "person.birth.city"].contains(field.canonicalPath.rawValue) else {
            return [primary]
        }
        return [primary, FormFieldReference(formNumber: "I-130A", page: 1, fieldName: field.englishFormLabel)]
    }

    private func syntheticPagePNG() throws -> Data {
        let width = 600, height = 780
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw finishNotFound() }
        context.setFillColor(CGColor(red: 0.98, green: 0.97, blue: 0.94, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(gray: 0.22, alpha: 1))
        context.fill(CGRect(x: 54, y: 690, width: 280, height: 22))
        context.setFillColor(CGColor(gray: 0.72, alpha: 1))
        for row in 0..<12 {
            context.fill(CGRect(x: 54, y: 620 - row * 43, width: row % 3 == 0 ? 430 : 490, height: 8))
        }
        guard let image = context.makeImage() else { throw finishNotFound() }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { throw finishNotFound() }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw finishNotFound() }
        return output as Data
    }

    private static func digest(_ value: String) -> String {
        CapturePayloadProcessor.sha256(of: Data(value.utf8))
    }

    private static func shareURL(token: String) -> URL {
        URL(string: "https://relay.lapluma.example/r/\(token)")!
    }

    private func requireRelayKey(_ key: String) throws {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProblemDetails(type: "https://api.aperture.app/problems/idempotency-key-required", title: "Idempotency key required", status: 422)
        }
    }

    private func scoped<Value>(_ values: [Value], by person: KeyPath<Value, PersonID>) -> [Value] {
        guard let personScope else { return values }
        return values.filter { personScope.contains($0[keyPath: person]) }
    }

    /// Production returns 404 for both absent and inaccessible case resources. The
    /// stub mirrors that boundary so UI code cannot learn authorization by comparing
    /// error shapes.
    private func requireFinishCapability(_ capability: WorkflowCapability, caseID: CaseID) throws {
        guard WorkflowPolicy.capabilities(for: workspaceRoles).contains(capability),
              let summary = storage.allCases.first(where: { $0.id == caseID }),
              let folder = storage.folders.first(where: { $0.id == summary.folderID }) else {
            throw finishNotFound()
        }
        if workspaceRoles.contains(.applicant), folder.ownerUserID == currentUser { return }

        let assignment = storage.assignments?[caseID] ?? CaseAssignments(
            preparerID: UserID("u_stub_preparer"),
            reviewerID: UserID("u_stub_reviewer"),
            approverID: UserID("u_stub_approver")
        )
        if workspaceRoles.contains(.preparer), assignment.preparerID == currentUser { return }
        if capability == .viewProofMap,
           (workspaceRoles.contains(.reviewer) && assignment.reviewerID == currentUser
            || workspaceRoles.contains(.approver) && assignment.approverID == currentUser) { return }
        throw finishNotFound()
    }

    private func finishNotFound() -> ProblemDetails {
        ProblemDetails(type: "https://api.aperture.app/problems/not-found", title: "Not found", status: 404)
    }
}
