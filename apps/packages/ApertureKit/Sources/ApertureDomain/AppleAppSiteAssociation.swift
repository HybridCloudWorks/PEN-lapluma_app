import Foundation

/// Canonical representation of the `/.well-known/apple-app-site-association` payload
/// conforming to Apple's WebAuthn / Passkey Relying Party specification.
public struct AppleAppSiteAssociation: Codable, Sendable, Equatable {

    public struct WebCredentials: Codable, Sendable, Equatable {
        public let apps: [String]

        public init(apps: [String]) {
            self.apps = apps
        }
    }

    public let webcredentials: WebCredentials

    public init(webcredentials: WebCredentials) {
        self.webcredentials = webcredentials
    }

    /// Convenience initializer binding an Apple Development Team ID to the primary bundle identifier.
    public init(teamId: String, bundleId: String = "app.aperture.mobile") {
        self.webcredentials = WebCredentials(apps: ["\(teamId).\(bundleId)"])
    }

    /// Generates canonical formatted UTF-8 JSON data.
    public func toJsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(self)
    }
}
