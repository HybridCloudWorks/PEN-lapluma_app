import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import ApertureDomain
@testable import ApertureAPI

/// These are not smoke tests. Each one pins an invariant the deliverable claims, so
/// that a future change which quietly breaks the compliance position fails the build
/// instead of shipping.
///
/// They mirror the server-side `INVARIANT-GATE`, which cannot be overridden by
/// engineering under any circumstance.
@Suite("Compliance invariants")
struct InvariantTests {

    // MARK: C-20 — progress is never a percentage

    @Test("ProgressCounters exposes no ratio, percentage or completeness score")
    func progressHasNoPercentage() throws {
        let counters = ProgressCounters(
            fieldsFilled: 174, fieldsRequired: 218,
            documentsCollected: 7, documentsRequired: 11,
            blockingItems: 6, advisoryItems: 3
        )
        let json = try JSONEncoder().encode(counters)
        let object = try #require(
            try JSONSerialization.jsonObject(with: json) as? [String: Any]
        )

        // The same rule the API contract test enforces server-side.
        let forbidden = try Regex("percent|completeness|completionScore|progressRatio")
        for key in object.keys {
            #expect(
                key.firstMatch(of: forbidden.ignoresCase()) == nil,
                "ProgressCounters encoded a forbidden key: \(key)"
            )
        }
        // And the denominators are actually present, so the UI can never be forced to
        // invent one.
        #expect(object["fieldsRequired"] != nil)
        #expect(object["documentsRequired"] != nil)
    }

    @Test("Readiness requires every counter satisfied and no blocking items")
    func readinessIsMechanical() {
        let notReady = ProgressCounters(
            fieldsFilled: 218, fieldsRequired: 218,
            documentsCollected: 11, documentsRequired: 11,
            blockingItems: 1, advisoryItems: 0
        )
        #expect(notReady.isReadyToFile == false)

        let ready = ProgressCounters(
            fieldsFilled: 218, fieldsRequired: 218,
            documentsCollected: 11, documentsRequired: 11,
            blockingItems: 0, advisoryItems: 3
        )
        // Advisory items never block readiness — only agency-required items do.
        #expect(ready.isReadyToFile)
    }

    // MARK: AI-1 — nothing model-touched reaches a form unattended

    @Test("A FieldValue cannot be constructed without a human confirmer")
    func fieldValueRequiresHuman() {
        // `confirmedBy` and `confirmedAt` are non-optional, so the type system refuses
        // to represent an unattended value. This test documents that guarantee and
        // fails to compile if someone relaxes it.
        let value = FieldValue(
            caseID: CaseID("c1"), subjectPersonID: PersonID("p1"),
            canonicalPath: CanonicalPath("person.birth.date"),
            value: "1979-03-14", confidenceBand: .verified, origin: .manual,
            provenance: .manualEntry(by: UserID("u1"), at: .now),
            confirmedBy: UserID("u1"), confirmedAt: .now
        )
        #expect(value.confirmedBy == UserID("u1"))
    }

    @Test("An open proposal marks the field as still needing a human")
    func openProposalNeedsHuman() {
        let proposal = ValueProposal(
            id: ProposalID("vp1"), caseID: CaseID("c1"), subjectPersonID: PersonID("p1"),
            canonicalPath: CanonicalPath("person.birth.date"),
            proposedValue: "1979-03-14", confidenceBand: .needsReview,
            origin: .extraction,
            provenance: .document(Self.anchor(confidence: 0.94)),
            createdAt: .now
        )
        let field = ReviewableField(
            subjectPersonID: PersonID("p1"),
            canonicalPath: CanonicalPath("person.birth.date"),
            localizedLabel: "Fecha de nacimiento", englishFormLabel: "Date of Birth",
            formReference: "I-130 Part 2, Item 8",
            confirmed: nil, openProposal: proposal
        )
        #expect(field.needsHuman)
        #expect(proposal.isAwaitingHuman)
    }

    // MARK: ADR-010 — confidence is banded, never a percentage

    @Test("Confidence bands never expose a raw score to the applicant surface")
    func bandsAreNotNumbers() {
        for band in ConfidenceBand.allCases {
            #expect(!band.chipKey.isEmpty)
            #expect(!band.explanationKey.isEmpty)
            // Only VERIFIED is bulk-acceptable, and bulk accept is reviewer-only.
            #expect(band.isBulkAcceptable == (band == .verified))
        }
    }

    @Test("A checkmark is not used for VERIFIED — it reads as endorsement")
    func verifiedIsNotACheckmark() {
        // UX-2 forbids affordances that read as approval of the application itself.
        #expect(!ConfidenceBand.verified.symbolName.contains("checkmark"))
    }

    // MARK: C-06 — sealed medical documents are never opened

    @Test("Sealed medical documents allow no preview and no extraction")
    func sealedMedicalIsOpaque() {
        #expect(DocumentClass.sealedMedical.isOpaqueByPolicy)

        let sealed = CaseDocument(
            id: DocumentID("d1"), folderID: FolderID("f1"), subjectPersonID: PersonID("p1"),
            originalName: "I-693 sealed envelope", verifiedMimeType: "image/jpeg",
            sizeBytes: 1_000, documentClass: .sealedMedical, documentSubtype: nil,
            processingState: .opaqueStored, detectedLanguage: nil,
            uploadedAt: .now, isOpaque: true
        )
        #expect(!sealed.allowsPreview)
        #expect(!sealed.allowsExtraction)

        // No other class is opaque by policy.
        for documentClass in DocumentClass.allCases where documentClass != .sealedMedical {
            #expect(!documentClass.isOpaqueByPolicy, "\(documentClass) should not be opaque")
        }
    }

    // MARK: ADR-003 — form fidelity

    @Test("Only AcroForm encodings support automatic fill")
    func onlyAcroFormFills() {
        #expect(FormEncoding.acroForm.supportsAutomaticFill)
        #expect(!FormEncoding.xfa.supportsAutomaticFill)
        #expect(!FormEncoding.flat.supportsAutomaticFill)
    }

    // MARK: DP-3 — provenance is inseparable from the value

    @Test("A degenerate bounding polygon is detected rather than trusted")
    func degenerateAnchorIsRejected() {
        let degenerate = DocumentAnchor(
            documentID: DocumentID("d1"), documentName: "Passport", pageNumber: 1,
            boundingPolygon: [CGPointCodable(x: 0.1, y: 0.1)],
            engine: "test", engineVersion: "1", rawConfidence: 0.99
        )
        // A value the model produced without a locatable source region is not
        // extraction — it is invention.
        #expect(degenerate.isDegenerate)
        #expect(!Self.anchor(confidence: 0.9).isDegenerate)
    }

    // MARK: ADR-007 — household trust boundary

    @Test("A minor can never be invited to hold their own credential")
    func minorsCannotBeInvited() {
        let minor = Person(
            id: PersonID("p_child"), displayLabel: "Ana R.", isMinor: true,
            participation: .active, holdsOwnCredential: false
        )
        #expect(!minor.canBeInvited)
    }

    // MARK: Consent defaults

    @Test("Analytics consent defaults to off and is withdrawable")
    func analyticsDefaultsOff() {
        #expect(!ConsentRecord.Purpose.analytics.defaultsToGranted)
        #expect(ConsentRecord.Purpose.analytics.isWithdrawable)
        // Service terms are the only non-withdrawable purpose.
        #expect(!ConsentRecord.Purpose.serviceTerms.isWithdrawable)
    }

    @Test("Security notifications cannot be suppressed")
    func securityNotificationsAlwaysOn() {
        #expect(!InboxItem.Category.security.isSuppressible)
        for category in InboxItem.Category.allCases where category != .security {
            #expect(category.isSuppressible)
        }
    }

    // MARK: Helpers

    static func anchor(confidence: Double) -> DocumentAnchor {
        DocumentAnchor(
            documentID: DocumentID("d1"), documentName: "Passport (Guatemala)",
            pageNumber: 2,
            boundingPolygon: [
                CGPointCodable(x: 0.14, y: 0.31), CGPointCodable(x: 0.48, y: 0.31),
                CGPointCodable(x: 0.48, y: 0.35), CGPointCodable(x: 0.14, y: 0.35)
            ],
            engine: "azure-document-intelligence",
            engineVersion: "prebuilt-idDocument@2024-11-30",
            rawConfidence: confidence
        )
    }
}

