# ADR-007 — Per-person trust boundaries within a folder

**Status:** Accepted · **Date:** 2026-08-01
**Deciders:** CX Lead, Risk Officer, Principal Security Architect, CISO
**Related:** [C-05](../00-design-authority-record.md#c-05--a-household-folder-is-not-a-single-trust-boundary), RISK-009

## Context

The brief models a Virtual Applicant Folder as containing "applicant, family members, dependents"
under one owner. That model assumes the people in a folder have aligned interests.

In family-based immigration they frequently do not. The petitioner commonly holds leverage over the
beneficiary — the ability to withdraw the petition is, in practice, control over the other person's
future. Information the beneficiary must supply (prior marriages, prior entries, criminal history, a
history of abuse) may be information they must not be forced to disclose to the petitioner. VAWA
self-petitions exist precisely because that leverage is abused at scale.

A design in which the folder owner sees everything makes the platform an instrument of that control.

## Options considered

1. **Folder-level access (as briefed).** *Rejected — makes us complicit in a known abuse pattern.*
2. **Folder-level with a "hide from other members" flag.** *Rejected — a hidden item whose
   *existence* is visible is worse than useless. "What's in the hidden folder?" is a question an
   abuser can ask.*
3. **Per-person access with an existence-invisible Private Annex.** *Selected.*
4. **Separate folders per person.** *Rejected — breaks the shared-case model the forms require, and
   pushes the coordination burden onto the user.*

## Decision

Four coupled mechanisms:

1. **Access is per-`Person`, not per-folder.** A `FolderMembership` grants a role scoped to a set of
   `PersonId`s and a set of sections.
2. **Private Annex.** Any adult in a folder may hold their own credential and a private store the
   folder owner **cannot enumerate** — not merely cannot read, cannot see the existence of. Enforced
   by a second RLS predicate keyed to `OwnerUserId`, so a `COUNT(*)` returns the same number whether
   the annex holds three items or none.
3. **Quiet Exit.** An adult may sever participation, revoke consent, and request erasure of their
   private annex, generating **zero notifications to any other member**. The shared folder shows
   only "Participant no longer active", with no reason and no precise date.
4. **Person-scoped agent retrieval.** Interview agents are bound to one `person_id` at the data
   layer. A query for another person's answers returns empty because of the query scope, not because
   a prompt told the model not to look.

## Consequences

**Positive.** The platform cannot be used as a surveillance tool by one household member against
another. Meets the safety bar required before the sensitive-matter segment can be considered.

**Negative.** 21 story points. The authorization model is materially more complex — every query
carries a person scope, and every UI surface must be designed twice (owner view, participant view).
The API response shape must be identical regardless of annex contents, which constrains what we can
return.

**Neutral.** Some legitimate coordination becomes harder: a folder owner genuinely helping a spouse
cannot see everything. This is the correct trade — the cost falls on convenience, the benefit falls
on safety.

## Compliance and enforcement

FR-CASE-003 · dual RLS predicates ([05 §5.4](../05-data-architecture.md#54-row-level-security)) ·
household boundary invariant test in CI asserting (a) a folder owner cannot enumerate an annex and
(b) Quiet Exit generates zero notification rows.

## Revisit triggers

None. This is a safety property, not an optimization.
