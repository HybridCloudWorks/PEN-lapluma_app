import Foundation
import ApertureDomain

/// Fixture data for the stub client.
///
/// The personas are the ones the design was written against — María Ramírez preparing
/// an I-130 for her husband Carlos — because a scaffold seeded with "John Smith" and
/// "Test Case 1" hides exactly the problems this product has to handle: names with
/// diacritics, two documents that disagree, and a value nobody has confirmed yet.
struct StubStorage {
    var folders: [Folder] = []
    var allCases: [CaseSummary] = []
    var documents: [CaseDocument] = []
    var pendingUploads: [DocumentID: CaseDocument] = [:]
    var catalog: [FormPackage] = []
    var requirements: [String: RequirementSet] = [:]
    var reviewable: [CaseID: [ReviewableField]] = [:]
    var missingItems: [CaseID: [MissingItem]] = [:]
    var batches: [CaseID: [MissingItemBatch]] = [:]
    var sessions: [SessionID: InterviewSession] = [:]
    var packages: [CaseID: GeneratedPackage] = [:]
    var inbox: [InboxItem] = []
    var consents: [ConsentRecord] = []

    static let mariaID = PersonID("p_maria")
    static let carlosID = PersonID("p_carlos")
    static let caseID = CaseID("c_ramirez_i130")
    static let folderID = FolderID("f_ramirez")

