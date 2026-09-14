import Foundation
import Testing
import ApertureDomain
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

    private struct ModernContract: Decodable {
        let contractVersion: String
        let packageMappings: [LegacyPackageMapping]
    }

    @Test("Legacy package mappings resolve to versioned Collections and pinned Blueprints (INT-03, APP-01, APP-04)")
    func packageMappingsMatchCollections() async throws {
        let contractURL = try #require(repositoryFile("contracts/catalog-package-compatibility.json"))
        let contract = try JSONDecoder().decode(ModernContract.self, from: Data(contentsOf: contractURL))
        #expect(contract.packageMappings.count == 7)

        let api = StubAPIClient()
        await api.setDelay(.zero)
        let collections = try await api.libraryCollections(tenantID: nil)
        let blueprints = try await api.libraryBlueprints(tenantID: nil)

        #expect(collections.count == 7)
        #expect(blueprints.count == 9)

        for mapping in contract.packageMappings {
            let targetNamespace = mapping.collectionNamespace
            let targetCollectionId = mapping.collectionId
            let collection = collections.first { c in
                c.namespace == targetNamespace && c.collectionId == targetCollectionId
            }
            let resolved = try #require(collection)
            #expect(resolved.revision == mapping.pinnedRevision)
            #expect(resolved.members.count == mapping.blueprintMembers.count)
            #expect(resolved.members.count == mapping.formNumbers.count)

            for member in mapping.blueprintMembers {
                let memberNamespace = member.namespace
                let memberBlueprintId = member.blueprintId
                let blueprint = blueprints.first { b in
                    b.namespace == memberNamespace && b.blueprintId == memberBlueprintId
                }
                let bp = try #require(blueprint)
                #expect(bp.revision == member.pinnedRevision)
                #expect(bp.preparationMode == member.preparationMode)
            }
        }
    }

    @Test("Unsupported choices have explicit explanations and fail case creation safely (APP-04)")
    func unsupportedChoicesFailSafely() async throws {
        let api = StubAPIClient()
        await api.setDelay(.zero)
        let collections = try await api.libraryCollections(tenantID: nil)

        let passport = try #require(collections.first { $0.collectionId == "us-passport-ds11" })
        #expect(!passport.isSupported)
        #expect(passport.unsupportedReason != nil)
        #expect(!passport.allowsCaseCreation)

        let fafsa = try #require(collections.first { $0.collectionId == "federal-student-aid-fafsa" })
        #expect(!fafsa.isSupported)
        #expect(fafsa.unsupportedReason != nil)
        #expect(!fafsa.allowsCaseCreation)
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
