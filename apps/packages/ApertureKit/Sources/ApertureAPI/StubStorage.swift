import Foundation
import ApertureDomain

/// Fixture data for the stub client.
///
/// The personas are the ones the design was written against — María Ramírez preparing
/// an I-130 for her husband Carlos — because a scaffold seeded with "John Smith" and
/// "Test Case 1" hides exactly the problems this product has to handle: names with
/// diacritics, two documents that disagree, and a value nobody has confirmed yet.
struct StubStorage: Codable {
    var folders: [Folder] = []
    var allCases: [CaseSummary] = []
    var documents: [CaseDocument] = []
    var pendingUploads: [DocumentID: CaseDocument] = [:]
    /// Optional so state written before upload sessions were correlated remains
    /// decodable. Legacy pending documents cannot be completed without a known
    /// session identifier and will fail closed.
    var uploadSessions: [String: StubUploadSession]?
    var catalog: [FormPackage] = []
    var requirements: [String: RequirementSet] = [:]
    var reviewable: [CaseID: [ReviewableField]] = [:]
    /// Optional for backward-compatible decoding of persisted vertical-slice data
    /// written before the E-06 ledger was introduced.
    var valueHistory: [CaseID: [ValueHistoryEntry]]?
    var missingItems: [CaseID: [MissingItem]] = [:]
    var batches: [CaseID: [MissingItemBatch]] = [:]
    var sessions: [SessionID: InterviewSession] = [:]
    var packages: [CaseID: GeneratedPackage] = [:]
    var inbox: [InboxItem] = []
    var consents: [ConsentRecord] = []
    /// Optional so fixture state persisted before Alpha 0.1 remains decodable.
    var marketingSafeCopy: Bool?

    static let mariaID = PersonID("p_maria")
    static let carlosID = PersonID("p_carlos")
    static let caseID = CaseID("c_ramirez_i130")
    static let folderID = FolderID("f_ramirez")