    static func seeded() -> StubStorage {
        var s = StubStorage()
        let now = Date()
        let uscis = URL(string: "https://www.uscis.gov/i-130")!

        // MARK: People and folder

        let maria = Person(
            id: mariaID,
            displayLabel: "María R.",
            isMinor: false,
            participation: .active,
            holdsOwnCredential: true,
            relationships: [Relationship(kind: .petitionerFor, objectPersonID: carlosID)]
        )
        let carlos = Person(
            id: carlosID,
            displayLabel: "Carlos R.",
            isMinor: false,
            participation: .active,
            holdsOwnCredential: true,
            relationships: [Relationship(kind: .beneficiaryOf, objectPersonID: mariaID)]
        )

        // MARK: Catalog

        let i130 = FormPackage(
            packageCode: "FAMILY_I130",
            title: "Petition for Alien Relative",
            agency: "USCIS",
            agencyCategoryLabel: "Family-based petitions",
            forms: [
                CatalogForm(formNumber: "I-130", title: "Petition for Alien Relative",
                            editionDate: date(2025, 11, 4), encoding: .acroForm, pageCount: 14),
                CatalogForm(formNumber: "I-130A", title: "Supplemental Information for Spouse Beneficiary",
                            editionDate: date(2025, 11, 4), encoding: .acroForm, pageCount: 8)
            ],
            feeUSDCents: 67_500,
            feeCitationURL: uscis,
            sourceURL: uscis,
            lastVerified: now.addingTimeInterval(-3600)
        )
        let n400 = FormPackage(
            packageCode: "NATURALIZATION_N400",
            title: "Application for Naturalization",
            agency: "USCIS",
            agencyCategoryLabel: "Citizenship",
            forms: [CatalogForm(formNumber: "N-400", title: "Application for Naturalization",
                                editionDate: date(2025, 9, 12), encoding: .acroForm, pageCount: 20)],
            feeUSDCents: 76_000,
            feeCitationURL: URL(string: "https://www.uscis.gov/n-400")!,
            sourceURL: URL(string: "https://www.uscis.gov/n-400")!,
            lastVerified: now.addingTimeInterval(-7200)
        )
        let i765 = FormPackage(
            packageCode: "EAD_I765",
            title: "Application for Employment Authorization",
            agency: "USCIS",
            agencyCategoryLabel: "Employment authorization",
            forms: [CatalogForm(formNumber: "I-765", title: "Application for Employment Authorization",
                                editionDate: date(2025, 7, 30), encoding: .acroForm, pageCount: 7)],
            feeUSDCents: 52_000,
            feeCitationURL: URL(string: "https://www.uscis.gov/i-765")!,
            sourceURL: URL(string: "https://www.uscis.gov/i-765")!,
            lastVerified: now.addingTimeInterval(-7200)
        )
        s.catalog = [i130, n400, i765]

        let statusCitation = Citation(
            sourceURL: uscis,
            documentTitle: "Instructions for Form I-130",
            sectionRef: "What Evidence Must You Submit",
            revisionDate: date(2025, 11, 4),
            quotedText: "Evidence of your U.S. citizenship or lawful permanent resident status."
        )
        let priorMarriageCitation = Citation(
            sourceURL: uscis,
            documentTitle: "Instructions for Form I-130",
            sectionRef: "What Evidence Must You Submit",
            revisionDate: date(2025, 11, 4),
            quotedText: "If you or your spouse were previously married, submit copies of documents showing that all prior marriages were legally terminated."
        )

        s.requirements["FAMILY_I130"] = RequirementSet(
            packageCode: "FAMILY_I130",
            fieldCount: 218,
            evidence: [
                EvidenceRequirement(
                    code: "PROOF_OF_STATUS", personRole: "PETITIONER",
                    requirementDescription: "Evidence of your U.S. citizenship or lawful permanent resident status",
                    isConditional: false, conditionText: nil, citation: statusCitation),
                EvidenceRequirement(
                    code: "MARRIAGE_CERTIFICATE", personRole: "BOTH",
                    requirementDescription: "A copy of your marriage certificate",
                    isConditional: false, conditionText: nil, citation: statusCitation),
                EvidenceRequirement(
                    code: "PRIOR_MARRIAGE_TERMINATION", personRole: "BOTH",
                    requirementDescription: "Documents terminating any prior marriage",
                    isConditional: true,
                    conditionText: "If you or your spouse were previously married, submit copies of documents showing that all prior marriages were legally terminated.",
                    citation: priorMarriageCitation)
            ]
        )

        // MARK: The case

        let counters = ProgressCounters(
            fieldsFilled: 174, fieldsRequired: 218,
            documentsCollected: 7, documentsRequired: 11,
            blockingItems: 6, advisoryItems: 3
        )
        let ramirezCase = CaseSummary(
            id: caseID, folderID: folderID,
            packageCode: "FAMILY_I130", packageTitle: i130.title,
            state: .collecting, counters: counters,
            pinnedForms: i130.forms.map {
                PinnedForm(formNumber: $0.formNumber, editionDate: $0.editionDate,
                           sourceSHA256: "9f2c…", encoding: $0.encoding)
            }
        )
        s.allCases = [ramirezCase]
        s.folders = [Folder(id: folderID, name: "Familia Ramírez", ownerUserID: UserID("u_stub_maria"),
                            persons: [maria, carlos], documentCount: 7, cases: [ramirezCase])]

        // MARK: Documents

        s.documents = [
            CaseDocument(id: DocumentID("d_passport"), folderID: folderID, subjectPersonID: carlosID,
                         originalName: "Passport (Guatemala)", verifiedMimeType: "image/jpeg",
                         sizeBytes: 3_841_204, documentClass: .identity, documentSubtype: "PASSPORT",
                         processingState: .extracted, detectedLanguage: "es", uploadedAt: now.addingTimeInterval(-86_400)),
            CaseDocument(id: DocumentID("d_birthcert"), folderID: folderID, subjectPersonID: carlosID,
                         originalName: "Birth certificate", verifiedMimeType: "application/pdf",
                         sizeBytes: 1_204_880, documentClass: .civil, documentSubtype: "BIRTH_CERTIFICATE",
                         processingState: .extracted, detectedLanguage: "es", uploadedAt: now.addingTimeInterval(-82_800)),
            CaseDocument(id: DocumentID("d_greencard"), folderID: folderID, subjectPersonID: mariaID,
                         originalName: "Permanent Resident Card", verifiedMimeType: "image/heic",
                         sizeBytes: 2_918_400, documentClass: .identity, documentSubtype: "GREEN_CARD",
                         processingState: .extracted, detectedLanguage: "en", uploadedAt: now.addingTimeInterval(-79_200)),
            // A sealed medical exam. Stored, never opened, never previewed, never
            // sent to a model. The checklist records possession only.
            CaseDocument(id: DocumentID("d_sealed"), folderID: folderID, subjectPersonID: carlosID,
                         originalName: "I-693 sealed envelope", verifiedMimeType: "image/jpeg",
                         sizeBytes: 1_100_000, documentClass: .sealedMedical, documentSubtype: nil,
                         processingState: .opaqueStored, detectedLanguage: nil,
                         uploadedAt: now.addingTimeInterval(-3_600), isOpaque: true)
        ]

        // MARK: Reviewable fields — including one real disagreement

        let passportAnchor = DocumentAnchor(
            documentID: DocumentID("d_passport"), documentName: "Passport (Guatemala)",
            pageNumber: 2,
            boundingPolygon: [.init(x: 0.14, y: 0.31), .init(x: 0.48, y: 0.31),
                              .init(x: 0.48, y: 0.35), .init(x: 0.14, y: 0.35)],
            engine: "azure-document-intelligence",
            engineVersion: "prebuilt-idDocument@2024-11-30",
            rawConfidence: 0.9412, checksumValid: true,
            normalizationNote: "Source format DD/MM/YYYY; normalized to ISO-8601."
        )
        let birthCertAnchor = DocumentAnchor(
            documentID: DocumentID("d_birthcert"), documentName: "Birth certificate",
            pageNumber: 1,
            boundingPolygon: [.init(x: 0.20, y: 0.44), .init(x: 0.55, y: 0.44),
                              .init(x: 0.55, y: 0.48), .init(x: 0.20, y: 0.48)],
            engine: "azure-document-intelligence",
            engineVersion: "custom-neural-birthcert@3",
            rawConfidence: 0.8871, checksumValid: nil, normalizationNote: nil
        )
        let nameAnchor = DocumentAnchor(
            documentID: DocumentID("d_passport"), documentName: "Passport (Guatemala)",
            pageNumber: 2,
            boundingPolygon: [.init(x: 0.11, y: 0.22), .init(x: 0.39, y: 0.22),
                              .init(x: 0.39, y: 0.26), .init(x: 0.11, y: 0.26)],
            engine: "azure-document-intelligence",
            engineVersion: "prebuilt-idDocument@2024-11-30",
            rawConfidence: 0.9812, checksumValid: nil, normalizationNote: nil
        )

        s.reviewable[caseID] = [
            // Two documents disagree about a date of birth. The system records both and
            // asks — it never picks a winner.
            ReviewableField(
                subjectPersonID: carlosID, canonicalPath: CanonicalPath("person.birth.date"),
                localizedLabel: "Fecha de nacimiento", englishFormLabel: "Date of Birth",
                formReference: "I-130 Part 2, Item 8",
                confirmed: nil,
                openProposal: ValueProposal(
                    id: ProposalID("vp_dob"), caseID: caseID, subjectPersonID: carlosID,
                    canonicalPath: CanonicalPath("person.birth.date"),
                    proposedValue: "1979-03-14", confidenceBand: .needsReview,
                    origin: .extraction, provenance: .document(passportAnchor),
                    createdAt: now.addingTimeInterval(-86_000))
            ),
            ReviewableField(
                subjectPersonID: carlosID, canonicalPath: CanonicalPath("person.name.family"),
                localizedLabel: "Apellido", englishFormLabel: "Family Name (Last Name)",
                formReference: "I-130 Part 2, Item 1.a",
                confirmed: nil,
                openProposal: ValueProposal(
                    id: ProposalID("vp_family"), caseID: caseID, subjectPersonID: carlosID,
                    canonicalPath: CanonicalPath("person.name.family"),
                    proposedValue: "Ramírez", confidenceBand: .extracted,
                    origin: .extraction, provenance: .document(nameAnchor),
                    createdAt: now.addingTimeInterval(-86_000))
            ),
            // A checksum-validated passport number, agreed across sources.
            ReviewableField(
                subjectPersonID: carlosID, canonicalPath: CanonicalPath("person.document.passportNumber"),
                localizedLabel: "Número de pasaporte", englishFormLabel: "Passport Number",
                formReference: "I-130 Part 2, Item 22",
                confirmed: FieldValue(
                    caseID: caseID, subjectPersonID: carlosID,
                    canonicalPath: CanonicalPath("person.document.passportNumber"),
                    value: "AB1234567", confidenceBand: .verified, origin: .extraction,
                    provenance: .document(passportAnchor),
                    acceptedProposalID: ProposalID("vp_passport"),
                    confirmedBy: UserID("u_stub_maria"), confirmedAt: now.addingTimeInterval(-70_000)),
                openProposal: nil
            )
        ]

        // Attach the disagreement to the date-of-birth row.
        if var fields = s.reviewable[caseID], let index = fields.firstIndex(where: {
            $0.canonicalPath == CanonicalPath("person.birth.date")
        }) {
            let original = fields[index]
            fields[index] = ReviewableField(
                subjectPersonID: original.subjectPersonID,
                canonicalPath: original.canonicalPath,
                localizedLabel: original.localizedLabel,
                englishFormLabel: original.englishFormLabel,
                formReference: original.formReference,
                confirmed: FieldValue(
                    caseID: caseID, subjectPersonID: carlosID,
                    canonicalPath: CanonicalPath("person.birth.date"),
                    value: "1979-03-14", confidenceBand: .needsReview, origin: .extraction,
                    provenance: .document(passportAnchor),
                    confirmedBy: UserID("u_stub_maria"), confirmedAt: now,
                    discrepancy: Discrepancy(
                        id: DiscrepancyID("disc_dob"), kind: .dateConflict, severity: .blocking,
                        description: "Two of your documents disagree about this date.",
                        alternativeValue: "1979-04-13", alternativeAnchor: birthCertAnchor)),
                openProposal: original.openProposal
            )
            s.reviewable[caseID] = fields
        }

        // MARK: Missing items

        let batch = MissingItemBatch(id: BatchID("mi_batch_017"), itemCount: 5,
                                     estimatedMinutes: 6, supportedModalities: [.chat, .voice, .form])
        s.batches[caseID] = [batch]
        s.missingItems[caseID] = [
            MissingItem(id: MissingItemID("mi_0141"), kind: .evidence, severity: .blocking,
                        assignedPersonID: mariaID, assignedPersonLabel: "María R.",
                        title: "Proof of your U.S. citizenship or permanent resident status",
                        whyRequired: "Form I-130 instructions require this from the petitioner.",
                        citation: statusCitation,
                        resolutionPaths: [
                            ResolutionPath(kind: .scan, label: "Take a photo of your green card"),
                            ResolutionPath(kind: .importFile, label: "Choose a file you already have"),
                            ResolutionPath(kind: .cannotObtain, label: "I can't get this")
                        ],
                        batchID: nil, ageDays: 4),
            MissingItem(id: MissingItemID("mi_0142"), kind: .field, severity: .blocking,
                        assignedPersonID: carlosID, assignedPersonLabel: "Carlos R.",
                        title: "City or town where Carlos was born",
                        whyRequired: "Form I-130 asks for the beneficiary's place of birth.",
                        citation: statusCitation,
                        resolutionPaths: [
                            ResolutionPath(kind: .answer, label: "Answer this question"),
                            ResolutionPath(kind: .type, label: "Type it in")
                        ],
                        batchID: batch.id, ageDays: 4),
            MissingItem(id: MissingItemID("mi_0143"), kind: .evidence, severity: .advisory,
                        assignedPersonID: mariaID, assignedPersonLabel: "María R.",
                        title: "Photographs of you and Carlos together",
                        whyRequired: "The instructions list this among the kinds of evidence you may submit.",
                        citation: statusCitation,
                        resolutionPaths: [ResolutionPath(kind: .scan, label: "Add photos")],
                        batchID: nil, ageDays: 2)
        ]

        // MARK: Inbox

        s.inbox = [
            InboxItem(id: NotificationID("n_1"), category: .actionRequired,
                      title: "2 documents still needed",
                      body: "Proof of status and a birth certificate.",
                      deepLink: URL(string: "aperture://cases/\(caseID)/missing-items"),
                      createdAt: now.addingTimeInterval(-7_200)),
            InboxItem(id: NotificationID("n_2"), category: .discrepancyFound,
                      title: "Two documents disagree",
                      body: "Carlos's date of birth differs between his passport and birth certificate.",
                      deepLink: URL(string: "aperture://cases/\(caseID)/review"),
                      createdAt: now.addingTimeInterval(-10_800))
        ]

        // MARK: Consent — analytics defaults to off

        s.consents = [
            ConsentRecord(purpose: .serviceTerms, granted: true, noticeVersion: "2026.03", grantedAt: now),
            ConsentRecord(purpose: .aiProcessing, granted: true, noticeVersion: "2026.03", grantedAt: now),
            ConsentRecord(purpose: .voiceRecording, granted: false, noticeVersion: "2026.03", grantedAt: nil),
            ConsentRecord(purpose: .voiceClipRetention, granted: false, noticeVersion: "2026.03", grantedAt: nil),
            ConsentRecord(purpose: .analytics, granted: false, noticeVersion: "2026.03", grantedAt: nil)
        ]

        return s
    }

