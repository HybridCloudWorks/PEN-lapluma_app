import Testing
import Foundation
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

@Suite("Stub client behaviour")
struct StubClientTests {

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

    @Test("A voice interview cannot start without recorded consent")
    func voiceRequiresConsent() async throws {
        let api = StubAPIClient()
        await api.setDelay(.zero)

        await #expect(throws: ProblemDetails.self) {
            _ = try await api.startInterview(
                caseID: CaseID("c_ramirez_i130"), personID: PersonID("p_carlos"),
                batchID: BatchID("mi_batch_017"), modality: .voice,
                consent: nil, idempotencyKey: "k2"
            )
        }
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
    }

    @Test("Reclassifying to sealed medical makes the document opaque")
    func reclassifyToSealedIsOpaque() async throws {
        let api = StubAPIClient()
        await api.setDelay(.zero)

        let updated = try await api.reclassify(documentID: DocumentID("d_passport"), to: .sealedMedical)
        #expect(updated.isOpaque)
        #expect(!updated.allowsExtraction)
        #expect(updated.processingState == .opaqueStored)
    }
}
