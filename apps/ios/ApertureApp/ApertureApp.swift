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
        let testPrincipal: (UserID?, Set<WorkspaceRole>?) = {
            if arguments.contains("--ui-testing-role=reviewer") {
                return (UserID("u_stub_reviewer"), [.reviewer])
            }
            if arguments.contains("--ui-testing-role=preparer") {
                return (UserID("u_stub_preparer"), [.preparer])
            }
            return (nil, nil)
        }()
        let api: StubAPIClient
        if arguments.contains("--ui-testing-marketing-safe") {
            api = StubAPIClient(persistenceURL: nil, fixtureProfile: .marketingSafe)
        } else {
            api = StubAPIClient(
                persistenceURL: AppStorageLocation.apiStateURL,
                fixtureProfile: .realisticInternal,
                userID: testPrincipal.0,
                roles: testPrincipal.1
            )
        }
        #else
        let forceOffline = false
        let forceExpensive = false
        let api = StubAPIClient(
            persistenceURL: AppStorageLocation.apiStateURL,
            fixtureProfile: .realisticInternal
        )
        #endif
        let connectivity = ConnectivityMonitor(
            forceOffline: forceOffline,
            forceExpensive: forceExpensive
        )
        let session = AppSession(
            api: api,
            demoAPI: StubAPIClient(
                persistenceURL: AppStorageLocation.demoAPIStateURL,
                fixtureProfile: .marketingSafe,
                allowsSyntheticPersistence: true
            ),
            captureQueue: PendingCaptureQueue(directoryURL: AppStorageLocation.captureQueueURL),
            connectivity: connectivity
        )
        #if DEBUG
        if arguments.contains("--ui-testing-authenticated") {
            session.signIn(as: testPrincipal.0 ?? UserID("u_stub_maria"))
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
            if ApertureRuntimeMode.current == .internalDemo || session.isDemoWorkspace {
                Label("Synthetic demo workspace · Do not use real information", systemImage: "testtube.2")
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
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-multipage-scan") {
                ScanEncoderDiagnosticView()
            } else if let previewRoute = StorePreviewRoute.requested {
                StorePreviewView(route: previewRoute)
            } else {
                RootView()
            }
            #else
            RootView()
            #endif
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
            // The launch-time drain is skipped until the first path update; when the
            // path arrives with isOnline already at its optimistic initial value, no
            // isOnline change fires, so the first real path is its own trigger.
            .onChange(of: session.connectivity.hasCurrentPath) { _, hasPath in
                guard hasPath else { return }
                Task { await session.resumePendingCaptures() }
            }
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
    private let liveAPI: any ApertureAPIClient
    private let demoAPI: any ApertureAPIClient
    var api: any ApertureAPIClient { isDemoWorkspace ? demoAPI : liveAPI }
    let captureQueue: PendingCaptureQueue
    let connectivity: ConnectivityMonitor

    /// **Not an authentication mechanism.** This is a local-stub session marker, and
    /// its scope is deliberately recorded here so it is never mistaken for one:
    /// it is a plain `UserDefaults` boolean, so relaunching restores the session
    /// with no passkey assertion, no biometric prompt, and no server check, and
    /// `init` pairs it with a hard-coded stub user. Anyone holding an unlocked
    /// device reaches folders, documents, and exports — acceptable only because
    /// every record behind it is local fixture data.
    ///
    /// The `precondition(runtimeMode.allowsLocalStub)` at launch is what keeps this
    /// out of production. It must be replaced by a Keychain-held session and an
    /// `LAContext` gate as part of the passkey work (TODO T-18) before any
    /// production runtime mode exists — not afterwards.
    var isAuthenticated = false {
        didSet { defaults.set(isAuthenticated, forKey: Keys.isAuthenticated) }
    }
    var currentUserID: UserID?
    /// The workspace selected at authentication. In production this is display-only
    /// context derived from the server-issued session; it must never be trusted as an
    /// authorization claim or copied into an `X-Tenant-ID` header by the client.
    var currentWorkspaceCode: String?
    var activePersona: AppPersona = .workforce
    var isDemoWorkspace = false
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
        static let preferredLocale = AperturePreferredLocaleKey
        static let accessibilityProfile = "preferences.accessibilityProfile"
        static let plainLanguage = "preferences.plainLanguage"
        static let waitsForWiFi = "preferences.waitsForWiFiForLargeUploads"
    }

    init(
        api: any ApertureAPIClient,
        demoAPI: (any ApertureAPIClient)? = nil,
        captureQueue: PendingCaptureQueue,
        connectivity: ConnectivityMonitor,
        defaults: UserDefaults = .standard
    ) {
        liveAPI = api
        self.demoAPI = demoAPI ?? api
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
        if isAuthenticated {
            currentUserID = UserID("u_stub_maria")
            currentWorkspaceCode = "LOCAL-DEMO"
        }
    }

    func signIn(as userID: UserID, workspaceCode: String = "LOCAL-DEMO", persona: AppPersona = .workforce) {
        currentUserID = userID
        currentWorkspaceCode = workspaceCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        activePersona = persona
        isAuthenticated = true
    }

    func enterDemoWorkspace() {
        isDemoWorkspace = true
        currentWorkspaceCode = "DEMO-SYNTHETIC"
        activePersona = .workforce
        dataDidChange()
    }

    func exitDemoWorkspace() {
        isDemoWorkspace = false
        currentWorkspaceCode = "LOCAL-DEMO"
        dataDidChange()
    }

    func resetDemoWorkspace() async throws {
        guard isDemoWorkspace else { return }
        _ = try await demoAPI.resetDemoWorkspace(idempotencyKey: IdempotencyKey.make())
        dataDidChange()
    }

    func signOut() {
        currentUserID = nil
        currentWorkspaceCode = nil
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
        // hasCurrentPath: isOnline is optimistic until the first path update, and a
        // launch in airplane mode must not start a drain inside that window.
        guard connectivity.hasCurrentPath, connectivity.isOnline, pendingCaptureCount > 0 else {
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
                throw CaptureDrainFailure.permanentlyInvalid(reason: "checksum-mismatch")
            }
        }
        pendingCaptureCount = result.remainingCount
        pendingCaptureBytes = await captureQueue.pendingByteCount()
        if result.uploadedCount > 0 { dataDidChange() }
        return result
    }

    /// Deletion must not silently fail: anything left on disk resurrects on the
    /// next launch, so a failed erase surfaces to the confirmation screen.
    func deleteAllLocalData() async throws {
        if let localClient = api as? StubAPIClient {
            try await localClient.deleteAllUserData()
        }
        try await captureQueue.erase()
        // Exported copies are applicant data too; leaving them behind would make the
        // deletion screen's promise false for as long as `tmp` survives.
        try ExportScratch.clear()
        pendingCaptureCount = 0
        pendingCaptureBytes = 0
        preferredLocale = .current
        accessibilityProfileEnabled = false
        plainLanguageEnabled = false
        waitsForWiFiForLargeUploads = true
        defaults.removeObject(forKey: Keys.preferredLocale)
        defaults.removeObject(forKey: Keys.accessibilityProfile)
        defaults.removeObject(forKey: Keys.plainLanguage)
        defaults.removeObject(forKey: Keys.waitsForWiFi)
        currentUserID = nil
        currentWorkspaceCode = nil
        isAuthenticated = false
    }
}

