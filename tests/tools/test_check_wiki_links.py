"""
T-69: the wiki link-checker policy gate is itself under test.

Every test drives `tools/check-wiki-links.py` as a subprocess with a directory argument,
verifying the exit code, fail-closed detection of broken links/anchors, and tolerance
of valid constructs (code blocks, comments, duplicate anchors).
"""
import pathlib
import subprocess
import sys
import tempfile
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
CHECKER = REPO_ROOT / "tools" / "check-wiki-links.py"


def run_checker(wiki_dir: pathlib.Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(CHECKER), str(wiki_dir)],
        capture_output=True,
        text=True,
        check=False,
    )


class CheckWikiLinksTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.wiki = pathlib.Path(self._tmp.name)

    def tearDown(self):
        self._tmp.cleanup()

    def test_clean_wiki_passes(self):
        (self.wiki / "Home.md").write_text(
            "# Home\n"
            "Welcome. See [About](About) and [Installation](#installation).\n"
            "## Installation\n"
            "Run installer.\n",
            encoding="utf-8",
        )
        (self.wiki / "About.md").write_text(
            "# About\n"
            "Back to [Home](Home#installation).\n",
            encoding="utf-8",
        )
        result = run_checker(self.wiki)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("0 problems", result.stdout)

    def test_dead_page_link_is_flagged(self):
        (self.wiki / "Home.md").write_text(
            "# Home\n"
            "Go to [NonExistent](NoSuchPage).\n",
            encoding="utf-8",
        )
        result = run_checker(self.wiki)
        self.assertEqual(result.returncode, 1)
        self.assertIn("no such page -> NoSuchPage", result.stdout)

    def test_dead_self_anchor_is_flagged(self):
        (self.wiki / "Home.md").write_text(
            "# Home\n"
            "Jump to [Missing](#non-existent-anchor).\n",
            encoding="utf-8",
        )
        result = run_checker(self.wiki)
        self.assertEqual(result.returncode, 1)
        self.assertIn("dead self-anchor -> #non-existent-anchor", result.stdout)

    def test_dead_target_page_anchor_is_flagged(self):
        (self.wiki / "Home.md").write_text(
            "# Home\n"
            "See [Details](Details#missing-section).\n",
            encoding="utf-8",
        )
        (self.wiki / "Details.md").write_text(
            "# Details\n"
            "## Present Section\n"
            "Content.\n",
            encoding="utf-8",
        )
        result = run_checker(self.wiki)
        self.assertEqual(result.returncode, 1)
        self.assertIn("no such anchor -> Details#missing-section", result.stdout)

    def test_unconverted_repo_path_is_flagged(self):
        (self.wiki / "Home.md").write_text(
            "# Home\n"
            "See [Doc](docs/Guide.md).\n",
            encoding="utf-8",
        )
        result = run_checker(self.wiki)
        self.assertEqual(result.returncode, 1)
        self.assertIn("unconverted repo path -> docs/Guide.md", result.stdout)

    def test_code_blocks_and_external_links_are_ignored(self):
        (self.wiki / "Home.md").write_text(
            "# Home\n"
            "Visit [External](https://example.com) or [Email](mailto:user@example.com).\n"
            "```sql\n"
            "SELECT [Col] FROM [Table](Param);\n"
            "```\n"
            "<!-- [Hidden](DeadLink) -->\n",
            encoding="utf-8",
        )
        result = run_checker(self.wiki)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("0 problems", result.stdout)

    def test_duplicate_heading_anchors_resolve_correctly(self):
        (self.wiki / "Home.md").write_text(
            "# FAQ\n"
            "## Question\nFirst.\n"
            "## Question\nSecond.\n"
            "Link to [First](#question) and [Second](#question-1).\n",
            encoding="utf-8",
        )
        result = run_checker(self.wiki)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
