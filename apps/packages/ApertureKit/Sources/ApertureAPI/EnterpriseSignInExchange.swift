import CryptoKit
import Foundation

/// An RFC 7636 code verifier and its S256 challenge, plus the `state` value sent alongside them.
///
/// The verifier never leaves the device until the code exchange, and then only to
/// `POST /auth/token` over TLS. Only the challenge, a SHA-256 hash, goes through the browser.
public struct PKCEPair: Sendable, Equatable {
    public static let method = "S256"

    public let verifier: String
    public let challenge: String

    public init(verifier: String) {
        self.verifier = verifier
        self.challenge = Self.challenge(for: verifier)
    }

    /// 32 random bytes, base64url-encoded: 43 characters, inside RFC 7636's 43 to 128.
    public static func generate() -> PKCEPair {
        PKCEPair(verifier: Base64URL.encode(randomBytes(count: 32)))
    }

    public static func challenge(for verifier: String) -> String {
        Base64URL.encode(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    /// The opaque `state` the app checks on the callback: 32 characters from 24 random bytes.
    public static func generateState() -> String {
        Base64URL.encode(randomBytes(count: 24))
    }

    static func randomBytes(count: Int) -> Data {
        // SystemRandomNumberGenerator is the platform CSPRNG (arc4random_buf on Apple platforms).
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: UInt8.min...UInt8.max, using: &generator) })
    }
}

public enum Base64URL {
    public static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// What the sign-in callback said.
public enum EnterpriseSignInCallback: Sendable, Equatable {
    /// A one-time code to redeem with the verifier.
    case code(String)
    /// The backend or the identity provider turned the sign-in down; `reason` is its problem code.
    case denied(reason: String)
    /// The callback is not an answer to the sign-in this app started.
    case mismatched

    /// Reads `lapluma://auth/callback?code=…&state=…` or `?error=…&error_description=…&state=…`.
    /// A callback whose `state` is not `expectedState` is refused before anything else is read.
    public static func parse(_ url: URL, expectedState: String) -> EnterpriseSignInCallback {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first(where: { $0.name == name })?.value
        }

        guard let state = value("state"), state == expectedState else {
            return .mismatched
        }
        if let error = value("error") {
            return .denied(reason: value("error_description") ?? error)
        }
        guard let code = value("code"), !code.isEmpty else {
            return .mismatched
        }
        return .code(code)
    }
}

public enum EnterpriseSignInError: Error, Sendable, Equatable {
    case denied(reason: String)
    case mismatchedCallback
    case exchangeFailed(status: Int, type: String?)
    case malformedResponse
}

/// Redeems a sign-in code for a session token at `POST /auth/token`.
public struct SessionTokenExchange: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    /// The app's ASWebAuthenticationSession callback. It must match the backend's
    /// `SignIn__RedirectUris` entry exactly.
    public static let redirectURI = "lapluma://auth/callback"
    public static let callbackScheme = "lapluma"

    public static let urlSessionTransport: Transport = { request in
        try await URLSession.shared.data(for: request)
    }

    public let baseURL: URL
    private let transport: Transport

    public init(baseURL: URL, transport: @escaping Transport = SessionTokenExchange.urlSessionTransport) {
        self.baseURL = baseURL
        self.transport = transport
    }

    public func makeRequest(code: String, verifier: String, redirectURI: String = SessionTokenExchange.redirectURI) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("auth/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Neither the code nor the verifier may be cached anywhere on the device.
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let fields: [(String, String)] = [
            ("grant_type", "authorization_code"),
            ("code", code),
            ("code_verifier", verifier),
            ("redirect_uri", redirectURI),
        ]
        request.httpBody = Data(fields.map { "\($0.0)=\(Self.formEncode($0.1))" }.joined(separator: "&").utf8)
        return request
    }

    public func redeem(
        code: String,
        verifier: String,
        redirectURI: String = SessionTokenExchange.redirectURI,
        now: Date = Date()
    ) async throws -> SessionCredential {
        let (data, response) = try await transport(makeRequest(code: code, verifier: verifier, redirectURI: redirectURI))
        guard let http = response as? HTTPURLResponse else {
            throw EnterpriseSignInError.malformedResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let problem = try? JSONDecoder().decode(ProblemDetails.self, from: data)
            throw EnterpriseSignInError.exchangeFailed(status: http.statusCode, type: problem?.type)
        }
        guard let body = try? JSONDecoder().decode(TokenResponse.self, from: data),
              !body.accessToken.isEmpty,
              body.tokenType.caseInsensitiveCompare("Bearer") == .orderedSame,
              body.expiresIn > 0 else {
            throw EnterpriseSignInError.malformedResponse
        }
        return SessionCredential(
            accessToken: body.accessToken,
            tenantID: body.tenantId,
            userID: body.userId,
            email: body.email ?? body.userId,
            roles: body.roles ?? [],
            expiresAt: now.addingTimeInterval(TimeInterval(body.expiresIn))
        )
    }

    /// `application/x-www-form-urlencoded`: everything but RFC 3986 unreserved characters is
    /// percent-encoded.
    static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        // alphanumerics includes non-ASCII letters; restrict to ASCII explicitly.
        return value.unicodeScalars.map { scalar in
            if scalar.isASCII, allowed.contains(scalar) {
                return String(scalar)
            }
            return String(scalar).utf8.map { String(format: "%%%02X", $0) }.joined()
        }.joined()
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let tokenType: String
        let expiresIn: Int
        let tenantId: String
        let userId: String
        let email: String?
        let roles: [String]?
    }
}
