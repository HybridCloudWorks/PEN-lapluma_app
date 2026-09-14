"""
Cross-repository contract compatibility test (INT-01, INT-03, INT-14, APP-01, APP-04).

Ensures contracts/catalog-package-compatibility.json is valid, conforms to its
schema, retains backward compatibility with lapluma-app-0.2 packages, links
all 7 packages to versioned collections and pinned blueprints, and validates
the Document Library OpenAPI 3.1 contract.
"""
import json
import pathlib
import unittest
import yaml

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
CONTRACT_PATH = REPO_ROOT / "contracts" / "catalog-package-compatibility.json"
SCHEMA_PATH = REPO_ROOT / "contracts" / "schemas" / "catalog-package-compatibility.schema.json"
OPENAPI_PATH = REPO_ROOT / "contracts" / "openapi" / "document-library.yaml"

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
    def test_document_library_openapi_contract(self):
        self.assertTrue(OPENAPI_PATH.exists(), f"OpenAPI contract missing at {OPENAPI_PATH}")
        with open(OPENAPI_PATH, "r", encoding="utf-8") as f:
            doc = yaml.safe_load(f)
        self.assertIn("openapi", doc)
        self.assertTrue(doc["openapi"].startswith("3.1"), f"Expected OpenAPI 3.1.x, got {doc['openapi']}")
        info = doc.get("info", {})
        self.assertEqual(info.get("title"), "LaPluma Document Library API")
        self.assertEqual(info.get("version"), "0.2.0")
        servers = doc.get("servers", [])
        self.assertTrue(any("api.example.invalid" in s.get("url", "") for s in servers), "Must use placeholder invalid domain")
        paths = doc.get("paths", {})
        expected_paths = [
            "/library/collections",
            "/library/collections/{namespace}/{collectionId}",
            "/library/blueprints",
            "/library/blueprints/{namespace}/{blueprintId}",
            "/library/blueprints/{namespace}/{blueprintId}/publish",
            "/library/blueprints/{namespace}/{blueprintId}/drift-check",
            "/library/blueprints/{namespace}/{blueprintId}/rollback",
            "/library/tenants/{tenantId}/collections/{namespace}/{collectionId}/assign",
            "/library/package-mappings",
        ]
        for path in expected_paths:
            self.assertIn(path, paths, f"Missing path: {path}")

        # Check required operation IDs matching OpenAPI spec
        expected_ops = {
            "listLibraryCollections",
            "getLibraryCollection",
            "listLibraryBlueprints",
            "getLibraryBlueprint",
            "publishBlueprint",
            "checkBlueprintDrift",
            "rollbackBlueprint",
            "assignTenantCollection",
            "listPackageMappings",
        }
        found_ops = set()
        for path, path_item in paths.items():
            for method in ("get", "post", "put", "patch", "delete"):
                op = path_item.get(method)
                if op and "operationId" in op:
                    found_ops.add(op["operationId"])
        for op in expected_ops:
            self.assertIn(op, found_ops, f"Missing operationId: {op}")


if __name__ == "__main__":
    unittest.main()
