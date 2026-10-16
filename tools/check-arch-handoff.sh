#!/usr/bin/env bash
set -euo pipefail

base_ref="${1:-origin/${GITHUB_BASE_REF:-main}}"
changed="$(git diff --name-only "$base_ref"...HEAD)"
if ! grep -qx 'docs/project/ARCH-HANDOFF.md' <<<"$changed"; then
  echo 'docs/project/ARCH-HANDOFF.md must change in every pull request.' >&2
  exit 1
fi
added="$(git diff --unified=0 "$base_ref"...HEAD -- docs/project/ARCH-HANDOFF.md | sed -n 's/^+//p')"
if ! grep -Eq '^### [0-9]{4}-[0-9]{2}-[0-9]{2} — ' <<<"$added"; then
  echo 'Add a dated change-ledger heading to docs/project/ARCH-HANDOFF.md.' >&2
  exit 1
fi
if ! grep -Eq '^\*\*Last updated:\*\* [0-9]{4}-[0-9]{2}-[0-9]{2}$' docs/project/ARCH-HANDOFF.md; then
  echo 'docs/project/ARCH-HANDOFF.md needs a valid Last updated date.' >&2
  exit 1
fi
