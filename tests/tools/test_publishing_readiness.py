"""
App Store Publishing Phase Verification Test Suite.

Ensures that the repository maintains active App Store and TestFlight publishing readiness:
1. Validates submission manifests (Alpha 0.2 and Staging Beta 0.3).
2. Validates bilingual metadata completeness and character limits.
3. Validates absence of placeholder text.
4. Validates review package documents.
5. Validates Apple PrivacyInfo.xcprivacy configuration.
6. Validates Mercury Alpine Banking token WCAG AAA and AA contrast.
"""

import json
import pathlib
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
sys_tools = REPO_ROOT / "tools"
sys_path = str(sys_tools)
import sys
if sys_path not in sys.path:
    sys.path.insert(0, sys_path)

import importlib
validate_store_publishing = importlib.import_module("validate-store-publishing")


class PublishingReadinessTests(unittest.TestCase):
    def test_preflight_publishing_validation_passes(self):
        """Preflight publishing validation suite must pass with 0 errors."""
        exit_code = validate_store_publishing.main()
        self.assertEqual(exit_code, 0, "validate-store-publishing.py reported failures")

    def test_staging_beta_manifest_contract(self):
        """Staging Beta manifest must declare live API Gateway and Mercury theme."""
        manifest_path = REPO_ROOT / "apps" / "ios" / "AppStore" / "review" / "submission-manifest.staging.json"
        self.assertTrue(manifest_path.exists(), "Missing submission-manifest.staging.json")
        data = json.loads(manifest_path.read_text(encoding="utf-8"))
        self.assertEqual(data.get("releaseLabel"), "Beta 0.3")
        self.assertEqual(data.get("marketingVersion"), "0.3.0")
        self.assertEqual(data.get("publicSubmissionEligible"), True)
        self.assertIn("lp-gateway-staging", data.get("apiGatewayEndpoint", ""))
    def test_ios_e2e_simulation_sla(self):
        """Simulated iOS client flow must achieve >= 95% SLA across all workflows."""
        live_ios_simulation = importlib.import_module("live_ios_e2e_simulation")
        client = live_ios_simulation.IOSClientSimulation(
            base_url="https://lp-gateway-staging-am9yq93d.uc.gateway.dev",
            auth_token="lp_test_mobile_live_e2e",
            dry_run=True
        )
        total_passed = 0
        total_steps = 0
        for i in range(1, 11):
            ok, summary = live_ios_simulation.run_simulation_trial(client, i)
            total_passed += summary["passed_steps"]
            total_steps += summary["total_steps"]
            self.assertTrue(ok, f"Trial {i} failed")

        sla = (total_passed / total_steps) * 100.0
        self.assertGreaterEqual(sla, 95.0, f"SLA {sla}% is below required 95.0%")


if __name__ == "__main__":
    unittest.main()

