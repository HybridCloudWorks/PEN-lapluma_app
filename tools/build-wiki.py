#!/usr/bin/env python3
"""
Build the GitHub wiki from the docs/ tree.

GitHub wiki pages are flat: a page's name is its filename, and links between pages
use the page name, not a path. So this script flattens docs/ into wiki page names
and rewrites every internal link accordingly. Heading anchors are unchanged —
GitHub generates them the same way in wikis as in repo markdown.

Usage:  python3 tools/build-wiki.py <repo-root> <wiki-checkout> [repo-url] [branch]

  repo-url  defaults to https://github.com/saulpatinojr/Work-Application_Builder
  branch    defaults to main

Links to repo files that are not wiki pages (workflows, scripts) are rewritten to
absolute URLs against repo-url/branch, since a relative repo path does not resolve
from a wiki page.
"""
import os
import re
import sys
import shutil

# repo-relative source  ->  wiki page name (no .md)
PAGE_MAP = {
    "README.md":                                   "Home",
    "docs/00-design-authority-record.md":          "00-Design-Authority-Record",
    "docs/01-executive-summary.md":                "01-Executive-Summary",
    "docs/02-product-requirements.md":             "02-Product-Requirements",
    "docs/03-solution-architecture.md":            "03-Solution-Architecture",
    "docs/04-ai-agent-architecture.md":            "04-AI-Agent-Architecture",
    "docs/05-data-architecture.md":                "05-Data-Architecture",
    "docs/06-security-architecture.md":            "06-Security-Architecture",
    "docs/07-api-architecture.md":                 "07-API-Architecture",
    "docs/08-ux-design.md":                        "08-UX-Design",
    "docs/09-responsible-ai.md":                   "09-Responsible-AI",
    "docs/10-devsecops-and-continuity.md":         "10-DevSecOps-and-Continuity",
    "docs/11-roadmap.md":                          "11-Roadmap",
    "docs/12-risks-and-gap-analysis.md":           "12-Risks-and-Gap-Analysis",
    "docs/13-v2-recommendations.md":               "13-V2-Recommendations",
    "docs/14-sme-review-and-signoff.md":           "14-SME-Review-and-Sign-Off",
    "docs/adr/README.md":                          "ADR-Index",
    "docs/adr/ADR-001-scrivener-boundary.md":      "ADR-001-Scrivener-Boundary",
    "docs/adr/ADR-002-no-efiling.md":              "ADR-002-No-E-Filing",
    "docs/adr/ADR-003-form-fidelity.md":           "ADR-003-Form-Fidelity",
    "docs/adr/ADR-004-backend-runtime.md":         "ADR-004-Backend-Runtime",
    "docs/adr/ADR-005-compute-platform.md":        "ADR-005-Compute-Platform",
    "docs/adr/ADR-006-polyglot-persistence.md":    "ADR-006-Polyglot-Persistence",
    "docs/adr/ADR-007-household-trust-boundaries.md": "ADR-007-Household-Trust-Boundaries",
    "docs/adr/ADR-008-agent-capability-boundary.md":  "ADR-008-Agent-Capability-Boundary",
    "docs/adr/ADR-009-durable-orchestration.md":   "ADR-009-Durable-Orchestration",
    "docs/adr/ADR-010-confidence-banding.md":      "ADR-010-Confidence-Banding",
    "docs/adr/ADR-011-passkeys-no-sms.md":         "ADR-011-Passkeys-No-SMS",
    "docs/adr/ADR-012-no-third-party-client-sdks.md": "ADR-012-No-Third-Party-Client-SDKs",
    "docs/adr/ADR-013-alpha-02-platform-boundaries.md": "ADR-013-Alpha-02-Platform-Boundaries",
    "docs/adr/ADR-014-delivery-anchored-retention.md": "ADR-014-Delivery-Anchored-Retention",
    "docs/adr/ADR-015-lapluma-name-and-repository-boundary.md": "ADR-015-LaPluma-Name-And-Repository-Boundary",
    "docs/appendix/appendix-a-backlog.md":         "Appendix-A-Backlog",
    "docs/appendix/appendix-b-traceability.md":    "Appendix-B-Traceability",
    "docs/appendix/appendix-c-glossary.md":        "Appendix-C-Glossary",
}