/// Exports are copies of the applicant's own records, written outside the protected
/// store so the share sheet can read them. They are held in one directory, each
/// export in its own subdirectory, so a fixed filename can never hand back a stale
/// copy, the screen that created one can remove it, and erasing local data erases
/// them too. Without this, "this permanently removes everything stored by this
/// mobile build" is untrue for as long as iOS keeps `tmp` around.
enum ExportScratch {
    static var directoryURL: URL {
        FileManager.default.temporaryDirectory
            .appending(path: "LaPluma-Exports", directoryHint: .isDirectory)
    }

    /// A URL inside a fresh subdirectory. Callers write with complete protection and
    /// pass the URL back to `discard(_:)` once the share sheet is done with it.
    static func makeURL(named name: String) throws -> URL {
        // Suggested names cross the API boundary. Refuse separators and traversal
        // instead of letting a compromised response escape the protected export
        // directory or overwrite another local file.
        guard !name.isEmpty,
              URL(fileURLWithPath: name).lastPathComponent == name,
              name != ".",
              name != ".." else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let directory = directoryURL.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        return directory.appending(path: name, directoryHint: .notDirectory)
    }

    static func discard(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    static func clear() throws {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return }
        try FileManager.default.removeItem(at: directoryURL)
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

    static var demoAPIStateURL: URL {
        apiStateURL.deletingLastPathComponent()
            .appending(path: "DemoTenant", directoryHint: .isDirectory)
            .appending(path: "synthetic-state.json", directoryHint: .notDirectory)
    }

    /// Gives XCUITest a deterministic starting point without adding a reset control to
    /// the applicant UI. The caller is compiled only into Debug builds.
    static func resetForUITesting() {
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing-reset") else { return }
        try? FileManager.default.removeItem(at: apiStateURL)
        try? FileManager.default.removeItem(at: captureQueueURL)
        try? FileManager.default.removeItem(at: demoAPIStateURL.deletingLastPathComponent())
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

#if DEBUG
/// Debug-only routing makes store art reproducible without adding deep links or
/// preview controls to the applicant product. It always renders real feature views.
private enum StorePreviewRoute: String {
    case welcome
    case home
    case capture
    case missing
    case review
    case package

    static var requested: Self? {
        ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix("--ui-testing-preview-route=") })?
            .split(separator: "=", maxSplits: 1)
            .last
            .flatMap { Self(rawValue: String($0)) }
    }
}

/// Written when the requested preview route's content is actually on screen, so
/// screenshot tooling can poll for readiness instead of guessing with a fixed
/// sleep that captures the launch screen on a slow cold start.
private enum StorePreviewReadiness {
    static func markReady() {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "store-preview-ready", directoryHint: .notDirectory)
        try? Data("ready".utf8).write(to: url)
    }
}

