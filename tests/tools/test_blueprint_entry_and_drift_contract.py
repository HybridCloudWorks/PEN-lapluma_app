#!/usr/bin/env python3
"""Contract and invariant test suite for Blueprint-driven entry and offline drift reconciliation (APP-05, APP-06)."""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class TestBlueprintEntryAndDriftContract(unittest.TestCase):

    def setUp(self) -> None:
        self.blueprint_def_path = ROOT / "apps/packages/ApertureKit/Sources/ApertureDomain/BlueprintDefinition.swift"
        self.blueprint_drift_path = ROOT / "apps/packages/ApertureKit/Sources/ApertureDomain/BlueprintDriftPolicy.swift"
        self.offline_store_path = ROOT / "apps/packages/ApertureKit/Sources/ApertureDomain/OfflineCaseStore.swift"
        self.entry_view_path = ROOT / "apps/ios/ApertureApp/Features/Workflow/BlueprintFormEntryView.swift"
        self.stub_storage_path = ROOT / "apps/packages/ApertureKit/Sources/ApertureAPI/StubStorage.swift"
        self.en_strings_path = ROOT / "apps/ios/ApertureApp/en.lproj/Localizable.strings"
        self.es_strings_path = ROOT / "apps/ios/ApertureApp/es.lproj/Localizable.strings"

    def test_blueprint_definition_declarative_schema_models(self) -> None:
        """Verify BlueprintDefinition implements sections, fields, conditions, and evidence matching schema."""
        self.assertTrue(self.blueprint_def_path.is_file(), "BlueprintDefinition.swift must exist")
        text = self.blueprint_def_path.read_text(encoding="utf-8")

        # Models present
        self.assertIn("struct BlueprintDefinition", text)
        self.assertIn("struct BlueprintSection", text)
        self.assertIn("struct BlueprintField", text)
        self.assertIn("struct BlueprintCondition", text)
        self.assertIn("enum BlueprintConditionOperator", text)
        self.assertIn("enum BlueprintOverflowStrategy", text)
        self.assertIn("struct BlueprintEvidenceRequirement", text)

        # Condition operators
        for op in ["equals", "notEquals", "isSet", "isNotSet", "inValues"]:
            self.assertIn(op, text, f"Missing condition operator {op}")

        # Overflow strategies
        for strat in ["attachmentAddendum", "truncateError", "splitPages"]:
            self.assertIn(strat, text, f"Missing overflow strategy {strat}")

    def test_declarative_safety_enforced(self) -> None:
        """Verify configuration cannot add executable behavior (APP-05)."""
        text = self.blueprint_def_path.read_text(encoding="utf-8")
        self.assertIn("validateDeclarativeSafety", text)
        self.assertIn("<script", text)
        self.assertIn("javascript:", text)

    def test_blueprint_drift_policy_and_generation_blocking(self) -> None:
        """Verify edition drift detection and strict generation blocking (APP-06)."""
        self.assertTrue(self.blueprint_drift_path.is_file(), "BlueprintDriftPolicy.swift must exist")
        text = self.blueprint_drift_path.read_text(encoding="utf-8")

        self.assertIn("struct BlueprintDrift", text)
        self.assertIn("enum BlueprintDriftReason", text)
        self.assertIn("revisionReplaced", text)
        self.assertIn("quarantined", text)
        self.assertIn("withdrawn", text)
        self.assertIn("rolledBack", text)
        self.assertIn("missingFromCatalog", text)
        self.assertIn("evaluateDrift", text)
        self.assertIn("blocksPackageGeneration", text)

    def test_offline_case_store_and_conflict_preservation(self) -> None:
        """Verify offline draft store preserves pinned revisions and 412 conflicts (APP-06)."""
        self.assertTrue(self.offline_store_path.is_file(), "OfflineCaseStore.swift must exist")
        text = self.offline_store_path.read_text(encoding="utf-8")

        self.assertIn("struct CaseRevisionPin", text)
        self.assertIn("struct OfflineSectionDraft", text)
        self.assertIn("struct OfflineCaseDraft", text)
        self.assertIn("actor OfflineCaseStore", text)
        self.assertIn("recordConflict", text)
        self.assertIn("resolveConflict", text)
        self.assertIn("clearTenant", text)

    def test_synthetic_non_immigration_blueprints_in_stub_storage(self) -> None:
        """Verify synthetic non-immigration blueprints are seeded in StubStorage (APP-05)."""
        text = self.stub_storage_path.read_text(encoding="utf-8")

        # 4 synthetic non-immigration blueprints
        self.assertIn("clinic-legal-org", text)
        self.assertIn("hope-heritage", text)
        self.assertIn("scholarship-app", text)
        self.assertIn("ds-11", text)
        self.assertIn("fafsa", text)
        self.assertIn("loadSeedBlueprintDefinitions", text)

    def test_dynamic_entry_view_and_guidance_rendering(self) -> None:
        """Verify BlueprintFormEntryView renders dynamic sections, guidance, and conflict resolution (APP-05)."""
        self.assertTrue(self.entry_view_path.is_file(), "BlueprintFormEntryView.swift must exist")
        text = self.entry_view_path.read_text(encoding="utf-8")

        self.assertIn("struct BlueprintFormEntryView", text)
        self.assertIn("guidanceSection", text)
        self.assertIn("renderSection", text)
        self.assertIn("renderField", text)
        self.assertIn("evidenceSection", text)
        self.assertIn("struct ConflictResolutionSheet", text)
        self.assertIn("commitSection", text)
        self.assertIn("status == 412", text)

    def test_localization_key_parity_for_blueprint_keys(self) -> None:
        """Verify 100% key-for-key English/Spanish parity for all Blueprint keys."""
        def extract_keys(path: Path) -> dict[str, str]:
            return dict(re.findall(r'^"((?:\\.|[^"\\])+)"\s*=\s*"((?:\\.|[^"\\])*)"\s*;', path.read_text(encoding="utf-8"), re.M))

        en_keys = extract_keys(self.en_strings_path)
        es_keys = extract_keys(self.es_strings_path)

        blueprint_keys = [
            "Blueprint Data Entry",
            "blueprint.entry.title",
            "blueprint.entry.commit",
            "blueprint.entry.committing",
            "blueprint.entry.committed",
            "blueprint.entry.reviewReopened",
            "blueprint.entry.approvalInvalidated",
            "blueprint.entry.conflictDetected",
            "blueprint.entry.repeatableAdd",
            "blueprint.entry.repeatableRemove",
            "blueprint.guidance.header",
            "blueprint.guidance.feeCitation",
            "blueprint.guidance.officialInstructions",
            "blueprint.guidance.evidenceChecklist",
            "blueprint.guidance.institutionNotes",
            "blueprint.conflict.title",
            "blueprint.conflict.explanation",
            "blueprint.conflict.localVersion",
            "blueprint.conflict.serverVersion",
            "blueprint.conflict.keepLocal",
            "blueprint.conflict.acceptServer",
            "blueprint.conflict.close",
            "blueprint.drift.warningTitle",
            "blueprint.drift.warningDetail",
            "blueprint.drift.quarantinedBadge",
        ]

        for k in blueprint_keys:
            self.assertIn(k, en_keys, f"Missing en key: {k}")
            self.assertIn(k, es_keys, f"Missing es key: {k}")
            self.assertTrue(len(en_keys[k]) > 0)
            self.assertTrue(len(es_keys[k]) > 0)


if __name__ == "__main__":
    unittest.main()
