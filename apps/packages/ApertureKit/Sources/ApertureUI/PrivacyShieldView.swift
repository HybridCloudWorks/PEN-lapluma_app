import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Full-screen privacy overlay shielding sensitive applicant records, documents,
/// and personal identity data from being captured in the iOS App Switcher snapshot (NFR-SEC-007).
public struct PrivacyShieldView: View {

    public init() {}

    public var body: some View {
        ZStack {
            Aperture.Palette.surface
                .ignoresSafeArea()

            VStack(spacing: Aperture.Spacing.m) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Aperture.Palette.accent)
                    .accessibilityHidden(true)

                Text("LaPluma Secure Session")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Aperture.Palette.onSurface)

                Text("Confidential applicant records and personal details are concealed while this app is inactive.")
                    .font(Aperture.Typography.secondaryLanguage)
                    .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Aperture.Spacing.l)
            }
            .padding(Aperture.Spacing.xl)
        }
        .accessibilityIdentifier("privacy-shield-overlay")
    }
}

/// Detects screen recording and screenshot events on sensitive document viewers (NFR-SEC-007).
@Observable
@MainActor
public final class DocumentPrivacyMonitor {

    public static let shared = DocumentPrivacyMonitor()

    public var isScreenRecorded: Bool = false
    public var lastScreenshotTimestamp: Date?

    public init() {
        #if os(iOS)
        checkCurrentCaptureState()
        NotificationCenter.default.addObserver(
            forName: UIScreen.capturedDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkCurrentCaptureState()
            }
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.userDidTakeScreenshotNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.lastScreenshotTimestamp = Date()
            }
        }
        #endif
    }

    private func checkCurrentCaptureState() {
        #if os(iOS)
        isScreenRecorded = UIScreen.main.isCaptured
        #endif
    }
}

/// View modifier applying screenshot deterrence and screen recording protection (NFR-SEC-007).
public struct DocumentPrivacyModifier: ViewModifier {
    @State private var privacyMonitor = DocumentPrivacyMonitor.shared
    @State private var showScreenshotWarning = false

    public init() {}

    public func body(content: Content) -> some View {
        content
            .overlay {
                if privacyMonitor.isScreenRecorded {
                    ZStack {
                        Aperture.Palette.surface
                            .ignoresSafeArea()
                        VStack(spacing: Aperture.Spacing.s) {
                            Image(systemName: "video.slash.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(Aperture.Palette.warning)
                            Text("Screen Recording Detected")
                                .font(.headline)
                                .foregroundStyle(Aperture.Palette.onSurface)
                            Text("Protected case documents are hidden while screen recording or mirroring is active.")
                                .font(Aperture.Typography.caption)
                                .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, Aperture.Spacing.l)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .onChange(of: privacyMonitor.lastScreenshotTimestamp) { _, newTimestamp in
                guard newTimestamp != nil else { return }
                showScreenshotWarning = true
            }
            .alert("Confidential Document", isPresented: $showScreenshotWarning) {
                Button("Dismiss", role: .cancel) {}
            } message: {
                Text("Screenshots of immigration filings and identity evidence may contain sensitive personal data. Store responsibly.")
            }
    }
}

public extension View {
    /// Protects document viewing surfaces from screen recording and alerts on screenshots (NFR-SEC-007).
    func documentPrivacyProtected() -> some View {
        modifier(DocumentPrivacyModifier())
    }
}
