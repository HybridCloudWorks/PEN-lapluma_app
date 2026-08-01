import SwiftUI
import ApertureAPI
import ApertureDomain

@main
struct ApertureApp: App {
    @State private var session = AppSession(api: StubAPIClient())

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                // The user's chosen language wins over the device language: people in
                // this population frequently use a device set up by someone else.
                .environment(\.locale, session.preferredLocale)
        }
    }
}

/// App-wide state. `@Observable` (iOS 17+) rather than `ObservableObject` so views
/// re-render only on the properties they actually read.
@Observable
@MainActor
final class AppSession {
    let api: any ApertureAPIClient

    var isAuthenticated = false
    var currentUserID: UserID?
    var preferredLocale: Locale = .current
    /// Drives voice-first defaults, larger targets and a waived voice budget.
    var accessibilityProfileEnabled = false
    /// Targets a 4th-grade reading level and simplifies question phrasing.
    var plainLanguageEnabled = false
    var unreadNotificationCount = 0

    init(api: any ApertureAPIClient) {
        self.api = api
    }

    func signIn(as userID: UserID) {
        currentUserID = userID
        isAuthenticated = true
    }

    func signOut() {
        currentUserID = nil
        isAuthenticated = false
    }
}

struct RootView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        if session.isAuthenticated {
            MainTabView()
        } else {
            WelcomeView()
        }
    }
}

/// Four tabs is the ceiling for this population. Capture is a tab rather than a button
/// because it is the highest-frequency action in the product.
struct MainTabView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") {
                HomeView()
            }
            Tab("Capture", systemImage: "camera") {
                CaptureEntryView()
            }
            Tab("Missing", systemImage: "list.bullet.clipboard") {
                MissingItemsEntryView()
            }
            Tab("Me", systemImage: "person.crop.circle") {
                SettingsView()
            }
        }
    }
}
