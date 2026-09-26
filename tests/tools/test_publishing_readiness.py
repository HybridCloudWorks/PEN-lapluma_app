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
        self.assertEqual(data.get("theme", {}).get("name"), "Mercury")


if __name__ == "__main__":
    unittest.main()