@Suite("Extraction safety policy")
struct ExtractionSafetyPolicyTests {
    @Test("Engine claims without a source region are dropped")
    func unanchoredClaimsAreDropped() {
        let decision = ExtractionSafetyPolicy.assess(ExtractionCandidate(
            source: .extractionEngine,
            kind: .text,
            anchor: nil
        ))
        #expect(decision.disposition == .dropUnanchoredClaim)

        let degenerate = DocumentAnchor(
            documentID: DocumentID("d1"), documentName: "Document", pageNumber: 1,
            boundingPolygon: [.init(x: 0.1, y: 0.1)],
            engine: "engine", engineVersion: "1", rawConfidence: 0.99
        )
        #expect(ExtractionSafetyPolicy.assess(ExtractionCandidate(
            source: .extractionEngine,
            kind: .text,
            anchor: degenerate
        )).disposition == .dropUnanchoredClaim)
    }

    @Test("Ambiguous dates require a human without choosing an interpretation")
    func ambiguousDatesNeedReview() {
        let decision = ExtractionSafetyPolicy.assess(ExtractionCandidate(
            source: .extractionEngine,
            kind: .date,
            anchor: anchor(),
            dateInterpretations: ["2020-03-04", "2020-04-03"]
        ))
        #expect(decision.confidenceBand == .needsReview)
        #expect(decision.reviewReasons == [.ambiguousDate])
    }

    @Test("Instruction-like document text stays inert and raises a security event")
    func instructionLikeTextIsFlagged() {
        let decision = ExtractionSafetyPolicy.assess(ExtractionCandidate(
            source: .extractionEngine,
            kind: .text,
            anchor: anchor(),
            instructionLikeTextDetected: true
        ))
        #expect(decision.disposition == .offerForHumanReview)
        #expect(decision.confidenceBand == .needsReview)
        #expect(decision.reviewReasons.contains(.instructionLikeText))
        #expect(decision.raisesSecurityEvent)
    }

    @Test("Original-script names survive encoding without heuristic splitting")
    func originalScriptNameRoundTrips() throws {
        let original = ExtractedName(
            original: "كارلوس راميريز",
            script: "Arab",
            transliteration: "Carlos Ramírez"
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ExtractedName.self, from: encoded)
        #expect(decoded == original)
        #expect(decoded.original == "كارلوس راميريز")
    }

    private func anchor(checksumValid: Bool? = nil) -> DocumentAnchor {
        DocumentAnchor(
            documentID: DocumentID("d1"), documentName: "Document", pageNumber: 1,
            boundingPolygon: [
                .init(x: 0.1, y: 0.1), .init(x: 0.4, y: 0.1),
                .init(x: 0.4, y: 0.2), .init(x: 0.1, y: 0.2)
            ],
            engine: "engine", engineVersion: "1", rawConfidence: 0.95,
            checksumValid: checksumValid
        )
    }
}

@Suite("Stub client behaviour")
struct StubClientTests {

