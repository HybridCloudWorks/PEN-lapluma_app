import Foundation

/// A LaPluma session token as `POST /auth/token` returns it: an RS256 JWT the app treats as
/// opaque, valid for one hour. It lives only in memory, never in a URL, a log, or `UserDefaults`.
public struct SessionCredential: Sendable, Equatable {
    public let accessToken: String
    public let tenantID: String
    public let userID: String
    public let email: String
    public let roles: [String]
    public let expiresAt: Date

    public init(
        accessToken: String,
        tenantID: String,
        userID: String,
        email: String,
        roles: [String],
        expiresAt: Date
    ) {
        self.accessToken = accessToken
        self.tenantID = tenantID
        self.userID = userID
        self.email = email
        self.roles = roles
        self.expiresAt = expiresAt
    }

    /// True while the token has more than `leeway` seconds left, so a request sent now does not
    /// arrive after it expires.
    public func isUsable(at now: Date, leeway: TimeInterval = SessionCredentialStore.renewalLeeway) -> Bool {
        expiresAt.timeIntervalSince(now) > leeway
    }
}

/// What the app needs to sign the same person in again without asking who they are: the
/// institution's domain, the identity provider, and the API it signed in against. Not a secret
/// and not a credential; it is kept in `UserDefaults` so renewal also works after a relaunch.
public struct EnterpriseSignInContext: Codable, Sendable, Equatable {
    public let domain: String
    public let provider: String
    public let baseUrl: String

    public init(domain: String, provider: String, baseUrl: String) {
        self.domain = domain
        self.provider = provider
        self.baseUrl = baseUrl
    }
}

/// The result of one renewal attempt.
public enum SessionRenewalOutcome: Sendable, Equatable {
    case renewed(SessionCredential)
    /// Nothing to renew with, or no window to show the sign-in sheet in. Not a failure: the next
    /// request may try again.
    case unavailable
    /// The user cancelled or the sign-in failed. The store waits `renewalCooldown` before asking
    /// again, so a declined prompt does not reappear on every request.
    case failed
}

/// Holds the current session credential and renews it.
///
/// Sessions last one hour and there is no refresh token (INT-22): the backend would need shared
/// state to rotate one safely, and its database is stopped. Instead, when the token is missing or
/// within `renewalLeeway` of expiry, or a request comes back `401`, the store calls its renewal
/// handler, which runs enterprise SSO again. With the identity provider's single-sign-on cookie
/// in place that needs no password, only the system's sign-in confirmation. Concurrent requests
/// share one renewal, so the user sees one prompt, not one per request.
public actor SessionCredentialStore {
    public static let shared = SessionCredentialStore()

    /// Renew this long before expiry rather than sending a token that dies in flight.
    public static let renewalLeeway: TimeInterval = 60

    /// After a cancelled or failed renewal, how long to wait before prompting again.
    public static let renewalCooldown: TimeInterval = 120

    private static let contextKey = "auth.enterpriseSignInContext"

    private var credential: SessionCredential?
    private var renewalHandler: (@Sendable () async -> SessionRenewalOutcome)?
    private var renewalTask: Task<SessionRenewalOutcome, Never>?
    private var lastFailedRenewal: Date?
    private var generation = 0
    private let clock: @Sendable () -> Date
    private let defaultsSuiteName: String?

    /// - Parameter defaultsSuiteName: where the sign-in context is persisted; `nil` is
    ///   `UserDefaults.standard`. Tests pass their own suite.
    public init(defaultsSuiteName: String? = nil, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.defaultsSuiteName = defaultsSuiteName
        self.clock = clock
    }

    public var current: SessionCredential? { credential }

    /// Records a completed sign-in and what is needed to repeat it.
    public func store(_ credential: SessionCredential, context: EnterpriseSignInContext? = nil) {
        self.credential = credential
        lastFailedRenewal = nil
        if let context, let data = try? JSONEncoder().encode(context) {
            defaults.set(data, forKey: Self.contextKey)
        }
    }

    public func renewalContext() -> EnterpriseSignInContext? {
        guard let data = defaults.data(forKey: Self.contextKey) else { return nil }
        return try? JSONDecoder().decode(EnterpriseSignInContext.self, from: data)
    }

    /// Sign-out: forgets the token and the sign-in context, and discards any renewal in flight.
    public func clear() {
        generation += 1
        credential = nil
        renewalTask?.cancel()
        renewalTask = nil
        lastFailedRenewal = nil
        defaults.removeObject(forKey: Self.contextKey)
    }

    public func setRenewalHandler(_ handler: (@Sendable () async -> SessionRenewalOutcome)?) {
        renewalHandler = handler
    }

    /// The token for the next request, renewing first when none is held or the held one is
    /// about to expire. `nil` when there is no session to send.
    public func accessTokenForRequest() async -> String? {
        if let credential, credential.isUsable(at: clock()) {
            return credential.accessToken
        }
        return await renew()
    }

    /// Called after a `401`. If another request has already replaced `rejectedToken`, the new
    /// token is returned without a second renewal.
    public func tokenAfterRejection(of rejectedToken: String?) async -> String? {
        if let credential, credential.accessToken != rejectedToken, credential.isUsable(at: clock()) {
            return credential.accessToken
        }
        if let rejectedToken, credential?.accessToken == rejectedToken {
            credential = nil
        }
        return await renew()
    }

    private func renew() async -> String? {
        if let renewalTask {
            let joinedGeneration = generation
            let outcome = await renewalTask.value
            return generation == joinedGeneration ? Self.token(from: outcome) : nil
        }
        guard let renewalHandler else { return nil }
        if let lastFailedRenewal, clock().timeIntervalSince(lastFailedRenewal) < Self.renewalCooldown {
            return nil
        }

        let startedGeneration = generation
        let task = Task { await renewalHandler() }
        renewalTask = task
        let outcome = await task.value
        // A sign-out while the sheet was up wins: its result is discarded, not stored.
        guard generation == startedGeneration else { return nil }
        renewalTask = nil
        switch outcome {
        case .renewed(let renewed):
            credential = renewed
            lastFailedRenewal = nil
        case .failed:
            lastFailedRenewal = clock()
        case .unavailable:
            break
        }
        return Self.token(from: outcome)
    }

    private static func token(from outcome: SessionRenewalOutcome) -> String? {
        if case .renewed(let credential) = outcome {
            return credential.accessToken
        }
        return nil
    }

    private var defaults: UserDefaults {
        if let defaultsSuiteName, let suite = UserDefaults(suiteName: defaultsSuiteName) {
            return suite
        }
        return .standard
    }
}

extension NetworkAPIClient {
    /// A client whose requests carry the session token from `store`, renewing it before it
    /// expires and once more after a `401`.
    public static func signedIn(
        store: SessionCredentialStore = .shared,
        fallbackClient: (any ApertureAPIClient)?
    ) -> NetworkAPIClient {
        NetworkAPIClient(
            tokenProvider: { await store.accessTokenForRequest() },
            unauthorizedRecovery: { refused in await store.tokenAfterRejection(of: refused) },
            fallbackClient: fallbackClient
        )
    }
}
