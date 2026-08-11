import Foundation
import Testing
import ApertureAPI

@Suite("Mobile compatibility snapshot")
struct ContractCompatibilityTests {
    private struct Contract: Decodable {
        struct Package: Decodable {
            let packageCode: String
            let formNumbers: [String]
        }

        let contractVersion: String
        let packages: [Package]
    }

    @Test("Every shipped catalog package matches the compatibility snapshot")
    func catalogMatchesSnapshot() async throws {
        let contractURL = try #require(repositoryFile("contracts/catalog-package-compatibility.json"))
        let contract = try JSONDecoder().decode(Contract.self, from: Data(contentsOf: contractURL))
        let api = StubAPIClient()
        await api.setDelay(.zero)
        let catalog = try await api.catalogPackages(query: nil)

        let expected = Dictionary(uniqueKeysWithValues: contract.packages.map {
            ($0.packageCode, $0.formNumbers)
        })
        let actual = Dictionary(uniqueKeysWithValues: catalog.map {
            ($0.packageCode, $0.forms.map(\.formNumber))
        })

        #expect(contract.contractVersion == "lapluma-app-0.2")
        #expect(expected.count == 7)
        #expect(actual == expected)
    }

    private func repositoryFile(_ relativePath: String) -> URL? {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = directory.appending(path: relativePath)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            directory.deleteLastPathComponent()
        }
        return nil
    }
}
