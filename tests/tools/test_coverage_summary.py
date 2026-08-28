"""
T-70: the coverage summarizer renders the LLVM JSON export faithfully and
refuses the empty-report fail-open shape (T-26's lesson).
"""
import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
TOOL = REPO_ROOT / "tools" / "coverage-summary.py"

spec = importlib.util.spec_from_file_location("coverage_summary", TOOL)
coverage_summary = importlib.util.module_from_spec(spec)
spec.loader.exec_module(coverage_summary)

FIXTURE = {
    "data": [{
        "files": [
            {
                "filename": "/w/apps/packages/ApertureKit/Sources/ApertureUI/FeatureModels.swift",
                "summary": {"lines": {"count": 100, "covered": 90, "percent": 90.0}},
            },
            {
                "filename": "/w/apps/packages/ApertureKit/Sources/ApertureAPI/StubAPIClient.swift",
                "summary": {"lines": {"count": 200, "covered": 100, "percent": 50.0}},
            },
            {
                "filename": "/w/apps/packages/ApertureKit/Tests/ApertureKitTests/FeatureModelTests.swift",
                "summary": {"lines": {"count": 50, "covered": 50, "percent": 100.0}},
            },
        ],
    }],
}


class CoverageSummaryTests(unittest.TestCase):
    def test_sources_are_listed_worst_first_with_totals(self):
        table = coverage_summary.summarize(FIXTURE)
        self.assertIn("| `ApertureAPI/StubAPIClient.swift` | 100/200 | 50.0% |", table)
        self.assertIn("| `ApertureUI/FeatureModels.swift` | 90/100 | 90.0% |", table)
        self.assertNotIn("FeatureModelTests", table)
        self.assertIn("| **Total (2 files)** | **190/300** | **63.3%** |", table)
        self.assertLess(table.index("StubAPIClient"), table.index("FeatureModels"))

    def test_no_matching_files_refuses_to_render(self):
        with self.assertRaises(SystemExit):
            coverage_summary.summarize(FIXTURE, path_filter="/Nowhere/")

    def test_cli_reads_a_json_file(self):
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as stream:
            json.dump(FIXTURE, stream)
            path = stream.name
        try:
            result = subprocess.run(
                [sys.executable, str(TOOL), path],
                capture_output=True, text=True, check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("Package line coverage", result.stdout)
        finally:
            pathlib.Path(path).unlink()


if __name__ == "__main__":
    unittest.main()