    @Test("Upload completion returns the server content digest")
    func uploadIntegrityRoundTrip() async throws {
        let api = StubAPIClient()
        await api.setDelay(.zero)
        let digest = CapturePayloadProcessor.sha256(of: Data("document".utf8))
        let upload = try await api.createUploadSession(
            folderID: FolderID("f_ramirez"),
            subjectPersonID: PersonID("p_carlos"),
            originalName: "document.jpg",
            sizeBytes: 8,
            source: .files,
            quality: nil,
            contentSHA256: digest,
            idempotencyKey: "integrity-create"
        )
        let completed = try await api.completeUpload(
            sessionID: upload.sessionID,
            idempotencyKey: "integrity-complete"
        )
        #expect(completed.contentSHA256 == digest)
    }

    @Test("Creating a case without an attestation is refused")
    func attestationRequired() async throws {
        let api = StubAPIClient()
        await api.setDelay(.zero)

        await #expect(throws: ProblemDetails.self) {
            _ = try await api.createCase(
                folderID: FolderID("f_ramirez"),
                packageCode: "FAMILY_I130",
                roleAssignments: [:],
                attestation: SelectionAttestation(
                    attested: false, attestationVersion: "2026.03", text: "…"
                ),
                idempotencyKey: "k1"
            )
        }
    }

    @Test("An interview cannot start for a person this case has no fields for")
    func interviewRequiresASubjectWithFields() async throws {
        let api = StubAPIClient()
        await api.setDelay(.zero)

        // A session for an unrelated person would look alive and then fail on the
        // first confirmation, which is how a hard-coded fixture identifier hid.
        await #expect(throws: ProblemDetails.self) {
            _ = try await api.startInterview(
                caseID: CaseID("c_ramirez_i130"), personID: PersonID("p_not_in_this_case"),
                batchID: BatchID("mi_batch_017"), modality: .chat,
                consent: nil, accessibilityProfileEnabled: false, idempotencyKey: "wrong-person"
            )
        }
    }

    @Test("A voice interview cannot start without recorded consent")
    func voiceRequiresConsent() async throws {
        let api = StubAPIClient()
        await api.setDelay(.zero)

        await #expect(throws: ProblemDetails.self) {
            _ = try await api.startInterview(
                caseID: CaseID("c_ramirez_i130"), personID: PersonID("p_carlos"),
                batchID: BatchID("mi_batch_017"), modality: .voice,
                consent: nil, accessibilityProfileEnabled: false, idempotencyKey: "k2"
            )
        }
    }

    @Test("The accessibility profile waives the voice budget")
    func accessibilityProfileWaivesVoiceBudget() async throws {
        let api = StubAPIClient()
        await api.setDelay(.zero)

        let session = try await api.startInterview(
            caseID: CaseID("c_ramirez_i130"),
            personID: PersonID("p_carlos"),
            batchID: BatchID("mi_batch_017"),
            modality: .voice,
            consent: VoiceConsent(
                noticeVersion: "test",
                noticeSHA256: "test",
                spokenAndDisplayed: true,
                retainAudioClips: false,
                grantedAt: Date()
            ),
            accessibilityProfileEnabled: true,
            idempotencyKey: "accessibility-budget"
        )

        #expect(session.budget?.isWaived == true)
        #expect(session.budget?.isExhausted == false)
    }

    @Test("The catalog returns the same order regardless of caller")
    func catalogIsNotPersonalised() async throws {
        let api = StubAPIClient()
        await api.setDelay(.zero)

        let first = try await api.catalogPackages(query: nil).map(\.packageCode)
        let second = try await api.catalogPackages(query: nil).map(\.packageCode)
        #expect(first == second)
        #expect(first == first.sorted(), "Catalog must be deterministically ordered")
    }

    @Test("Confirming a value attributes it to a human")
    func confirmationIsAttributed() async throws {
        let api = StubAPIClient()
        await api.setDelay(.zero)

        let confirmed = try await api.confirmValues(
            caseID: CaseID("c_ramirez_i130"),
            confirmations: [ValueConfirmation(
                personID: PersonID("p_carlos"),
                canonicalPath: CanonicalPath("person.birth.date"),
                value: "1979-03-14"
            )],
            idempotencyKey: "k3"
        )
        #expect(confirmed.count == 1)
        // Non-optional by construction, but assert it explicitly so the intent is
        // visible in the test report.
        #expect(confirmed[0].confirmedBy.rawValue.isEmpty == false)
        #expect(confirmed[0].discrepancy?.id == DiscrepancyID("disc_dob"))
        let readiness = try await api.packageGenerationReadiness(caseID: CaseID("c_ramirez_i130"))
        #expect(!readiness.canGenerate)
        #expect(readiness.blockingDiscrepancies > 0)
    }

    @Test("Confirming an unchanged value cannot resolve its own blocking discrepancy")
    func confirmationCannotSelfResolveDiscrepancy() async throws {
        let api = StubAPIClient()
        await api.setDelay(.zero)
        let caseID = CaseID("c_ramirez_i130")
        let path = CanonicalPath("person.birth.date")
        let seeded = try #require(
            try await api.reviewableFields(caseID: caseID).first { $0.canonicalPath == path }
        )
        let discrepancy = try #require(seeded.confirmed?.discrepancy)
        let unchangedValue = try #require(seeded.confirmed?.value)
        #expect(discrepancy.severity == .blocking)

        // The identifier matches, so the identity check alone would pass. The
        // value is unchanged, meaning nothing was adjudicated — the shape a
        // client produces when it supplies the identifier reflexively (T-37).
        do {
            _ = try await api.confirmValues(
                caseID: caseID,
                confirmations: [ValueConfirmation(
                    personID: PersonID("p_carlos"),
                    canonicalPath: path,
                    value: unchangedValue,
                    resolvesDiscrepancyID: discrepancy.id
                )],
                idempotencyKey: "self-resolve"
            )
        } catch let problem as ProblemDetails {
            #expect(problem.status == 422)
        }

        // Whatever the endpoint decided, the gate must still be closed.
        let readiness = try await api.packageGenerationReadiness(caseID: caseID)
        #expect(readiness.blockingDiscrepancies > 0)
        #expect(readiness.canGenerate == false)
    }

    @Test("Choosing the alternative value resolves the discrepancy")
    func adjudicatingToAlternativeResolvesDiscrepancy() async throws {
        let api = StubAPIClient()
        await api.setDelay(.zero)
        let caseID = CaseID("c_ramirez_i130")
        let path = CanonicalPath("person.birth.date")
        let seeded = try #require(
            try await api.reviewableFields(caseID: caseID).first { $0.canonicalPath == path }
        )
        let discrepancy = try #require(seeded.confirmed?.discrepancy)
        let alternative = try #require(discrepancy.alternativeValue)

        _ = try await api.confirmValues(
            caseID: caseID,
            confirmations: [ValueConfirmation(
                personID: PersonID("p_carlos"),
                canonicalPath: path,
                value: alternative,
                resolvesDiscrepancyID: discrepancy.id
            )],
            idempotencyKey: "adjudicate-alternative"
        )

        let field = try #require(
            try await api.reviewableFields(caseID: caseID).first { $0.canonicalPath == path }
        )
        #expect(field.confirmed?.value == alternative)
        #expect(field.confirmed?.discrepancy == nil)
        #expect(field.isBlocked == false)
    }

    @Test("A confirmation can resolve only the discrepancy attached to its field")
    func confirmationValidatesDiscrepancyIdentity() async throws {
        let api = StubAPIClient()
        await api.setDelay(.zero)
        let confirmation = ValueConfirmation(
            personID: PersonID("p_carlos"),
            canonicalPath: CanonicalPath("person.birth.date"),
            value: "1979-03-14",
            resolvesDiscrepancyID: DiscrepancyID("disc_unknown")
        )

        do {
            _ = try await api.confirmValues(
                caseID: CaseID("c_ramirez_i130"),
                confirmations: [confirmation],
                idempotencyKey: "unknown-discrepancy"
            )
            Issue.record("An unrelated discrepancy identifier must be rejected")
        } catch let problem as ProblemDetails {
            #expect(problem.status == 422)
        }

        let field = try #require(
            try await api.reviewableFields(caseID: CaseID("c_ramirez_i130"))
                .first { $0.canonicalPath == CanonicalPath("person.birth.date") }
        )
        #expect(field.confirmed?.discrepancy?.id == DiscrepancyID("disc_dob"))
    }

    @Test("Completing concurrent upload sessions selects the matching document")
    func uploadCompletionHonorsSessionIdentity() async throws {
        let api = StubAPIClient()
        await api.setDelay(.zero)
        let first = try await api.createUploadSession(
            folderID: FolderID("f_ramirez"), subjectPersonID: PersonID("p_maria"),
            originalName: "maria.jpg", sizeBytes: 10, source: .camera,
            quality: nil, contentSHA256: "first-digest", idempotencyKey: "upload-first"
        )
        let second = try await api.createUploadSession(
            folderID: FolderID("f_ramirez"), subjectPersonID: PersonID("p_carlos"),
            originalName: "carlos.jpg", sizeBytes: 20, source: .camera,
            quality: nil, contentSHA256: "second-digest", idempotencyKey: "upload-second"
        )

        let completedSecond = try await api.completeUpload(
            sessionID: second.sessionID,
            idempotencyKey: "complete-second"
        )
        #expect(completedSecond.id == second.documentID)
        #expect(completedSecond.subjectPersonID == PersonID("p_carlos"))
        #expect(completedSecond.contentSHA256 == "second-digest")

        let completedFirst = try await api.completeUpload(
            sessionID: first.sessionID,
            idempotencyKey: "complete-first"
        )
        #expect(completedFirst.id == first.documentID)
        #expect(completedFirst.subjectPersonID == PersonID("p_maria"))
        #expect(completedFirst.contentSHA256 == "first-digest")
    }

    @Test("Expired and unknown upload sessions fail closed")
    func uploadCompletionValidatesExpiry() async throws {
        final class Clock: @unchecked Sendable {
            var value = Date(timeIntervalSince1970: 1_000)
        }
        let clock = Clock()
        let api = StubAPIClient(now: { clock.value })
        await api.setDelay(.zero)
        let session = try await api.createUploadSession(
            folderID: FolderID("f_ramirez"), subjectPersonID: nil,
            originalName: "expired.jpg", sizeBytes: 10, source: .camera,
            quality: nil, contentSHA256: "digest", idempotencyKey: "create-expired"
        )
        clock.value = session.expiresAt

        do {
            _ = try await api.completeUpload(
                sessionID: session.sessionID,
                idempotencyKey: "complete-expired"
            )
            Issue.record("An expired upload session must be rejected")
        } catch let problem as ProblemDetails {
            #expect(problem.status == 410)
        }
        do {
            _ = try await api.completeUpload(
                sessionID: "us_unknown",
                idempotencyKey: "complete-unknown"
            )
            Issue.record("An unknown upload session must be rejected")
        } catch let problem as ProblemDetails {
            #expect(problem.status == 404)
        }
    }

    @Test("Accepting an extraction preserves its source and supersedes the proposal")
    func acceptingExtractionPreservesSource() async throws {
        let api = StubAPIClient()
        await api.setDelay(.zero)

        let confirmed = try await api.confirmValues(
            caseID: CaseID("c_ramirez_i130"),
            confirmations: [ValueConfirmation(
                personID: PersonID("p_carlos"),
                canonicalPath: CanonicalPath("person.name.family"),
                value: "Ramírez"
            )],
            idempotencyKey: "accept-extraction"
        )

        let value = try #require(confirmed.first)
        #expect(value.acceptedProposalID == ProposalID("vp_family"))
        #expect(value.origin == .extraction)
        guard case .document(let anchor) = value.provenance else {
            Issue.record("Accepting an extraction must preserve its document anchor")
            return
        }
        #expect(anchor.documentID == DocumentID("d_passport"))

        let history = try await api.valueHistory(
            caseID: CaseID("c_ramirez_i130"),
            personID: PersonID("p_carlos"),
            canonicalPath: CanonicalPath("person.name.family")
        )
        #expect(history.contains { $0.action == .proposalSuperseded })
        #expect(history.contains { $0.action == .humanConfirmed })
        #expect(history.filter { $0.action.requiresHumanActor }.allSatisfy { $0.hasRequiredAttribution })
    }

    @Test("A correction is append-only, persists, and does not inflate progress")
    func correctionHistoryPersists() async throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "aperture-value-history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let caseID = CaseID("c_ramirez_i130")
        let personID = PersonID("p_carlos")
        let path = CanonicalPath("person.name.family")
        let api = StubAPIClient(persistenceURL: url)
        await api.setDelay(.zero)
        let before = try await api.progress(caseID: caseID).fieldsFilled

        _ = try await api.confirmValues(
            caseID: caseID,
            confirmations: [ValueConfirmation(
                personID: personID,
                canonicalPath: path,
                value: "Ramirez corrected"
            )],
            idempotencyKey: "correction-1"
        )
        let afterConfirmation = try await api.progress(caseID: caseID).fieldsFilled
        #expect(afterConfirmation == before + 1)

        _ = try await api.confirmValues(
            caseID: caseID,
            confirmations: [ValueConfirmation(
                personID: personID,
                canonicalPath: path,
                value: "Ramírez Gómez"
            )],
            idempotencyKey: "correction-2"
        )
        #expect(try await api.progress(caseID: caseID).fieldsFilled == afterConfirmation)

        let relaunched = StubAPIClient(persistenceURL: url)
        await relaunched.setDelay(.zero)
        let field = try #require(
            try await relaunched.reviewableFields(caseID: caseID)
                .first { $0.canonicalPath == path }
        )
        #expect(field.confirmed?.value == "Ramírez Gómez")
        #expect(field.openProposal == nil)

        let history = try await relaunched.valueHistory(
            caseID: caseID,
            personID: personID,
            canonicalPath: path
        )
        #expect(history.filter { $0.action == .humanCorrected }.count == 2)
        #expect(history.contains { $0.previousValue == "Ramirez corrected" })
        #expect(history.filter { $0.action.requiresHumanActor }.allSatisfy { $0.hasRequiredAttribution })
    }

    @Test("Package generation refuses every unattended value")
    func packageGenerationFailsClosed() async throws {
        let api = StubAPIClient()
        await api.setDelay(.zero)
        let blockedCase = CaseID("c_ramirez_i130")

        let readiness = try await api.packageGenerationReadiness(caseID: blockedCase)
        #expect(!readiness.canGenerate)
        #expect(readiness.unconfirmedRequiredFields > 0)
        #expect(readiness.openProposals > 0)
        #expect(readiness.blockingDiscrepancies > 0)

        do {
            _ = try await api.requestPackageGeneration(
                caseID: blockedCase,
                idempotencyKey: "must-fail"
            )
            Issue.record("Generation must fail while a proposal is unresolved")
        } catch let problem as ProblemDetails {
            #expect(problem.status == 409)
            #expect(problem.type.hasSuffix("human-confirmation-required"))
            #expect(problem.errors?.count == 3)
        }

        let ready = try await api.requestPackageGeneration(
            caseID: CaseID("c_demo_ready"),
            idempotencyKey: "ready-package"
        )
        #expect(ready.verification.passed)
    }

    @Test("Reclassifying to sealed medical makes the document opaque")
    func reclassifyToSealedIsOpaque() async throws {
        let api = StubAPIClient()
        await api.setDelay(.zero)

        let updated = try await api.reclassify(documentID: DocumentID("d_passport"), to: .sealedMedical)
        #expect(updated.isOpaque)
        #expect(!updated.allowsExtraction)
        #expect(updated.processingState == .opaqueStored)
        #expect(updated.classificationBand == .humanConfirmed)
        #expect(updated.classificationOverride?.previousClass == .identity)
    }

    @Test("A human classification override is authoritative and persists")
    func classificationOverridePersists() async throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "aperture-classification-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let api = StubAPIClient(persistenceURL: url)
        await api.setDelay(.zero)
        let updated = try await api.reclassify(
            documentID: DocumentID("d_birthcert"),
            to: .translation
        )
        #expect(updated.documentClass == .translation)
        #expect(updated.classificationBand == .humanConfirmed)
        #expect(updated.classificationOverride?.previousClass == .civil)
        #expect(updated.processingState == .extracted)

        let relaunched = StubAPIClient(persistenceURL: url)
        await relaunched.setDelay(.zero)
        let documents = try await relaunched.documents(folderID: FolderID("f_ramirez"))
        let persisted = try #require(documents.first { $0.id == DocumentID("d_birthcert") })
        #expect(persisted.documentClass == .translation)
        #expect(persisted.classificationBand == .humanConfirmed)
        #expect(persisted.classificationOverride != nil)
    }

    @Test("Opened I-693 refuses extraction without becoming opaque")
    func openedMedicalExamRefusesExtraction() async throws {
        let api = StubAPIClient()
        await api.setDelay(.zero)

        let updated = try await api.reclassify(
            documentID: DocumentID("d_birthcert"),
            to: .openedMedicalExam
        )
        #expect(!updated.isOpaque)
        #expect(updated.allowsPreview)
        #expect(!updated.allowsExtraction)
        #expect(updated.processingState == .extractionFailed)
    }

    @Test("A sealed document cannot be made readable later")
    func sealedClassificationIsIrreversible() async throws {
        let api = StubAPIClient()
        await api.setDelay(.zero)

        await #expect(throws: ProblemDetails.self) {
            try await api.reclassify(documentID: DocumentID("d_sealed"), to: .identity)
        }
        let documents = try await api.documents(folderID: FolderID("f_ramirez"))
        let sealed = try #require(documents.first { $0.id == DocumentID("d_sealed") })
        #expect(sealed.isOpaque)
        #expect(!sealed.allowsExtraction)
    }

    @Test("Mobile state survives recreating the local client")
    func localPersistenceSurvivesRelaunch() async throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "aperture-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let first = StubAPIClient(persistenceURL: url)
        await first.setDelay(.zero)
        let created = try await first.createFolder(name: "Saved folder", idempotencyKey: "persist-1")

        let relaunched = StubAPIClient(persistenceURL: url)
        await relaunched.setDelay(.zero)
        let folders = try await relaunched.folders()
        #expect(folders.contains(where: { $0.id == created.id && $0.name == "Saved folder" }))
    }

    @Test("Delete everything preserves only public catalog data")
    func localDeleteErasesApplicantRecords() async throws {
        let api = StubAPIClient()
        await api.setDelay(.zero)
        try await api.deleteAllUserData()

        let folders = try await api.folders()
        let inbox = try await api.inbox()
        let consents = try await api.consents()
        let catalog = try await api.catalogPackages(query: nil)
        #expect(folders.isEmpty)
        #expect(inbox.isEmpty)
        #expect(consents.isEmpty)
        #expect(catalog.isEmpty == false)
    }
}

