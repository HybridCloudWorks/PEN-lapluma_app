import SwiftUI
import ApertureAPI
import ApertureDomain
import ApertureUI

@main
struct ApertureApp: App {
    @State private var session: AppSession

    init() {
        let runtimeMode = ApertureRuntimeMode.current
        precondition(
            runtimeMode.allowsLocalStub,
            "Production mode requires a production API client; refusing to start with StubAPIClient."
        )
        let arguments = ProcessInfo.processInfo.arguments
        #if DEBUG
        if arguments.contains("--ui-testing-reset") {
            AppStorageLocation.resetForUITesting()
        }
        let forceOffline = arguments.contains("--ui-testing-offline")
        let forceExpensive = arguments.contains("--ui-testing-expensive-network")
        #else
        let forceOffline = false
        let forceExpensive = false
        #endif
        let connectivity = ConnectivityMonitor(
            forceOffline: forceOffline,
            forceExpensive: forceExpensive
        )
        let session = AppSession(
            api: StubAPIClient(persistenceURL: AppStorageLocation.apiStateURL),
            captureQueue: PendingCaptureQueue(directoryURL: AppStorageLocation.captureQueueURL),
            connectivity: connectivity
        )
        #if DEBUG
        if arguments.contains("--ui-testing-authenticated") {
            session.signIn(as: UserID("u_stub_maria"))
        }
        #endif
        _session = State(initialValue: session)
    }

    var body: some Scene {
        WindowGroup {
            ConfiguredRootView()
                .environment(session)
        }
    }
}

/// Reads observable preferences below the environment boundary so changing a setting
/// updates the active hierarchy immediately rather than only after a relaunch.
private struct ConfiguredRootView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        VStack(spacing: 0) {
            if ApertureRuntimeMode.current == .internalDemo {
                Label("Internal demo · Do not use real information", systemImage: "testtube.2")
                    .font(Aperture.Typography.caption.weight(.semibold))
                    .foregroundStyle(Aperture.Palette.onSurface)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Aperture.Spacing.s)
                    .background(Aperture.Palette.accent.opacity(0.14))
                    .accessibilityIdentifier("internal-demo-banner")
            }
            if !session.connectivity.isOnline {
                Label("You're offline. Captures and typed answers stay on this device.",
                      systemImage: "wifi.slash")
                    .font(Aperture.Typography.caption)
                    .foregroundStyle(Aperture.Palette.onSurface)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Aperture.Spacing.s)
                    .background(Aperture.Palette.warning.opacity(0.18))
                    .accessibilityIdentifier("offline-banner")
            }
            RootView()
        }
            // The user's chosen language wins over the device language: people in
            // this population frequently use a device set up by someone else.
            .environment(\.locale, session.preferredLocale)
            .environment(\.apertureAccessibilityProfileEnabled, session.accessibilityProfileEnabled)
            .environment(
                \.defaultMinListRowHeight,
                session.accessibilityProfileEnabled
                    ? Aperture.Spacing.accessibleTarget
                    : Aperture.Spacing.minimumTarget
            )
            .task { await session.resumePendingCaptures() }
            .onChange(of: session.connectivity.isOnline) { _, isOnline in
                guard isOnline else { return }
                Task { await session.resumePendingCaptures() }
            }
            .onChange(of: session.connectivity.isExpensive) { _, isExpensive in
                guard !isExpensive else { return }
                Task { await session.resumePendingCaptures() }
            }
            .onChange(of: session.connectivity.isConstrained) { _, isConstrained in
                guard !isConstrained else { return }
                Task { await session.resumePendingCaptures() }
            }
    }
}

private enum ApertureRuntimeMode: String {
    case local
    case internalDemo = "internal-demo"
    case production

    var allowsLocalStub: Bool { self != .production }

    static var current: Self {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "ApertureRuntimeMode") as? String,
              let mode = Self(rawValue: value) else {
            #if DEBUG
            return .local
            #else
            fatalError("ApertureRuntimeMode must be configured for non-Debug builds.")
            #endif
        }
        return mode
    }
}

