import Foundation
import Testing
@testable import ApertureAPI

@Suite("Marketing fixture privacy")
struct MarketingFixtureTests {
    @Test("Marketing fixture contains no realistic internal persona values")
    func fixtureRejectsRealisticPersonaValues() throws {
        let fixture = StubStorage.seeded(profile: .marketingSafe)
        let data = try JSONEncoder().encode(fixture)
        let encoded = try #require(String(data: data, encoding: .utf8)).lowercased()

        for forbidden in [
            "maría", "maria", "carlos", "ramírez", "ramirez", "familia",
            "guatemala", "ab1234567", "u_stub_maria", "p_carlos", "c_ramirez"
        ] {
            #expect(!encoded.contains(forbidden), "Marketing fixture leaked: \(forbidden)")
        }

        #expect(encoded.contains("sample applicant"))
        #expect(encoded.contains("sample family member"))
        #expect(encoded.contains("sample paperwork"))
    }

    @Test("Marketing client cannot read or overwrite the internal fixture file")
    func fixtureIsNonPersistent() async throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "aperture-marketing-fixture-\(UUID().uuidString).json")
        let sentinel = Data("internal-fixture-sentinel".utf8)
        try sentinel.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let client = StubAPIClient(persistenceURL: url, fixtureProfile: .marketingSafe)
        await client.setDelay(.zero)
        let folders = try await client.folders()
        #expect(folders.first?.name == "Sample paperwork")

        _ = try await client.createFolder(name: "Another sample", idempotencyKey: "sample-create")
        #expect(try Data(contentsOf: url) == sentinel)
    }
}
