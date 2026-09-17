import Testing
import Foundation
import CryptoKit
import ApertureAPI
import ApertureDomain

@Suite("Encrypted Local Store Tests (NFR-SEC-002 / NFR-SEC-006)")
struct EncryptedLocalStoreTests {

    private struct TestDraftMetadata: Codable, Equatable, Sendable {
        let id: String
        let title: String
        let applicantNotes: String
        let createdAt: Date
    }

    private func makeTemporaryDirectory() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "EncryptedStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    @Test("Stores and loads Codable payload with AES-256-GCM encryption")
    func testStoreAndLoadCodable() async throws {
        let tempDir = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let key = SymmetricKey(size: .bits256)
        let store = EncryptedLocalStore(storageDirectory: tempDir, key: key)

        let testPayload = TestDraftMetadata(
            id: "draft_123",
            title: "I-130 Petition Draft",
            applicantNotes: "Confidential applicant personal information",
            createdAt: Date()
        )

        try await store.store(testPayload, forKey: "draft-123")

        let exists = await store.exists(forKey: "draft-123")
        #expect(exists)

        let loaded = try await store.load(TestDraftMetadata.self, forKey: "draft-123")
        #expect(loaded != nil)
        #expect(loaded?.id == testPayload.id)
        #expect(loaded?.title == testPayload.title)
        #expect(loaded?.applicantNotes == testPayload.applicantNotes)
    }

    @Test("Stored bytes on disk are authenticated ciphertext and do not expose plaintext")
    func testStoredBytesAreCiphertext() async throws {
        let tempDir = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let key = SymmetricKey(size: .bits256)
        let store = EncryptedLocalStore(storageDirectory: tempDir, key: key)

        let secretString = "TopSecretApplicantSocialSecurityNumber-999-00-1234"
        let secretData = Data(secretString.utf8)

        try await store.storeData(secretData, forKey: "secret-doc")

        // Read raw file bytes directly from file system
        let fileURL = tempDir.appending(path: "secret-doc.enc")
        let rawDiskBytes = try Data(contentsOf: fileURL)

        // Raw bytes must not contain the secret string
        let diskString = String(decoding: rawDiskBytes, as: UTF8.self)
        #expect(!diskString.contains(secretString))
        #expect(!diskString.contains("999-00-1234"))

        // Reading through store decrypts properly
        let decryptedData = try await store.loadData(forKey: "secret-doc")
        #expect(decryptedData == secretData)
    }

    @Test("Tampered ciphertext fails AES-GCM authentication tag check")
    func testTamperedCiphertextFails() async throws {
        let tempDir = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let key = SymmetricKey(size: .bits256)
        let store = EncryptedLocalStore(storageDirectory: tempDir, key: key)

        let data = Data("Sensitive biometric data payload".utf8)
        try await store.storeData(data, forKey: "biometric")

        // Tamper with bytes on disk
        let fileURL = tempDir.appending(path: "biometric.enc")
        var rawBytes = try Data(contentsOf: fileURL)
        if rawBytes.count > 10 {
            rawBytes[rawBytes.count - 5] ^= 0xFF // Flip bits in ciphertext or auth tag
        }
        try rawBytes.write(to: fileURL)

        // Attempting to read tampered file must throw
        await #expect(throws: EncryptedLocalStoreError.self) {
            try await store.loadData(forKey: "biometric")
        }
    }

    @Test("Decryption with wrong symmetric key fails closed")
    func testDecryptionWithWrongKeyFails() async throws {
        let tempDir = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let key1 = SymmetricKey(size: .bits256)
        let key2 = SymmetricKey(size: .bits256)

        let store1 = EncryptedLocalStore(storageDirectory: tempDir, key: key1)
        let store2 = EncryptedLocalStore(storageDirectory: tempDir, key: key2)

        try await store1.storeData(Data("Applicant Passport Scan".utf8), forKey: "passport")

        // Store2 has a different key and must fail closed
        await #expect(throws: EncryptedLocalStoreError.self) {
            try await store2.loadData(forKey: "passport")
        }
    }

    @Test("Path traversal attempts in cache keys are rejected")
    func testPathTraversalRejection() async throws {
        let tempDir = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let key = SymmetricKey(size: .bits256)
        let store = EncryptedLocalStore(storageDirectory: tempDir, key: key)

        await #expect(throws: EncryptedLocalStoreError.self) {
            try await store.storeData(Data("bad".utf8), forKey: "../escape")
        }

        await #expect(throws: EncryptedLocalStoreError.self) {
            try await store.storeData(Data("bad".utf8), forKey: "sub/folder")
        }

        await #expect(throws: EncryptedLocalStoreError.self) {
            try await store.storeData(Data("bad".utf8), forKey: "")
        }
    }

    @Test("Remove and clearAll manage cached files correctly")
    func testRemoveAndClearAll() async throws {
        let tempDir = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let key = SymmetricKey(size: .bits256)
        let store = EncryptedLocalStore(storageDirectory: tempDir, key: key)

        try await store.storeData(Data("1".utf8), forKey: "doc1")
        try await store.storeData(Data("2".utf8), forKey: "doc2")
        try await store.storeData(Data("3".utf8), forKey: "doc3")

        var keys = await store.allKeys()
        #expect(keys.count == 3)

        try await store.remove(forKey: "doc2")
        let doc2Exists = await store.exists(forKey: "doc2")
        #expect(!doc2Exists)

        keys = await store.allKeys()
        #expect(keys.count == 2)

        try await store.clearAll()
        keys = await store.allKeys()
        #expect(keys.isEmpty)
    }
}