/// App-wide state. `@Observable` (iOS 17+) rather than `ObservableObject` so views
/// re-render only on the properties they actually read.
@Observable
@MainActor
final class AppSession {
    let api: any ApertureAPIClient
    let captureQueue: PendingCaptureQueue
    let connectivity: ConnectivityMonitor

    var isAuthenticated = false {
        didSet { defaults.set(isAuthenticated, forKey: Keys.isAuthenticated) }
    }
    var currentUserID: UserID?
    var preferredLocale: Locale = .current {
        didSet { defaults.set(preferredLocale.identifier, forKey: Keys.preferredLocale) }
    }
    /// Drives voice-first defaults, larger targets and a waived voice budget.
    var accessibilityProfileEnabled = false {
        didSet { defaults.set(accessibilityProfileEnabled, forKey: Keys.accessibilityProfile) }
    }
    /// Targets a 4th-grade reading level and simplifies question phrasing.
    var plainLanguageEnabled = false {
        didSet { defaults.set(plainLanguageEnabled, forKey: Keys.plainLanguage) }
    }
    var unreadNotificationCount = 0
    var pendingCaptureCount = 0
    var pendingCaptureBytes: Int64 = 0
    var waitsForWiFiForLargeUploads = true {
        didSet { defaults.set(waitsForWiFiForLargeUploads, forKey: Keys.waitsForWiFi) }
    }
    /// Incremented after a successful local mutation so independently-owned screens
    /// refresh without coupling their view models together.
    var dataRevision = 0

    private let defaults: UserDefaults

    private enum Keys {
        static let isAuthenticated = "session.isAuthenticated"
        static let preferredLocale = "preferences.locale"
        static let accessibilityProfile = "preferences.accessibilityProfile"
        static let plainLanguage = "preferences.plainLanguage"
        static let waitsForWiFi = "preferences.waitsForWiFiForLargeUploads"
    }

    init(
        api: any ApertureAPIClient,
        captureQueue: PendingCaptureQueue,
        connectivity: ConnectivityMonitor,
        defaults: UserDefaults = .standard
    ) {
        self.api = api
        self.captureQueue = captureQueue
        self.connectivity = connectivity
        self.defaults = defaults
        isAuthenticated = defaults.bool(forKey: Keys.isAuthenticated)
        if let identifier = defaults.string(forKey: Keys.preferredLocale) {
            preferredLocale = Locale(identifier: identifier)
        }
        accessibilityProfileEnabled = defaults.bool(forKey: Keys.accessibilityProfile)
        plainLanguageEnabled = defaults.bool(forKey: Keys.plainLanguage)
        if defaults.object(forKey: Keys.waitsForWiFi) != nil {
            waitsForWiFiForLargeUploads = defaults.bool(forKey: Keys.waitsForWiFi)
        }
        if isAuthenticated { currentUserID = UserID("u_stub_maria") }
    }

    func signIn(as userID: UserID) {
        currentUserID = userID
        isAuthenticated = true
    }

    func signOut() {
        currentUserID = nil
        isAuthenticated = false
    }

    func dataDidChange() { dataRevision += 1 }

    @discardableResult
    func saveCapture(
        data: Data,
        folderID: FolderID,
        originalName: String,
        source: DocumentSource,
        quality: CaptureQuality?
    ) async throws -> CaptureDrainResult {
        let prepared = try CapturePayloadProcessor.prepare(data)
        _ = try await captureQueue.enqueue(
            data: prepared.data,
            folderID: folderID,
            subjectPersonID: nil,
            originalName: originalName,
            source: source,
            quality: quality,
            verifiedMIMEType: prepared.verifiedMIMEType,
            pageCount: prepared.pageCount
        )
        pendingCaptureCount = await captureQueue.pendingCount()
        pendingCaptureBytes = await captureQueue.pendingByteCount()
        guard connectivity.isOnline else {
            return CaptureDrainResult(uploadedCount: 0, remainingCount: pendingCaptureCount)
        }
        return await resumePendingCaptures()
    }