    static func seeded(profile: StubFixtureProfile = .realisticInternal) -> StubStorage {
        var s = StubStorage()
        let now = Date()
        let uscis = URL(string: "https://www.uscis.gov/i-130")!
        let isMarketingSafe = profile == .marketingSafe
        let mariaID = isMarketingSafe ? PersonID("p_sample_applicant") : Self.mariaID
        let carlosID = isMarketingSafe ? PersonID("p_sample_member") : Self.carlosID
        let caseID = isMarketingSafe ? CaseID("c_sample_active") : Self.caseID
        let folderID = isMarketingSafe ? FolderID("f_sample") : Self.folderID
        let currentUserID = isMarketingSafe ? UserID("u_sample") : UserID("u_stub_maria")
        let firstPersonLabel = isMarketingSafe ? "Sample applicant" : "María R."
        let secondPersonLabel = isMarketingSafe ? "Sample family member" : "Carlos R."
        let secondPersonName = isMarketingSafe ? "the sample family member" : "Carlos"
        let folderName = isMarketingSafe ? "Sample paperwork" : "Familia Ramírez"
        let identityDocumentName = isMarketingSafe ? "Sample identity document" : "Passport (Guatemala)"
        let sampleFamilyName = isMarketingSafe ? "Sample" : "Ramírez"
        let sampleBirthDate = isMarketingSafe ? "1980-01-01" : "1979-03-14"
        let sampleAlternativeBirthDate = isMarketingSafe ? "1980-01-02" : "1979-04-13"
        let samplePassportNumber = isMarketingSafe ? "SAMPLE123" : "AB1234567"
        let discrepancyBody = isMarketingSafe
            ? "The sample family member's date of birth differs between two documents."
            : "Carlos's date of birth differs between his passport and birth certificate."
        s.marketingSafeCopy = isMarketingSafe

        // MARK: People and folder

        let maria = Person(
            id: mariaID,
            displayLabel: firstPersonLabel,
            isMinor: false,
            participation: .active,
            holdsOwnCredential: true,
            relationships: [Relationship(kind: .petitionerFor, objectPersonID: carlosID)]
        )
        let carlos = Person(
            id: carlosID,
            displayLabel: secondPersonLabel,
            isMinor: false,
            participation: .active,
            holdsOwnCredential: true,
            relationships: [Relationship(kind: .beneficiaryOf, objectPersonID: mariaID)]
        )

        // MARK: Catalog

        let federal = CatalogCategory(code: "FEDERAL", title: "Federal forms", sortOrder: 10)
        let education = CatalogCategory(code: "EDUCATION", title: "Education", sortOrder: 20)
        let immigration = CatalogSubcategory(
            code: "IMMIGRATION", categoryCode: federal.code, title: "Immigration", sortOrder: 10
        )
        let passport = CatalogSubcategory(
            code: "PASSPORT", categoryCode: federal.code, title: "Passport", sortOrder: 20
        )
        let financialAid = CatalogSubcategory(
            code: "FINANCIAL_AID", categoryCode: education.code, title: "Financial aid", sortOrder: 10
        )
        func source(_ authority: String, page: URL, verified: Date) -> FormSourceMetadata {
            FormSourceMetadata(
                issuingAuthority: authority,
                sourcePageURL: page,
                artifactURL: nil,
                officialDomain: page.host ?? "",
                sha256: nil,
                lastVerified: verified
            )
        }

        let i130 = FormPackage(
            packageCode: "FAMILY_I130",
            title: "Petition for Alien Relative",
            category: federal,
            subcategory: immigration,
            agency: "USCIS",
            agencyCategoryLabel: "Family-based petitions",
            forms: [
                CatalogForm(formNumber: "I-130", title: "Petition for Alien Relative",
                            editionDate: date(2025, 11, 4), encoding: .acroForm, pageCount: 14,
                            activationState: .pilot,
                            source: source("USCIS", page: uscis, verified: now.addingTimeInterval(-3600))),
                CatalogForm(formNumber: "I-130A", title: "Supplemental Information for Spouse Beneficiary",
                            editionDate: date(2025, 11, 4), encoding: .acroForm, pageCount: 8,
                            activationState: .pilot,
                            source: source("USCIS", page: uscis, verified: now.addingTimeInterval(-3600)))
            ],
            feeUSDCents: 67_500,
            feeCitationURL: uscis,
            sourceURL: uscis,
            lastVerified: now.addingTimeInterval(-3600)
        )
        let n400 = FormPackage(
            packageCode: "NATURALIZATION_N400",
            title: "Application for Naturalization",
            category: federal,
            subcategory: immigration,
            agency: "USCIS",
            agencyCategoryLabel: "Citizenship",
            forms: [CatalogForm(formNumber: "N-400", title: "Application for Naturalization",
                                editionDate: date(2025, 9, 12), encoding: .acroForm, pageCount: 20,
                                activationState: .catalogOnly,
                                source: source("USCIS", page: URL(string: "https://www.uscis.gov/n-400")!,
                                               verified: now.addingTimeInterval(-7200)))],
            feeUSDCents: 76_000,
            feeCitationURL: URL(string: "https://www.uscis.gov/n-400")!,
            sourceURL: URL(string: "https://www.uscis.gov/n-400")!,
            lastVerified: now.addingTimeInterval(-7200)
        )
        let i765 = FormPackage(
            packageCode: "EAD_I765",
            title: "Application for Employment Authorization",
            category: federal,
            subcategory: immigration,
            agency: "USCIS",
            agencyCategoryLabel: "Employment authorization",
            forms: [CatalogForm(formNumber: "I-765", title: "Application for Employment Authorization",
                                editionDate: date(2025, 7, 30), encoding: .acroForm, pageCount: 7,
                                activationState: .unavailable,
                                source: source("USCIS", page: URL(string: "https://www.uscis.gov/i-765")!,
                                               verified: now.addingTimeInterval(-7200)))],
            feeUSDCents: 52_000,
            feeCitationURL: URL(string: "https://www.uscis.gov/i-765")!,
            sourceURL: URL(string: "https://www.uscis.gov/i-765")!,
            lastVerified: now.addingTimeInterval(-7200)
        )
        let i485 = FormPackage(
            packageCode: "ADJUSTMENT_I485_I864",
            title: "Adjustment of Status with Affidavit of Support",
            category: federal,
            subcategory: immigration,
            agency: "USCIS",
            agencyCategoryLabel: "Permanent residence",
            forms: [
                CatalogForm(formNumber: "I-485", title: "Application to Register Permanent Residence or Adjust Status",
                            editionDate: date(2025, 10, 24), encoding: .acroForm, pageCount: 20,
                            activationState: .assisted,
                            source: source("USCIS", page: URL(string: "https://www.uscis.gov/i-485")!,
                                           verified: now.addingTimeInterval(-7200))),
                CatalogForm(formNumber: "I-864", title: "Affidavit of Support Under Section 213A of the INA",
                            editionDate: date(2025, 10, 17), encoding: .acroForm, pageCount: 12,
                            activationState: .assisted,
                            source: source("USCIS", page: URL(string: "https://www.uscis.gov/i-864")!,
                                           verified: now.addingTimeInterval(-7200)))
            ],
            feeUSDCents: 144_000,
            feeCitationURL: URL(string: "https://www.uscis.gov/i-485")!,
            sourceURL: URL(string: "https://www.uscis.gov/i-485")!,
            lastVerified: now.addingTimeInterval(-7200)
        )
        let ds11URL = URL(string: "https://travel.state.gov/content/travel/en/passports/how-apply/forms.html")!
        let ds11 = FormPackage(
            packageCode: "PASSPORT_DS11",
            title: "U.S. Passport Application",
            category: federal,
            subcategory: passport,
            agency: "U.S. Department of State",
            agencyCategoryLabel: "Passport forms",
            forms: [CatalogForm(
                formNumber: "DS-11", title: "Application for a U.S. Passport",
                editionDate: date(2025, 1, 1), encoding: .acroForm, pageCount: 2,
                activationState: .catalogOnly,
                source: source("U.S. Department of State", page: ds11URL,
                               verified: now.addingTimeInterval(-7200))
            )],
            feeUSDCents: nil,
            feeCitationURL: nil,
            sourceURL: ds11URL,
            lastVerified: now.addingTimeInterval(-7200)
        )
        let fafsaURL = URL(string: "https://studentaid.gov/h/apply-for-aid/fafsa")!
        let fafsa = FormPackage(
            packageCode: "FINANCIAL_AID_FAFSA",
            title: "Free Application for Federal Student Aid",
            category: education,
            subcategory: financialAid,
            agency: "Federal Student Aid",
            agencyCategoryLabel: "Financial aid",
            forms: [CatalogForm(
                formNumber: "FAFSA", title: "Free Application for Federal Student Aid",
                editionDate: date(2026, 7, 1), encoding: .flat, pageCount: 0,
                artifactKind: .externalWorkflow,
                fillCapability: .referenceOnly,
                activationState: .unavailable,
                source: source("Federal Student Aid", page: fafsaURL,
                               verified: now.addingTimeInterval(-7200))
            )],
            feeUSDCents: nil,
            feeCitationURL: nil,
            sourceURL: fafsaURL,
            lastVerified: now.addingTimeInterval(-7200)
        )
        s.catalog = [i130, i485, n400, i765, ds11, fafsa]

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
        s.requirements["NATURALIZATION_N400"] = RequirementSet(
            packageCode: "NATURALIZATION_N400",
            fieldCount: 143,
            evidence: [
                EvidenceRequirement(
                    code: "PERMANENT_RESIDENT_CARD", personRole: "APPLICANT",
                    requirementDescription: "A copy of both sides of your Permanent Resident Card",
                    isConditional: false, conditionText: nil, citation: statusCitation)
            ]
        )
        s.requirements["EAD_I765"] = RequirementSet(
            packageCode: "EAD_I765",
            fieldCount: 87,
            evidence: [
                EvidenceRequirement(
                    code: "IDENTITY_DOCUMENT", personRole: "APPLICANT",
                    requirementDescription: "A copy of a government-issued identity document",
                    isConditional: false, conditionText: nil, citation: statusCitation)
            ]
        )
        s.requirements["ADJUSTMENT_I485_I864"] = RequirementSet(
            packageCode: "ADJUSTMENT_I485_I864",
            fieldCount: 391,
            evidence: [
                EvidenceRequirement(
                    code: "IDENTITY_AND_STATUS", personRole: "APPLICANT",
                    requirementDescription: "Identity and immigration-status documents listed in the form instructions",
                    isConditional: false, conditionText: nil, citation: statusCitation),
                EvidenceRequirement(
                    code: "FINANCIAL_EVIDENCE", personRole: "SPONSOR",
                    requirementDescription: "Financial evidence listed in the Form I-864 instructions",
                    isConditional: false, conditionText: nil, citation: statusCitation)
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
        let readyCaseID = isMarketingSafe ? CaseID("c_sample_ready") : CaseID("c_demo_ready")
        let readyCase = CaseSummary(
            id: readyCaseID, folderID: folderID,
            packageCode: "NATURALIZATION_N400", packageTitle: n400.title,
            state: .generated,
            counters: ProgressCounters(
                fieldsFilled: 143, fieldsRequired: 143,
                documentsCollected: 8, documentsRequired: 8,
                blockingItems: 0, advisoryItems: 0
            ),
            pinnedForms: n400.forms.map {
                PinnedForm(formNumber: $0.formNumber, editionDate: $0.editionDate,
                           sourceSHA256: "demo-verified", encoding: $0.encoding)
            }
        )
        s.allCases = [ramirezCase, readyCase]
        s.folders = [Folder(id: folderID, name: folderName, ownerUserID: currentUserID,
                            persons: [maria, carlos], documentCount: 7, cases: [ramirezCase, readyCase])]

        // A complete, verified package makes the mobile export journey reachable
        // without falsely treating the in-progress I-130 fixture as ready to file.
        s.packages[readyCaseID] = GeneratedPackage(
            id: PackageID("pkg_demo_ready"),
            caseID: readyCaseID,
            generatedAt: now.addingTimeInterval(-1_800),
            verification: VerificationReport(passed: true, fieldsVerified: 143, mismatches: 0),
            preparer: PreparerAttribution(
                organizationName: "Prepared with LaPluma",
                verificationStatus: "UNREPRESENTED",
                verificationType: nil
            ),
            outputs: [
                PDFOutput(id: "out_index", kind: .coverIndex, fillMode: .acroFormFilled,
                          formNumber: nil, editionDate: nil, pageCount: 2, sortOrder: 0),
                PDFOutput(id: "out_n400", kind: .filledForm, fillMode: .acroFormFilled,
                          formNumber: "N-400", editionDate: date(2025, 9, 12),
                          pageCount: 20, sortOrder: 1),
                PDFOutput(id: "out_checklist", kind: .checklist, fillMode: .acroFormFilled,
                          formNumber: nil, editionDate: nil, pageCount: 2, sortOrder: 2)
            ],
            filingChecklist: FilingChecklist(
                feeUSDCents: 76_000,
                filingAddress: "See the current USCIS Direct Filing Addresses page",
                wetInkSignaturePoints: [SignaturePoint(formNumber: "N-400", partLabel: "Part 14")],
                citation: statusCitation
            )
        )

        // MARK: Documents

        s.documents = [
            CaseDocument(id: DocumentID("d_passport"), folderID: folderID, subjectPersonID: carlosID,
                         originalName: identityDocumentName, verifiedMimeType: "image/jpeg",
                         sizeBytes: 3_841_204, documentClass: .identity, documentSubtype: "PASSPORT",
                         classificationBand: .likelyMatch,
                         processingState: .extracted, detectedLanguage: "es", uploadedAt: now.addingTimeInterval(-86_400)),
            CaseDocument(id: DocumentID("d_birthcert"), folderID: folderID, subjectPersonID: carlosID,
                         originalName: "Birth certificate", verifiedMimeType: "application/pdf",
                         sizeBytes: 1_204_880, documentClass: .civil, documentSubtype: "BIRTH_CERTIFICATE",
                         classificationBand: .needsReview,
                         processingState: .needsClassification, detectedLanguage: "es", uploadedAt: now.addingTimeInterval(-82_800)),
            CaseDocument(id: DocumentID("d_greencard"), folderID: folderID, subjectPersonID: mariaID,
                         originalName: "Permanent Resident Card", verifiedMimeType: "image/heic",
                         sizeBytes: 2_918_400, documentClass: .identity, documentSubtype: "GREEN_CARD",
                         classificationBand: .likelyMatch,
                         processingState: .extracted, detectedLanguage: "en", uploadedAt: now.addingTimeInterval(-79_200)),
            // A sealed medical exam. Stored, never opened, never previewed, never
            // sent to a model. The checklist records possession only.
            CaseDocument(id: DocumentID("d_sealed"), folderID: folderID, subjectPersonID: carlosID,
                         originalName: "I-693 sealed envelope", verifiedMimeType: "image/jpeg",
                         sizeBytes: 1_100_000, documentClass: .sealedMedical, documentSubtype: nil,
                         classificationBand: .likelyMatch,
                         processingState: .opaqueStored, detectedLanguage: nil,
                         uploadedAt: now.addingTimeInterval(-3_600), isOpaque: true)
        ]

        // MARK: Reviewable fields — including one real disagreement

        let passportAnchor = DocumentAnchor(
            documentID: DocumentID("d_passport"), documentName: identityDocumentName,
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
            documentID: DocumentID("d_passport"), documentName: identityDocumentName,
            pageNumber: 2,
            boundingPolygon: [.init(x: 0.11, y: 0.22), .init(x: 0.39, y: 0.22),
                              .init(x: 0.39, y: 0.26), .init(x: 0.11, y: 0.26)],
            engine: "azure-document-intelligence",
            engineVersion: "prebuilt-idDocument@2024-11-30",
            rawConfidence: 0.9812, checksumValid: nil, normalizationNote: nil
        )
        let ambiguousDateAnchor = DocumentAnchor(
            documentID: DocumentID("d_birthcert"), documentName: "Birth certificate",
            pageNumber: 1,
            boundingPolygon: [.init(x: 0.61, y: 0.52), .init(x: 0.78, y: 0.52),
                              .init(x: 0.78, y: 0.56), .init(x: 0.61, y: 0.56)],
            engine: "azure-document-intelligence",
            engineVersion: "custom-neural-birthcert@3",
            rawConfidence: 0.91, checksumValid: nil,
            normalizationNote: "Source text 03/04/2020 has two valid date interpretations."
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
                    proposedValue: sampleBirthDate, confidenceBand: .needsReview,
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
                    proposedValue: sampleFamilyName, confidenceBand: .extracted,
                    origin: .extraction, provenance: .document(nameAnchor),
                    extractedName: ExtractedName(original: sampleFamilyName, script: "Latn"),
                    createdAt: now.addingTimeInterval(-86_000))
            ),
            ReviewableField(
                subjectPersonID: carlosID, canonicalPath: CanonicalPath("person.entry.lastDate"),
                localizedLabel: "Fecha de última entrada", englishFormLabel: "Date of Last Arrival",
                formReference: "I-130 Part 4, Item 46.a",
                confirmed: nil,
                openProposal: ValueProposal(
                    id: ProposalID("vp_arrival_date"), caseID: caseID,
                    subjectPersonID: carlosID,
                    canonicalPath: CanonicalPath("person.entry.lastDate"),
                    proposedValue: "03/04/2020", confidenceBand: .needsReview,
                    origin: .extraction, provenance: .document(ambiguousDateAnchor),
                    extractionReviewReasons: [.ambiguousDate],
                    createdAt: now.addingTimeInterval(-81_000))
            ),
            // A checksum-validated passport number, agreed across sources.
            ReviewableField(
                subjectPersonID: carlosID, canonicalPath: CanonicalPath("person.document.passportNumber"),
                localizedLabel: "Número de pasaporte", englishFormLabel: "Passport Number",
                formReference: "I-130 Part 2, Item 22",
                confirmed: FieldValue(
                    caseID: caseID, subjectPersonID: carlosID,
                    canonicalPath: CanonicalPath("person.document.passportNumber"),
                    value: samplePassportNumber, confidenceBand: .verified, origin: .extraction,
                    provenance: .document(passportAnchor),
                    acceptedProposalID: ProposalID("vp_passport"),
                    confirmedBy: currentUserID, confirmedAt: now.addingTimeInterval(-70_000)),
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
                    value: sampleBirthDate, confidenceBand: .needsReview, origin: .extraction,
                    provenance: .document(passportAnchor),
                    confirmedBy: currentUserID, confirmedAt: now,
                    discrepancy: Discrepancy(
                        id: DiscrepancyID("disc_dob"), kind: .dateConflict, severity: .blocking,
                        description: "Two of your documents disagree about this date.",
                        alternativeValue: sampleAlternativeBirthDate, alternativeAnchor: birthCertAnchor)),
                openProposal: original.openProposal
            )
            s.reviewable[caseID] = fields
        }

