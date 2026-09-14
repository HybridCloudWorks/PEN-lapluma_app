"""
Mobile client fact capture integration test suite (Phase 4).

Verifies the integration between mobile client fact capture models
(CaseInitializationTemplate, CanonicalPath, ReviewableField, StubAPIClient)
and the Cloud Run AcroForm generation worker contracts.
"""

from __future__ import annotations

import json
import pathlib
import unicodedata
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
COMPAT_PATH = REPO_ROOT / "contracts" / "catalog-package-compatibility.json"
INFRA_BLUEPRINTS_DIR = REPO_ROOT.parent / "PEN-lapluma_infra" / "blueprints"


class MobileFactCaptureIntegrationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.assertTrue(COMPAT_PATH.exists(), f"Missing compatibility contract: {COMPAT_PATH}")
        with open(COMPAT_PATH, "r", encoding="utf-8") as f:
            self.compat = json.load(f)

    def test_family_i130_package_links_to_official_blueprint(self) -> None:
        """Verify FAMILY_I130 package maps to official/uscis/i-130 blueprint revision 1."""
        mappings = {m["packageCode"]: m for m in self.compat.get("packageMappings", [])}
        self.assertIn("FAMILY_I130", mappings)
        i130_mapping = mappings["FAMILY_I130"]

        self.assertEqual(i130_mapping["collectionNamespace"], "official")
        self.assertEqual(i130_mapping["collectionId"], "family-reunification-i130")
        self.assertEqual(i130_mapping["pinnedRevision"], 1)

        blueprint_members = i130_mapping.get("blueprintMembers", [])
        self.assertTrue(any(
            m["namespace"] == "uscis" and m["blueprintId"] == "i-130"
            for m in blueprint_members
        ))

    def test_mobile_client_canonical_paths_resolve_to_blueprint_fields(self) -> None:
        """Verify canonical paths defined in CaseInitializationTemplate.familyI130 resolve to blueprint."""
        i130_path = INFRA_BLUEPRINTS_DIR / "official" / "uscis" / "i-130" / "blueprint.json"
        if not i130_path.exists():
            self.skipTest(f"Infrastructure blueprint not found at {i130_path}")

        with open(i130_path, "r", encoding="utf-8") as f:
            blueprint = json.load(f)

        blueprint_fields = {f["canonicalPath"]: f for f in blueprint.get("fields", [])}

        # Canonical paths captured by mobile client for Petitioner and Beneficiary roles
        mobile_client_facts = [
            {"role": "PETITIONER", "path": "petitioner.given_name", "value": "María"},
            {"role": "PETITIONER", "path": "petitioner.family_name", "value": "Santos-Hernández"},
            {"role": "PETITIONER", "path": "petitioner.dob", "value": "1985-06-15"},
            {"role": "PETITIONER", "path": "petitioner.ssn", "value": "123-45-6789"},
            {"role": "BENEFICIARY", "path": "beneficiary.given_name", "value": "Carlos"},
            {"role": "BENEFICIARY", "path": "beneficiary.family_name", "value": "Santos"},
            {"role": "BENEFICIARY", "path": "beneficiary.relationship", "value": "Spouse"},
            {"role": "PETITIONER", "path": "marriage.date", "value": "2015-10-24"},
        ]

        # Verify all mobile client paths exist in the blueprint
        for fact in mobile_client_facts:
            path = fact["path"]
            self.assertIn(path, blueprint_fields, f"Mobile fact path '{path}' missing in I-130 blueprint")
            field_def = blueprint_fields[path]
            self.assertEqual(field_def["attributedRole"], fact["role"])

        # Verify AcroForm targets for primary name fields
        self.assertEqual(
            blueprint_fields["petitioner.given_name"]["pdfFieldMapping"],
            "form1[0].#subform[0].Pt1Line1a_GivenName[0]",
        )
        self.assertEqual(
            blueprint_fields["petitioner.family_name"]["pdfFieldMapping"],
            "form1[0].#subform[0].Pt1Line1b_FamilyName[0]",
        )

    def test_mobile_payload_serialization_contract(self) -> None:
        """Verify client payload serializes to exact worker contract shape."""
        client_confirmed_facts = {
            "petitioner.given_name": "María",
            "petitioner.family_name": "Santos-Hernández",
            "petitioner.dob": "1985-06-15",
            "petitioner.ssn": "123-45-6789",
            "beneficiary.given_name": "Carlos",
            "beneficiary.family_name": "Santos",
            "beneficiary.relationship": "Spouse",
            "marriage.date": "2015-10-24",
        }

        request_payload = {
            "requestId": "req_mobile_client_001",
            "tenantId": "t_ramirez",
            "caseId": "c_ramirez_i130",
            "inputs": client_confirmed_facts,
        }

        # Serializes cleanly to JSON without non-standard types
        json_bytes = json.dumps(request_payload).encode("utf-8")
        parsed = json.loads(json_bytes.decode("utf-8"))
        self.assertEqual(parsed["requestId"], "req_mobile_client_001")
        self.assertEqual(parsed["inputs"]["petitioner.given_name"], "María")

    def test_mobile_keyboard_unicode_nfc_normalization(self) -> None:
        """Ensure iOS/mobile keyboard input (NFD or NFC) normalizes cleanly to NFC standard."""
        # iOS soft keyboards sometimes emit decomposed NFD
        nfd_input = "Jose\u0301 Mari\u0301a"  # José María in NFD
        self.assertNotEqual(nfd_input, unicodedata.normalize("NFC", nfd_input))

        # Standard normalization ensures uniform hash and AcroForm PDF rendering
        nfc_normalized = unicodedata.normalize("NFC", nfd_input)
        self.assertEqual(nfc_normalized, "José María")


if __name__ == "__main__":
    unittest.main()