@Suite("Offline capture queue")
struct OfflineCaptureQueueTests {
    private actor CaptureRecorder {
        private(set) var ids: [String] = []

        func append(_ id: String) { ids.append(id) }
    }

    @Test("Captured bytes and retry identity survive relaunch")
    func queueSurvivesRelaunch() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "aperture-capture-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let payload = Data("private document bytes".utf8)

        let first = PendingCaptureQueue(directoryURL: directory)
        let queued = try await first.enqueue(
            data: payload,
            folderID: FolderID("f1"),
            subjectPersonID: PersonID("p1"),
            originalName: "document.jpg",
            source: .camera
        )

        let relaunched = PendingCaptureQueue(directoryURL: directory)
        let restored = try #require(await relaunched.pendingCaptures().first)
        #expect(restored.id == queued.id)
        #expect(restored.createSessionIdempotencyKey == queued.createSessionIdempotencyKey)
        #expect(restored.completeUploadIdempotencyKey == queued.completeUploadIdempotencyKey)
        #expect(try await relaunched.payload(for: restored) == payload)
    }

    @Test("A failed drain retains bytes and a successful retry removes them")
    func drainIsLossless() async throws {
        struct ExpectedFailure: Error {}

        let directory = FileManager.default.temporaryDirectory
            .appending(path: "aperture-drain-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = PendingCaptureQueue(directoryURL: directory)
        let queued = try await queue.enqueue(
            data: Data([1, 2, 3]),
            folderID: FolderID("f1"),
            subjectPersonID: nil,
            originalName: "scan.pdf",
            source: .files
        )

        let failed = await queue.drain { _, _ in throw ExpectedFailure() }
        #expect(failed == CaptureDrainResult(uploadedCount: 0, remainingCount: 1))
        #expect(await queue.pendingCaptures().first?.id == queued.id)

        let succeeded = await queue.drain { capture, bytes in
            #expect(capture.id == queued.id)
            #expect(bytes == Data([1, 2, 3]))
        }
        #expect(succeeded == CaptureDrainResult(uploadedCount: 1, remainingCount: 0))
        #expect(await queue.pendingCount() == 0)
    }

    @Test("Concurrent drains do not duplicate an in-flight upload")
    func concurrentDrainsAreCoalesced() async throws {
        actor UploadGate {
            var callCount = 0
            var continuation: CheckedContinuation<Void, Never>?

            func wait() async {
                callCount += 1
                await withCheckedContinuation { continuation = $0 }
            }

            func release() { continuation?.resume() }
        }

        let directory = FileManager.default.temporaryDirectory
            .appending(path: "aperture-concurrent-drain-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = PendingCaptureQueue(directoryURL: directory)
        _ = try await queue.enqueue(
            data: Data([1]), folderID: FolderID("f1"), subjectPersonID: nil,
            originalName: "one.jpg", source: .camera
        )
        let gate = UploadGate()
        let first = Task {
            await queue.drain { _, _ in await gate.wait() }
        }

        // Bounded: an unbounded spin here turns any regression that stops the drain
        // from reaching the upload into a 30-minute CI timeout instead of a failure.
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while await gate.callCount == 0 {
            try #require(
                ContinuousClock.now < deadline,
                "The drain never invoked the upload operation"
            )
            await Task.yield()
        }
        let overlapping = await queue.drain { _, _ in
            Issue.record("Overlapping drain must not invoke the upload operation")
        }
        #expect(overlapping.wasAlreadyDraining)
        #expect(await gate.callCount == 1)
        await gate.release()
        #expect(await first.value.uploadedCount == 1)
    }

    @Test("A permanently invalid capture is retained for recovery and does not block later work")
    func permanentFailureMovesToDeadLetter() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "aperture-dead-letter-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = PendingCaptureQueue(directoryURL: directory)
        let poison = try await queue.enqueue(
            data: Data([1]), folderID: FolderID("f1"), subjectPersonID: nil,
            originalName: "poison.jpg", source: .camera
        )
        let valid = try await queue.enqueue(
            data: Data([2]), folderID: FolderID("f1"), subjectPersonID: nil,
            originalName: "valid.jpg", source: .camera
        )
        let uploaded = CaptureRecorder()

        let result = await queue.drain { capture, _ in
            if capture.id == poison.id {
                throw CaptureDrainFailure.permanentlyInvalid(reason: "invalid-local-capture")
            }
            await uploaded.append(capture.id)
        }

        #expect(result == CaptureDrainResult(uploadedCount: 1, remainingCount: 0, deadLetterCount: 1))
        #expect(await uploaded.ids == [valid.id])
        let failed = try #require(await queue.deadLetterCaptures().first)
        #expect(failed.id == poison.id)
        #expect(failed.retryCount == 1)
        #expect(failed.deadLetterReason == "invalid-local-capture")
        #expect(try await queue.payload(for: failed) == Data([1]))

        let relaunched = PendingCaptureQueue(directoryURL: directory)
        #expect(await relaunched.deadLetterCaptures().first?.id == poison.id)
        #expect(await relaunched.pendingCount() == 0)
    }

    @Test("Transient poison is bounded before later captures proceed")
    func transientFailureHasBoundedRetries() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "aperture-bounded-retry-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = PendingCaptureQueue(directoryURL: directory)
        let poison = try await queue.enqueue(
            data: Data([1]), folderID: FolderID("f1"), subjectPersonID: nil,
            originalName: "poison.jpg", source: .camera
        )
        let valid = try await queue.enqueue(
            data: Data([2]), folderID: FolderID("f1"), subjectPersonID: nil,
            originalName: "valid.jpg", source: .camera
        )
        let uploaded = CaptureRecorder()
        let operation: @Sendable (PendingCapture, Data) async throws -> Void = { capture, _ in
            if capture.id == poison.id { throw CaptureDrainFailure.transient }
            await uploaded.append(capture.id)
        }

        let first = await queue.drain(maximumAttempts: 2, using: operation)
        #expect(first.remainingCount == 2)
        #expect(first.deadLetterCount == 0)
        let second = await queue.drain(maximumAttempts: 2, using: operation)
        #expect(second == CaptureDrainResult(uploadedCount: 1, remainingCount: 0, deadLetterCount: 1))
        #expect(await uploaded.ids == [valid.id])
        let failed = try #require(await queue.deadLetterCaptures().first)
        #expect(failed.retryCount == 2)
        #expect(failed.deadLetterReason == "retry-limit-exceeded")
    }

    @Test("A corrupted local payload is dead-lettered before upload")
    func corruptPayloadFailsIntegrityGate() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "aperture-corrupt-payload-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = PendingCaptureQueue(directoryURL: directory)
        let corrupt = try await queue.enqueue(
            data: Data([1, 2, 3]), folderID: FolderID("f1"), subjectPersonID: nil,
            originalName: "corrupt.jpg", source: .camera
        )
        let valid = try await queue.enqueue(
            data: Data([4, 5, 6]), folderID: FolderID("f1"), subjectPersonID: nil,
            originalName: "valid.jpg", source: .camera
        )
        try Data([9, 9, 9]).write(
            to: directory.appending(path: "capture-\(corrupt.id).payload"),
            options: .atomic
        )
        let uploaded = CaptureRecorder()

        let result = await queue.drain { capture, _ in await uploaded.append(capture.id) }

        #expect(result == CaptureDrainResult(uploadedCount: 1, remainingCount: 0, deadLetterCount: 1))
        #expect(await uploaded.ids == [valid.id])
        #expect(await queue.deadLetterCaptures().first?.deadLetterReason == "local-payload-checksum-mismatch")
    }

    @Test("Pending byte estimate matches protected payloads")
    func pendingByteEstimate() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "aperture-estimate-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = PendingCaptureQueue(directoryURL: directory)
        _ = try await queue.enqueue(
            data: Data(repeating: 1, count: 12),
            folderID: FolderID("f1"),
            subjectPersonID: nil,
            originalName: "one.jpg",
            source: .camera
        )
        _ = try await queue.enqueue(
            data: Data(repeating: 2, count: 30),
            folderID: FolderID("f1"),
            subjectPersonID: nil,
            originalName: "two.jpg",
            source: .camera
        )
        #expect(await queue.pendingCount() == 2)
        #expect(await queue.pendingByteCount() == 42)
    }

    @Test("A malformed manifest is preserved and reported without deleting payloads")
    func corruptManifestIsRecoverable() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "aperture-corrupt-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = PendingCaptureQueue(directoryURL: directory)
        let capture = try await queue.enqueue(
            data: Data([1, 2, 3]), folderID: FolderID("f1"),
            subjectPersonID: nil, originalName: "scan.jpg", source: .camera
        )
        let manifest = directory.appending(path: "manifest.json")
        try Data("not-json".utf8).write(to: manifest, options: .atomic)

        let relaunched = PendingCaptureQueue(directoryURL: directory)
        guard case .corruptManifestPreserved(let preserved) = await relaunched.recoveryIssue() else {
            Issue.record("Corrupt manifest recovery must be surfaced")
            return
        }
        #expect(FileManager.default.fileExists(atPath: preserved.path))
        let payload = directory.appending(path: "capture-\(capture.id).payload")
        #expect(FileManager.default.fileExists(atPath: payload.path))
    }

    @Test("Valid manifest entries survive an invalid sibling")
    func manifestDecodesPerEntry() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "aperture-partial-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = PendingCaptureQueue(directoryURL: directory)
        let capture = try await queue.enqueue(
            data: Data([4, 5, 6]), folderID: FolderID("f1"),
            subjectPersonID: nil, originalName: "valid.jpg", source: .camera
        )
        let manifest = directory.appending(path: "manifest.json")
        let data = try Data(contentsOf: manifest)
        var entries = try #require(JSONSerialization.jsonObject(with: data) as? [Any])
        entries.append(["id": "missing-required-fields"])
        try JSONSerialization.data(withJSONObject: entries).write(to: manifest, options: .atomic)

        let relaunched = PendingCaptureQueue(directoryURL: directory)
        #expect(await relaunched.pendingCaptures().map(\.id) == [capture.id])
        #expect(await relaunched.recoveryIssue() == .partiallyRecovered(invalidEntryCount: 1))
    }

    @Test("Orphan payloads are reaped only when the manifest is valid")
    func orphanPayloadIsReaped() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "aperture-orphan-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = PendingCaptureQueue(directoryURL: directory)
        _ = try await queue.enqueue(
            data: Data([7]), folderID: FolderID("f1"),
            subjectPersonID: nil, originalName: "valid.jpg", source: .camera
        )
        let orphan = directory.appending(path: "capture-orphan.payload")
        try Data([8]).write(to: orphan, options: .atomic)

        _ = PendingCaptureQueue(directoryURL: directory)
        #expect(!FileManager.default.fileExists(atPath: orphan.path))
    }
}