private struct StorePreviewView: View {
    let route: StorePreviewRoute

    @ViewBuilder
    var body: some View {
        switch route {
        case .welcome:
            WelcomeView().onAppear { StorePreviewReadiness.markReady() }
        case .home:
            ClientDashboardView().onAppear { StorePreviewReadiness.markReady() }
        case .capture:
            CaptureEntryView().onAppear { StorePreviewReadiness.markReady() }
        case .missing:
            StorePreviewCaseView(route: route)
        case .review:
            StorePreviewCaseView(route: route)
        case .package:
            StorePreviewCaseView(route: route)
        }
    }
}

private struct StorePreviewCaseView: View {
    let route: StorePreviewRoute
    @Environment(AppSession.self) private var session
    @State private var caseID: CaseID?

    var body: some View {
        NavigationStack {
            if let caseID {
                Group {
                    switch route {
                    case .missing:
                        MissingItemsView(caseID: caseID)
                    case .review:
                        ReviewView(caseID: caseID)
                    case .package:
                        PackageView(caseID: caseID)
                    default:
                        ApertureLoadingView()
                    }
                }
                // Marked only once the resolved case content is on screen —
                // the loading placeholder must never count as ready.
                .onAppear { StorePreviewReadiness.markReady() }
            } else {
                ApertureLoadingView()
            }
        }
        .task {
            let cases = ((try? await session.api.folders()) ?? []).flatMap(\.cases)
            switch route {
            case .package:
                caseID = cases.first(where: { $0.state == .generated })?.id
            default:
                caseID = cases.first(where: { $0.state != .generated })?.id ?? cases.first?.id
            }
        }
    }
}
#endif

/// Four tabs keeps the primary work areas immediately reachable. The client list is
/// the authenticated entry point; selecting a client opens the existing folder flow.
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
        Group {
            if session.activePersona == .workforce && UIDevice.current.userInterfaceIdiom == .pad {
                TabView(selection: $selection) {
                    Tab("Clients", systemImage: "person.2", value: AppSection.home) { ClientDashboardView() }
                    Tab("Queue", systemImage: "tray.full", value: AppSection.queue) { ReviewerQueueView() }
                    Tab("Me", systemImage: "person.crop.circle", value: AppSection.me) { SettingsView() }
                }
            } else {
                TabView(selection: $selection) {
                    Tab("Home", systemImage: "house", value: AppSection.home) { HomeView() }
                    Tab("Capture", systemImage: "camera", value: AppSection.capture) { CaptureEntryView() }
                    Tab("Missing", systemImage: "list.bullet.clipboard", value: AppSection.missing) { MissingItemsEntryView() }
                    Tab("Me", systemImage: "person.crop.circle", value: AppSection.me) { SettingsView() }
                }
            }
        }
    }
}

private enum AppSection: String, Hashable {
    case home
    case capture
    case missing
    case queue
    case me
}
