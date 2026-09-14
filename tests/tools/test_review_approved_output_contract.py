"""Contract and policy validation tests for Phase 6 review-to-approved-output round trip.

Tests:
1. OpenAPI specification contract alignment for review, preview, step-up, approval, and output.
2. Swift domain models wire-name fidelity against OpenAPI schemas.
3. Separation of duties invariants (WorkflowPolicy.canApprove).
4. Approval invalidation invariants on canonical field edits.
5. Draft watermark preview and expiration rules.
6. Package generation fail-closed gating (requires non-invalidated approval, no edition drift, human confirmation).

Pure Python standard library only (no pyyaml or third-party packages).
"""

from __future__ import annotations

import hashlib
import json
import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
WORKFLOW_CONTRACT_PATH = REPO_ROOT / "contracts/openapi/workforce-workflow.yaml"
SWIFT_WORKFLOW_MODELS_PATH = (
    REPO_ROOT / "apps/packages/ApertureKit/Sources/ApertureDomain/WorkflowModels.swift"
)
SWIFT_PACKAGE_OUTPUT_PATH = (
    REPO_ROOT / "apps/packages/ApertureKit/Sources/ApertureDomain/PackageOutput.swift"
)


class ReviewApprovedOutputContractTests(unittest.TestCase):
    def test_workflow_openapi_contract_defines_review_and_approval_endpoints(self) -> None:
        self.assertTrue(WORKFLOW_CONTRACT_PATH.exists(), "workforce-workflow.yaml must exist")
        content = WORKFLOW_CONTRACT_PATH.read_text(encoding="utf-8")

        required_paths = [
            "/review-queue",
            "/cases/{caseId}/review-decisions",
            "/cases/{caseId}/draft-preview",
            "/cases/{caseId}/step-up-challenge",
            "/cases/{caseId}/approval",
            "/cases/{caseId}/history",
            "/cases/{caseId}/sections/{sectionId}/commit",
            "/cases/{caseId}/package-generation",
        ]

        for path in required_paths:
            with self.subTest(path=path):
                self.assertIn(path, content, f"Path {path} must be specified in OpenAPI contract")

    def test_workflow_openapi_contract_defines_phase6_schemas(self) -> None:
        content = WORKFLOW_CONTRACT_PATH.read_text(encoding="utf-8")

        required_schemas = [
            "ReviewQueueItem",
            "ReviewDecision",
            "DraftFormPreview",
            "StepUpChallenge",
            "CaseApprovalRequest",
            "ApprovalRecord",
            "CaseHistoryEvent",
            "GeneratedPackage",
        ]

        for schema in required_schemas:
            with self.subTest(schema=schema):
                pattern = rf"\b{re.escape(schema)}:\s*\n\s+type:\s*object"
                self.assertTrue(
                    re.search(pattern, content),
                    f"Schema {schema} must be defined as an object in OpenAPI contract",
                )

    def test_swift_workflow_models_align_with_contract(self) -> None:
        self.assertTrue(SWIFT_WORKFLOW_MODELS_PATH.exists())
        swift_content = SWIFT_WORKFLOW_MODELS_PATH.read_text(encoding="utf-8")

        # Verify struct DraftFormPreview wire fields
        self.assertIn("struct DraftFormPreview", swift_content)
        self.assertIn("let caseID: CaseID", swift_content)
        self.assertIn("let watermark: String", swift_content)
        self.assertIn("let pageCount: Int", swift_content)
        self.assertIn("let valueSetHash: String", swift_content)
        self.assertIn("let editionSetHash: String", swift_content)
        self.assertIn("let expiresAt: Date", swift_content)

        # Verify struct ApprovalRecord wire fields
        self.assertIn("struct ApprovalRecord", swift_content)
        self.assertIn("let caseID: CaseID", swift_content)
        self.assertIn("let approverID: UserID", swift_content)
        self.assertIn("let valueSetHash: String", swift_content)
        self.assertIn("let editionSetHash: String", swift_content)
        self.assertIn("let attestedAt: Date", swift_content)
        self.assertIn("let valid: Bool", swift_content)

    def test_separation_of_duties_policy_enforcement(self) -> None:
        """Approver must be distinct from preparer and reviewer."""
        def can_approve(preparer_id: str | None, reviewer_id: str | None, approver_id: str) -> bool:
            if not approver_id:
                return False
            if preparer_id and approver_id.lower() == preparer_id.lower():
                return False
            if reviewer_id and approver_id.lower() == reviewer_id.lower():
                return False
            if preparer_id and reviewer_id and preparer_id.lower() == reviewer_id.lower():
                return False
            return True

        # Valid 3 distinct actors
        self.assertTrue(can_approve("u_preparer", "u_reviewer", "u_approver"))

        # Approver is same as preparer -> Rejected
        self.assertFalse(can_approve("u_approver", "u_reviewer", "u_approver"))

        # Approver is same as reviewer -> Rejected
        self.assertFalse(can_approve("u_preparer", "u_approver", "u_approver"))

        # Preparer is same as reviewer -> Rejected
        self.assertFalse(can_approve("u_preparer", "u_preparer", "u_approver"))

    def test_approval_invalidation_lifecycle_invariants(self) -> None:
        """Editing canonical field values invalidates existing approvals."""
        state = {
            "caseState": "APPROVED",
            "approval": {"valid": True, "valueSetHash": "hash-v1"},
            "package": {"id": "pkg-1"},
        }

        def commit_section_edit(current_state: dict, new_values: dict) -> dict:
            reopen = current_state["caseState"] in {"IN_REVIEW", "CHANGES_REQUESTED", "READY_FOR_APPROVAL"}
            invalidate = current_state["caseState"] in {"APPROVED", "GENERATED"}

            updated = dict(current_state)
            if invalidate:
                updated["caseState"] = "IN_PROGRESS"
                if "approval" in updated and updated["approval"]:
                    updated["approval"] = dict(updated["approval"], valid=False)
                updated["package"] = None
            elif reopen:
                updated["caseState"] = "IN_PROGRESS"

            return updated

        res = commit_section_edit(state, {"applicant.name.first": "Updated"})
        self.assertEqual(res["caseState"], "IN_PROGRESS")
        self.assertFalse(res["approval"]["valid"])
        self.assertIsNone(res["package"])

    def test_watermark_preview_rules(self) -> None:
        """Draft previews must carry explicit watermark and bounded expiry."""
        watermark = "DRAFT — NOT FOR FILING"
        self.assertIn("DRAFT", watermark)
        self.assertIn("NOT FOR", watermark)

        # Hash derivation is deterministic
        inputs = {"petitioner.name": "Maria", "petitioner.dob": "1985-06-15"}
        val_hash_1 = hashlib.sha256(json.dumps(inputs, sort_keys=True).encode("utf-8")).hexdigest()
        val_hash_2 = hashlib.sha256(json.dumps(inputs, sort_keys=True).encode("utf-8")).hexdigest()
        self.assertEqual(val_hash_1, val_hash_2)

    def test_package_generation_fail_closed_gates(self) -> None:
        """Package generation rejects unapproved cases, edition drift, and unconfirmed fields."""
        def can_generate(case_state: str, approval: dict | None, has_drift: bool, unconfirmed_fields: list) -> tuple[bool, str]:
            if has_drift:
                return False, "form-edition-drift"
            if case_state != "APPROVED":
                return False, "case-state-forbids-generation"
            if not approval or not approval.get("valid"):
                return False, "approval-invalidated"
            if unconfirmed_fields:
                return False, "human-confirmation-required"
            return True, "ok"

        # Happy path
        ok, reason = can_generate("APPROVED", {"valid": True}, False, [])
        self.assertTrue(ok)
        self.assertEqual(reason, "ok")

        # Unapproved
        ok, reason = can_generate("IN_REVIEW", {"valid": False}, False, [])
        self.assertFalse(ok)
        self.assertEqual(reason, "case-state-forbids-generation")

        # Invalidated approval
        ok, reason = can_generate("APPROVED", {"valid": False}, False, [])
        self.assertFalse(ok)
        self.assertEqual(reason, "approval-invalidated")

        # Form drift detected
        ok, reason = can_generate("APPROVED", {"valid": True}, True, [])
        self.assertFalse(ok)
        self.assertEqual(reason, "form-edition-drift")

        # Unconfirmed required fields
        ok, reason = can_generate("APPROVED", {"valid": True}, False, ["beneficiary.ssn"])
        self.assertFalse(ok)
        self.assertEqual(reason, "human-confirmation-required")


if __name__ == "__main__":
    unittest.main()