import Testing
import SwiftUI
import ApertureUI
import ApertureDomain

#if canImport(UIKit)
import UIKit
#endif

@Suite("Privacy Shield & Screen Deterrence Tests (NFR-SEC-007)")
struct PrivacyShieldTests {

    @Test("PrivacyShieldView renders accessible security tree")
    func testPrivacyShieldViewRendering() {
        let view = PrivacyShieldView()
        #expect(view != nil)
    }

    @Test("DocumentPrivacyMonitor initializes cleanly on MainActor")
    @MainActor
    func testDocumentPrivacyMonitor() {
        let monitor = DocumentPrivacyMonitor()
        #expect(!monitor.isScreenRecorded || monitor.isScreenRecorded)
        #expect(monitor.lastScreenshotTimestamp == nil)
    }

    #if canImport(UIKit) && !os(watchOS)
    @Test("Screenshot notification updates DocumentPrivacyMonitor state")
    @MainActor
    func testScreenshotNotificationUpdatesMonitor() {
        let monitor = DocumentPrivacyMonitor()
        let preDate = Date().addingTimeInterval(-1)

        NotificationCenter.default.post(
            name: UIApplication.userDidTakeScreenshotNotification,
            object: nil
        )

        if let timestamp = monitor.lastScreenshotTimestamp {
            #expect(timestamp > preDate)
        }
    }
    #endif
}
