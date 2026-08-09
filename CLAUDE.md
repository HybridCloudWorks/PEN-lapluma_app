# CLAUDE.md — working agreements for this repository

Instructions for AI assistants (and useful for humans) doing review, audit,
remediation, documentation, or handoff work in `PEN-lapluma_app`.

---

## 1. The tracking files and what each one is for

Four root files carry the state of review work. They answer different questions;
do not merge or duplicate them.

| File | Answers | Lifecycle |
|---|---|---|
| `CODE_REVIEW.md` | *What was wrong?* — findings with `file:line` evidence, severity, and a concrete failure scenario | Point-in-time record. Do not rewrite history; annotate status instead |
| `TODO.md` | *What are we doing about it, and where does it stand?* — tasks `T-nn` with priority, category, status, resolution | Living. The file to read for "what is left" |
| `REVIEW.md` | *What is needed from the user?* — blockers `R-n` an engineer cannot clear alone | Living. Shrinks as blockers are cleared |
| `CHANGELOG.md` | *What shipped?* — Keep a Changelog format | Living |

A finding flows: `CODE_REVIEW.md` finding → `TODO.md` task → if it cannot be
finished without a decision, credential, or access, a `REVIEW.md` blocker holds
the part that is stuck. Cross-reference by ID in both directions.

**Naming wart:** `REVIEW.md` sits next to `CODE_REVIEW.md` and reads like a
duplicate of it. It is not — it is the user-blocked list. `BLOCKERS.md` would be
a clearer name; the rename has not been made. Do not confuse the two.

---

## 2. Triage routing — findings must land in the tracking files

Any issue, risk, debt, bug, follow-up, question, dependency, or blocker
discovered during any task must be recorded in `TODO.md` or `REVIEW.md`.
**These files always take priority as the destination for triage output.**

- Actionable by engineering → `TODO.md` entry (title, priority, category,
  description, recommended action, dependencies, status, notes).
- Requires a user decision, credential, approval, or environment access →
  `REVIEW.md` entry (blocker, why it exists, impact, exact steps required,
  expected outcome, recommended next action).
- Partly both → a `TODO.md` task recording the engineering half, plus a
  `REVIEW.md` blocker for the part that is stuck. Link them by ID.

Do not leave triage output only in chat, only in a commit message, or only in a
pull-request body. Anything not written into these files is lost at the end of
the session.

---

## 3. Dot-prefixed folder policy

Examples: `.claude/`, `.cursor/`, `.windsurf/`, `.vscode/`, `.devcontainer/`,
`.github/`, `.config/`, `.azure/`.

These are usually owned by tools, IDEs, agents, platforms, or repository
infrastructure, and are not the target of documentation or content review.

### Excluded by default — documentation and content work

Unless the user explicitly asks otherwise, do **not**:

- analyze dot-prefixed folders for documentation review or consolidation;
- migrate, restructure, or rewrite content in them;
- create new markdown files inside them;
- generate documentation findings, TODO items, `REVIEW.md` entries, or
  changelog entries from their *documentation* content;
- recommend documentation changes in them.

Do not go looking inside dot folders for documentation to migrate. If
documentation is encountered incidentally during approved work: flag it, record
the location, recommend evaluation — do not migrate it automatically.

### Not excluded — defects in the files themselves

Dot-prefixed folders are still part of the repository. **If a file inside one
has an actual defect, it is triaged like any other defect** and routed per
section 2. Exclusion is about documentation and content churn, not about
ignoring broken infrastructure.

This carve-out is load-bearing. The 2026-08-06 review of this repository found
these in `.github/`, and a blanket exclusion would have missed all of them:

- **H-8** — the internal TestFlight workflow was pinned to `0.1.0` against a
  `0.2.0` project, so the repository's only release path failed preflight on
  every dispatch.
- **M-22** — `publish-wiki.yml` interpolated `${{ github.ref_name }}` straight
  into a `run:` script (the documented injection antipattern) and let a manual
  dispatch from any branch overwrite the entire wiki.
- The `GITHUB_TOKEN` persisted in the wiki clone's `.git/config`, and mutable
  action tags in three workflows against the repo's own SHA-pinning standard.

Security defects, broken or dead CI/CD, release-path breakage, secret handling,
and supply-chain issues in dot folders are **always in scope for triage**.

### Explicit exceptions for entering a dot folder

1. The user asks for it.
2. A finding outside the folder depends on content inside it.
3. The folder holds repository-required configuration for the requested task.
4. The task targets agent, IDE, automation, CI/CD, or platform configuration.
5. A file inside has a defect requiring triage (section 2).

When entering under an exception: minimize changes, prefer observation over
modification, avoid new markdown files, avoid restructuring tool-owned content,
and avoid large-scale migration. Do the minimum the request requires.

---

## 4. Review scope priority

Prioritize: source code → application code → infrastructure code → tests →
root `README.md` → `CHANGELOG.md` → `REVIEW.md` → `TODO.md` → GitHub Wiki
references.

Deprioritize: dot-prefixed folders (subject to section 3), other tool-, IDE-,
and agent-owned folders, generated content, caches, build output, temporary
artifacts.

---

## 5. Verification discipline

Earned the hard way in this repository — a data-loss regression reached `main`
because these rules were not followed.

- **Never report work complete on an unfinished CI run.** "In progress" is not
  "passing."
- **A `cancelled` run deserves the same scrutiny as a failed one.** A job that
  hangs to its timeout reports as cancelled, which reads like infrastructure
  noise. Check whether a step hit `timeout-minutes`. This is exactly how the
  T-35 regression hid across three commits and a merge to `main`.
- **State what was actually verified.** Swift and Xcode are unavailable in the
  Linux review container, so `swift test` and XCUITest cannot run there; say so
  rather than implying local verification. `tools/check-swift-static.py` and the
  wiki build/link check *do* run there.
- **Prefer bounded waits in tests.** An unbounded spin turns a regression into a
  30-minute CI timeout instead of a failure.
- **Anchor claims to what gates them.** Document counts and verification as
  "what CI runs on every PR", not as a point-in-time count that silently goes
  stale (see `README.md`).

---

## 6. Repository facts worth knowing

- Default branch `main`; the wiki is a generated mirror of `docs/` — never edit
  it directly.
- `tools/check-swift-static.py` is a source-policy gate: delimiter balance,
  banned APIs, forbidden third-party SDKs, and en/es localization key parity. It
  rejects user-facing string literals with no localization key. For text that
  must never reach a user (debug scaffolding), use `Text(verbatim:)` rather than
  adding the string to the localization tables.
- Internal Swift module and target names may keep the `Aperture` codename per
  ADR-015; **user-visible surfaces must say LaPluma**.
- No third-party dependencies in `ApertureKit` — `Package.swift` declares
  `dependencies: []` and this is enforced deliberately.
- Never commit credentials, production endpoints, or Apple key material.