        s.valueHistory = [caseID: Self.initialHistoryEntries(for: s.reviewable[caseID] ?? [])]

        // MARK: Missing items

        let batch = MissingItemBatch(id: BatchID("mi_batch_017"), itemCount: 5,
                                     estimatedMinutes: 6, supportedModalities: [.chat, .voice, .form])
        s.batches[caseID] = [batch]
        s.missingItems[caseID] = [
            MissingItem(id: MissingItemID("mi_0141"), kind: .evidence, severity: .blocking,
                        assignedPersonID: mariaID, assignedPersonLabel: firstPersonLabel,
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
                        assignedPersonID: carlosID, assignedPersonLabel: secondPersonLabel,
                        title: "City or town where \(secondPersonName) was born",
                        whyRequired: "Form I-130 asks for the beneficiary's place of birth.",
                        citation: statusCitation,
                        resolutionPaths: [
                            ResolutionPath(kind: .answer, label: "Answer this question"),
                            ResolutionPath(kind: .type, label: "Type it in")
                        ],
                        batchID: batch.id, ageDays: 4),
            MissingItem(id: MissingItemID("mi_0143"), kind: .evidence, severity: .advisory,
                        assignedPersonID: mariaID, assignedPersonLabel: firstPersonLabel,
                        title: "Photographs of you and \(secondPersonName) together",
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
                      body: discrepancyBody,
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

    mutating func ensureValueHistory(caseID: CaseID) {
        var history = valueHistory ?? [:]
        guard history[caseID] == nil else { return }
        history[caseID] = Self.initialHistoryEntries(for: reviewable[caseID] ?? [])
        valueHistory = history
    }

    mutating func applyConfirmation(
        caseID: CaseID,
        value: FieldValue,
        historyEntries: [ValueHistoryEntry]
    ) {
        ensureValueHistory(caseID: caseID)
        guard var fields = reviewable[caseID],
              let index = fields.firstIndex(where: {
                  $0.subjectPersonID == value.subjectPersonID && $0.canonicalPath == value.canonicalPath
              }) else { return }
        let original = fields[index]
        let incrementsFilledCounter = original.confirmed == nil
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
        var history = valueHistory ?? [:]
        history[caseID, default: []].append(contentsOf: historyEntries)
        valueHistory = history
        bumpCounters(caseID: caseID, incrementsFilledCounter: incrementsFilledCounter)
    }

    mutating func clearDiscrepancy(caseID: CaseID, discrepancyID: DiscrepancyID, chosen: String, by user: UserID) {
        ensureValueHistory(caseID: caseID)
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
        var history = valueHistory ?? [:]
        history[caseID, default: []].append(ValueHistoryEntry(
            caseID: caseID,
            subjectPersonID: existing.subjectPersonID,
            canonicalPath: existing.canonicalPath,
            action: .discrepancyResolved,
            value: chosen,
            previousValue: existing.value,
            provenance: .manualEntry(by: user, at: Date()),
            confidenceBand: .verified,
            actorUserID: user,
            recordedAt: Date()
        ))
        valueHistory = history
        bumpCounters(caseID: caseID, incrementsFilledCounter: false)
    }

    private static func initialHistoryEntries(for fields: [ReviewableField]) -> [ValueHistoryEntry] {
        fields.flatMap { field in
            var entries: [ValueHistoryEntry] = []
            if let confirmed = field.confirmed {
                entries.append(ValueHistoryEntry(
                    id: "seed-confirmed-\(field.id)",
                    caseID: confirmed.caseID,
                    subjectPersonID: confirmed.subjectPersonID,
                    canonicalPath: confirmed.canonicalPath,
                    action: .humanConfirmed,
                    value: confirmed.value,
                    provenance: confirmed.provenance,
                    confidenceBand: confirmed.confidenceBand,
                    actorUserID: confirmed.confirmedBy,
                    actorOnBehalfOf: confirmed.confirmedOnBehalfOf,
                    sourceProposalID: confirmed.acceptedProposalID,
                    recordedAt: confirmed.confirmedAt
                ))
            }
            if let proposal = field.openProposal {
                entries.append(ValueHistoryEntry(
                    id: "seed-proposal-\(proposal.id.rawValue)",
                    caseID: proposal.caseID,
                    subjectPersonID: proposal.subjectPersonID,
                    canonicalPath: proposal.canonicalPath,
                    action: .proposalRecorded,
                    value: proposal.proposedValue,
                    provenance: proposal.provenance,
                    confidenceBand: proposal.confidenceBand,
                    actorUserID: nil,
                    sourceProposalID: proposal.id,
                    recordedAt: proposal.createdAt
                ))
            }
            return entries
        }
    }

    private mutating func bumpCounters(caseID: CaseID, incrementsFilledCounter: Bool) {
        guard let index = allCases.firstIndex(where: { $0.id == caseID }) else { return }
        let existing = allCases[index]
        let blocking = (reviewable[caseID] ?? []).filter(\.isBlocked).count
            + (missingItems[caseID] ?? []).filter { $0.severity == .blocking }.count
        let counters = ProgressCounters(
            fieldsFilled: min(
                existing.counters.fieldsFilled + (incrementsFilledCounter ? 1 : 0),
                existing.counters.fieldsRequired
            ),
            fieldsRequired: existing.counters.fieldsRequired,
            documentsCollected: existing.counters.documentsCollected,
            documentsRequired: existing.counters.documentsRequired,
            blockingItems: blocking,
            advisoryItems: existing.counters.advisoryItems
        )
        let updated = CaseSummary(
            id: existing.id, folderID: existing.folderID, packageCode: existing.packageCode,
            packageTitle: existing.packageTitle, state: existing.state,
            counters: counters, pinnedForms: existing.pinnedForms
        )
        allCases[index] = updated
        if let folderIndex = folders.firstIndex(where: { $0.id == existing.folderID }) {
            let folder = folders[folderIndex]
            folders[folderIndex] = Folder(
                id: folder.id,
                name: folder.name,
                ownerUserID: folder.ownerUserID,
                persons: folder.persons,
                documentCount: folder.documentCount,
                cases: folder.cases.map { $0.id == caseID ? updated : $0 }
            )
        }
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
            prompt: marketingSafeCopy == true
                ? "¿En qué ciudad nació la persona de ejemplo?"
                : "¿En qué ciudad nació Carlos?",
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

struct StubUploadSession: Codable, Sendable {
    let documentID: DocumentID
    let expiresAt: Date
}
