#!/usr/bin/env python3
"""
Render a markdown coverage summary from the LLVM JSON export that
`swift test --enable-code-coverage` produces (`swift test --show-codecov-path`).

Usage:  python3 tools/coverage-summary.py <codecov.json> [path-filter]

  path-filter   only files whose path contains this substring are listed
                (default "/Sources/", which keeps test targets and generated
                runner files out of the table)

Advisory by design: the output is a report, not a gate. A threshold, if the
project ever wants one, belongs in the workflow so the policy is reviewable —
this script only states the numbers (CLAUDE.md §5: anchor claims to what CI
runs, and let the evidence speak).
"""
import json
import sys


def summarize(codecov: dict, path_filter: str = "/Sources/") -> str:
    export = codecov["data"][0]
    rows = []
    for entry in export.get("files", []):
        filename = entry.get("filename", "")
        if path_filter not in filename:
            continue
        lines = entry.get("summary", {}).get("lines", {})
        count, covered = lines.get("count", 0), lines.get("covered", 0)
        percent = lines.get("percent", 0.0)
        short = filename.split(path_filter, 1)[-1] if path_filter in filename else filename
        rows.append((percent, covered, count, short))

    out = ["### Package line coverage (advisory)", ""]
    if not rows:
        # An empty table would read as "no source files", which is exactly the
        # fail-open shape T-26 taught this repository to refuse.
        raise SystemExit(f"no files matched path filter {path_filter!r}; refusing to render an empty report")

    out.append("| File | Lines covered | Coverage |")
    out.append("|---|---|---|")
    for percent, covered, count, short in sorted(rows):
        out.append(f"| `{short}` | {covered}/{count} | {percent:.1f}% |")

    total_count = sum(count for _, _, count, _ in rows)
    total_covered = sum(covered for _, covered, _, _ in rows)
    total_percent = 100.0 * total_covered / total_count if total_count else 0.0
    out.append(f"| **Total ({len(rows)} files)** | **{total_covered}/{total_count}** | **{total_percent:.1f}%** |")
    return "\n".join(out) + "\n"


def main() -> int:
    if len(sys.argv) < 2:
        raise SystemExit("usage: coverage-summary.py <codecov.json> [path-filter]")
    with open(sys.argv[1], encoding="utf-8") as stream:
        codecov = json.load(stream)
    path_filter = sys.argv[2] if len(sys.argv) > 2 else "/Sources/"
    print(summarize(codecov, path_filter), end="")
    return 0


if __name__ == "__main__":
    sys.exit(main())
