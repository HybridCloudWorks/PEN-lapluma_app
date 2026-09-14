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
import yaml

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
        with open(CONTRACT_PATH, "r", encoding="utf-8") as f:
            self.contract = yaml.safe_load(f)
        self.raw_text = CONTRACT_PATH.read_text(encoding="utf-8")

    def test_openapi_specification_metadata(self):
        self.assertEqual(self.contract.get("openapi"), "3.1.0")
        info = self.contract.get("info", {})
        self.assertEqual(info.get("title"), "LaPluma Documents Upload API")
        self.assertEqual(info.get("version"), "0.2.0")

        # Must declare placeholder server host
        servers = self.contract.get("servers", [])
        self.assertTrue(len(servers) > 0)
        self.assertEqual(servers[0].get("url"), "https://api.example.invalid/v1")

        # Must mandate authenticated tenant session
        security = self.contract.get("security", [])
        self.assertEqual(security, [{"tenantSession": []}])

    def test_gateway_32mb_bypass_rationale_in_description(self):
        desc = self.contract.get("info", {}).get("description", "")
        self.assertIn("Direct-to-storage document ingestion", desc)
        self.assertIn("104857600 bytes", desc)
        self.assertIn("fifteen minutes", desc)
        self.assertIn("ADR-019", desc)
        self.assertIn("Google Cloud Storage", desc)
        self.assertIn("32 MB", desc)

    def test_required_endpoints_and_operations(self):
        paths = self.contract.get("paths", {})
        self.assertIn("/documents/upload-sessions", paths)
        self.assertIn("/documents/upload-sessions/{sessionId}/complete", paths)

        create_op = paths["/documents/upload-sessions"]["post"]
        self.assertEqual(create_op.get("operationId"), "createUploadSession")
        self.assertIn("201", create_op.get("responses", {}))
        self.assertIn("404", create_op.get("responses", {}))
        self.assertIn("422", create_op.get("responses", {}))
        self.assertIn("503", create_op.get("responses", {}))

        complete_op = paths["/documents/upload-sessions/{sessionId}/complete"]["post"]
        self.assertEqual(complete_op.get("operationId"), "completeUpload")
        self.assertIn("200", complete_op.get("responses", {}))
        self.assertIn("404", complete_op.get("responses", {}))
        self.assertIn("409", complete_op.get("responses", {}))
        self.assertIn("422", complete_op.get("responses", {}))

    def test_idempotency_key_parameter_contract(self):
        components = self.contract.get("components", {})
        params = components.get("parameters", {})
        self.assertIn("IdempotencyKey", params)
        idemp = params["IdempotencyKey"]
        self.assertEqual(idemp.get("name"), "Idempotency-Key")
        self.assertEqual(idemp.get("in"), "header")
        self.assertTrue(idemp.get("required"))
        schema = idemp.get("schema", {})
        self.assertEqual(schema.get("type"), "string")
        self.assertEqual(schema.get("minLength"), 1)
        self.assertEqual(schema.get("maxLength"), 128)

    def test_create_upload_session_request_schema(self):
        schemas = self.contract.get("components", {}).get("schemas", {})
        self.assertIn("CreateUploadSessionRequest", schemas)
        req = schemas["CreateUploadSessionRequest"]
        self.assertEqual(
            req.get("required"),
            ["folderId", "originalName", "sizeBytes", "contentSha256"],
        )
        props = req.get("properties", {})
        self.assertEqual(props["sizeBytes"].get("minimum"), 1)
        self.assertEqual(props["sizeBytes"].get("maximum"), 104857600)
        self.assertEqual(props["contentSha256"].get("pattern"), "^[a-f0-9]{64}$")
        self.assertEqual(props["originalName"].get("maxLength"), 255)

    def test_upload_session_response_schema(self):
        schemas = self.contract.get("components", {}).get("schemas", {})
        self.assertIn("UploadSession", schemas)
        session = schemas["UploadSession"]
        self.assertEqual(
            session.get("required"),
            [
                "sessionId",
                "documentId",
                "uploadUrl",
                "uploadMethod",
                "expiresAt",
                "expectedContentSha256",
            ],
        )
        props = session.get("properties", {})
        self.assertEqual(props["uploadMethod"].get("const"), "PUT")
        self.assertEqual(props["uploadUrl"].get("format"), "uri")
        self.assertEqual(props["expiresAt"].get("format"), "date-time")
        self.assertEqual(props["expectedContentSha256"].get("pattern"), "^[a-f0-9]{64}$")

    def test_upload_receipt_response_schema(self):
        schemas = self.contract.get("components", {}).get("schemas", {})
        self.assertIn("UploadReceipt", schemas)
        receipt = schemas["UploadReceipt"]
        self.assertEqual(
            receipt.get("required"),
            ["sessionId", "documentId", "contentSha256", "processingState"],
        )
        props = receipt.get("properties", {})
        self.assertEqual(props["contentSha256"].get("pattern"), "^[a-f0-9]{64}$")
        self.assertEqual(
            props["processingState"].get("enum"),
            ["SCANNING", "SANITIZED", "CLASSIFYING", "EXTRACTING", "EXTRACTED"],
        )

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