# Directory links that should resolve to a page rather than a folder listing
DIR_MAP = {
    "docs/adr": "ADR-Index",
    "docs/appendix": "Appendix-A-Backlog",
}

LINK_RE = re.compile(r'(?<!\!)\[([^\]]*)\]\(([^)\s]+)\)')


def resolve(src_repo_path: str, href: str, repo_root: str, repo_url: str, branch: str):
    """
    Map a repo-relative markdown link to something that works from a wiki page.

      - a documented page  -> the wiki page name
      - any other repo file (workflows, scripts, configs) -> an absolute blob URL,
        because a relative repo path is meaningless once the page lives in the wiki
      - anything else      -> None, leave it alone for the validator to flag
    """
    if href.startswith(("http://", "https://", "mailto:", "#")):
        return None
    path, _, frag = href.partition("#")
    if not path:
        return None
    target = os.path.normpath(os.path.join(os.path.dirname(src_repo_path), path))
    # normpath already drops a leading "./"; do NOT lstrip("./") here — that strips
    # characters, not a prefix, and would turn ".github/..." into "github/...".
    target = target.replace(os.sep, "/")

    page = PAGE_MAP.get(target) or DIR_MAP.get(target.rstrip("/"))
    if page:
        return f"{page}#{frag}" if frag else page

    # Not a wiki page. If it is a real file or directory in the repo, link to it on GitHub.
    on_disk = os.path.join(repo_root, target)
    if os.path.exists(on_disk):
        kind = "tree" if os.path.isdir(on_disk) else "blob"
        url = f"{repo_url}/{kind}/{branch}/{target}"
        return f"{url}#{frag}" if frag else url
    return None


def convert(src_repo_path: str, text: str, repo_root: str, repo_url: str, branch: str) -> str:
    def sub(m):
        label, href = m.group(1), m.group(2)
        new = resolve(src_repo_path, href, repo_root, repo_url, branch)
        return f"[{label}]({new})" if new else m.group(0)

    # Protect fenced code blocks from link rewriting
    parts = re.split(r'(```.*?```|~~~.*?~~~)', text, flags=re.S)
    for i in range(0, len(parts), 2):
        parts[i] = LINK_RE.sub(sub, parts[i])
    return "".join(parts)


SIDEBAR = """### Aperture — Solution Definition
**Rev B** · conditionally signed off

**[Home](Home)**

**Governance**
* [00 Design Authority Record](00-Design-Authority-Record)
* [14 SME Review & Sign-Off](14-SME-Review-and-Sign-Off)

**Product**
* [01 Executive Summary](01-Executive-Summary)
* [02 Product Requirements](02-Product-Requirements)
* [11 Roadmap](11-Roadmap)
* [12 Risks & Gap Analysis](12-Risks-and-Gap-Analysis)
* [13 V2 Recommendations](13-V2-Recommendations)

**Architecture**
* [03 Solution Architecture](03-Solution-Architecture)
* [04 AI Agent Architecture](04-AI-Agent-Architecture)
* [05 Data Architecture](05-Data-Architecture)
* [07 API Architecture](07-API-Architecture)

**Assurance**
* [06 Security Architecture](06-Security-Architecture)
* [09 Responsible AI](09-Responsible-AI)
* [10 DevSecOps & Continuity](10-DevSecOps-and-Continuity)

**Design**
* [08 UX Design](08-UX-Design)

**[ADRs](ADR-Index)**
* [001 Scrivener Boundary](ADR-001-Scrivener-Boundary)
* [002 No E-Filing](ADR-002-No-E-Filing)
* [003 Form Fidelity](ADR-003-Form-Fidelity)
* [004 Backend Runtime](ADR-004-Backend-Runtime)
* [005 Compute Platform](ADR-005-Compute-Platform)
* [006 Polyglot Persistence](ADR-006-Polyglot-Persistence)
* [007 Household Trust](ADR-007-Household-Trust-Boundaries)
* [008 Capability Boundary](ADR-008-Agent-Capability-Boundary)
* [009 Durable Orchestration](ADR-009-Durable-Orchestration)
* [010 Confidence Banding](ADR-010-Confidence-Banding)
* [011 Passkeys, No SMS](ADR-011-Passkeys-No-SMS)
* [012 No 3rd-Party SDKs](ADR-012-No-Third-Party-Client-SDKs)
* [013 Alpha 0.2 Boundaries](ADR-013-Alpha-02-Platform-Boundaries)
* [014 Delivery-Anchored Retention](ADR-014-Delivery-Anchored-Retention)
* [015 LaPluma Name & Repo Boundary](ADR-015-LaPluma-Name-And-Repository-Boundary)

**Appendices**
* [A — Backlog](Appendix-A-Backlog)
* [B — Traceability](Appendix-B-Traceability)
* [C — Glossary](Appendix-C-Glossary)
"""

