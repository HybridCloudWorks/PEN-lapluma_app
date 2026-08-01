# ADR-010 — Three confidence bands from measurable signals, never model self-report

**Status:** Accepted · **Date:** 2026-08-01
**Deciders:** Responsible AI Lead, CAIO, Lead QA Architect
**Consulted:** UX Architect, Principal Data Architect
**Related:** [C-14](../00-design-authority-record.md#c-14--confidence-scores-from-a-language-model-are-not-calibrated-probabilities)

## Context

The brief requires "confidence scoring." The obvious implementation — ask the model how confident it
is and display the number — produces a fluent, plausible figure that is unrelated to accuracy.

Displaying "94% confident" beside a person's date of birth is worse than displaying nothing. It
manufactures assurance exactly where verification matters most, and it will cause reviewers to skip
checking the values most likely to be wrong.

## Options considered

1. **Model self-reported confidence, displayed as a percentage.** *Rejected — uncalibrated and
   actively harmful.*
2. **Raw engine confidence, displayed as a percentage.** *Rejected — better grounded, but a
   percentage invites false precision and means nothing to María.*
3. **Three bands derived from measurable signals, with plain-language meanings.* *Selected.*
4. **No confidence indication at all.** *Rejected — reviewers need to prioritize, and users deserve
   to know when we are unsure.*

## Decision

Confidence comes only from signals that can be measured:

- the document AI service's own per-field confidence (trained and calibrated on the extraction task);
- deterministic cross-source agreement;
- checksum validation (MRZ, A-Number format);
- presence and quality of a source anchor;
- capture-quality signals from the device.

**Model self-report is not used anywhere, for anything.**

Three bands with defined meanings: `VERIFIED` · `EXTRACTED` · `NEEDS_REVIEW`. Applicants see the
band and a plain-language sentence. **Numeric scores are never shown to an applicant**; they are
retained in the ledger for calibration analysis and shown in the reviewer workbench, where the
audience is trained and the number is actionable.

Enforced in the schema, not in application code: `CK_EV_ModelNeedsReview` requires that any
model-generated value carries band `NEEDS_REVIEW`, and `CK_EV_ChecksumBand` requires that a failed
checksum cannot be `VERIFIED`.

Bands are **not static configuration**. They are retuned against measured reviewer behavior — if
reviewers edit `VERIFIED` values more than 3 % of the time, the band has not earned its name and the
threshold moves.

## Consequences

**Positive.** Confidence means something and can be validated against ground truth. Reviewers can
prioritize honestly. Calibration becomes a measurable property with a target (ECE ≤ 0.08 → 0.05).

**Negative.** Less granular than a percentage, which some reviewers will want. Requires ongoing
calibration work — a monthly report and a retuning process — rather than a one-time implementation.

**Neutral.** Forces the uncomfortable but correct admission that we cannot always tell how sure we
are, and that saying "we're not sure, please check" is a feature.

## Revisit triggers

If a model provider ships genuinely calibrated confidence with published reliability curves,
reassess. Until then, this stands.
