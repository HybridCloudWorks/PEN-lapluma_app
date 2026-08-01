#!/usr/bin/env python3
"""
Validate a generated wiki checkout: every internal link must resolve to a page
that exists, and every anchor to a heading that exists.

Exits non-zero on any failure so the publish workflow fails loudly rather than
shipping a wiki full of dead links.

Usage:  python3 tools/check-wiki-links.py <wiki-checkout>
"""
import os
import re
import sys
import urllib.parse

LINK_RE = re.compile(r'(?<!\!)\[([^\]]*)\]\(([^)\s]+)\)')


def strip_code(text: str) -> str:
    """Blank out fenced code blocks so SQL like dbo.[Case](CaseId) isn't read as a link."""
    out, in_fence = [], False
    for line in text.split("\n"):
        if re.match(r'^\s*(```|~~~)', line):
            in_fence = not in_fence
            out.append("")
            continue
        out.append("" if in_fence else line)
    return "\n".join(out)


def slug(heading: str) -> str:
    """GitHub's heading-anchor algorithm."""
    s = heading.strip().lower()
    s = re.sub(r'`', '', s)
    s = re.sub(r'\[([^\]]*)\]\([^)]*\)', r'\1', s)   # link -> label
    s = re.sub(r'[*_]', '', s)
    s = re.sub(r'[^\w\s-]', '', s)                    # drop punctuation, em-dashes
    return s.replace(' ', '-')                        # EACH space becomes a hyphen


def main() -> int:
    wiki = sys.argv[1]
    pages = {f[:-3] for f in os.listdir(wiki) if f.endswith(".md")}

    anchors = {}
    for page in pages:
        text = strip_code(open(os.path.join(wiki, page + ".md"), encoding="utf-8").read())
        seen, found = {}, set()
        for h in re.findall(r'^#{1,6}\s+(.*?)\s*$', text, re.M):
            s = slug(h)
            if s in seen:
                seen[s] += 1
                found.add(f"{s}-{seen[s]}")
            else:
                seen[s] = 0
                found.add(s)
        anchors[page] = found

    failures = []
    for page in sorted(pages):
        raw = open(os.path.join(wiki, page + ".md"), encoding="utf-8").read()
        text = strip_code(raw)
        text = re.sub(r'`[^`\n]*`', '', text)          # inline code
        text = re.sub(r'<!--.*?-->', '', text, flags=re.S)
        for m in LINK_RE.finditer(text):
            href = m.group(2)
            if href.startswith(("http://", "https://", "mailto:")):
                continue
            if href.endswith(".md") or "/" in href.rstrip("/"):
                failures.append(f"{page}: unconverted repo path -> {href}")
                continue
            if href.startswith("#"):
                if urllib.parse.unquote(href[1:]) not in anchors[page]:
                    failures.append(f"{page}: dead self-anchor -> {href}")
                continue
            target, _, frag = href.partition("#")
            if target not in pages:
                failures.append(f"{page}: no such page -> {href}")
                continue
            if frag and urllib.parse.unquote(frag) not in anchors[target]:
                failures.append(f"{page}: no such anchor -> {href}")

    for f in failures:
        print(f"FAIL {f}")
    print(f"{len(pages)} pages checked, {len(failures)} problems")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
