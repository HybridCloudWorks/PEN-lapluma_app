import Foundation
import CryptoKit
import Security

/// Errors encountered by `EncryptedLocalStore`.
public enum EncryptedLocalStoreError: Error, Sendable, CustomStringConvertible {
    case keychainError(status: OSStatus)
    case encryptionFailed(String)
    case decryptionFailed(String)
    case invalidKeyName(String)
    case serializationFailed(String)
    case fileSystemError(String)

    public var description: String {
        switch self {
        case .keychainError(let status):
            return "Keychain error with OSStatus: \(status)"
        case .encryptionFailed(let detail):
            return "Encryption failed: \(detail)"
        case .decryptionFailed(let detail):
            return "Decryption failed: \(detail)"
        case .invalidKeyName(let name):
            return "Invalid cache key name: '\(name)'"
        case .serializationFailed(let detail):
            return "Serialization failed: \(detail)"
        case .fileSystemError(let detail):
            return "File system error: \(detail)"
        }
    }
}

/// Secure local on-device encrypted store (NFR-SEC-002, NFR-SEC-006).
///
/// Encrypts cached applicant documents, case metadata, and offline drafts using
/// hardware-backed or Keychain-stored AES-256-GCM symmetric keys, and enforces
/// `NSFileProtectionComplete` at rest so data is inaccessible while the device is locked.
public actor EncryptedLocalStore: Sendable {

    public let storageDirectory: URL
    private let key: SymmetricKey

    /// Initializes with an explicit encryption key and storage directory.
    public init(storageDirectory: URL, key: SymmetricKey) {
        self.storageDirectory = storageDirectory
        self.key = key
    }

    /// Convenience initializer resolving or creating a key in the system Keychain.
    public init(
        storageDirectory: URL,
        keychainService: String = "app.aperture.secure-storage",
        keychainAccount: String = "master-encryption-key"
    ) throws {
        self.storageDirectory = storageDirectory
        self.key = try Self.resolveOrCreateKeychainKey(service: keychainService, account: keychainAccount)
    }

    /// Stores encodable data encrypted with AES-256-GCM.
    public func store<T: Encodable>(_ value: T, forKey key: String) throws {
        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            data = try encoder.encode(value)
        } catch {
            throw EncryptedLocalStoreError.serializationFailed(error.localizedDescription)
        }
        try storeData(data, forKey: key)
    }

    /// Encrypts raw data using AES-GCM and writes with Complete File Protection.
    public func storeData(_ data: Data, forKey cacheKey: String) throws {
        let fileURL = try fileURL(for: cacheKey)

        do {
            try FileManager.default.createDirectory(
                at: storageDirectory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
        } catch {
            throw EncryptedLocalStoreError.fileSystemError("Failed to create storage directory: \(error.localizedDescription)")
        }

        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.seal(data, using: key)
        } catch {
            throw EncryptedLocalStoreError.encryptionFailed(error.localizedDescription)
        }

        guard let combined = sealedBox.combined else {
            throw EncryptedLocalStoreError.encryptionFailed("Failed to generate combined ciphertext payload")
        }

        do {
            try combined.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            throw EncryptedLocalStoreError.fileSystemError("Failed to write encrypted payload: \(error.localizedDescription)")
        }
    }

    /// Loads and decrypts encodable value.
    public func load<T: Decodable>(_ type: T.Type, forKey key: String) throws -> T? {
        guard let data = try loadData(forKey: key) else {
            return nil
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(type, from: data)
        } catch {
            throw EncryptedLocalStoreError.serializationFailed(error.localizedDescription)
        }
    }

    /// Loads and decrypts raw bytes.
    public func loadData(forKey cacheKey: String) throws -> Data? {
        let fileURL = try fileURL(for: cacheKey)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let encryptedBytes: Data
        do {
            encryptedBytes = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        } catch {
            throw EncryptedLocalStoreError.fileSystemError("Failed to read encrypted file: \(error.localizedDescription)")
        }

        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.SealedBox(combined: encryptedBytes)
        } catch {
            throw EncryptedLocalStoreError.decryptionFailed("Invalid or corrupted ciphertext structure")
        }

        do {
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw EncryptedLocalStoreError.decryptionFailed("Authentication tag mismatch or invalid decryption key")
        }
    }

    /// Checks if a valid entry exists for the given key.
    public func exists(forKey key: String) -> Bool {
        guard let fileURL = try? fileURL(for: key) else { return false }
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// Removes the encrypted file for the given key.
    public func remove(forKey key: String) throws {
        let fileURL = try fileURL(for: key)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    /// Clears all encrypted files in the store.
    public func clearAll() throws {
        guard FileManager.default.fileExists(atPath: storageDirectory.path) else { return }
        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: storageDirectory,
            includingPropertiesForKeys: nil
        )
        for url in fileURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Returns list of cache keys stored.
    public func allKeys() -> [String] {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: storageDirectory.path) else {
            return []
        }
        return files.filter { $0.hasSuffix(".enc") }.map { String($0.dropLast(4)) }
    }

    // MARK: - Key Security & Path Protection

    private func fileURL(for key: String) throws -> URL {
        let sanitized = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty,
              !sanitized.contains("/"),
              !sanitized.contains("\\"),
              sanitized != ".",
              sanitized != ".." else {
            throw EncryptedLocalStoreError.invalidKeyName(key)
        }
        return storageDirectory.appending(path: "\(sanitized).enc", directoryHint: .notDirectory)
    }

    private static func resolveOrCreateKeychainKey(service: String, account: String) throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecSuccess, let keyData = item as? Data {
            return SymmetricKey(data: keyData)
        }

        if status != errSecItemNotFound && status != errSecSuccess {
            throw EncryptedLocalStoreError.keychainError(status: status)
        }

        // Generate a new 256-bit AES key
        let newKey = SymmetricKey(size: .bits256)
        let newKeyData = newKey.withUnsafeBytes { Data($0) }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: newKeyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw EncryptedLocalStoreError.keychainError(status: addStatus)
        }

        return newKey
    }
}
