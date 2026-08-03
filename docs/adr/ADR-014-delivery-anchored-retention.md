# ADR-014 — Delivery-anchored case retention

**Status:** Proposed · **Date:** 2026-08-02 · **Required approvers:** Data, Privacy, Legal, Security

## Context

The Alpha 0.2 steering prompt fixes deletion at 90 days after delivery. Existing
materials use case closure, optional extension, and longer generated-package
retention. Shipping both policies would create an untruthful privacy promise.

## Proposed decision

- Source documents and working extracted/mapped data are scheduled for deletion at
  `deliveredAt + 90 days`, or earlier after an approved erasure request.
- Delivered PDF bytes exist only for a bounded delivery-link window. The exact hash
  and minimized audit fact remain under the approved audit schedule.
- Abandoned and never-delivered cases receive a separate finite TTL so delivery is not
  required to start deletion.
- An attestation distinguishes removal from live systems, backup expiry, and verified
  crypto-shred. A lifecycle request alone is not proof of deletion.
- Audit identifiers are pseudonymized and retained only for the approved evidence
  period, never described as permanent.

## Status consequence

This ADR is not active until all named approvers accept the policy, exceptions, backup
language, abandoned-case TTL, and user-facing copy. Code may model the milestones
behind a disabled feature flag, but release behavior continues to fail closed.

