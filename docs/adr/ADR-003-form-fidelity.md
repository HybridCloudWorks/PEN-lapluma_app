# ADR-003 — Fill the agency's own AcroForm; never redraw a form

**Status:** Accepted · **Date:** 2026-08-01
**Deciders:** Lead Backend Architect, Principal Application Architect, CTO
**Consulted:** Compliance Officer, Lead QA Architect, Catalog Operations
**Related:** [C-03](../00-design-authority-record.md#c-03--pdf-generation-against-government-forms-is-harder-than-the-brief-assumes), RISK-003

## Context

Producing a filled government form looks like a solved problem and is not. Two failure modes are
severe and both are silent.

**Edition drift.** Agencies reject packages submitted on superseded form editions. Edition dates
change without notice, and the field set can change with them. Generating from a stale template
produces a rejectable filing that looks perfect.

**Encoding.** Many current federal forms are AcroForm PDFs and can be filled programmatically. Some
legacy federal, and many state and county, forms are dynamic **XFA** PDFs, which most PDF libraries
cannot fill correctly and which render as "please use Adobe Reader" in Apple's PDFKit.

A third, quieter failure: a field map that puts the right value in the wrong box produces a document
that passes every automated check and is wrong in a way only an adjudicator will notice.

## Options considered

1. **Recreate the form's appearance and fill our own rendering.** *Rejected — the output is not the
   agency's form. Layout drift, missing revision markers, and rejection risk. Also invites the
   question of whether we have altered a government document.*
2. **Fill the agency's published AcroForm.** *Selected.*
3. **Data sheet only; the user transcribes.** *Rejected as the default — it discards most of the
   product's value. Retained as the fallback for non-AcroForm encodings.*

## Decision

Four coupled mechanisms:

1. **Form Catalog as a first-class service.** Every form stored as
   `(form_id, edition_date, agency, source_url, sha256, field_map_version, encoding)`.
2. **Daily edition-drift monitor.** Hash the agency's published PDF. On change: create a new version
   row, mark the old `SUPERSEDED`, move affected in-flight cases to `QUARANTINED_FORM_DRIFT`, and
   notify within 1 hour with a guided migration that flags every field that changed, appeared, or
   disappeared.
3. **Edition pinning.** A case pins editions at creation; generation pins again and records both in
   the approval record and the PDF metadata.
4. **Round-trip verification.** Re-parse the generated PDF, re-extract every field, assert equality
   with the source record. **Any mismatch fails generation.** It does not warn.

Field maps require **two-person approval** and a passing per-form fixture test before activation.
Overflow generates a conforming addendum; truncation is never acceptable. `XFA` and `FLAT` forms are
**Assisted-Fill-Only** with the limitation stated plainly on screen, and MVP scope is restricted to
`ACROFORM` forms.

## Consequences

**Positive.** Output is the agency's own document. Silent wrongness becomes loud failure. Drift is
caught in hours rather than by a rejection notice months later.

**Negative.** 34 story points added. Catalog operations becomes a permanent staffed function. Some
forms — particularly state and county — cannot be filled at all, which constrains
[OPEN-04](../12-risks-and-gap-analysis.md#127-open-decisions). Generation is slower.

**Neutral.** Makes the walking skeleton the highest-priority Phase 0 deliverable, because if this
does not work reliably, nothing else matters.

## Compliance and enforcement

FR-FORM-001..008 · `Package.VerificationPassed` is a database check constraint that cannot be
false · fixture test per form-version in CI · G0 exit requires the drift monitor to catch a
simulated edition change.

## Revisit triggers

An agency publishes structured form definitions (a schema rather than a PDF). That would simplify
this substantially and should be adopted immediately if it happens.
