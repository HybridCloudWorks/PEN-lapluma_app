import XCTest
@testable import ApertureDomain

final class AppleAppSiteAssociationTests: XCTestCase {

    func testAppleAppSiteAssociationJsonStructure() throws {
        let teamId = "9ABCDE1234"
        let bundleId = "app.aperture.mobile"
        let aasa = AppleAppSiteAssociation(teamId: teamId, bundleId: bundleId)

        let data = try aasa.toJsonData()
        let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(jsonObject)
        let webCredentials = jsonObject?["webcredentials"] as? [String: Any]
        XCTAssertNotNil(webCredentials)

        let apps = webCredentials?["apps"] as? [String]
        XCTAssertEqual(apps, ["\(teamId).\(bundleId)"])
    }

    func testAppleAppSiteAssociationRoundTripDecoding() throws {
        let original = AppleAppSiteAssociation(
            webcredentials: .init(apps: ["XYZ1234567.app.aperture.mobile", "XYZ1234567.app.aperture.enterprise"])
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppleAppSiteAssociation.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    func testAssociatedDomainEntitlementSyntax() {
        let configuredDomains = [
            "webcredentials:lp-gateway-dev-2pou78uy.uc.gateway.dev?mode=developer",
            "webcredentials:lapluma.ai"
        ]

        for domain in configuredDomains {
            XCTAssertTrue(domain.hasPrefix("webcredentials:"), "Domain '\(domain)' must begin with 'webcredentials:'")
            let stripped = domain.replacingOccurrences(of: "webcredentials:", with: "")
            XCTAssertFalse(stripped.isEmpty)
        }
    }
}
