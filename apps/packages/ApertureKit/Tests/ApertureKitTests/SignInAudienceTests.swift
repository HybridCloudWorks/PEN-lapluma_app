import XCTest
@testable import ApertureDomain

/// APP-16: consumer applicants sign in with a passkey on any email domain; only
/// the workforce (institution SSO) path turns consumer domains away (ADR-011).
final class SignInAudienceTests: XCTestCase {

    private let consumerAddresses = [
        "applicant@gmail.com",
        "applicant@googlemail.com",
        "applicant@outlook.com",
        "applicant@hotmail.com",
        "applicant@yahoo.com",
        "applicant@icloud.com"
    ]

    func testApplicantsContinueWithAConsumerDomain() {
        for email in consumerAddresses {
            XCTAssertTrue(
                SignInEligibility.applicantCanContinue(email: email),
                "An applicant using \(email) must reach the passkey"
            )
        }
    }

    func testApplicantsContinueWithAnyOtherDomainAndNoWorkspaceCode() {
        XCTAssertTrue(SignInEligibility.applicantCanContinue(email: "maria@example.test"))
        XCTAssertTrue(SignInEligibility.applicantCanContinue(email: "staff@berkeley.edu"))
    }

    func testApplicantsStillNeedAnEmailAddress() {
        XCTAssertFalse(SignInEligibility.applicantCanContinue(email: ""))
        XCTAssertFalse(SignInEligibility.applicantCanContinue(email: "maria"))
    }

    func testWorkforceKeepsTheInstitutionRequirement() {
        for email in consumerAddresses {
            XCTAssertFalse(
                SignInEligibility.workforceCanContinue(email: email, workspaceCode: "NYC-01"),
                "Institution SSO has no directory for \(email)"
            )
            XCTAssertTrue(SignInEligibility.isConsumerDomain(email: email))
        }
    }

    func testWorkforceNeedsAnInstitutionalAddressAndAWorkspaceCode() {
        XCTAssertTrue(SignInEligibility.workforceCanContinue(email: "caseworker@example.test", workspaceCode: "nyc-01"))
        XCTAssertFalse(SignInEligibility.workforceCanContinue(email: "caseworker@example.test", workspaceCode: "ny"))
        XCTAssertFalse(SignInEligibility.workforceCanContinue(email: "caseworker@example.test", workspaceCode: "   "))
        XCTAssertFalse(SignInEligibility.workforceCanContinue(email: "caseworker", workspaceCode: "NYC-01"))
        XCTAssertFalse(SignInEligibility.isConsumerDomain(email: "caseworker@example.test"))
    }

    func testWorkspaceCodesNormalizeToTrimmedUppercase() {
        XCTAssertEqual(SignInEligibility.normalizedWorkspaceCode("  nyc-01 \n"), "NYC-01")
    }

    func testBothAudiencesAreOffered() {
        XCTAssertEqual(SignInAudience.allCases, [.applicant, .workforce])
    }
}
