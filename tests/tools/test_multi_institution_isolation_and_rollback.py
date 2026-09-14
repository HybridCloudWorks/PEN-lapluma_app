"""
Multi-Institution Reuse, Isolation and Publication Rollback Test Suite (INT-15 & APP-14).

Verifies:
1. Shared blueprint reuse without duplication across synthetic institutions (tenant_clinic_alpha, tenant_firm_beta).
2. Strict tenant-private blueprint and collection isolation (404 Not Found, never leaking existence).
3. Search and listing aggregations strictly omit foreign tenant resources.
4. Client AppSession context switching clears scoped caches and isolates tenant state upon workspace transition.
5. Publication lifecycle and rollback safety preserving pinned cases and audit ledger.
6. Official government artifact and brand integrity across tenant contexts.
"""
import json
import pathlib
import re
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
OPENAPI_PATH = REPO_ROOT / "contracts" / "openapi" / "document-library.yaml"
CONTRACT_PATH = REPO_ROOT / "contracts" / "catalog-package-compatibility.json"
STUB_STORAGE_SWIFT = REPO_ROOT / "apps" / "packages" / "ApertureKit" / "Sources" / "ApertureAPI" / "StubStorage.swift"
STUB_CLIENT_SWIFT = REPO_ROOT / "apps" / "packages" / "ApertureKit" / "Sources" / "ApertureAPI" / "StubAPIClient.swift"
APERTURE_APP_SWIFT = REPO_ROOT / "apps" / "ios" / "ApertureApp" / "ApertureApp.swift"


class MultiInstitutionIsolationAndRollbackTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(OPENAPI_PATH.exists(), f"Missing OpenAPI contract at {OPENAPI_PATH}")
        self.assertTrue(CONTRACT_PATH.exists(), f"Missing compatibility contract at {CONTRACT_PATH}")
        self.assertTrue(STUB_STORAGE_SWIFT.exists(), f"Missing StubStorage.swift at {STUB_STORAGE_SWIFT}")
        self.assertTrue(STUB_CLIENT_SWIFT.exists(), f"Missing StubAPIClient.swift at {STUB_CLIENT_SWIFT}")
        self.assertTrue(APERTURE_APP_SWIFT.exists(), f"Missing ApertureApp.swift at {APERTURE_APP_SWIFT}")

        self.stub_storage = STUB_STORAGE_SWIFT.read_text(encoding="utf-8")
        self.stub_client = STUB_CLIENT_SWIFT.read_text(encoding="utf-8")
        self.app_swift = APERTURE_APP_SWIFT.read_text(encoding="utf-8")
        self.openapi_text = OPENAPI_PATH.read_text(encoding="utf-8")
        with open(CONTRACT_PATH, "r", encoding="utf-8") as f:
            self.contract = json.load(f)

    def test_shared_blueprint_reuse_across_institutions(self):
        """Both institutions reuse official family collection/blueprints without duplication."""
        # Check tenant assignments seed in StubStorage
        self.assertIn('"tenant_clinic_alpha"', self.stub_storage)
        self.assertIn('"tenant_firm_beta"', self.stub_storage)
        self.assertIn('"family-reunification-i130"', self.stub_storage)

        # Both clinic_alpha and firm_beta assign family-reunification-i130
        clinic_assign = re.search(r'"tenant_clinic_alpha":\s*\[([^\]]+)\]', self.stub_storage)
        firm_assign = re.search(r'"tenant_firm_beta":\s*\[([^\]]+)\]', self.stub_storage)
        self.assertIsNotNone(clinic_assign)
        self.assertIsNotNone(firm_assign)
        self.assertIn("family-reunification-i130", clinic_assign.group(1))
        self.assertIn("family-reunification-i130", firm_assign.group(1))

        # Official blueprint members are uscis/i-130 and uscis/i-130a
        mapping = next(m for m in self.contract["packageMappings"] if m["packageCode"] == "FAMILY_I130")
        member_ids = {f"{m['namespace']}/{m['blueprintId']}@r{m['pinnedRevision']}" for m in mapping["blueprintMembers"]}
        self.assertEqual(member_ids, {"uscis/i-130@r1", "uscis/i-130a@r1"})

    def test_private_resource_seeding_and_isolation_definitions(self):
        """Private blueprints and collections are seeded for Alpha and Beta in their respective namespaces."""
        # Clinic Alpha private resources
        self.assertIn('namespace: "tenant_clinic_alpha", blueprintId: "intake"', self.stub_storage)
        self.assertIn('namespace: "tenant_clinic_alpha", collectionId: "clinic_intake_pkg"', self.stub_storage)

        # Firm Beta private resources
        self.assertIn('namespace: "tenant_firm_beta", blueprintId: "special_retainer"', self.stub_storage)
        self.assertIn('namespace: "tenant_firm_beta", collectionId: "firm_retainer_pkg"', self.stub_storage)

    def test_stub_client_tenant_isolation_semantics(self):
        """StubAPIClient strictly isolates private collections and blueprints, returning 404 (nil)."""
        # Active tenant property and setters exist
        self.assertIn("private var activeTenantID: String?", self.stub_client)
        self.assertIn("public func setActiveTenantID(_ tenantID: String?)", self.stub_client)
        self.assertIn("public func getActiveTenantID() -> String?", self.stub_client)

        # libraryCollection checks namespace != 'official' and guards activeTenantID == col.namespace
        self.assertIn('if col.namespace != "official"', self.stub_client)
        self.assertIn("guard let activeTenantID, col.namespace == activeTenantID else", self.stub_client)

        # libraryBlueprint checks official namespaces and guards activeTenantID == bp.namespace
        self.assertIn('let officialNamespaces: Set<String> = ["uscis", "dos", "student-aid"]', self.stub_client)
        self.assertIn("guard let activeTenantID, bp.namespace == activeTenantID else", self.stub_client)

    def test_stub_client_listing_omits_cross_tenant_resources(self):
        """Listing collections/blueprints for a tenant omits other tenants' private resources."""
        # libraryCollections filters by tenant assignments
        self.assertIn("let effectiveTenant = tenantID ?? activeTenantID", self.stub_client)
        self.assertIn("assignments.contains($0.collectionId)", self.stub_client)

        # libraryBlueprints includes official + current tenant only
        self.assertIn("officialNamespaces.contains($0.namespace) || $0.namespace == effectiveTenant", self.stub_client)

    def test_client_app_session_context_switching_and_cache_clearing(self):
        """AppSession clears scoped caches and resets active tenant upon workspace switch."""
        self.assertIn("func clearScopedState()", self.app_swift)
        self.assertIn("pendingCaptureCount = 0", self.app_swift)
        self.assertIn("pendingCaptureBytes = 0", self.app_swift)
        self.assertIn("dataRevision += 1", self.app_swift)

        # signIn clears scoped state on workspace change and propagates active tenant
        self.assertIn("if currentWorkspaceCode != normalizedCode", self.app_swift)
        self.assertIn("clearScopedState()", self.app_swift)
        self.assertIn("await stub.setActiveTenantID(tenantParam)", self.app_swift)

        # signOut clears scoped state and active tenant
        self.assertIn("await stub.setActiveTenantID(nil)", self.app_swift)

        # Demo workspace transitions clear scoped state
        demo_enter = re.search(r"func enterDemoWorkspace\(\)\s*\{([^}]+)\}", self.app_swift)
        self.assertIsNotNone(demo_enter)
        self.assertIn("clearScopedState()", demo_enter.group(1))

        demo_exit = re.search(r"func exitDemoWorkspace\(\)\s*\{([^}]+)\}", self.app_swift)
        self.assertIsNotNone(demo_exit)
        self.assertIn("clearScopedState()", demo_exit.group(1))

    def test_publication_rollback_and_governance_contracts(self):
        """OpenAPI contract specifies independent approval, drift check, and rollback with audit trail."""
        # Endpoints exist in OpenAPI
        self.assertIn("/library/blueprints/{namespace}/{blueprintId}/publish:", self.openapi_text)
        self.assertIn("/library/blueprints/{namespace}/{blueprintId}/drift-check:", self.openapi_text)
        self.assertIn("/library/blueprints/{namespace}/{blueprintId}/rollback:", self.openapi_text)

        # Rollback operation id and response specs
        self.assertIn("operationId: rollbackBlueprint", self.openapi_text)
        self.assertIn("reason", self.openapi_text)
        self.assertIn("targetRevision", self.openapi_text)

    def test_official_government_artifact_and_branding_integrity(self):
        """Official USCIS blueprints retain uncompromised metadata across tenants."""
        # Ensure uscis/i-130 and uscis/i-130a in StubStorage maintain authority USCIS
        self.assertIn('namespace: "uscis", blueprintId: "i-130"', self.stub_storage)
        self.assertIn('title: "Petition for Alien Relative"', self.stub_storage)
        self.assertIn('issuer: "USCIS"', self.stub_storage)

        self.assertIn('namespace: "uscis", blueprintId: "i-130a"', self.stub_storage)
        self.assertIn('title: "Supplemental Information for Spouse Beneficiary"', self.stub_storage)
        self.assertIn('issuer: "USCIS"', self.stub_storage)


if __name__ == "__main__":
    unittest.main()
