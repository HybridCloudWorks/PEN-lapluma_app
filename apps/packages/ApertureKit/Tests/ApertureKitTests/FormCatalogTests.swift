import Foundation
import Testing
import ApertureDomain
import ApertureAPI

@Suite("Versioned form catalog")
struct FormCatalogTests {
    @Test("Edition identity changes without mutating the form identity")
    func editionIdentityIsComposite() {
        let first = FormEditionID(
            authority: "USCIS",
            formID: "I-130",
            editionDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let replacement = FormEditionID(
            authority: "USCIS",
            formID: "I-130",
            editionDate: Date(timeIntervalSince1970: 1_800_000_000)
        )

        #expect(first.formID == replacement.formID)
        #expect(first != replacement)
        #expect(first.id != replacement.id)

        let anotherAuthority = FormEditionID(
            authority: "Example state agency",
            formID: "I-130",
            editionDate: first.editionDate
        )
        #expect(first != anotherAuthority)
        #expect(first.id != anotherAuthority.id)
    }

    @Test("Extracted schemas are pinned to one form edition")
    func schemaPinsEditionAndFieldManifest() throws {
        let edition = FormEditionID(
            authority: "USCIS",
            formID: "I-130",
            editionDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let schema = ExtractedFormSchema(
            edition: edition,
            schemaVersion: "field-map-1",
            fields: [ExtractedFieldManifest(
                fieldName: "Pt1Line1_FamilyName",
                label: "Family Name",
                valueType: .text,
                required: true,
                confidence: 0.98,
                bounds: FieldBounds(page: 1, x: 0.1, y: 0.2, width: 0.3, height: 0.04)
            )]
        )

        let decoded = try JSONDecoder().decode(
            ExtractedFormSchema.self,
            from: JSONEncoder().encode(schema)
        )
        #expect(decoded == schema)
        #expect(decoded.edition == edition)
        #expect(decoded.fields.first?.required == true)
    }

    @Test("Catalog taxonomy and activation are deterministic and non-personalized")
    func catalogTaxonomyAndActivation() async throws {
        let api = StubAPIClient()
        await api.setDelay(.zero)
        let catalog = try await api.catalogPackages(query: nil)

        #expect(catalog.isEmpty == false)
        #expect(catalog.map(\.packageCode) == catalog.map(\.packageCode).sorted())
        #expect(catalog.allSatisfy { $0.subcategory.categoryCode == $0.category.code })
        #expect(catalog.flatMap(\.forms).allSatisfy { form in
            guard let source = form.source else { return false }
            return source.sourcePageURL.host == source.officialDomain
        })
        #expect(catalog.flatMap(\.forms).allSatisfy { $0.edition.authority.isEmpty == false })
        #expect(catalog.first(where: { $0.packageCode == "FAMILY_I130" })?.activationState == .pilot)
        #expect(catalog.first(where: { $0.packageCode == "ADJUSTMENT_I485_I864" })?.activationState == .assisted)
        #expect(catalog.first(where: { $0.packageCode == "FINANCIAL_AID_FAFSA" })?.activationState == .unavailable)
    }

    @Test("Artifact kinds match the platform contract")
    func artifactKindsMatchContract() {
        #expect(Set(FormArtifactKind.allCases.map(\.rawValue)) == Set([
            "OFFICIAL_PDF", "EXTERNAL_WORKFLOW", "PROPRIETARY_FORM", "AUTHORED_TEMPLATE"
        ]))
    }

    @Test("Legacy edition identity decodes without an authority")
    func legacyEditionIdentityDecoding() throws {
        struct LegacyEdition: Encodable {
            let formID = "I-130"
            let editionDate = Date(timeIntervalSince1970: 1_700_000_000)
        }

        let decoded = try JSONDecoder().decode(
            FormEditionID.self,
            from: JSONEncoder().encode(LegacyEdition())
        )
        #expect(decoded.authority.isEmpty)
        #expect(decoded.formID == "I-130")
    }

    @Test("Category search has no case or person input")
    func categorySearch() async throws {
        let api = StubAPIClient()
        await api.setDelay(.zero)

        let education = try await api.catalogPackages(query: "Education")
        #expect(education.map(\.packageCode) == ["FINANCIAL_AID_FAFSA"])

        let passport = try await api.catalogPackages(query: "Passport")
        #expect(passport.map(\.packageCode) == ["PASSPORT_DS11"])
    }

    @Test("Legacy catalog JSON decodes to fail-closed defaults")
    func legacyCatalogDecoding() throws {
        struct LegacyPackage: Encodable {
            let packageCode = "LEGACY"
            let title = "Legacy form"
            let agency = "Example agency"
            let agencyCategoryLabel: String? = nil
            let forms = [LegacyForm()]
            let feeUSDCents: Int? = nil
            let feeCitationURL: URL? = nil
            let sourceURL = URL(string: "https://example.gov/form")!
            let lastVerified = Date(timeIntervalSince1970: 1_700_000_000)
        }
        struct LegacyForm: Encodable {
            let formNumber = "X-1"
            let title = "Legacy form"
            let editionDate = Date(timeIntervalSince1970: 1_700_000_000)
            let encoding = FormEncoding.acroForm
            let pageCount = 1
        }

        let decoded = try JSONDecoder().decode(
            FormPackage.self,
            from: JSONEncoder().encode(LegacyPackage())
        )
        #expect(decoded.category == .uncategorized)
        #expect(decoded.subcategory == .uncategorized)
        #expect(decoded.forms.first?.activationState == .catalogOnly)
        #expect(decoded.forms.first?.fillCapability == .automaticFill)
    }

    @Test("An in-memory empty package is unavailable")
    func emptyPackageIsUnavailable() {
        let package = FormPackage(
            packageCode: "EMPTY",
            title: "Malformed package",
            agency: "Example agency",
            agencyCategoryLabel: nil,
            forms: [],
            feeUSDCents: nil,
            feeCitationURL: nil,
            sourceURL: URL(string: "https://example.gov/form")!,
            lastVerified: Date(timeIntervalSince1970: 1_700_000_000)
        )

        #expect(package.activationState == .unavailable)
        #expect(package.supportsAutomaticFill == false)
    }

    @Test("An empty package fails decoding")
    func emptyPackageFailsDecoding() throws {
        let package = FormPackage(
            packageCode: "EMPTY",
            title: "Malformed package",
            agency: "Example agency",
            agencyCategoryLabel: nil,
            forms: [],
            feeUSDCents: nil,
            feeCitationURL: nil,
            sourceURL: URL(string: "https://example.gov/form")!,
            lastVerified: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let encoded = try JSONEncoder().encode(package)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(FormPackage.self, from: encoded)
        }
    }
}