@Suite("Metered capture transfer policy")
struct CaptureTransferPolicyTests {
    @Test("Only large transfers wait on expensive or constrained networks")
    func largeTransfersWait() {
        let policy = CaptureTransferPolicy(largeUploadThresholdBytes: 10)
        #expect(!policy.shouldDefer(
            sizeBytes: 10, waitsForWiFi: true,
            networkIsExpensive: true, networkIsConstrained: false
        ))
        #expect(policy.shouldDefer(
            sizeBytes: 11, waitsForWiFi: true,
            networkIsExpensive: true, networkIsConstrained: false
        ))
        #expect(policy.shouldDefer(
            sizeBytes: 11, waitsForWiFi: true,
            networkIsExpensive: false, networkIsConstrained: true
        ))
        #expect(!policy.shouldDefer(
            sizeBytes: 11, waitsForWiFi: false,
            networkIsExpensive: true, networkIsConstrained: true
        ))
        #expect(!policy.shouldDefer(
            sizeBytes: 11, waitsForWiFi: true,
            networkIsExpensive: false, networkIsConstrained: false
        ))
    }
}

@Suite("Capture privacy and integrity")
struct CapturePayloadProcessorTests {
    @Test("Image metadata is stripped before hashing and persistence")
    func imageMetadataIsStripped() throws {
        let input = try imageWithGPSMetadata()
        let inputSource = try #require(CGImageSourceCreateWithData(input as CFData, nil))
        let inputProperties = try #require(
            CGImageSourceCopyPropertiesAtIndex(inputSource, 0, nil) as? [CFString: Any]
        )
        #expect(inputProperties[kCGImagePropertyGPSDictionary] != nil)

