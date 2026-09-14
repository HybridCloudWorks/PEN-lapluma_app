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
    var collections: [DocumentCollection]?
    var blueprints: [DocumentBlueprint]?
    var packageMappings: [LegacyPackageMapping]?
    var guidance: [String: DocumentGuidance]?
    var tenantAssignments: [String: [String]]?
    var requirements: [String: RequirementSet] = [:]
    var reviewable: [CaseID: [ReviewableField]] = [:]
    /// Optional for backward-compatible decoding of persisted vertical-slice data
    /// written before the E-06 ledger was introduced.
    var valueHistory: [CaseID: [ValueHistoryEntry]]?
    var missingItems: [CaseID: [MissingItem]] = [:]
    var batches: [CaseID: [MissingItemBatch]] = [:]
    var sessions: [SessionID: InterviewSession] = [:]
    var packages: [CaseID: GeneratedPackage] = [:]
    /// Cached so Files and Print receive byte-identical copies of one generated
    /// package. Optional for persisted fixtures written before local PDF export.
    var packageArtifacts: [PackageID: PackageArtifact]?
    var inbox: [InboxItem] = []
    var consents: [ConsentRecord] = []
    /// Successful mutation responses keyed by endpoint and client idempotency key.
    /// Optional so fixtures written before retry replay was implemented still decode.
    var idempotencyRecords: [String: StubIdempotencyRecord]?
    /// Optional so fixture state persisted before Alpha 0.1 remains decodable.
    var marketingSafeCopy: Bool?
    /// Workforce vertical-slice state is optional so older persisted applicant
    /// fixtures remain decodable and are upgraded from current seed data.
    var assignments: [CaseID: CaseAssignments]?
    var sectionRevisions: [CaseID: [String: Int]]?
    var sectionValues: [CaseID: [String: [String: String]]]?
    var evidenceLinks: [CaseID: [String: [DocumentID]]]?
    var reviewDecisions: [CaseID: [ReviewDecision]]?
    var approvals: [CaseID: ApprovalRecord]?
    var history: [CaseID: [CaseHistoryEvent]]?
    var demoLastResetAt: Date?
    /// Finish Together state is optional so pre-feature fixture stores decode.
    var evidenceRelays: [EvidenceRelayID: EvidenceRelay]?
    var relaySecrets: [EvidenceRelayID: StubRelaySecret]?
    var relayGrants: [String: StubRelayGrant]?
    var relayUploadSessions: [String: StubRelayUploadSession]?
    var relayAttempts: [String: StubRelayAttempt]?

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
        let i131URL = URL(string: "https://www.uscis.gov/i-131")!
        let i131 = FormPackage(
            packageCode: "TRAVEL_I131",
            title: "Application for Travel Documents, Parole Documents, and Arrival/Departure Records",
            category: federal,
            subcategory: immigration,
            agency: "USCIS",
            agencyCategoryLabel: "Travel and parole documents",
            forms: [CatalogForm(
                formNumber: "I-131",
                title: "Application for Travel Documents, Parole Documents, and Arrival/Departure Records",
                editionDate: date(2025, 1, 20),
                encoding: .xfa,
                pageCount: 14,
                activationState: .catalogOnly,
                source: source(
                    "USCIS",
                    page: i131URL,
                    verified: now.addingTimeInterval(-7200)
                )
            )],
            // I-131 fees vary by application type and filing channel. A single
            // package-level amount would be misleading, so the official fee
            // schedule remains authoritative until category-aware fees exist.
            feeUSDCents: nil,
            feeCitationURL: URL(string: "https://www.uscis.gov/g-1055")!,
            sourceURL: i131URL,
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
        s.catalog = [i130, i485, n400, i765, i131, ds11, fafsa]

        // MARK: Document Library Collections & Blueprints (INT-03, APP-01, APP-04)
        let bpI130 = DocumentBlueprint(
            namespace: "uscis", blueprintId: "i-130", revision: 1,
            title: "Petition for Alien Relative", issuer: "USCIS",
            officialEditionDate: date(2025, 11, 4),
            preparationMode: .fillablePdf, artifactType: .officialPdf,
            sourceUrl: URL(string: "https://www.uscis.gov/i-130")!,
            publicationState: .published, isLatest: true, fieldCount: 218
        )
        let bpI130a = DocumentBlueprint(
            namespace: "uscis", blueprintId: "i-130a", revision: 1,
            title: "Supplemental Information for Spouse Beneficiary", issuer: "USCIS",
            officialEditionDate: date(2025, 11, 4),
            preparationMode: .fillablePdf, artifactType: .officialPdf,
            sourceUrl: URL(string: "https://www.uscis.gov/i-130a")!,
            publicationState: .published, isLatest: true, fieldCount: 42
        )
        let bpI485 = DocumentBlueprint(
            namespace: "uscis", blueprintId: "i-485", revision: 1,
            title: "Application to Register Permanent Residence or Adjust Status", issuer: "USCIS",
            officialEditionDate: date(2025, 10, 24),
            preparationMode: .fillablePdf, artifactType: .officialPdf,
            sourceUrl: URL(string: "https://www.uscis.gov/i-485")!,
            publicationState: .published, isLatest: true, fieldCount: 260
        )
        let bpI864 = DocumentBlueprint(
            namespace: "uscis", blueprintId: "i-864", revision: 1,
            title: "Affidavit of Support Under Section 213A of the INA", issuer: "USCIS",
            officialEditionDate: date(2025, 10, 17),
            preparationMode: .fillablePdf, artifactType: .officialPdf,
            sourceUrl: URL(string: "https://www.uscis.gov/i-864")!,
            publicationState: .published, isLatest: true, fieldCount: 110
        )
        let bpN400 = DocumentBlueprint(
            namespace: "uscis", blueprintId: "n-400", revision: 1,
            title: "Application for Naturalization", issuer: "USCIS",
            officialEditionDate: date(2025, 9, 17),
            preparationMode: .fillablePdf, artifactType: .officialPdf,
            sourceUrl: URL(string: "https://www.uscis.gov/n-400")!,
            publicationState: .published, isLatest: true, fieldCount: 195
        )
        let bpI765 = DocumentBlueprint(
            namespace: "uscis", blueprintId: "i-765", revision: 1,
            title: "Application for Employment Authorization", issuer: "USCIS",
            officialEditionDate: date(2025, 8, 20),
            preparationMode: .fillablePdf, artifactType: .officialPdf,
            sourceUrl: URL(string: "https://www.uscis.gov/i-765")!,
            publicationState: .published, isLatest: true, fieldCount: 85
        )
        let bpI131 = DocumentBlueprint(
            namespace: "uscis", blueprintId: "i-131", revision: 1,
            title: "Application for Travel Documents", issuer: "USCIS",
            officialEditionDate: date(2025, 6, 15),
            preparationMode: .staticAssisted, artifactType: .officialPdf,
            sourceUrl: URL(string: "https://www.uscis.gov/i-131")!,
            publicationState: .published, isLatest: true, fieldCount: 120
        )
        let bpDs11 = DocumentBlueprint(
            namespace: "dos", blueprintId: "ds-11", revision: 1,
            title: "Application for a U.S. Passport", issuer: "U.S. Department of State",
            officialEditionDate: date(2025, 1, 1),
            preparationMode: .fillablePdf, artifactType: .officialPdf,
            sourceUrl: ds11URL,
            publicationState: .published, isLatest: true, fieldCount: 45
        )
        let bpFafsa = DocumentBlueprint(
            namespace: "student-aid", blueprintId: "fafsa", revision: 1,
            title: "Free Application for Federal Student Aid", issuer: "Federal Student Aid",
            officialEditionDate: date(2026, 7, 1),
            preparationMode: .externalReference, artifactType: .flat,
            sourceUrl: fafsaURL,
            publicationState: .published, isLatest: true, fieldCount: 0
        )
        let bpAlphaIntake = DocumentBlueprint(
            namespace: "tenant_clinic_alpha", blueprintId: "intake", revision: 1,
            title: "Clinic Intake Questionnaire", issuer: "Alpha Legal Clinic",
            officialEditionDate: date(2026, 1, 1),
            preparationMode: .fillablePdf, artifactType: .authoredTemplate,
            publicationState: .published, isLatest: true, fieldCount: 12
        )
        let bpBetaRetainer = DocumentBlueprint(
            namespace: "tenant_firm_beta", blueprintId: "special_retainer", revision: 1,
            title: "Immigration Representation Retainer Agreement", issuer: "Beta Law Partners LLP",
            officialEditionDate: date(2026, 1, 1),
            preparationMode: .staticAssisted, artifactType: .flat,
            publicationState: .published, isLatest: true, fieldCount: 6
        )
        let baselineBlueprints = [bpI130, bpI130a, bpI485, bpI864, bpN400, bpI765, bpI131, bpDs11, bpFafsa, bpAlphaIntake, bpBetaRetainer]
        s.blueprints = loadManifestBlueprints(baseline: baselineBlueprints)
        s.guidance = loadGuidance()

        let colFamily = DocumentCollection(
            namespace: "official", collectionId: "family-reunification-i130", revision: 1,
            title: "Family Reunification (Form I-130 / I-130A)",
            descriptionText: "Petition for immediate family members and spouses with required supplemental biographical disclosures.",
            authority: "USCIS", publicationState: .published, isLatest: true,
            members: [
                CollectionBlueprintMember(namespace: "uscis", blueprintId: "i-130", pinnedRevision: 1, preparationMode: .fillablePdf, displayOrder: 1, isRequired: true),
                CollectionBlueprintMember(namespace: "uscis", blueprintId: "i-130a", pinnedRevision: 1, preparationMode: .fillablePdf, displayOrder: 2, isRequired: false)
            ],
            legacyPackageCode: "FAMILY_I130", isSupported: true, unsupportedReason: nil
        )
        let colAdjustment = DocumentCollection(
            namespace: "official", collectionId: "adjustment-of-status-i485", revision: 1,
            title: "Adjustment of Status (Form I-485 / I-864)",
            descriptionText: "Application for Lawful Permanent Resident status together with mandatory sponsor Affidavit of Support.",
            authority: "USCIS", publicationState: .published, isLatest: true,
            members: [
                CollectionBlueprintMember(namespace: "uscis", blueprintId: "i-485", pinnedRevision: 1, preparationMode: .fillablePdf, displayOrder: 1, isRequired: true),
                CollectionBlueprintMember(namespace: "uscis", blueprintId: "i-864", pinnedRevision: 1, preparationMode: .fillablePdf, displayOrder: 2, isRequired: true)
            ],
            legacyPackageCode: "ADJUSTMENT_I485_I864", isSupported: true, unsupportedReason: nil
        )
        let colNaturalization = DocumentCollection(
            namespace: "official", collectionId: "naturalization-n400", revision: 1,
            title: "Application for Naturalization (Form N-400)",
            descriptionText: "Application for U.S. citizenship by eligible permanent residents.",
            authority: "USCIS", publicationState: .published, isLatest: true,
            members: [
                CollectionBlueprintMember(namespace: "uscis", blueprintId: "n-400", pinnedRevision: 1, preparationMode: .fillablePdf, displayOrder: 1, isRequired: true)
            ],
            legacyPackageCode: "NATURALIZATION_N400", isSupported: true, unsupportedReason: nil
        )
        let colEad = DocumentCollection(
            namespace: "official", collectionId: "employment-authorization-i765", revision: 1,
            title: "Application for Employment Authorization (Form I-765)",
            descriptionText: "Application for work authorization document (EAD card).",
            authority: "USCIS", publicationState: .published, isLatest: true,
            members: [
                CollectionBlueprintMember(namespace: "uscis", blueprintId: "i-765", pinnedRevision: 1, preparationMode: .fillablePdf, displayOrder: 1, isRequired: true)
            ],
            legacyPackageCode: "EAD_I765", isSupported: true, unsupportedReason: nil
        )
        let colTravel = DocumentCollection(
            namespace: "official", collectionId: "travel-documents-i131", revision: 1,
            title: "Application for Travel Documents (Form I-131)",
            descriptionText: "Travel document applications including re-entry permits and advance parole.",
            authority: "USCIS", publicationState: .published, isLatest: true,
            members: [
                CollectionBlueprintMember(namespace: "uscis", blueprintId: "i-131", pinnedRevision: 1, preparationMode: .staticAssisted, displayOrder: 1, isRequired: true)
            ],
            legacyPackageCode: "TRAVEL_I131", isSupported: true, unsupportedReason: nil
        )
        let colPassport = DocumentCollection(
            namespace: "official", collectionId: "us-passport-ds11", revision: 1,
            title: "Application for a U.S. Passport (Form DS-11)",
            descriptionText: "State Department application for first-time U.S. passport applicants.",
            authority: "U.S. Department of State", publicationState: .published, isLatest: true,
            members: [
                CollectionBlueprintMember(namespace: "dos", blueprintId: "ds-11", pinnedRevision: 1, preparationMode: .fillablePdf, displayOrder: 1, isRequired: true)
            ],
            legacyPackageCode: "PASSPORT_DS11", isSupported: false,
            unsupportedReason: "Catalog preview only. Automatic preparation is currently enabled for USCIS immigration workflows."
        )
        let colFafsa = DocumentCollection(
            namespace: "official", collectionId: "federal-student-aid-fafsa", revision: 1,
            title: "Free Application for Federal Student Aid (FAFSA)",
            descriptionText: "Federal financial aid application for college and career school students.",
            authority: "Federal Student Aid", publicationState: .published, isLatest: true,
            members: [
                CollectionBlueprintMember(namespace: "student-aid", blueprintId: "fafsa", pinnedRevision: 1, preparationMode: .externalReference, displayOrder: 1, isRequired: true)
            ],
            legacyPackageCode: "FINANCIAL_AID_FAFSA", isSupported: false,
            unsupportedReason: "External workflow. FAFSA must be completed directly through the Federal Student Aid portal."
        )
        let colAlphaIntake = DocumentCollection(
            namespace: "tenant_clinic_alpha", collectionId: "clinic_intake_pkg", revision: 1,
            title: "Community Clinic Intake Package",
            descriptionText: "Alpha Clinic client onboarding intake questionnaire and biographical disclosure.",
            authority: "Alpha Legal Clinic", publicationState: .published, isLatest: true,
            members: [
                CollectionBlueprintMember(namespace: "tenant_clinic_alpha", blueprintId: "intake", pinnedRevision: 1, preparationMode: .fillablePdf, displayOrder: 1, isRequired: true)
            ],
            legacyPackageCode: "CLINIC_INTAKE", isSupported: true, unsupportedReason: nil
        )
        let colBetaRetainer = DocumentCollection(
            namespace: "tenant_firm_beta", collectionId: "firm_retainer_pkg", revision: 1,
            title: "Beta Law Retainer Package",
            descriptionText: "Beta Law Partners retainer agreement and standard legal representation terms.",
            authority: "Beta Law Partners LLP", publicationState: .published, isLatest: true,
            members: [
                CollectionBlueprintMember(namespace: "tenant_firm_beta", blueprintId: "special_retainer", pinnedRevision: 1, preparationMode: .staticAssisted, displayOrder: 1, isRequired: true)
            ],
            legacyPackageCode: "FIRM_RETAINER", isSupported: true, unsupportedReason: nil
        )
        s.collections = [colFamily, colAdjustment, colNaturalization, colEad, colTravel, colPassport, colFafsa, colAlphaIntake, colBetaRetainer]

        s.tenantAssignments = [
            "tenant_clinic_alpha": ["family-reunification-i130", "clinic_intake_pkg"],
            "tenant_firm_beta": ["family-reunification-i130", "firm_retainer_pkg"]
        ]

        s.packageMappings = [
            LegacyPackageMapping(
                packageCode: "FAMILY_I130", collectionNamespace: "official",
                collectionId: "family-reunification-i130", pinnedRevision: 1,
                displayName: "Family Reunification (Form I-130 / I-130A)", authority: "USCIS",
                formNumbers: ["I-130", "I-130A"],
                blueprintMembers: colFamily.members
            ),
            LegacyPackageMapping(
                packageCode: "ADJUSTMENT_I485_I864", collectionNamespace: "official",
                collectionId: "adjustment-of-status-i485", pinnedRevision: 1,
                displayName: "Adjustment of Status (Form I-485 / I-864)", authority: "USCIS",
                formNumbers: ["I-485", "I-864"],
                blueprintMembers: colAdjustment.members
            ),
            LegacyPackageMapping(
                packageCode: "NATURALIZATION_N400", collectionNamespace: "official",
                collectionId: "naturalization-n400", pinnedRevision: 1,
                displayName: "Application for Naturalization (Form N-400)", authority: "USCIS",
                formNumbers: ["N-400"],
                blueprintMembers: colNaturalization.members
            ),
            LegacyPackageMapping(
                packageCode: "EAD_I765", collectionNamespace: "official",
                collectionId: "employment-authorization-i765", pinnedRevision: 1,
                displayName: "Application for Employment Authorization (Form I-765)", authority: "USCIS",
                formNumbers: ["I-765"],
                blueprintMembers: colEad.members
            ),
            LegacyPackageMapping(
                packageCode: "TRAVEL_I131", collectionNamespace: "official",
                collectionId: "travel-documents-i131", pinnedRevision: 1,
                displayName: "Application for Travel Documents (Form I-131)", authority: "USCIS",
                formNumbers: ["I-131"],
                blueprintMembers: colTravel.members
            ),
            LegacyPackageMapping(
                packageCode: "PASSPORT_DS11", collectionNamespace: "official",
                collectionId: "us-passport-ds11", pinnedRevision: 1,
                displayName: "Application for a U.S. Passport (Form DS-11)", authority: "U.S. Department of State",
                formNumbers: ["DS-11"],
                blueprintMembers: colPassport.members
            ),
            LegacyPackageMapping(
                packageCode: "FINANCIAL_AID_FAFSA", collectionNamespace: "official",
                collectionId: "federal-student-aid-fafsa", pinnedRevision: 1,
                displayName: "Free Application for Federal Student Aid (FAFSA)", authority: "Federal Student Aid",
                formNumbers: ["FAFSA"],
                blueprintMembers: colFafsa.members
            )
        ]

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
            ),
            // No document mentions the birth city at all — the field the interview
            // exists to fill. No proposal: the only possible source is the human.
            ReviewableField(
                subjectPersonID: carlosID, canonicalPath: CanonicalPath("person.birth.city"),
                localizedLabel: "Ciudad de nacimiento", englishFormLabel: "City/Town/Village of Birth",
                formReference: "I-130 Part 2, Item 9",
                confirmed: nil,
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

        // itemCount matches both the seeded missing items and the scripted
        // interview questions — the advertised count is a promise the
        // questionnaire has to keep.
        let batch = MissingItemBatch(id: BatchID("mi_batch_017"), itemCount: 3,
                                     estimatedMinutes: 6, supportedModalities: [.chat, .voice, .form])
        s.batches[caseID] = [batch]
        s.missingItems[caseID] = [
            MissingItem(id: MissingItemID("mi_0141"), kind: .evidence, severity: .blocking,
                        assignedPersonID: mariaID, assignedPersonLabel: firstPersonLabel,
                        title: "Proof of your U.S. citizenship or permanent resident status",
                        whyRequired: "Form I-130 instructions require this from the petitioner.",
                        citation: statusCitation,
                        resolutionPaths: [
                            ResolutionPath(kind: .scan, label: "Take a photo of your green card", estimatedMinutes: 4),
                            ResolutionPath(kind: .importFile, label: "Choose a file you already have", estimatedMinutes: 3),
                            ResolutionPath(kind: .privateRelay, label: "Ask someone to send it", estimatedMinutes: 2),
                            ResolutionPath(kind: .cannotObtain, label: "I can't get this", estimatedMinutes: 5)
                        ],
                        batchID: nil, ageDays: 4,
                        requirementCode: "PROOF_OF_STATUS", minimumEstimatedMinutes: 2),
            MissingItem(id: MissingItemID("mi_0142"), kind: .field, severity: .blocking,
                        assignedPersonID: carlosID, assignedPersonLabel: secondPersonLabel,
                        title: "City or town where \(secondPersonName) was born",
                        whyRequired: "Form I-130 asks for the beneficiary's place of birth.",
                        citation: statusCitation,
                        resolutionPaths: [
                            ResolutionPath(kind: .answer, label: "Answer this question", estimatedMinutes: 2),
                            ResolutionPath(kind: .type, label: "Type it in", estimatedMinutes: 2)
                        ],
                        batchID: batch.id, ageDays: 4,
                        canonicalPath: CanonicalPath("person.birth.city"), minimumEstimatedMinutes: 2),
            MissingItem(id: MissingItemID("mi_0143"), kind: .evidence, severity: .advisory,
                        assignedPersonID: mariaID, assignedPersonLabel: firstPersonLabel,
                        title: "Photographs of you and \(secondPersonName) together",
                        whyRequired: "The instructions list this among the kinds of evidence you may submit.",
                        citation: statusCitation,
                        resolutionPaths: [
                            ResolutionPath(kind: .scan, label: "Add photos", estimatedMinutes: 4),
                            ResolutionPath(kind: .privateRelay, label: "Ask someone to send them", estimatedMinutes: 2)
                        ],
                        batchID: nil, ageDays: 2,
                        requirementCode: "RELATIONSHIP_PHOTOS", minimumEstimatedMinutes: 2)
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

    /// The same lazily-seeded baseline `ensureValueHistory` would materialise,
    /// computed without mutating stored state — reads must not write.
    func valueHistorySnapshot(for caseID: CaseID) -> [ValueHistoryEntry] {
        valueHistory?[caseID] ?? Self.initialHistoryEntries(for: reviewable[caseID] ?? [])
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
        reconcileMissingItems(caseID: caseID)
        bumpCounters(caseID: caseID, incrementsFilledCounter: incrementsFilledCounter)
    }

    mutating func reconcileMissingItems(caseID: CaseID) {
        let confirmedPaths = Set((reviewable[caseID] ?? []).compactMap { field in
            field.confirmed == nil ? nil : field.canonicalPath
        })
        let linkedRequirements = Set((evidenceLinks?[caseID] ?? [:]).compactMap { code, documents in
            documents.isEmpty ? nil : code
        })
        missingItems[caseID]?.removeAll { item in
            if let path = item.canonicalPath, confirmedPaths.contains(path) { return true }
            if let code = item.requirementCode, linkedRequirements.contains(code) { return true }
            return false
        }
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

    mutating func bumpCounters(
        caseID: CaseID,
        incrementsFilledCounter: Bool,
        incrementsDocumentsCounter: Bool = false
    ) {
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
            documentsCollected: min(
                existing.counters.documentsCollected + (incrementsDocumentsCounter ? 1 : 0),
                existing.counters.documentsRequired
            ),
            documentsRequired: existing.counters.documentsRequired,
            blockingItems: blocking,
            advisoryItems: (missingItems[caseID] ?? []).filter { $0.severity == .advisory }.count
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

    /// The finite question script for a batch. Every question targets a canonical
    /// path the case actually requires, so a saved answer is a real confirmation.
    private func questionScript(for session: InterviewSession) -> [InterviewQuestion] {
        let sample = marketingSafeCopy == true
        return [
            InterviewQuestion(
                id: "q_birth_city",
                canonicalPath: CanonicalPath("person.birth.city"),
                subjectPersonID: session.personID,
                prompt: sample
                    ? "¿En qué ciudad nació la persona de ejemplo?"
                    : "¿En qué ciudad nació Carlos?",
                englishFormLabel: "City/Town/Village of Birth",
                formReference: "I-130 Part 2, Item 9",
                inputKind: .text,
                maxLength: 40
            ),
            InterviewQuestion(
                id: "q_family_name",
                canonicalPath: CanonicalPath("person.name.family"),
                subjectPersonID: session.personID,
                prompt: sample
                    ? "¿Cuál es el apellido de la persona de ejemplo?"
                    : "¿Cuál es el apellido de Carlos?",
                englishFormLabel: "Family Name (Last Name)",
                formReference: "I-130 Part 2, Item 1.a",
                inputKind: .text,
                maxLength: 40
            ),
            InterviewQuestion(
                id: "q_last_entry_date",
                canonicalPath: CanonicalPath("person.entry.lastDate"),
                subjectPersonID: session.personID,
                prompt: sample
                    ? "¿En qué fecha entró la persona de ejemplo por última vez a los Estados Unidos?"
                    : "¿En qué fecha entró Carlos por última vez a los Estados Unidos?",
                englishFormLabel: "Date of Last Arrival",
                formReference: "I-130 Part 4, Item 46.a",
                inputKind: .text,
                maxLength: 20
            )
        ]
    }

    /// Advances through the script by counting the questions already asked in
    /// this session, so each answered turn produces the next question and the
    /// script ends instead of repeating forever. Guardrail-blocked replies carry
    /// no question and therefore do not advance the cursor.
    func nextQuestion(for session: InterviewSession) -> InterviewQuestion? {
        let script = questionScript(for: session)
        let asked = session.turns.filter { $0.role == .assistant && $0.question != nil }.count
        guard asked < script.count else { return nil }
        return script[asked]
    }

    func nextPrompt(for session: InterviewSession) -> String {
        nextQuestion(for: session)?.prompt ?? "Thanks — that's everything for now."
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        // Pinned to UTC so seeded edition dates — and the identifiers derived from
        // them — are identical on every machine and timezone.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar.date(from: components) ?? Date()
    }

    private static func findRepositoryFile(_ relativePath: String) -> URL? {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<10 {
            let candidate = directory.appending(path: relativePath)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            directory.deleteLastPathComponent()
        }
        return nil
    }

    private static func loadManifestBlueprints(baseline: [DocumentBlueprint]) -> [DocumentBlueprint] {
        var map: [String: DocumentBlueprint] = [:]
        for bp in baseline {
            map["\(bp.namespace)/\(bp.blueprintId)@r\(bp.revision)"] = bp
        }

        guard let url = findRepositoryFile("contracts/uscis-official-manifest.json"),
              let data = try? Data(contentsOf: url) else {
            return Array(map.values)
        }

        struct ManifestPayload: Decodable {
            struct FormPayload: Decodable {
                let formId: String
                let title: String
                let issuer: String
                let sourceUrl: String
                let editionDate: String?
                let preparationCapability: String
                let artifactType: String
            }
            struct PreservedPayload: Decodable {
                let documentId: String
                let title: String
                let issuer: String
                let namespace: String
                let preparationMode: String
                let sourceUrl: String
            }
            let forms: [FormPayload]
            let preservedNonUscisDefinitions: [PreservedPayload]?
        }

        guard let manifest = try? JSONDecoder().decode(ManifestPayload.self, from: data) else {
            return Array(map.values)
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM/dd/yy"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        for f in manifest.forms {
            let key = "uscis/\(f.formId.lowercased())@r1"
            if map[key] != nil {
                continue
            }

            let prepMode: PreparationMode
            switch f.preparationCapability {
            case "STATIC_ASSISTED": prepMode = .staticAssisted
            case "EXTERNAL_REFERENCE": prepMode = .externalReference
            default: prepMode = .fillablePdf
            }

            let artType: BlueprintArtifactType
            switch f.artifactType {
            case "XFA": artType = .xfa
            case "FLAT": artType = .flat
            case "EXTERNAL_LINK": artType = .externalLink
            case "AUTHORED_TEMPLATE": artType = .authoredTemplate
            default: artType = .officialPdf
            }

            var edDate: Date? = nil
            if let eds = f.editionDate {
                edDate = dateFormatter.date(from: eds)
            }

            map[key] = DocumentBlueprint(
                namespace: "uscis",
                blueprintId: f.formId.lowercased(),
                revision: 1,
                title: f.title,
                issuer: f.issuer,
                officialEditionDate: edDate,
                preparationMode: prepMode,
                artifactType: artType,
                sourceUrl: URL(string: f.sourceUrl),
                sourceSha256: nil,
                publicationState: .published,
                isLatest: true,
                fieldCount: prepMode == .externalReference ? 0 : 35
            )
        }

        if let preserved = manifest.preservedNonUscisDefinitions {
            for p in preserved {
                let key = "\(p.namespace)/\(p.documentId.lowercased())@r1"
                if map[key] != nil {
                    continue
                }

                let prepMode: PreparationMode
                switch p.preparationMode {
                case "FILLABLE_PDF": prepMode = .fillablePdf
                case "EXTERNAL_REFERENCE": prepMode = .externalReference
                default: prepMode = .staticAssisted
                }

                map[key] = DocumentBlueprint(
                    namespace: p.namespace,
                    blueprintId: p.documentId.lowercased(),
                    revision: 1,
                    title: p.title,
                    issuer: p.issuer,
                    officialEditionDate: nil,
                    preparationMode: prepMode,
                    artifactType: prepMode == .externalReference ? .externalLink : .authoredTemplate,
                    sourceUrl: URL(string: p.sourceUrl),
                    sourceSha256: nil,
                    publicationState: .published,
                    isLatest: true,
                    fieldCount: 20
                )
            }
        }

        return Array(map.values)
    }

    private static func loadGuidance() -> [String: DocumentGuidance] {
        var map: [String: DocumentGuidance] = [:]
        guard let url = findRepositoryFile("contracts/uscis-official-guidance.json"),
              let data = try? Data(contentsOf: url) else {
            return map
        }

        struct GuidanceDoc: Decodable {
            struct Entry: Decodable {
                let formId: String
                let formNumber: String
                let authority: String
                let officialInstructionsUrl: String?
                let feeScheduleCitationUrl: String?
                let feeUsdCents: Int?
                let feeNotes: String?
                let evidenceChecklist: [String]
                let institutionGuidanceNotes: String?
            }
            let guidance: [Entry]
        }

        guard let doc = try? JSONDecoder().decode(GuidanceDoc.self, from: data) else {
            return map
        }

        for g in doc.guidance {
            let item = DocumentGuidance(
                formId: g.formId,
                formNumber: g.formNumber,
                authority: g.authority,
                officialInstructionsUrl: g.officialInstructionsUrl.flatMap { URL(string: $0) },
                feeScheduleCitationUrl: g.feeScheduleCitationUrl.flatMap { URL(string: $0) },
                feeUsdCents: g.feeUsdCents,
                feeNotes: g.feeNotes,
                evidenceChecklist: g.evidenceChecklist,
                institutionGuidanceNotes: g.institutionGuidanceNotes
            )
            let lower = g.formId.lowercased()
            map[lower] = item
            map["\(g.authority.lowercased())/\(lower)"] = item
            map["uscis/\(lower)"] = item
            map["official/\(lower)"] = item
            map[lower.replacingOccurrences(of: "-", with: "")] = item
        }

        return map
    }
}

struct StubIdempotencyRecord: Codable {
    let request: Data
    let response: Data
}

struct StubUploadSession: Codable, Sendable {
    let documentID: DocumentID
    let expiresAt: Date
}
