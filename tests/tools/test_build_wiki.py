"""
T-69: the wiki builder's fatal paths are themselves under test.

Both directions of the PAGE_MAP symmetry have shipped broken before: T-31 made
a mapped-but-missing source fatal, and T-39 made an unmapped source fatal after
three ADRs were silently rewritten to blob URLs the link checker skips. These
tests copy the real docs tree so the map stays honest against the actual
repository, then break it each way.
"""
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
BUILDER = REPO_ROOT / "tools" / "build-wiki.py"
LINKCHECK = REPO_ROOT / "tools" / "check-wiki-links.py"


def run_tool(tool: pathlib.Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(tool), *map(str, args)],
        capture_output=True, text=True, check=False,
    )


class BuildWikiFixture(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        base = pathlib.Path(self._tmp.name)
        self.repo = base / "repo"
        self.wiki = base / "wiki"
        self.wiki.mkdir()
        shutil.copytree(REPO_ROOT / "docs", self.repo / "docs")
        shutil.copy2(REPO_ROOT / "README.md", self.repo / "README.md")

    def tearDown(self):
        self._tmp.cleanup()

    def test_real_docs_tree_builds_and_links_check(self):
        # The success path runs against the real repository root, exactly as
        # publish-wiki.yml does: links to repo files outside docs/ resolve to
        # blob URLs only when the target actually exists on disk, so a stripped
        # fixture would flag every such link. The builder only writes into the
        # wiki checkout, never into the repo.
        result = run_tool(BUILDER, REPO_ROOT, self.wiki)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("_Sidebar + _Footer", result.stdout)
        self.assertTrue((self.wiki / "Home.md").exists())

        check = run_tool(LINKCHECK, self.wiki)
        self.assertEqual(check.returncode, 0, check.stdout + check.stderr)

    def test_unmapped_doc_fails_the_build(self):
        (self.repo / "docs" / "zz-test-unmapped.md").write_text(
            "# Unmapped\n", encoding="utf-8"
        )
        result = run_tool(BUILDER, self.repo, self.wiki)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("UNMAPPED docs/zz-test-unmapped.md", result.stderr)

    def test_mapped_but_missing_source_fails_the_build(self):
        (self.repo / "docs" / "11-roadmap.md").unlink()
        result = run_tool(BUILDER, self.repo, self.wiki)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("MISSING docs/11-roadmap.md", result.stderr)

    def test_wrong_paths_fail_with_a_named_path(self):
        result = run_tool(BUILDER, self.repo / "nope", self.wiki)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("repo root is not a directory", result.stderr)


if __name__ == "__main__":
    unittest.main()
