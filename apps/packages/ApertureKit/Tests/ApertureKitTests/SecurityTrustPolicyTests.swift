import Testing
import Foundation
import Security
import ApertureAPI

@Suite("Security Trust Policy & Pinning Tests (NFR-SEC-001)")
struct SecurityTrustPolicyTests {

    @Test("Hardened URLSessionConfiguration enforces TLS 1.3 / 1.2 and disables URLCache")
    func testHardenedConfiguration() {
        let config = SecurityTrustPolicy.makeHardenedConfiguration()

        #expect(config.tlsMinimumSupportedProtocolVersion == .TLSv12)
        #expect(config.tlsMaximumSupportedProtocolVersion == .TLSv13)
        #expect(config.httpCookieAcceptPolicy == .never)
        #expect(!config.httpShouldSetCookies)
        #expect(config.urlCache == nil)
    }

    @Test("Default configuration includes production and development gateway pins")
    func testDefaultPins() {
        let policy = SecurityTrustPolicy()
        let devHost = "lp-gateway-dev-2pou78uy.uc.gateway.dev"
        let prodHost = "api.lapluma.app"

        #expect(policy.pinnedHashesByHost[devHost] != nil)
        #expect(policy.pinnedHashesByHost[prodHost] != nil)
        #expect(policy.pinnedHashesByHost[devHost]?.count ?? 0 >= 2)
    }

    @Test("Creates bound URLSession with custom configuration")
    func testMakeSession() {
        let policy = SecurityTrustPolicy()
        let session = policy.makeSession()

        #expect(session.configuration.tlsMinimumSupportedProtocolVersion == .TLSv12)
        #expect(session.configuration.tlsMaximumSupportedProtocolVersion == .TLSv13)
    }

    @Test("Allows local test bypass for stub hosts when configured")
    func testLocalBypassForStubs() {
        let policy = SecurityTrustPolicy(allowsLocalTestBypass: true)
        #expect(policy.allowsLocalTestBypass)
    }
}
