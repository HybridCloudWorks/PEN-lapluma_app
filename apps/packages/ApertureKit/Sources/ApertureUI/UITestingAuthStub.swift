#if DEBUG
import Foundation
import ApertureAPI

/// Test-only enterprise sign-in for UI tests (INT-22).
///
/// With `--ui-testing-auth-stub` on the launch command line, `EnterpriseSignInFlow` returns this
/// credential instead of opening the browser or calling the backend, so UI journeys never touch
/// real authentication. The token is not a JWT and every LaPluma backend rejects it.
///
/// The whole file is `#if DEBUG`: it does not exist in a Release build, and
/// `tools/validate-ios-release.sh` fails the archive if either string below appears in it.
public enum UITestingAuthStub {
    public static let launchArgument = "--ui-testing-auth-stub"
    public static let accessToken = "ui-testing-auth-stub-session"

    public static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    public static func credential(domain: String, now: Date = Date()) -> SessionCredential {
        SessionCredential(
            accessToken: accessToken,
            tenantID: "tenant_ui_testing",
            userID: "ui-tester@\(domain)",
            email: "ui-tester@\(domain)",
            roles: ["preparer"],
            expiresAt: now.addingTimeInterval(3600)
        )
    }
}
#endif
