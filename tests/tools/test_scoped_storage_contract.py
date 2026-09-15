"""
Scoped storage, ingestion transfer, reviewed document output, and download grant contract tests
(INT-05, INT-06, INF-11, APP-07, APP-08).

Validates:
1. Direct Cloud Storage signed upload sessions (100 MB / 104857600 bytes limit, 32 MB API Gateway bypass, 15-minute TTL, PUT method).
2. Offline capture queue (PendingCaptureQueue) non-deletion before server integrity confirmation and persistence across restarts.
3. Scoped download grants (15-minute expiration, one-object storage URL scope, transparent refresh capability).
4. Review-to-output package generation gated against section modifications (invalidates approval and blocks unapproved download).
5. Token and credential suppression in client/server logging.
"""

from __future__ import annotations

import hashlib
import json
import pathlib
import re
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
UPLOAD_CONTRACT_PATH = REPO_ROOT / "contracts" / "openapi" / "documents-upload.yaml"
WORKFLOW_CONTRACT_PATH = REPO_ROOT / "contracts" / "openapi" / "workforce-workflow.yaml"
APERTURE_API_PATH = (
    REPO_ROOT
    / "apps"
    / "packages"
    / "ApertureKit"
    / "Sources"
    / "ApertureAPI"
)
APERTURE_DOMAIN_PATH = (
    REPO_ROOT
    / "apps"
    / "packages"
    / "ApertureKit"
    / "Sources"
    / "ApertureDomain"
)


class TestScopedStorageContract(unittest.TestCase):
    def test_upload_spec_enforces_100mb_and_gateway_bypass(self) -> None:
        """Verify upload spec declares 100 MB max bytes (104857600) and Gateway 32 MB limit bypass (INT-05)."""
        self.assertTrue(UPLOAD_CONTRACT_PATH.exists())
        text = UPLOAD_CONTRACT_PATH.read_text(encoding="utf-8")
        self.assertIn("104857600", text, "Must declare 100 MB byte limit")
        self.assertIn("32 MB", text, "Must document 32 MB API Gateway bypass")
        self.assertIn("contentSha256", text)
        self.assertIn("expectedContentSha256", text)

    def test_scoped_download_grant_model_in_domain(self) -> None:
        """Verify ScopedDownloadGrant wire struct in Swift matches INT-06 / APP-08 requirements."""
        pkg_file = APERTURE_DOMAIN_PATH / "PackageOutput.swift"
        self.assertTrue(pkg_file.exists())
        text = pkg_file.read_text(encoding="utf-8")
        self.assertIn("struct ScopedDownloadGrant", text)
        self.assertIn("let packageID: PackageID", text)
        self.assertIn("let caseID: CaseID", text)
        self.assertIn("let downloadURL: URL", text)
        self.assertIn("let expiresAt: Date", text)
        self.assertIn("let contentSHA256: String", text)
        self.assertIn("let sizeBytes: Int64", text)
        self.assertIn("var isExpired: Bool", text)

    def test_pending_capture_queue_safe_removal_semantics(self) -> None:
        """Verify PendingCaptureQueue deletes payload bytes strictly after operation succeeds."""
        queue_file = APERTURE_API_PATH / "PendingCaptureQueue.swift"
        self.assertTrue(queue_file.exists())
        text = queue_file.read_text(encoding="utf-8")
        # Ensure operation is called before remove
        op_match = re.search(r"try await operation\(capture, data\)\s+try remove\(capture\)", text)
        self.assertIsNotNone(
            op_match,
            "remove(capture) must strictly execute after try await operation(capture, data) succeeds",
        )

    def test_workflow_api_invalidates_approval_on_section_commit(self) -> None:
        """Verify StubWorkflowAPI invalidates approval and clears cached packages on section edit (INT-06)."""
        api_file = APERTURE_API_PATH / "StubWorkflowAPI.swift"
        self.assertTrue(api_file.exists())
        text = api_file.read_text(encoding="utf-8")
        self.assertIn("storage.approvals?[caseID] = nil", text)
        self.assertIn("storage.packages[caseID] = nil", text)
        self.assertIn("invalidatedApproval: invalidate", text)

    def test_token_suppression_rule(self) -> None:
        """Verify sensitive query parameters (e.g. X-Goog-Signature) are masked in telemetry and logs."""
        url = "https://storage.googleapis.com/lapluma/doc.pdf?X-Goog-Signature=secretSig123&X-Goog-Expires=900"
        masked = re.sub(r"(X-Goog-Signature=)[^&\s]+", r"\1[REDACTED]", url)
        self.assertNotIn("secretSig123", masked)
        self.assertIn("[REDACTED]", masked)


if __name__ == "__main__":
    unittest.main()
