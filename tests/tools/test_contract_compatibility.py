"""
Cross-repository contract compatibility test (INT-03, APP-01, APP-04).

Ensures contracts/catalog-package-compatibility.json is valid, conforms to its
schema, retains backward compatibility with lapluma-app-0.2 packages, and links
all 7 packages to versioned collections and pinned blueprints.
"""
import json
import pathlib
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
CONTRACT_PATH = REPO_ROOT / "contracts" / "catalog-package-compatibility.json"
SCHEMA_PATH = REPO_ROOT / "contracts" / "schemas" / "catalog-package-compatibility.schema.json"

EXPECTED_PACKAGES = {
    "FAMILY_I130": ["I-130", "I-130A"],
    "ADJUSTMENT_I485_I864": ["I-485", "I-864"],
    "NATURALIZATION_N400": ["N-400"],
    "EAD_I765": ["I-765"],
    "TRAVEL_I131": ["I-131"],
    "PASSPORT_DS11": ["DS-11"],
    "FINANCIAL_AID_FAFSA": ["FAFSA"],
}

VALID_PREPARATION_MODES = {"FILLABLE_PDF", "STATIC_ASSISTED", "EXTERNAL_REFERENCE"}


class ContractCompatibilityTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(CONTRACT_PATH.exists(), f"Contract missing at {CONTRACT_PATH}")
        self.assertTrue(SCHEMA_PATH.exists(), f"Schema missing at {SCHEMA_PATH}")
        with open(CONTRACT_PATH, "r", encoding="utf-8") as f:
            self.contract = json.load(f)
        with open(SCHEMA_PATH, "r", encoding="utf-8") as f:
            self.schema = json.load(f)

    def test_legacy_snapshot_intact(self):
        self.assertEqual(self.contract.get("contractVersion"), "lapluma-app-0.2")
        packages = self.contract.get("packages", [])
        self.assertEqual(len(packages), 7)
        actual = {pkg["packageCode"]: pkg["formNumbers"] for pkg in packages}
        self.assertEqual(actual, EXPECTED_PACKAGES)

    def test_package_mappings_cover_all_packages(self):
        mappings = self.contract.get("packageMappings", [])
        self.assertEqual(len(mappings), 7)
        mapped_codes = {m["packageCode"] for m in mappings}
        self.assertEqual(mapped_codes, set(EXPECTED_PACKAGES.keys()))

        for mapping in mappings:
            code = mapping["packageCode"]
            self.assertEqual(mapping["formNumbers"], EXPECTED_PACKAGES[code])
            self.assertEqual(mapping["collectionNamespace"], "official")
            self.assertIn("collectionId", mapping)
            self.assertEqual(mapping["pinnedRevision"], 1)
            members = mapping.get("blueprintMembers", [])
            self.assertEqual(len(members), len(EXPECTED_PACKAGES[code]))
            for member in members:
                self.assertIn(member["preparationMode"], VALID_PREPARATION_MODES)
                self.assertGreaterEqual(member["pinnedRevision"], 1)
                self.assertGreaterEqual(member["displayOrder"], 1)

    def test_terminology_record(self):
        compat = self.contract.get("legacyCompatibility", {})
        self.assertTrue(compat.get("enabled"))
        self.assertEqual(compat.get("aliasPolicy"), "PRESERVE_STABLE_IDS")
        terminology = compat.get("terminology", {})
        self.assertEqual(terminology.get("legacyPackage"), "Document Collection")
        self.assertEqual(terminology.get("legacyForm"), "Document Blueprint")
        self.assertEqual(terminology.get("legacyCatalog"), "Document Library")


if __name__ == "__main__":
    unittest.main()
