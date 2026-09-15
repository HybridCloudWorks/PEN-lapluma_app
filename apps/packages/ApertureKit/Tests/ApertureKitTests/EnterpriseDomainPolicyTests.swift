import XCTest
@testable import ApertureDomain

final class EnterpriseDomainPolicyTests: XCTestCase {

    func testPrimaryOrgDomainApprovesGoogleWorkspace() {
        let result = EnterpriseDomainPolicy.validate(email: "spatino@hybridcloudworks.com")
        XCTAssertEqual(result, .approved(domain: "hybridcloudworks.com", provider: .googleWorkspace))
        XCTAssertTrue(result.isApproved)
    }

    func testDisallowedConsumerDomainsAreRejected() {
        let personalEmails = [
            "user@gmail.com",
            "applicant@googlemail.com",
            "test@outlook.com",
            "worker@hotmail.com",
            "client@yahoo.com",
            "lawyer@icloud.com"
        ]

        for email in personalEmails {
            let result = EnterpriseDomainPolicy.validate(email: email)
            guard case .personalDomainDisallowed(let domain) = result else {
                XCTFail("Expected personalDomainDisallowed for \(email), got \(result)")
                continue
            }
            XCTAssertFalse(result.isApproved)
            XCTAssertTrue(EnterpriseDomainPolicy.disallowedConsumerDomains.contains(domain))
        }
    }

    func testInstitutionalDomainsApproveEntraID() {
        let institutional = [
            "staff@berkeley.edu",
            "attorney@legalaid.org",
            "admin@eastbayclinic.org"
        ]

        for email in institutional {
            let result = EnterpriseDomainPolicy.validate(email: email)
            guard case .approved(_, let provider) = result else {
                XCTFail("Expected approved for \(email), got \(result)")
                continue
            }
            XCTAssertEqual(provider, .entraID)
            XCTAssertTrue(result.isApproved)
        }
    }

    func testInvalidEmailFormats() {
        let invalid = ["invalid", "test@", "@domain.com", "nodomain@", ""]
        for email in invalid {
            let result = EnterpriseDomainPolicy.validate(email: email)
            XCTAssertEqual(result, .invalidEmail, "Expected invalidEmail for '\(email)'")
        }
    }

    func testConstructSamlLoginUrl() {
        let url = EnterpriseDomainPolicy.constructSamlLoginUrl(
            baseUrl: "https://api.lapluma.app",
            domain: "hybridcloudworks.com",
            provider: .googleWorkspace
        )

        XCTAssertNotNil(url)
        XCTAssertEqual(url?.scheme, "https")
        XCTAssertEqual(url?.host, "api.lapluma.app")
        XCTAssertEqual(url?.path, "/auth/saml/login")

        let components = URLComponents(url: url!, resolvingAgainstBaseURL: false)
        let domainItem = components?.queryItems?.first(where: { $0.name == "domain" })
        let providerItem = components?.queryItems?.first(where: { $0.name == "provider" })

        XCTAssertEqual(domainItem?.value, "hybridcloudworks.com")
        XCTAssertEqual(providerItem?.value, "google")
    }
}
