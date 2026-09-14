"""
Direct-to-storage document upload contract tests (INT-05, APP-07, INF-03).

Validates:
1. contracts/openapi/documents-upload.yaml conforms to OpenAPI 3.1.0.
2. 100 MB document upload bypasses API Gateway's 32 MB limit via short-lived,
   narrowly scoped create-only grants to private Cloud Storage objects over Google's internet endpoint.
3. Server-side validation requirements: 104857600 byte ceiling, lowercase 64-character SHA-256 digest,
   required Idempotency-Key header, and typed 422 problem details on mismatch.
4. Mobile client ApertureKit UploadSession model alignment and PendingCaptureQueue offline contract.
"""
import pathlib
import re
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
CONTRACT_PATH = REPO_ROOT / "contracts" / "openapi" / "documents-upload.yaml"
CLIENT_SWIFT_PATH = (
    REPO_ROOT
    / "apps"
    / "packages"
    / "ApertureKit"
    / "Sources"
    / "ApertureAPI"
    / "ApertureAPIClient.swift"
)
QUEUE_SWIFT_PATH = (
    REPO_ROOT
    / "apps"
    / "packages"
    / "ApertureKit"
    / "Sources"
    / "ApertureAPI"
    / "PendingCaptureQueue.swift"
)


class DocumentsUploadContractTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(CONTRACT_PATH.exists(), f"Contract missing at {CONTRACT_PATH}")
        self.text = CONTRACT_PATH.read_text(encoding="utf-8")

    def test_openapi_specification_metadata(self):
        self.assertTrue(
            self.text.startswith("openapi: 3.1.0\n") or "openapi: 3.1.0" in self.text[:30],
            "Must declare openapi: 3.1.0",
        )
        self.assertIn("title: LaPluma Documents Upload API", self.text)
        self.assertIn("version: 0.2.0", self.text)
        self.assertIn('servers: [{url: "https://api.example.invalid/v1"}]', self.text)
        self.assertIn("security: [{tenantSession: []}]", self.text)

    def test_gateway_32mb_bypass_rationale_in_description(self):
        self.assertIn("Direct-to-storage document ingestion", self.text)
        self.assertIn("104857600 bytes", self.text)
        self.assertIn("fifteen minutes", self.text)
        self.assertIn("ADR-019", self.text)
        self.assertIn("Google Cloud Storage", self.text)
        self.assertIn("32 MB", self.text)

    def test_required_endpoints_and_operations(self):
        self.assertIn("/documents/upload-sessions:", self.text)
        self.assertIn("operationId: createUploadSession", self.text)
        self.assertIn("/documents/upload-sessions/{sessionId}/complete:", self.text)
        self.assertIn("operationId: completeUpload", self.text)

        # Responses for createUploadSession
        self.assertIn("'201': {description: One-object write-only upload slot", self.text)
        self.assertIn("'404': {$ref: '#/components/responses/NotFound'}", self.text)
        self.assertIn("'422': {description: File metadata exceeds capture limits}", self.text)
        self.assertIn("'503': {description: Upload issuing is not configured in this environment}", self.text)

        # Responses for completeUpload
        self.assertIn("'200': {description: Received and handed to processing", self.text)
        self.assertIn("'409': {description: Session already consumed by a different request}", self.text)
        self.assertIn("'422': {description: Digest, size, page, type, or sanitization validation failed}", self.text)

    def test_idempotency_key_parameter_contract(self):
        self.assertIn("IdempotencyKey:", self.text)
        self.assertIn("name: Idempotency-Key", self.text)
        self.assertIn("in: header", self.text)
        self.assertIn("required: true", self.text)
        self.assertIn("maxLength: 128", self.text)

    def test_create_upload_session_request_schema(self):
        self.assertIn("CreateUploadSessionRequest:", self.text)
        self.assertIn("required: [folderId, originalName, sizeBytes, contentSha256]", self.text)
        self.assertIn("minimum: 1, maximum: 104857600", self.text)
        self.assertIn("pattern: '^[a-f0-9]{64}$'", self.text)
        self.assertIn("maxLength: 255", self.text)

    def test_upload_session_response_schema(self):
        self.assertIn("UploadSession:", self.text)
        self.assertIn(
            "required: [sessionId, documentId, uploadUrl, uploadMethod, expiresAt, expectedContentSha256]",
            self.text,
        )
        self.assertIn("uploadMethod: {type: string, const: PUT}", self.text)
        self.assertIn("format: uri", self.text)
        self.assertIn("format: date-time", self.text)

    def test_upload_receipt_response_schema(self):
        self.assertIn("UploadReceipt:", self.text)
        self.assertIn("required: [sessionId, documentId, contentSha256, processingState]", self.text)
        self.assertIn("enum: [SCANNING, SANITIZED, CLASSIFYING, EXTRACTING, EXTRACTED]", self.text)

    def test_mobile_client_model_alignment(self):
        self.assertTrue(CLIENT_SWIFT_PATH.exists(), f"Missing {CLIENT_SWIFT_PATH}")
        client_swift = CLIENT_SWIFT_PATH.read_text(encoding="utf-8")

        # Verify struct UploadSession has required properties
        self.assertIn("struct UploadSession: Codable, Sendable", client_swift)
        self.assertIn("public let sessionID: String", client_swift)
        self.assertIn("public let documentID: DocumentID", client_swift)
        self.assertIn("public let uploadURL: URL", client_swift)
        self.assertIn("public let expiresAt: Date", client_swift)
        self.assertIn("public let uploadMethod: String", client_swift)
        self.assertIn("public let expectedContentSHA256: String?", client_swift)

    def test_pending_capture_queue_idempotency_and_integrity(self):
        self.assertTrue(QUEUE_SWIFT_PATH.exists(), f"Missing {QUEUE_SWIFT_PATH}")
        queue_swift = QUEUE_SWIFT_PATH.read_text(encoding="utf-8")

        # Verify capture model preserves both idempotency keys
        self.assertIn("createSessionIdempotencyKey: String", queue_swift)
        self.assertIn("completeUploadIdempotencyKey: String", queue_swift)
        self.assertIn("contentSHA256: String?", queue_swift)
        self.assertIn("sizeBytes: Int64", queue_swift)


if __name__ == "__main__":
    unittest.main()
