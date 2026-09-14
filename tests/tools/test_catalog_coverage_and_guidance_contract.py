"""Contract verification for full USCIS catalog coverage, library search, and official guidance (INF-06..09, APP-02, APP-03)."""

import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST_PATH = ROOT / "contracts" / "uscis-official-manifest.json"
GUIDANCE_PATH = ROOT / "contracts" / "uscis-official-guidance.json"
GUIDANCE_SCHEMA_PATH = ROOT / "contracts" / "schemas" / "document-guidance.schema.json"
OPENAPI_PATH = ROOT / "contracts" / "openapi" / "document-library.yaml"
STUB_STORAGE_PATH = ROOT / "apps" / "packages" / "ApertureKit" / "Sources" / "ApertureAPI" / "StubStorage.swift"
STUB_API_PATH = ROOT / "apps" / "packages" / "ApertureKit" / "Sources" / "ApertureAPI" / "StubAPIClient.swift"
DOC_LIBRARY_PATH = ROOT / "apps" / "packages" / "ApertureKit" / "Sources" / "ApertureDomain" / "DocumentLibrary.swift"


class TestCatalogCoverageAndGuidanceContract(unittest.TestCase):
    def test_uscis_manifest_inventory(self):
        self.assertTrue(MANIFEST_PATH.is_file(), f"Manifest missing at {MANIFEST_PATH}")
        with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
            manifest = json.load(f)

        forms = manifest.get("forms", [])
        self.assertEqual(len(forms), 117, f"Expected exactly 117 USCIS forms, got {len(forms)}")

        series_counts = {"I": 0, "N": 0, "G": 0, "OTHER": 0}
        capability_counts = {"FILLABLE_PDF": 0, "STATIC_ASSISTED": 0, "EXTERNAL_REFERENCE": 0}

        for f in forms:
            s = f.get("series")
            self.assertIn(s, series_counts, f"Unexpected series '{s}' for form {f.get('formId')}")
            series_counts[s] += 1

            cap = f.get("preparationCapability")
            self.assertIn(cap, capability_counts, f"Unexpected capability '{cap}' for form {f.get('formId')}")
            capability_counts[cap] += 1

            # Verification of URLs
            self.assertTrue(f.get("sourceUrl", "").startswith("https://"), f"Non-https source URL for {f.get('formId')}")

        self.assertEqual(series_counts["I"], 91)
        self.assertEqual(series_counts["N"], 10)
        self.assertEqual(series_counts["G"], 14)
        self.assertEqual(series_counts["OTHER"], 2)

        # Preserved definitions
        preserved = manifest.get("preservedNonUscisDefinitions", [])
        self.assertEqual(len(preserved), 4)
        doc_ids = {p.get("documentId") for p in preserved}
        self.assertEqual(doc_ids, {"DS-11", "FAFSA", "CLINIC-INTAKE", "SCHOLARSHIP-APP"})

    def test_official_guidance_dataset_and_zero_fee_guessing(self):
        self.assertTrue(GUIDANCE_PATH.is_file(), f"Guidance missing at {GUIDANCE_PATH}")
        self.assertTrue(GUIDANCE_SCHEMA_PATH.is_file(), f"Guidance schema missing at {GUIDANCE_SCHEMA_PATH}")

        with open(GUIDANCE_PATH, "r", encoding="utf-8") as f:
            guidance_data = json.load(f)

        entries = guidance_data.get("guidance", [])
        self.assertEqual(len(entries), 121, f"Expected 121 guidance entries (117 forms + 4 non-USCIS), got {len(entries)}")

        seen_forms = set()
        for g in entries:
            fid = g.get("formId")
            self.assertNotIn(fid, seen_forms, f"Duplicate guidance entry: {fid}")
            seen_forms.add(fid)

            # Check instructions URL and citation URL
            self.assertTrue(g.get("officialInstructionsUrl", "").startswith("https://"))
            self.assertTrue(g.get("feeScheduleCitationUrl", "").startswith("https://"))

            # Zero fee guessing check
            cents = g.get("feeUsdCents")
            fee_notes = g.get("feeNotes", "")
            if cents is None:
                if g.get("authority") == "USCIS":
                    self.assertTrue(
                        "G-1055" in fee_notes or "free" in fee_notes.lower() or "0" in fee_notes,
                        f"USCIS form {fid} with null fee missing G-1055 citation",
                    )
            else:
                self.assertIsInstance(cents, int)
                self.assertGreater(cents, 0)

            # Evidence checklist separation
            evidence = g.get("evidenceChecklist")
            self.assertIsInstance(evidence, list)
            self.assertGreater(len(evidence), 0)

        # Spot check statutory fee for I-130: $675 -> 67500 cents
        i130_entry = next((e for e in entries if e["formId"] == "I-130"), None)
        self.assertIsNotNone(i130_entry)
        self.assertEqual(i130_entry["feeUsdCents"], 67500)

        # Spot check zero fee guessing for N-400: variable -> null
        n400_entry = next((e for e in entries if e["formId"] == "N-400"), None)
        self.assertIsNotNone(n400_entry)
        self.assertIsNone(n400_entry["feeUsdCents"])
        self.assertIn("G-1055", n400_entry["feeNotes"])

    def test_openapi_guidance_endpoint_contract(self):
        self.assertTrue(OPENAPI_PATH.is_file(), f"OpenAPI missing at {OPENAPI_PATH}")
        openapi_text = OPENAPI_PATH.read_text(encoding="utf-8")
        self.assertIn("/blueprints/{namespace}/{blueprintId}/guidance", openapi_text)
        self.assertIn("DocumentGuidance:", openapi_text)

    def test_swift_models_and_stub_coverage(self):
        # Verify DocumentGuidance struct
        doc_lib_text = DOC_LIBRARY_PATH.read_text(encoding="utf-8")
        self.assertIn("public struct DocumentGuidance", doc_lib_text)
        self.assertIn("public let officialInstructionsUrl: URL?", doc_lib_text)
        self.assertIn("public let feeScheduleCitationUrl: URL?", doc_lib_text)
        self.assertIn("public let feeUsdCents: Int?", doc_lib_text)

        # Verify StubStorage manifest and guidance loading
        stub_storage_text = STUB_STORAGE_PATH.read_text(encoding="utf-8")
        self.assertIn("loadManifestBlueprints", stub_storage_text)
        self.assertIn("loadGuidance", stub_storage_text)
        self.assertIn("var guidance: [String: DocumentGuidance]?", stub_storage_text)

        # Verify StubAPIClient library query and guidance
        stub_api_text = STUB_API_PATH.read_text(encoding="utf-8")
        self.assertIn("func libraryBlueprints(tenantID: String?, query: String? = nil)", stub_api_text)
        self.assertIn("func documentGuidance(namespace: String, id: String)", stub_api_text)


if __name__ == "__main__":
    unittest.main()