FOOTER = (
    "---\n"
    "**Aperture is not a law firm and does not provide legal advice.** "
    "This wiki is generated from `docs/` on the `main` branch — "
    "edit there, not here. See [00 Design Authority Record](00-Design-Authority-Record) "
    "for decision rights and [14 SME Review & Sign-Off](14-SME-Review-and-Sign-Off) "
    "for outstanding conditions.\n"
)

BANNER = (
    "> ℹ️ **Generated page.** This wiki mirrors `docs/` on the `main` branch of the "
    "repository. Edits made here are overwritten on the next publish — "
    "raise a pull request against `main` instead.\n\n"
)


DEFAULT_REPO_URL = "https://github.com/HybridCloudWorks/PEN-lapluma_app"


def main():
    repo, wiki = sys.argv[1], sys.argv[2]
    repo_url = (sys.argv[3] if len(sys.argv) > 3 else DEFAULT_REPO_URL).rstrip("/")
    branch = sys.argv[4] if len(sys.argv) > 4 else "main"

    # Clear existing pages (keep .git)
    for entry in os.listdir(wiki):
        if entry == ".git":
            continue
        p = os.path.join(wiki, entry)
        shutil.rmtree(p) if os.path.isdir(p) else os.remove(p)

    documented = {
        os.path.relpath(os.path.join(root, name), repo).replace(os.sep, "/")
        for root, _, names in os.walk(os.path.join(repo, "docs"))
        for name in names
        if name.endswith(".md")
    }
    unmapped = sorted(documented - PAGE_MAP.keys())
    if unmapped:
        # resolve() rewrites unmapped-but-present links to absolute blob URLs and
        # check-wiki-links.py skips https:// links, so without this the pipeline
        # reports success while under-mirroring docs/.
        for src in unmapped:
            print(f"  UNMAPPED {src}", file=sys.stderr)
        sys.exit(f"{len(unmapped)} docs page(s) missing from PAGE_MAP; add them before publishing")

    written = 0
    missing = []
    for src, page in PAGE_MAP.items():
        full = os.path.join(repo, src)
        if not os.path.exists(full):
            missing.append(src)
            continue
        text = convert(src, open(full, encoding="utf-8").read(), repo, repo_url, branch)
        # Banner goes after the H1 so the page title still renders first
        lines = text.split("\n")
        if lines and lines[0].startswith("# "):
            text = lines[0] + "\n\n" + BANNER + "\n".join(lines[1:])
        else:
            text = BANNER + text
        open(os.path.join(wiki, page + ".md"), "w", encoding="utf-8").write(text)
        written += 1

    open(os.path.join(wiki, "_Sidebar.md"), "w", encoding="utf-8").write(SIDEBAR)
    open(os.path.join(wiki, "_Footer.md"), "w", encoding="utf-8").write(FOOTER)
    print(f"  {written} pages + _Sidebar + _Footer")
    if missing:
        # The build already wiped every wiki page; publishing a partial mirror
        # would silently delete the pages for any renamed source file.
        for src in missing:
            print(f"  MISSING {src}", file=sys.stderr)
        sys.exit(f"{len(missing)} mapped source file(s) are missing; update PAGE_MAP")


if __name__ == "__main__":
    main()