        let prepared = try CapturePayloadProcessor.prepare(input)
        #expect(prepared.strippedImageMetadata)
        #expect(prepared.verifiedMIMEType == "image/jpeg")
        #expect(prepared.pageCount == 1)
        #expect(prepared.contentSHA256 == CapturePayloadProcessor.sha256(of: prepared.data))

        let outputSource = try #require(CGImageSourceCreateWithData(prepared.data as CFData, nil))
        let outputProperties = try #require(
            CGImageSourceCopyPropertiesAtIndex(outputSource, 0, nil) as? [CFString: Any]
        )
        #expect(outputProperties[kCGImagePropertyGPSDictionary] == nil)
        let outputEXIF = outputProperties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        #expect(outputEXIF?[kCGImagePropertyExifUserComment] == nil)
    }

    @Test("Out-of-range EXIF orientation falls back safely")
    func invalidEXIFOrientationFallsBack() throws {
        let input = try imageWithGPSMetadata(orientation: UInt32.max)
        let prepared = try CapturePayloadProcessor.prepare(input)
        #expect(prepared.pageCount == 1)
        #expect(prepared.strippedImageMetadata)
    }

    @Test("Unsupported and empty payloads fail closed")
    func invalidPayloadsFailClosed() {
        #expect(throws: CapturePayloadError.empty) {
            try CapturePayloadProcessor.prepare(Data())
        }
        #expect(throws: CapturePayloadError.unsupportedType) {
            try CapturePayloadProcessor.prepare(Data("not a document".utf8))
        }
    }

    @Test("SHA-256 uses lowercase canonical hexadecimal")
    func digestIsCanonical() {
        #expect(
            CapturePayloadProcessor.sha256(of: Data("abc".utf8))
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    @Test("Published mobile size and PDF page limits fail at the boundary")
    func publishedLimitsAreEnforced() throws {
        try CapturePayloadProcessor.validateByteCount(CapturePayloadProcessor.maximumBytes)
        #expect(throws: CapturePayloadError.tooLarge(maxBytes: 104_857_600)) {
            try CapturePayloadProcessor.validateByteCount(CapturePayloadProcessor.maximumBytes + 1)
        }
        try CapturePayloadProcessor.validatePDFPageCount(CapturePayloadProcessor.maximumPDFPages)
        #expect(throws: CapturePayloadError.tooManyPages(maxPages: 500)) {
            try CapturePayloadProcessor.validatePDFPageCount(
                CapturePayloadProcessor.maximumPDFPages + 1
            )
        }
    }

    private func imageWithGPSMetadata(orientation: UInt32 = 1) throws -> Data {
        let pixels: [UInt8] = [
            255, 255, 255, 255, 0, 0, 0, 255,
            0, 0, 0, 255, 255, 255, 255, 255
        ]
        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        let image = try #require(CGImage(
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ))
        let metadata: [CFString: Any] = [
            kCGImagePropertyOrientation: orientation,
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 41.8781,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 87.6298,
                kCGImagePropertyGPSLongitudeRef: "W"
            ],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifUserComment: "private source metadata"
            ]
        ]
        CGImageDestinationAddImage(destination, image, metadata as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }
}
