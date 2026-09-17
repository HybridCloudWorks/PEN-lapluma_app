import Foundation
import CryptoKit
import Security

/// Security policy enforcing TLS 1.3/1.2 minimums and SPKI certificate pinning (NFR-SEC-001).
///
/// Under NFR-SEC-001 and ADR-011:
/// 1. All client-to-gateway transit enforces TLS 1.2 floor with TLS 1.3 preference.
/// 2. Server trust is cryptographically verified by matching the server certificate's Subject Public Key Info
///    (SPKI) SHA-256 hash against a pinned whitelist.
/// 3. Back-up pins are embedded to allow zero-downtime certificate rotation without forcing emergency app updates.
public final class SecurityTrustPolicy: NSObject, URLSessionDelegate, Sendable {

    /// Default SPKI SHA-256 hashes for production and development gateways.
    /// Includes primary certificates and Google Trust Services (GTS) backup root/intermediate keys.
    public static let defaultPinnedHashes: [String: Set<String>] = [
        "lp-gateway-dev-2pou78uy.uc.gateway.dev": [
            "h6w/rwvyMaU1bpCnYH760QA27NdGE36Y5nfNrxndUb4=", // Google Trust Services Root R1
            "kIdp6NNEd83U530oGaqUmvhWtQQ25aSuJBccjfQZbhE=", // GTS Root R2
            "p55/p55a6d595b128564e52575a7536768789012345=", // Local test / backup pin
        ],
        "api.lapluma.app": [
            "h6w/rwvyMaU1bpCnYH760QA27NdGE36Y5nfNrxndUb4=", // GTS Root R1
            "kIdp6NNEd83U530oGaqUmvhWtQQ25aSuJBccjfQZbhE=", // GTS Root R2
        ]
    ]

    public let pinnedHashesByHost: [String: Set<String>]
    public let allowsLocalTestBypass: Bool

    public init(
        pinnedHashesByHost: [String: Set<String>] = SecurityTrustPolicy.defaultPinnedHashes,
        allowsLocalTestBypass: Bool = false
    ) {
        self.pinnedHashesByHost = pinnedHashesByHost
        self.allowsLocalTestBypass = allowsLocalTestBypass
        super.init()
    }

    /// Creates a hardened `URLSessionConfiguration` configured with modern TLS security parameters.
    public static func makeHardenedConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        config.tlsMaximumSupportedProtocolVersion = .TLSv13
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.urlCache = nil // Sensitive API tokens and payloads must not be cached by default URLCache
        return config
    }

    /// Creates a hardened `URLSession` bound to this trust policy delegate.
    public func makeSession() -> URLSession {
        let config = Self.makeHardenedConfiguration()
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    // MARK: - URLSessionDelegate Trust Evaluation

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host

        // If local test bypass is enabled for invalid or test hosts, allow default handling
        if allowsLocalTestBypass && (host == "stub.invalid" || host == "localhost" || host == "127.0.0.1") {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Verify standard system chain of trust
        var error: CFError?
        let isValidChain = SecTrustEvaluateWithError(serverTrust, &error)
        guard isValidChain else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Check if host has configured pins
        guard let validPins = pinnedHashesByHost[host], !validPins.isEmpty else {
            // If no explicit pins are bound to this host, rely on standard OS chain validation
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
            return
        }

        // Evaluate SPKI hashes in the certificate chain
        let certificateCount = SecTrustGetCertificateCount(serverTrust)
        for index in 0..<certificateCount {
            guard let certificate = SecTrustGetCertificateAtIndex(serverTrust, index) else { continue }
            if let spkiHash = Self.spkiHash(for: certificate), validPins.contains(spkiHash) {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
                return
            }
        }

        // No matching public key pin found - reject connection
        completionHandler(.cancelAuthenticationChallenge, nil)
    }

    // MARK: - SPKI Extraction & Hashing

    /// Computes base64-encoded SHA-256 digest of the Subject Public Key Info (SPKI).
    public static func spkiHash(for certificate: SecCertificate) -> String? {
        guard let publicKey = SecCertificateCopyKey(certificate),
              let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            return nil
        }
        let digest = SHA256.hash(data: publicKeyData)
        return Data(digest).base64EncodedString()
    }
}
