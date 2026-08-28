"""
T-69: the static source-policy gate is itself under test.

Every test drives `tools/check-swift-static.py` exactly as CI does — as a
subprocess with a root argument — so the exit code and the CLI contract are
covered, not just internal helpers. Each rule class gets one known-bad fixture
that must fail; the clean fixture must pass. The gate has failed open twice
(T-26's empty-scan pass, T-40's invisible initializers); a rule change that
stops detecting its fixture now fails here first.
"""
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
GATE = REPO_ROOT / "tools" / "check-swift-static.py"

EMPTY_STRINGSDICT = (
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
    '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
    '<plist version="1.0"><dict/></plist>\n'
)


def run_gate(root: pathlib.Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(GATE), str(root)],
        capture_output=True, text=True, check=False,
    )


class GateFixture(unittest.TestCase):
    """A minimal root the gate accepts, which each test then breaks."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self._tmp.name) / "apps"
        ui = self.root / "packages/ApertureKit/Sources/ApertureUI/Resources"
        app = self.root / "ios/ApertureApp"
        for lproj in ("en.lproj", "es.lproj"):
            (ui / lproj).mkdir(parents=True)
            (ui / lproj / "Localizable.strings").write_text(
                '"shared.ok" = "Fine";\n', encoding="utf-8"
            )
            (app / lproj).mkdir(parents=True)
            (app / lproj / "Localizable.strings").write_text(
                '"app.hello" = "Hello";\n', encoding="utf-8"
            )
            (app / lproj / "Localizable.stringsdict").write_text(
                EMPTY_STRINGSDICT, encoding="utf-8"
            )
        (self.root / "Clean.swift").write_text(
            'import SwiftUI\nlet copy = ApertureString("shared.ok")\n',
            encoding="utf-8",
        )
        (app / "AppView.swift").write_text(
            'import SwiftUI\nlet greeting = LaPlumaString("app.hello")\n',
            encoding="utf-8",
        )

    def tearDown(self):
        self._tmp.cleanup()

    # -- the contract both directions --

    def test_clean_fixture_passes(self):
        result = run_gate(self.root)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("0 problems", result.stdout)

    def test_empty_scan_fails_instead_of_passing(self):
        # T-26/M-20: a wrong root once produced "0 files, 0 problems", exit 0.
        empty = pathlib.Path(self._tmp.name) / "nowhere"
        empty.mkdir()
        result = run_gate(empty)
        self.assertEqual(result.returncode, 1)
        self.assertIn("no Swift files found", result.stdout)

    # -- one fixture per rule class --

    def assert_flags(self, expected_fragment: str):
        result = run_gate(self.root)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn(expected_fragment, result.stdout)

    def test_banned_api_is_flagged(self):
        (self.root / "Banned.swift").write_text(
            "let link = NavigationLink(isActive: $flag) { EmptyView() }\n",
            encoding="utf-8",
        )
        self.assert_flags("NavigationLink(isActive:)")

    def test_forbidden_sdk_import_is_flagged(self):
        (self.root / "Sdk.swift").write_text("import Firebase\n", encoding="utf-8")
        self.assert_flags("ADR-012")

    def test_unbalanced_delimiters_are_flagged(self):
        (self.root / "Broken.swift").write_text("func f() {\n", encoding="utf-8")
        self.assert_flags("unbalanced")

    def test_raw_animation_is_flagged(self):
        (self.root / "Motion.swift").write_text(
            "func wiggle() { withAnimation(.default) { } }\n", encoding="utf-8"
        )
        self.assert_flags("Reduce Motion")

    def test_bundle_module_in_app_target_is_flagged(self):
        (self.root / "ios/ApertureApp/Module.swift").write_text(
            'let s = String(localized: "k", bundle: .module)\n', encoding="utf-8"
        )
        self.assert_flags("Bundle.module")

    def test_package_locale_drift_is_flagged(self):
        en = self.root / "packages/ApertureKit/Sources/ApertureUI/Resources/en.lproj/Localizable.strings"
        en.write_text('"shared.ok" = "Fine";\n"shared.extra" = "Only English";\n', encoding="utf-8")
        self.assert_flags("locale drift")

    def test_undefined_package_key_is_flagged(self):
        (self.root / "Uses.swift").write_text(
            'let s = ApertureString("shared.missing")\n', encoding="utf-8"
        )
        self.assert_flags("localisation key used in code but not defined")

    def test_bare_app_literal_is_flagged(self):
        (self.root / "ios/ApertureApp/Bare.swift").write_text(
            'import SwiftUI\nstruct V: View { var body: some View { Text("Untranslated words") } }\n',
            encoding="utf-8",
        )
        self.assert_flags("app localisation key used in code but not defined: Untranslated words")

    def test_t40_initializers_are_still_visible(self):
        # T-40: these two shipped unlocalized because the pattern list missed them.
        (self.root / "ios/ApertureApp/T40.swift").write_text(
            'import SwiftUI\n'
            'let a = ContentUnavailableView("Scanner unavailable", systemImage: "camera")\n'
            'struct S: View { var body: some View { List { }'
            '.searchable(text: $query, prompt: "Search by form number") } }\n',
            encoding="utf-8",
        )
        result = run_gate(self.root)
        self.assertEqual(result.returncode, 1)
        self.assertIn("Scanner unavailable", result.stdout)
        self.assertIn("Search by form number", result.stdout)

    def test_interpolated_applicant_copy_is_flagged(self):
        (self.root / "ios/ApertureApp/Interp.swift").write_text(
            'import SwiftUI\nstruct V: View { var body: some View { Text("Hello \\(name)") } }\n',
            encoding="utf-8",
        )
        self.assert_flags("interpolated applicant-facing copy")

    def test_hand_written_plural_suffix_is_flagged(self):
        (self.root / "ios/ApertureApp/Plural.swift").write_text(
            'let word = "document" + (count == 1 ? "" : "s")\n', encoding="utf-8"
        )
        self.assert_flags("hand-written English plural suffix")

    def test_missing_localization_resource_is_flagged(self):
        shutil.rmtree(self.root / "packages/ApertureKit/Sources/ApertureUI/Resources/es.lproj")
        self.assert_flags("required localisation resource is missing")


if __name__ == "__main__":
    unittest.main()
