# ADR-002 — No electronic filing

**Status:** Accepted · **Date:** 2026-08-01
**Deciders:** Principal Integration Architect, CTO, CPO
**Consulted:** Compliance Officer, CISO
**Related:** [C-02](../00-design-authority-record.md#c-02--workflow-step-15-assumes-an-e-filing-capability-that-does-not-exist)

## Context

The brief's workflow ends with "documents are exported or securely emailed," but the surrounding
roadmap discussion assumed eventual direct submission to the agency.

There is no general-purpose third-party filing API for USCIS. USCIS online filing is an interactive
human experience bound to a myUSCIS account; attorney and representative accounts exist but are not
machine-accessible to vendors. The Department of State's CEAC forms (DS-160, DS-260) are likewise
interactive-only. Automating a login-bound government portal on a user's behalf would require us to
hold or proxy the user's government credentials, would be a terms-of-service violation, and would
create a credential-handling risk profile we are not willing to accept for this population.

## Options considered

1. **Browser automation of the agency portal on the user's behalf.** *Rejected — ToS violation,
   credential custody risk, brittle, and an outage would strand filings at the worst moment.*
2. **Partner with a filing service.** *Rejected for v1 — the same problems, one step removed, plus
   a dependency on a third party's compliance posture.*
3. **Terminate at a generated, verified package handed to the human.** *Selected.*

## Decision

The workflow terminates at **package generation and delivery to the human**. All "submission"
language is removed from every product surface and replaced with "ready to file."

To make that ending genuinely useful rather than merely safe, the package includes a **Filing
Checklist** — where to file, the fee, which edition, and every point requiring a wet-ink signature —
each element a cited transcription of the agency's own published instructions.

## Consequences

**Positive.** Removes an entire class of legal, security, and reliability risk. Keeps the user in
control of the moment that matters most to them. Makes the "we are not your representative" position
coherent — we could not file for you even if you asked.

**Negative.** The last mile is manual. Some users will assemble a perfect package and never file it.
That drop-off is real and should be measured, and the Filing Checklist is the intervention.

**Neutral.** Descoped 21 story points; added 13 for the checklist and fee sheet.

## Revisit triggers

An agency publishes a documented, supported third-party filing API with terms permitting our use.
That is the only trigger. Absent it, this decision stands.
