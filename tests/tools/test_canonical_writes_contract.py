"""Contract and invariant tests for Canonical Case Writes, Section Commits, Conflicts & Approval Invalidation (INT-04).

Validates:
1. OpenAPI specification contract alignment for section commits, If-Match, IdempotencyKey, and 412 responses.
2. Swift domain model wire-name alignment (SectionCommit, FormSection, revision, reopenedReview, invalidatedApproval).
3. Optimistic concurrency and version conflict (412 PreconditionFailed) simulation.
4. Idempotency replay (200 with identical cached response) vs conflict (409 with mutated payload).
5. Review reopening and approval invalidation state-machine transitions.

Pure Python standard library only.
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
SWIFT_STUB_API_PATH = (
    REPO_ROOT / "apps/packages/ApertureKit/Sources/ApertureAPI/StubWorkflowAPI.swift"
)


class CanonicalCaseWritesContractTests(unittest.TestCase):
    def test_workflow_openapi_contract_defines_section_commit(self) -> None:
        self.assertTrue(WORKFLOW_CONTRACT_PATH.exists(), "workforce-workflow.yaml must exist")
        content = WORKFLOW_CONTRACT_PATH.read_text(encoding="utf-8")

        self.assertIn("/cases/{caseId}/sections/{sectionId}/commit:", content)
        self.assertIn("operationId: commitCanonicalSection", content)
        self.assertIn("If-Match", content)
        self.assertIn("IdempotencyKey", content)
        self.assertIn("'412': {description: Version conflict}", content)

    def test_swift_workflow_models_align_with_contract(self) -> None:
        self.assertTrue(SWIFT_WORKFLOW_MODELS_PATH.exists())
        swift_content = SWIFT_WORKFLOW_MODELS_PATH.read_text(encoding="utf-8")

        # Verify SectionCommit struct and fields
        self.assertIn("public struct SectionCommit: Codable, Sendable, Hashable", swift_content)
        self.assertIn("public let section: FormSection", swift_content)
        self.assertIn("public let reopenedReview: Bool", swift_content)
        self.assertIn("public let invalidatedApproval: Bool", swift_content)

        # Verify FormSection struct has revision
        self.assertIn("public struct FormSection: Identifiable, Codable, Sendable, Hashable", swift_content)
        self.assertIn("public let revision: Int", swift_content)

    def test_stub_workflow_api_enforces_concurrency_and_invalidation(self) -> None:
        self.assertTrue(SWIFT_STUB_API_PATH.exists())
        stub_content = SWIFT_STUB_API_PATH.read_text(encoding="utf-8")

        # Verify commitSection method exists and checks revision
        self.assertIn("func commitSection(", stub_content)
        self.assertIn("guard revision == baseRevision else", stub_content)
        self.assertIn("status: 412", stub_content)
        self.assertIn("version-conflict", stub_content)
        self.assertIn("SectionCommit(section: section, reopenedReview: reopen, invalidatedApproval: invalidate)", stub_content)

    def test_optimistic_concurrency_and_version_conflict_semantics(self) -> None:
        """Stale revision produces 412 PreconditionFailed."""
        class SectionCommitHandler:
            def __init__(self, current_revision: int):
                self.current_revision = current_revision

            def commit(self, base_revision: int, if_match: int | None) -> tuple[int, dict]:
                target_rev = if_match if if_match is not None else base_revision
                if target_rev != self.current_revision:
                    return 412, {
                        "type": "urn:lapluma:problem:version-conflict",
                        "title": "This section changed on another device",
                        "status": 412,
                    }
                self.current_revision += 1
                return 200, {
                    "section": {"id": "identity", "revision": self.current_revision},
                    "reopenedReview": False,
                    "invalidatedApproval": False,
                }

        handler = SectionCommitHandler(current_revision=2)

        # Stale revision 1 -> 412
        status, body = handler.commit(base_revision=1, if_match=None)
        self.assertEqual(status, 412)
        self.assertEqual(body["type"], "urn:lapluma:problem:version-conflict")

        # If-Match overrides baseRevision
        status, body = handler.commit(base_revision=1, if_match=2)
        self.assertEqual(status, 200)
        self.assertEqual(body["section"]["revision"], 3)

    def test_idempotency_replay_and_conflict_semantics(self) -> None:
        """Identical payload replays 200; mutated payload with same key returns 409."""
        class IdempotentCommitTracker:
            def __init__(self):
                self.seen_keys: dict[str, tuple[str, dict]] = {}

            def commit(self, key: str, payload: dict) -> tuple[int, dict]:
                payload_hash = hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()
                if key in self.seen_keys:
                    prev_hash, prev_result = self.seen_keys[key]
                    if prev_hash == payload_hash:
                        return 200, prev_result
                    return 409, {
                        "type": "urn:lapluma:problem:idempotency-key-conflict",
                        "title": "Idempotency key was already used with a different payload",
                        "status": 409,
                    }

                result = {"section": {"id": "identity", "revision": 2}, "reopenedReview": False, "invalidatedApproval": False}
                self.seen_keys[key] = (payload_hash, result)
                return 200, result

        tracker = IdempotentCommitTracker()
        key = "idemp-key-12345"

        # First commit
        status1, body1 = tracker.commit(key, {"first_name": "Maria"})
        self.assertEqual(status1, 200)

        # Replay with same payload
        status2, body2 = tracker.commit(key, {"first_name": "Maria"})
        self.assertEqual(status2, 200)
        self.assertEqual(body1, body2)

        # Replay with mutated payload
        status3, body3 = tracker.commit(key, {"first_name": "Elena"})
        self.assertEqual(status3, 409)
        self.assertEqual(body3["type"], "urn:lapluma:problem:idempotency-key-conflict")

    def test_review_reopen_and_approval_invalidation_semantics(self) -> None:
        """Section commits reopen reviews in reviewable states, and invalidate approvals in approved states."""
        def evaluate_commit_effects(case_state: str) -> tuple[bool, bool, str]:
            reopen = case_state in {"IN_REVIEW", "CHANGES_REQUESTED", "READY_FOR_APPROVAL"}
            invalidate = case_state in {"APPROVED", "GENERATED", "DELIVERED"}
            new_state = "IN_PROGRESS" if (reopen or invalidate) else case_state
            return reopen, invalidate, new_state

        # Case in review -> Reopened to IN_PROGRESS, not invalidated
        reopen, invalidate, new_state = evaluate_commit_effects("IN_REVIEW")
        self.assertTrue(reopen)
        self.assertFalse(invalidate)
        self.assertEqual(new_state, "IN_PROGRESS")

        # Case approved -> Invalidates approval, resets to IN_PROGRESS
        reopen, invalidate, new_state = evaluate_commit_effects("APPROVED")
        self.assertFalse(reopen)
        self.assertTrue(invalidate)
        self.assertEqual(new_state, "IN_PROGRESS")

        # Case intake -> Neither reopen nor invalidate
        reopen, invalidate, new_state = evaluate_commit_effects("INTAKE")
        self.assertFalse(reopen)
        self.assertFalse(invalidate)
        self.assertEqual(new_state, "INTAKE")


if __name__ == "__main__":
    unittest.main()