    @discardableResult
    func resumePendingCaptures() async -> CaptureDrainResult {
        pendingCaptureCount = await captureQueue.pendingCount()
        pendingCaptureBytes = await captureQueue.pendingByteCount()
        guard connectivity.isOnline, pendingCaptureCount > 0 else {
            return CaptureDrainResult(uploadedCount: 0, remainingCount: pendingCaptureCount)
        }

        let api = api
        let policy = CaptureTransferPolicy()
        let waitsForWiFi = waitsForWiFiForLargeUploads
        let networkIsExpensive = connectivity.isExpensive
        let networkIsConstrained = connectivity.isConstrained
        let result = await captureQueue.drain { capture, data in
            if policy.shouldDefer(
                sizeBytes: capture.sizeBytes,
                waitsForWiFi: waitsForWiFi,
                networkIsExpensive: networkIsExpensive,
                networkIsConstrained: networkIsConstrained
            ) {
                throw URLError(.dataNotAllowed)
            }
            let localSHA256 = capture.contentSHA256 ?? CapturePayloadProcessor.sha256(of: data)
            let upload = try await api.createUploadSession(
                folderID: capture.folderID,
                subjectPersonID: capture.subjectPersonID,
                originalName: capture.originalName,
                sizeBytes: capture.sizeBytes,
                source: capture.source,
                quality: capture.quality,
                contentSHA256: localSHA256,
                idempotencyKey: capture.createSessionIdempotencyKey
            )
            if upload.uploadURL.host != "stub.invalid" {
                var request = URLRequest(url: upload.uploadURL)
                request.httpMethod = "PUT"
                let (_, response) = try await URLSession.shared.upload(for: request, from: data)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
            }
            let completed = try await api.completeUpload(
                sessionID: upload.sessionID,
                idempotencyKey: capture.completeUploadIdempotencyKey
            )
            guard completed.contentSHA256 == localSHA256 else {
                throw URLError(.cannotDecodeContentData)
            }
        }
        pendingCaptureCount = result.remainingCount
        pendingCaptureBytes = await captureQueue.pendingByteCount()
        if result.uploadedCount > 0 { dataDidChange() }
        return result
    }

    func deleteAllLocalData() async {
        if let localClient = api as? StubAPIClient {
            await localClient.deleteAllUserData()
        }
        try? await captureQueue.erase()
        pendingCaptureCount = 0
        pendingCaptureBytes = 0
        defaults.removeObject(forKey: Keys.preferredLocale)
        defaults.removeObject(forKey: Keys.accessibilityProfile)
        defaults.removeObject(forKey: Keys.plainLanguage)
        defaults.removeObject(forKey: Keys.waitsForWiFi)
        currentUserID = nil
        isAuthenticated = false
    }
}

enum AppStorageLocation {
    static var apiStateURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "Aperture", directoryHint: .isDirectory)
            .appending(path: "mobile-state.json", directoryHint: .notDirectory)
    }

    static var captureQueueURL: URL {
        apiStateURL.deletingLastPathComponent()
            .appending(path: "PendingCaptures", directoryHint: .isDirectory)
    }

    /// Gives XCUITest a deterministic starting point without adding a reset control to
    /// the applicant UI. The caller is compiled only into Debug builds.
    static func resetForUITesting() {
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing-reset") else { return }
        try? FileManager.default.removeItem(at: apiStateURL)
        try? FileManager.default.removeItem(at: captureQueueURL)
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
        }
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
    @State private var selection: AppSection

    init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let requestedSection = arguments
            .first(where: { $0.hasPrefix("--ui-testing-start-tab=") })?
            .split(separator: "=", maxSplits: 1)
            .last
            .flatMap { AppSection(rawValue: String($0)) }
        _selection = State(initialValue: requestedSection ?? .home)
        #else
        _selection = State(initialValue: .home)
        #endif
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            tabs
                .tabBarMinimizeBehavior(.onScrollDown)
        } else {
            tabs
        }
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house", value: AppSection.home) {
                HomeView()
            }
            Tab("Capture", systemImage: "camera", value: AppSection.capture) {
                CaptureEntryView()
            }
            Tab("Missing", systemImage: "list.bullet.clipboard", value: AppSection.missing) {
                MissingItemsEntryView()
            }
            Tab("Me", systemImage: "person.crop.circle", value: AppSection.me) {
                SettingsView()
            }
        }
    }
}

private enum AppSection: String, Hashable {
    case home
    case capture
    case missing
    case me
}
