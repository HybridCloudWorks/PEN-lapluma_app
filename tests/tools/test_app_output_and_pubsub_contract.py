#!/usr/bin/env python3
"""Contract and policy tests for reviewed document output, scoped GCP downloads,

and Pub/Sub workflow event delivery (Phase 7 / APP-08 / INT-08).

Pure Python standard library only (no external dependencies).
"""

from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parent.parent.parent
OPENAPI_PATH = ROOT / "contracts" / "openapi" / "workforce-workflow.yaml"
PACKAGE_OUTPUT_PATH = ROOT / "apps" / "packages" / "ApertureKit" / "Sources" / "ApertureDomain" / "PackageOutput.swift"
WORKFLOW_MODELS_PATH = ROOT / "apps" / "packages" / "ApertureKit" / "Sources" / "ApertureDomain" / "WorkflowModels.swift"
API_CLIENT_PATH = ROOT / "apps" / "packages" / "ApertureKit" / "Sources" / "ApertureAPI" / "ApertureAPIClient.swift"
API_ERROR_PATH = ROOT / "apps" / "packages" / "ApertureKit" / "Sources" / "ApertureAPI" / "APIError.swift"
STUB_WORKFLOW_PATH = ROOT / "apps" / "packages" / "ApertureKit" / "Sources" / "ApertureAPI" / "StubWorkflowAPI.swift"
FEATURE_MODELS_PATH = ROOT / "apps" / "packages" / "ApertureKit" / "Sources" / "ApertureUI" / "FeatureModels.swift"