    // MARK: Mutation helpers

    mutating func applyConfirmation(caseID: CaseID, value: FieldValue) {
        guard var fields = reviewable[caseID],
              let index = fields.firstIndex(where: {
                  $0.subjectPersonID == value.subjectPersonID && $0.canonicalPath == value.canonicalPath
              }) else { return }
        let original = fields[index]
        fields[index] = ReviewableField(
            subjectPersonID: original.subjectPersonID,
            canonicalPath: original.canonicalPath,
            localizedLabel: original.localizedLabel,
            englishFormLabel: original.englishFormLabel,
            formReference: original.formReference,
            confirmed: value,
            openProposal: nil
        )
        reviewable[caseID] = fields
        bumpCounters(caseID: caseID)
    }

    mutating func clearDiscrepancy(caseID: CaseID, discrepancyID: DiscrepancyID, chosen: String, by user: UserID) {
        guard var fields = reviewable[caseID],
              let index = fields.firstIndex(where: { $0.confirmed?.discrepancy?.id == discrepancyID }),
              let existing = fields[index].confirmed else { return }
        let original = fields[index]
        fields[index] = ReviewableField(
            subjectPersonID: original.subjectPersonID,
            canonicalPath: original.canonicalPath,
            localizedLabel: original.localizedLabel,
            englishFormLabel: original.englishFormLabel,
            formReference: original.formReference,
            confirmed: FieldValue(
                caseID: existing.caseID, subjectPersonID: existing.subjectPersonID,
                canonicalPath: existing.canonicalPath, value: chosen,
                confidenceBand: .verified, origin: .manual,
                provenance: .manualEntry(by: user, at: Date()),
                confirmedBy: user, confirmedAt: Date(), discrepancy: nil),
            openProposal: nil
        )
        reviewable[caseID] = fields
        bumpCounters(caseID: caseID)
    }

