import Foundation
#if canImport(AuthenticationServices) && !os(watchOS)
import AuthenticationServices
#endif
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import ApertureAPI
import ApertureDomain

/// One enterprise sign-in, start to finish (INT-22):
///
/// 1. `GET /auth/saml/login` with the domain, `redirect_uri=lapluma://auth/callback`, a fresh PKCE
///    S256 challenge, and a fresh `state`, shown in `ASWebAuthenticationSession`.
/// 2. The backend answers the identity provider's assertion with a `302` to
///    `lapluma://auth/callback?code=…&state=…`, which the session hands back here.
/// 3. The `state` must be the one sent; the code is then redeemed with the verifier at
///    `POST /auth/token` for the session token. The token is never in a URL.
///
/// The browser session is not ephemeral, so the identity provider's single-sign-on cookie
/// survives and a later renewal (see `EnterpriseSessionRenewer`) completes without a password.
@MainActor
public final class EnterpriseSignInFlow {
    /// What the app holds while the browser is up.
    public struct Started: Sendable, Equatable {
        public let url: URL
        public let pkce: PKCEPair
        public let state: String
    }

    /// Presents `url` and returns the callback URL for `callbackScheme`.
    public typealias WebAuthenticator = @MainActor (_ url: URL, _ callbackScheme: String) async throws -> URL

    private let transport: SessionTokenExchange.Transport
    private let webAuthenticator: WebAuthenticator

    public init(
        transport: @escaping SessionTokenExchange.Transport = SessionTokenExchange.urlSessionTransport,
        webAuthenticator: WebAuthenticator? = nil
    ) {
        self.transport = transport
        self.webAuthenticator = webAuthenticator ?? Self.systemWebAuthenticator()
    }

    public static func start(
        baseUrl: String,
        domain: String,
        provider: EnterpriseIdPProvider,
        loginHint: String?
    ) -> Started? {
        let pkce = PKCEPair.generate()
        let state = PKCEPair.generateState()
        guard let url = EnterpriseDomainPolicy.constructSamlLoginUrl(
            baseUrl: baseUrl,
            domain: domain,
            provider: provider,
            loginHint: loginHint,
            redirectUri: SessionTokenExchange.redirectURI,
            codeChallenge: pkce.challenge,
            state: state
        ) else {
            return nil
        }
        return Started(url: url, pkce: pkce, state: state)
    }

    /// Runs the whole sign-in and returns the session credential.
    public func signIn(
        baseUrl: String,
        domain: String,
        provider: EnterpriseIdPProvider,
        loginHint: String?
    ) async throws -> SessionCredential {
        #if DEBUG
        if UITestingAuthStub.isActive {
            return UITestingAuthStub.credential(domain: domain)
        }
        #endif
        guard let started = Self.start(baseUrl: baseUrl, domain: domain, provider: provider, loginHint: loginHint) else {
            throw EnterpriseSignInError.malformedResponse
        }
        let callback = try await webAuthenticator(started.url, SessionTokenExchange.callbackScheme)
        return try await finish(callback: callback, started: started, baseUrl: baseUrl)
    }

    /// Checks the callback against the sign-in it answers, then redeems the code.
    public func finish(callback: URL, started: Started, baseUrl: String) async throws -> SessionCredential {
        switch EnterpriseSignInCallback.parse(callback, expectedState: started.state) {
        case .mismatched:
            throw EnterpriseSignInError.mismatchedCallback
        case .denied(let reason):
            throw EnterpriseSignInError.denied(reason: reason)
        case .code(let code):
            guard let base = URL(string: baseUrl) else {
                throw EnterpriseSignInError.malformedResponse
            }
            return try await SessionTokenExchange(baseURL: base, transport: transport)
                .redeem(code: code, verifier: started.pkce.verifier)
        }
    }

    private static func systemWebAuthenticator() -> WebAuthenticator {
        #if canImport(AuthenticationServices) && !os(watchOS)
        let runner = WebAuthenticationRunner()
        return { url, scheme in try await runner.run(url: url, callbackScheme: scheme) }
        #else
        return { _, _ in throw EnterpriseSignInError.malformedResponse }
        #endif
    }
}

/// Renews the session by signing in again, for `SessionCredentialStore` (INT-22).
///
/// The least risky way past the one-hour token: no long-lived refresh token exists to steal or
/// revoke, and disabling the account at the identity provider ends access within the hour.
/// Renewal reuses the identity provider's single-sign-on cookie, so the user confirms the system
/// sign-in prompt but enters no password. It never runs while the app is in the background, and
/// never for an account that did not sign in with enterprise SSO.
@MainActor
public final class EnterpriseSessionRenewer {
    public static let shared = EnterpriseSessionRenewer()

    private let store: SessionCredentialStore
    private let flow: EnterpriseSignInFlow
    private let isForeground: @MainActor () -> Bool

    public init(
        store: SessionCredentialStore = .shared,
        flow: EnterpriseSignInFlow = EnterpriseSignInFlow(),
        isForeground: (@MainActor () -> Bool)? = nil
    ) {
        self.store = store
        self.flow = flow
        self.isForeground = isForeground ?? Self.applicationIsActive
    }

    /// Registers this renewer as the store's renewal handler.
    public func install() async {
        await store.setRenewalHandler { [weak self] in
            await self?.renew() ?? .unavailable
        }
    }

    public func renew() async -> SessionRenewalOutcome {
        guard let context = await store.renewalContext(),
              let provider = EnterpriseIdPProvider(rawValue: context.provider) else {
            return .unavailable
        }
        guard isForeground() else {
            return .unavailable
        }
        do {
            let credential = try await flow.signIn(
                baseUrl: context.baseUrl,
                domain: context.domain,
                provider: provider,
                loginHint: nil
            )
            return .renewed(credential)
        } catch {
            return .failed
        }
    }

    private static func applicationIsActive() -> Bool {
        #if canImport(UIKit)
        return UIApplication.shared.applicationState == .active
        #else
        return true
        #endif
    }
}

#if canImport(AuthenticationServices) && !os(watchOS)
private enum WebAuthenticationFailure: Error {
    case noCallback
    case couldNotStart
}

/// `ASWebAuthenticationSession` as one `async` call. The SDK declares the presentation protocol
/// main-actor, so `presentationAnchor(for:)` is isolated like the rest of the class.
@MainActor
final class WebAuthenticationRunner: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var activeSession: ASWebAuthenticationSession?

    func run(url: URL, callbackScheme: String) async throws -> URL {
        activeSession?.cancel()
        defer { activeSession = nil }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, any Error>) in
            let once = ResumeOnce(continuation)
            // @Sendable, so the handler is not inferred main-actor isolated: the system may call it
            // off the main thread, and it touches nothing but the one-shot continuation.
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { @Sendable callbackURL, error in
                if let callbackURL {
                    once.resume(.success(callbackURL))
                } else {
                    let failure: any Error = error ?? WebAuthenticationFailure.noCallback
                    once.resume(.failure(failure))
                }
            }
            // Not ephemeral: the identity provider's single-sign-on cookie has to outlive this
            // sheet, or every hourly renewal would ask for the password again.
            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = self
            activeSession = session
            if !session.start() {
                once.resume(.failure(WebAuthenticationFailure.couldNotStart))
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(UIKit)
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
           let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first {
            return window
        }
        return ASPresentationAnchor()
        #elseif canImport(AppKit)
        return NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
}

/// Resumes a continuation at most once, whichever of the completion handler and a failed
/// `start()` gets there first.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, any Error>?

    init(_ continuation: CheckedContinuation<URL, any Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<URL, any Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}
#endif