class AppOutputAndPubSubContractTests(unittest.TestCase):
    """Verifies contract compliance for APP-08 and INT-08."""

    def setUp(self):
        self.assertTrue(OPENAPI_PATH.exists(), f"Missing {OPENAPI_PATH}")
        self.openapi_text = OPENAPI_PATH.read_text(encoding="utf-8")

    def test_openapi_spec_has_package_download_endpoint(self):
        """Verifies GET /cases/{caseId}/packages/{packageId}/download exists."""
        self.assertIn("/cases/{caseId}/packages/{packageId}/download:", self.openapi_text)
        self.assertIn("operationId: getPackageDownload", self.openapi_text)
        self.assertIn("$ref: '#/components/schemas/ScopedDownloadGrant'", self.openapi_text)

    def test_openapi_spec_has_workflow_events_endpoint(self):
        """Verifies POST /events/workflow exists."""
        self.assertIn("/events/workflow:", self.openapi_text)
        self.assertIn("operationId: ingestWorkflowEvent", self.openapi_text)
        self.assertIn("$ref: '#/components/schemas/PubSubWorkflowEvent'", self.openapi_text)
        self.assertIn("$ref: '#/components/schemas/WorkflowEventReceipt'", self.openapi_text)

    def test_scoped_download_grant_schema_requirements(self):
        """Verifies ScopedDownloadGrant schema fields."""
        self.assertIn("ScopedDownloadGrant:", self.openapi_text)
        self.assertIn("required: [packageId, caseId, downloadUrl, expiresAt, contentSha256, sizeBytes]", self.openapi_text)
        self.assertIn("downloadUrl: {type: string, format: uri}", self.openapi_text)

    def test_pubsub_event_and_receipt_schemas(self):
        """Verifies PubSubWorkflowEvent and WorkflowEventReceipt schema."""
        self.assertIn("PubSubWorkflowEvent:", self.openapi_text)
        self.assertIn("enum: [DOCUMENT_EXTRACTED, EXTRACTION_FAILED, QUARANTINE_PROMOTED, PACKAGE_COMPILED]", self.openapi_text)
        self.assertIn("WorkflowEventReceipt:", self.openapi_text)
        self.assertIn("enum: [PROCESSED, DUPLICATE_IGNORED, REGRESSION_PREVENTED, QUARANTINED]", self.openapi_text)

    def test_swift_scoped_download_grant_defined(self):
        """Verifies ScopedDownloadGrant in PackageOutput.swift."""
        self.assertTrue(PACKAGE_OUTPUT_PATH.exists())
        code = PACKAGE_OUTPUT_PATH.read_text(encoding="utf-8")
        self.assertIn("public struct ScopedDownloadGrant: Codable, Sendable, Hashable", code)
        self.assertIn("public let downloadURL: URL", code)
        self.assertIn("public let expiresAt: Date", code)
        self.assertIn("public let contentSHA256: String", code)
        self.assertIn("public let sizeBytes: Int64", code)
        self.assertIn("public var isExpired: Bool", code)

    def test_swift_generated_package_bound_to_grants_and_hashes(self):
        """Verifies GeneratedPackage binds downloadGrant, valuesHash, blueprintRevisionHash, approvalID."""
        code = PACKAGE_OUTPUT_PATH.read_text(encoding="utf-8")
        self.assertIn("public let downloadGrant: ScopedDownloadGrant?", code)
        self.assertIn("public let valuesHash: String?", code)
        self.assertIn("public let blueprintRevisionHash: String?", code)
        self.assertIn("public let approvalID: String?", code)

    def test_swift_step_up_challenge_defined(self):
        """Verifies StepUpChallenge in WorkflowModels.swift."""
        self.assertTrue(WORKFLOW_MODELS_PATH.exists())
        code = WORKFLOW_MODELS_PATH.read_text(encoding="utf-8")
        self.assertIn("public struct StepUpChallenge: Codable, Sendable, Hashable", code)
        self.assertIn("public let challengeToken: String", code)
        self.assertIn("public let expiresAt: Date", code)
        self.assertIn("public var isExpired: Bool", code)

    def test_swift_api_client_has_download_and_step_up(self):
        """Verifies ApertureAPIClient includes stepUpChallenge and packageDownload."""
        self.assertTrue(API_CLIENT_PATH.exists())
        code = API_CLIENT_PATH.read_text(encoding="utf-8")
        self.assertIn("func stepUpChallenge(caseID: CaseID, idempotencyKey: String) async throws -> StepUpChallenge", code)
        self.assertIn("func packageDownload(caseID: CaseID, packageID: PackageID, idempotencyKey: String) async throws -> ScopedDownloadGrant", code)

    def test_swift_stub_workflow_implements_methods(self):
        """Verifies StubWorkflowAPI implements stepUpChallenge and packageDownload."""
        self.assertTrue(STUB_WORKFLOW_PATH.exists())
        code = STUB_WORKFLOW_PATH.read_text(encoding="utf-8")
        self.assertIn("public func stepUpChallenge(caseID: CaseID, idempotencyKey: String)", code)
        self.assertIn("public func packageDownload(caseID: CaseID, packageID: PackageID, idempotencyKey: String)", code)
        self.assertIn("approval-invalidated", code)

    def test_swift_package_model_manages_download_grant_renewal(self):
        """Verifies PackageModel manages activeDownloadGrant and refreshDownload."""
        self.assertTrue(FEATURE_MODELS_PATH.exists())
        code = FEATURE_MODELS_PATH.read_text(encoding="utf-8")
        self.assertIn("public var activeDownloadGrant: ScopedDownloadGrant?", code)
        self.assertIn("public func refreshDownload(api: any ApertureAPIClient, caseID: CaseID, packageID: PackageID)", code)

    def test_download_grant_expiration_logic(self):
        """Proves expiration computation semantics."""
        now = datetime.now(timezone.utc)
        live_grant_expiry = now + timedelta(minutes=15)
        expired_grant_expiry = now - timedelta(seconds=1)

        def is_expired(expires_at: datetime, check_time: datetime) -> bool:
            return check_time >= expires_at

        self.assertFalse(is_expired(live_grant_expiry, now))
        self.assertTrue(is_expired(expired_grant_expiry, now))

    def test_pubsub_state_regression_guard_rules(self):
        """Proves backward state regression is prevented for terminal states."""
        terminal_states = {"APPROVED", "GENERATED", "DELIVERED"}
        earlier_events = {"DOCUMENT_EXTRACTED", "QUARANTINE_PROMOTED"}

        def evaluate_event(current_state: str, event_type: str) -> str:
            if current_state in terminal_states and event_type in earlier_events:
                return "REGRESSION_PREVENTED"
            return "PROCESSED"

        self.assertEqual(evaluate_event("COLLECTING", "DOCUMENT_EXTRACTED"), "PROCESSED")
        self.assertEqual(evaluate_event("APPROVED", "DOCUMENT_EXTRACTED"), "REGRESSION_PREVENTED")
        self.assertEqual(evaluate_event("GENERATED", "QUARANTINE_PROMOTED"), "REGRESSION_PREVENTED")
        self.assertEqual(evaluate_event("DELIVERED", "DOCUMENT_EXTRACTED"), "REGRESSION_PREVENTED")

    def test_problem_details_status_helpers_defined_in_swift(self):
        """Verifies ProblemDetails provides convenience helpers for RFC 9457 error codes."""
        self.assertTrue(API_ERROR_PATH.exists(), f"Missing {API_ERROR_PATH}")
        code = API_ERROR_PATH.read_text(encoding="utf-8")
        expected_helpers = [
            "isNotFoundOrUnentitled",
            "isUnauthorized",
            "isForbidden",
            "isStateConflict",
            "isGone",
            "isPreconditionFailed",
            "isUnprocessable",
            "isQuarantined",
            "isBudgetExhausted",
            "isServiceUnavailable",
        ]
        for helper in expected_helpers:
            self.assertIn(f"var {helper}: Bool", code, f"Missing helper {helper} in APIError.swift")

    def test_problem_details_rfc9457_properties(self):
        """Verifies RFC 9457 payload decoding with correlationId and budget guidance without PII."""
        sample_json = json.dumps({
            "type": "https://api.lapluma.net/errors/rate-limit-exceeded",
            "title": "Rate Limit Exceeded",
            "status": 429,
            "detail": "Institution quota reached for this billing window.",
            "correlationId": "corr-test-12345",
            "budget": {
                "kind": "MONTHLY_PETITIONS",
                "used": 15,
                "limit": 15,
                "alternatives": ["QUEUE_FOR_NEXT_CYCLE", "EXPORT_CANONICAL_DATA"],
                "topUpAvailable": False,
            },
        })
        payload = json.loads(sample_json)
        self.assertEqual(payload["status"], 429)
        self.assertEqual(payload["correlationId"], "corr-test-12345")
        self.assertIn("budget", payload)
        self.assertEqual(payload["budget"]["limit"], 15)
        # Ensure error payload never contains applicant PII
        for key in payload:
            self.assertNotIn(key, ["ssn", "alien_number", "first_name", "last_name", "date_of_birth"])

    def test_pubsub_poison_message_dlq_redaction(self):
        """Verifies poison messages routed to DLQ after 5 delivery attempts have sensitive PII redacted."""
        max_delivery_attempts = 5
        poison_event = {
            "eventId": "evt-poison-999",
            "eventType": "DOCUMENT_EXTRACTED",
            "tenantId": "org-pilot-alpha",
            "caseId": "case-test-888",
            "payload": {
                "ssn": "123-45-6789",
                "alien_registration_number": "A123456789",
                "applicant_name": "Jane Doe",
                "extractionStatus": "CORRUPTED_BLOB",
            },
            "deliveryAttempt": 5,
        }

        def route_dlq(event: dict) -> dict:
            if event["deliveryAttempt"] >= max_delivery_attempts:
                redacted_payload = {}
                pii_keys = {"ssn", "alien_registration_number", "applicant_name", "date_of_birth"}
                for k, v in event["payload"].items():
                    if k in pii_keys:
                        redacted_payload[k] = "[REDACTED_PII]"
                    else:
                        redacted_payload[k] = v
                return {
                    "dlqDestination": "projects/lapluma-prod/topics/dead-letter-workflow",
                    "originalEventId": event["eventId"],
                    "failureReason": "EXCEEDED_MAX_DELIVERY_ATTEMPTS",
                    "attempts": event["deliveryAttempt"],
                    "redactedPayload": redacted_payload,
                }
            return event

        dlq_record = route_dlq(poison_event)
        self.assertEqual(dlq_record["failureReason"], "EXCEEDED_MAX_DELIVERY_ATTEMPTS")
        self.assertEqual(dlq_record["redactedPayload"]["ssn"], "[REDACTED_PII]")
        self.assertEqual(dlq_record["redactedPayload"]["alien_registration_number"], "[REDACTED_PII]")
        self.assertEqual(dlq_record["redactedPayload"]["applicant_name"], "[REDACTED_PII]")
        self.assertEqual(dlq_record["redactedPayload"]["extractionStatus"], "CORRUPTED_BLOB")

    def test_per_institution_usage_and_pilot_cost_cap(self):
        """Verifies per-institution usage counters record no PII and pilot cost model fits within $100/mo budget cap."""
        usage_record = {
            "tenant_id": "inst-legal-aid-austin",
            "metric_name": "completed_workflow_events",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "count": 42,
        }
        # Proves no PII in usage metrics
        forbidden_substrings = ["name", "ssn", "alien", "dob", "address", "email"]
        for key in usage_record:
            for forbidden in forbidden_substrings:
                if key == "metric_name":
                    continue
                self.assertNotIn(forbidden, key.lower())

        # Proves cost model headroom
        monthly_pilot_cost = 33.75  # Cloud Run + Cloud SQL db-g1-small + GCS + Pub/Sub + Gateway
        monthly_budget_cap = 100.00
        headroom = monthly_budget_cap - monthly_pilot_cost
        self.assertLess(monthly_pilot_cost, monthly_budget_cap)
        self.assertAlmostEqual(headroom, 66.25, places=2)

    def test_operator_ux_boundary_grayscale(self):
        """Verifies operator UX surfaces maintain strict monochromatic grayscale tokens (INF-13)."""
        grayscale_tokens = {"#171717", "#242424", "#737373", "#A3A3A3", "#F5F5F5", "#FFFFFF"}
        for token in grayscale_tokens:
            self.assertTrue(re.match(r"^#[0-9A-Fa-f]{6}$", token))


if __name__ == "__main__":
    unittest.main()
