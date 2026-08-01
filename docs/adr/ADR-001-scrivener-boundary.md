# ADR-001 — The scrivener boundary: no legal advice, enforced in code

**Status:** Accepted · **Date:** 2026-08-01
**Deciders:** Compliance Officer (veto holder), CPO, CAIO, Responsible AI Lead
**Consulted:** Outside counsel (three jurisdictions), Risk Officer, Principal Security Architect
**Related:** [C-01](../00-design-authority-record.md#c-01--form-discovery-agent-as-briefed-is-unauthorized-practice-of-law), [09 §9.3](../09-responsible-ai.md#93-the-legal-advice-classifier)

## Context

The brief asks for a "Form Discovery Agent" that identifies requirements, and a workflow step in
which "the platform identifies requirements." Read naturally, that means: look at an applicant's
circumstances and determine what they should file.

In the United States, applying law to an individual's facts to select a remedy is the practice of
law under every state's formulation. In immigration specifically it is the conduct that state
attorneys general and federal courts prosecute as *notario* fraud. The federal exemption permitting
non-attorney "accredited representatives" (8 C.F.R. part 1292 subpart B) attaches to recognized
organizations and accredited individuals — not to software vendors.

The consequence of getting this wrong is not a fine. It is an injunction, and it is harm to people
who relied on us.

The CPO's position was that form discovery is the product's core differentiator and removing it
guts the value proposition. That position was heard and is recorded.

## Options considered

1. **Full discovery.** The agent reads the case and recommends a form package.
   *Rejected — unauthorized practice of law.*
2. **Discovery with a disclaimer.** As above, with prominent "this is not legal advice" text.
   *Rejected — a disclaimer does not change the character of the act. Courts look at what was done,
   not what was labelled.*
3. **Discovery behind an attorney.** The agent recommends; an attorney approves.
   *Rejected for v1 — it makes every consumer case require an attorney, which destroys the consumer
   product, and it makes us the source of a recommendation the attorney is then pressured to ratify.*
4. **Retrieval, not inference.** The human selects; the agent retrieves that selection's published
   requirements with citations. *Selected.*
5. **No form guidance at all.** *Rejected — unnecessarily restrictive; retrieving published
   requirements for a chosen form is transcription, not advice.*

## Decision

The platform is a **scrivener**. It transcribes and organizes information the user supplies onto a
form the user (or their credentialed representative) selected. It does not select, assess, predict,
or advise.

Enforced by five mechanisms, of which only the last is a policy:

1. **Architectural.** The Form Discovery Agent has **no access to case, person, or document data**.
   It cannot personalize because it cannot see the person. The catalog API accepts no case data
   ([07 §7.8](../07-api-architecture.md#78-form-catalog-apis)), so personalization is not
   disallowed — it is impossible.
2. **Classifier.** A three-stage Legal Advice Classifier sits on every generative egress path,
   tuned for recall, failing closed, blocking on ambiguity.
3. **Deterministic refusals.** Substitute text is written, reviewed, and static, so a refusal cannot
   itself drift into advice.
4. **Blocking gate.** An adversarial corpus of ≥ 1,000 prompts across nine speech acts and every
   supported language must produce **zero escapes** or the build does not ship.
5. **Governance.** The Compliance Officer holds an absolute veto over any change to this boundary.

## Consequences

**Positive.** Defensible in front of a regulator. Removes the single largest existential risk.
Differentiates us honestly from the operators we compete against. Makes every downstream design
question easier, because the answer to "should the AI decide this?" is already settled.

**Negative.** Users will be frustrated — the most-asked question is one we will not answer
([UR-01](../12-risks-and-gap-analysis.md#usability-risks)). A less scrupulous competitor will
out-feature us here, and we will lose some users to them (RISK-031, accepted). Roughly 8 % of benign
generative turns will be blocked as false positives, which is a real usability cost we are choosing.

**Neutral.** Creates the opening for [§13.2 Supervised Guidance](../13-v2-recommendations.md#132-supervised-guidance-a-human-in-the-loop-not-a-model-in-the-loop),
which addresses the frustration by changing *who* answers rather than *whether* we answer.

## Compliance and enforcement

FR-COMP-001..009 · test suite `UPL-*` · `UPL-GATE` in CI · 1 % production sampling with weekly
Compliance review · per-jurisdiction outside-counsel opinions before state-specific marketing.

## Revisit triggers

None that would relax the boundary. The boundary changes only if the underlying law changes, and
that assessment belongs to outside counsel, not to engineering or product.
