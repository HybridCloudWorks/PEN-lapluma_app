import XCTest
@testable import ApertureDomain

final class ApertureEnvironmentTests: XCTestCase {

    func testDevelopmentEnvironmentPointsToUnifiedGoogleApiGateway() {
        let env = ApertureEnvironment.development
        let expectedGatewayUrl = "https://lp-gateway-dev-2pou78uy.uc.gateway.dev"

        XCTAssertEqual(env.coreApiBaseUrl, expectedGatewayUrl)
        XCTAssertEqual(env.workflowApiBaseUrl, expectedGatewayUrl)
        XCTAssertEqual(env.authBaseUrl, expectedGatewayUrl)
    }

    func testEnvironmentEnumerationHasDistinctValidConfigurations() {
        let allEnvs = ApertureEnvironment.allCases
        XCTAssertEqual(allEnvs.count, 4)
        XCTAssertTrue(allEnvs.contains(.local))
        XCTAssertTrue(allEnvs.contains(.development))
        XCTAssertTrue(allEnvs.contains(.staging))
        XCTAssertTrue(allEnvs.contains(.production))

        for env in allEnvs {
            XCTAssertFalse(env.coreApiBaseUrl.isEmpty)
            XCTAssertFalse(env.workflowApiBaseUrl.isEmpty)
            XCTAssertFalse(env.authBaseUrl.isEmpty)
            XCTAssertTrue(env.coreApiBaseUrl.hasPrefix("http://") || env.coreApiBaseUrl.hasPrefix("https://"))
        }
    }

    func testSamlLoginUrlConstructionWithUnifiedGateway() {
        let gatewayBase = ApertureEnvironment.development.authBaseUrl

        let googleUrl = EnterpriseDomainPolicy.constructSamlLoginUrl(
            baseUrl: gatewayBase,
            domain: "hybridcloudworks.com",
            provider: .googleWorkspace
        )
        XCTAssertNotNil(googleUrl)
        XCTAssertEqual(
            googleUrl?.absoluteString,
            "https://lp-gateway-dev-2pou78uy.uc.gateway.dev/auth/saml/login?domain=hybridcloudworks.com&provider=google&hd=hybridcloudworks.com"
        )

        let entraUrl = EnterpriseDomainPolicy.constructSamlLoginUrl(
            baseUrl: gatewayBase,
            domain: "berkeley.edu",
            provider: .entraID
        )
        XCTAssertNotNil(entraUrl)
        XCTAssertEqual(
            entraUrl?.absoluteString,
            "https://lp-gateway-dev-2pou78uy.uc.gateway.dev/auth/saml/login?domain=berkeley.edu&provider=entra&prompt=select_account"
        )

        let domainOnlyUrl = EnterpriseDomainPolicy.constructSamlLoginUrl(
            baseUrl: gatewayBase,
            domain: "example.org",
            provider: nil
        )
        XCTAssertNotNil(domainOnlyUrl)
        XCTAssertEqual(
            domainOnlyUrl?.absoluteString,
            "https://lp-gateway-dev-2pou78uy.uc.gateway.dev/auth/saml/login?domain=example.org"
        )
    }
}