    private mutating func bumpCounters(caseID: CaseID) {
        guard let index = allCases.firstIndex(where: { $0.id == caseID }) else { return }
        let existing = allCases[index]
        let blocking = (reviewable[caseID] ?? []).filter(\.isBlocked).count
            + (missingItems[caseID] ?? []).filter { $0.severity == .blocking }.count
        let counters = ProgressCounters(
            fieldsFilled: min(existing.counters.fieldsFilled + 1, existing.counters.fieldsRequired),
            fieldsRequired: existing.counters.fieldsRequired,
            documentsCollected: existing.counters.documentsCollected,
            documentsRequired: existing.counters.documentsRequired,
            blockingItems: blocking,
            advisoryItems: existing.counters.advisoryItems
        )
        allCases[index] = CaseSummary(
            id: existing.id, folderID: existing.folderID, packageCode: existing.packageCode,
            packageTitle: existing.packageTitle, state: existing.state,
            counters: counters, pinnedForms: existing.pinnedForms
        )
    }

    // MARK: Interview scripting

    func openingTurns(for personID: PersonID) -> [InterviewTurn] {
        [InterviewTurn(
            id: UUID().uuidString, role: .assistant,
            text: "I'll ask you a few short questions to fill in what's missing. I'm not a lawyer, and I can't tell you what will happen with your application.",
            isDeterministic: true, timestamp: Date())]
    }

    func nextQuestion(for session: InterviewSession) -> InterviewQuestion? {
        InterviewQuestion(
            id: "q_birth_city",
            canonicalPath: CanonicalPath("person.birth.city"),
            subjectPersonID: session.personID,
            prompt: "¿En qué ciudad nació Carlos?",
            englishFormLabel: "City/Town/Village of Birth",
            formReference: "I-130 Part 2, Item 9",
            inputKind: .text,
            maxLength: 40
        )
    }

    func nextPrompt(for session: InterviewSession) -> String {
        nextQuestion(for: session)?.prompt ?? "Thanks — that's everything for now."
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        return Calendar(identifier: .gregorian).date(from: components) ?? Date()
    }
}
