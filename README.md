# Aperture — Application Preparation Platform

**Codename:** Aperture
**Working title:** Work-Application_Builder
**Document class:** Enterprise Solution Definition (ESD) — **Rev B**
**Status:** Conditionally signed off by all 18 discipline SMEs; approved for Architecture Review Board (ARB) and Security Review Board (SRB) intake
**Date:** 2026-08-01

---

## What this repository contains

This repository holds the complete, board-ready solution definition for **Aperture**, a native
Apple-platform (iOS / iPadOS / macOS) application that helps applicants and administrators
**prepare** immigration-related and government-agency applications — by collecting information,
extracting data from documents, conducting AI-guided interviews, validating completeness, filling
official agency forms, and generating a reviewable, exportable application package.

> ### Governing constraint — read this first
>
> **Aperture is not a law firm and does not provide legal advice.** It does not assess eligibility,
> predict outcomes, recommend which benefit to seek, or represent anyone before any agency. It is a
> *scrivener-class* tool: it organizes information the user supplies, transcribes it onto the
> official form the user (or their authorized legal representative) selected, and shows the user
> what is missing. Every architectural, product, and AI decision in this repository is subordinate
> to that constraint. See [§ 9 Responsible AI](docs/09-responsible-ai.md) and the
> [Unauthorized Practice of Law firewall](docs/06-security-architecture.md#68-the-upl-firewall-as-a-security-control).

---

## The single deliverable

The complete deliverable is the **document set below, read in order**. Each part is
self-contained enough to be handed to the owning function, and cross-linked so the whole reads as
one program definition.

| # | Document | Primary audience | Owner |
|---|---|---|---|
| 00 | [Design Authority Record](docs/00-design-authority-record.md) — who decided what, and every challenge raised and resolved | ARB, SRB, Exec | Principal Enterprise Architect |
| 01 | [Executive Summary](docs/01-executive-summary.md) | Board, Exec, Investors | Chief Product Officer |
| 02 | [Product Requirements Document](docs/02-product-requirements.md) — personas, stories, epics, acceptance criteria, MVP/P2/P3 scope | Product, Engineering, QA | Senior Product Manager |
| 03 | [Solution Architecture](docs/03-solution-architecture.md) — C4, logical/physical/integration/deployment, technology selection | ARB, Engineering | Principal Enterprise Architect |
| 04 | [AI Agent Architecture](docs/04-ai-agent-architecture.md) — the 23-agent framework, contracts, orchestration, failure and escalation | AI Team, ARB, Risk | AI Architect / Agentic AI Architect |
| 05 | [Data Architecture](docs/05-data-architecture.md) — canonical model, relational DDL, document model, metadata, retention | Data, Engineering, Privacy | Principal Data Architect |
| 06 | [Security Architecture](docs/06-security-architecture.md) — Zero Trust, STRIDE, attack paths, PIA | SRB, CISO, Risk | Principal Security Architect |
| 07 | [API Architecture](docs/07-api-architecture.md) — endpoints, payloads, versioning, errors, idempotency | Engineering, Integration | Principal Integration Architect |
| 08 | [UX Design](docs/08-ux-design.md) — IA, navigation, journeys, screen inventory and specifications | Design, Mobile Engineering | UX Architect |
| 09 | [Responsible AI](docs/09-responsible-ai.md) — guardrails, explainability, confidence, bias, consent | Responsible AI Lead, Compliance | Responsible AI Lead |
| 10 | [DevSecOps & Business Continuity](docs/10-devsecops-and-continuity.md) — CI/CD, IaC, test strategy, observability, BC/DR | Platform, SRE, QA | Lead DevSecOps Architect |
| 11 | [Roadmap](docs/11-roadmap.md) — phasing, sequencing, staffing, cost model | Exec, PMO | Chief Product Officer |
| 12 | [Risks & Gap Analysis](docs/12-risks-and-gap-analysis.md) — the adversarial review, register, and mitigations | Risk, Exec, ARB, SRB | Risk Officer |
| 13 | [Version 2 Recommendations](docs/13-v2-recommendations.md) | Exec, Product Strategy | Chief Technology Officer |
| 14 | [**SME Adversarial Review and Sign-Off**](docs/14-sme-review-and-signoff.md) — the review of *this deliverable*: 41 findings, 10 blocking, and the signature block | ARB, SRB, Exec, Board | Chief Technology Officer |

### Appendices

| Ref | Contents |
|---|---|
| [Appendix A](docs/appendix/appendix-a-backlog.md) | Full epic → feature → story backlog with story points |
| [Appendix B](docs/appendix/appendix-b-traceability.md) | Requirements traceability matrix (requirement → design → test → control) |
| [Appendix C](docs/appendix/appendix-c-glossary.md) | Glossary and controlled vocabulary |
| [ADRs](docs/adr/) | Architecture Decision Records ADR-001 … ADR-012 |

---

## The five decisions that define this program

Everything else follows from these. They were the contested points; the reasoning and the dissent
are recorded in [00 — Design Authority Record](docs/00-design-authority-record.md).

1. **Scrivener, not advisor.** The AI never selects a benefit category, never scores eligibility,
   never estimates approval odds. Form selection is an act of the user or their credentialed
   representative. A dedicated classifier gates *every* generative output for legal-advice leakage.
   → [ADR-001](docs/adr/ADR-001-scrivener-boundary.md)

2. **There is no e-filing.** No general-purpose third-party filing API exists for USCIS or the
   Department of State. The workflow terminates in a **generated, validated, exportable package**
   that the human files. Any roadmap item implying "we submit it for you" is descoped.
   → [ADR-002](docs/adr/ADR-002-no-efiling.md)

3. **We fill the government's PDF; we never redraw it.** Packages are produced by filling the
   agency's own published AcroForm, pinned to a specific **form edition date**, with an
   edition-drift monitor that quarantines packages when the agency republishes a form.
   → [ADR-003](docs/adr/ADR-003-form-fidelity.md)

4. **Household folders are not one trust boundary.** A petitioner and a beneficiary can have
   adverse interests (abuse, fraud, coercion). Access is per-*person* within a folder, with a
   silent-exit path. This is a safety requirement, not a permissions nicety.
   → [ADR-007](docs/adr/ADR-007-household-trust-boundaries.md)

5. **Azure-native, Apple-native, dual-runtime backend.** .NET 9 for the transactional core and
   Python for the AI/document runtime, both on Azure Container Apps behind API Management; SwiftUI
   with a shared Swift Package across iOS/iPadOS/macOS.
   → [ADR-004](docs/adr/ADR-004-backend-runtime.md), [ADR-005](docs/adr/ADR-005-compute-platform.md)

---

## MVP in one paragraph

A US-based applicant, or a paralegal at a small immigration practice, creates a secure **Virtual
Applicant Folder**, selects a supported **form package** (MVP: I-130 + I-130A, I-485 + I-864,
N-400, I-765), photographs their documents with the iPhone camera, and watches the platform
classify, OCR, and extract fields into a reviewable **Extraction Ledger** where every value carries
a source citation and a confidence band. Where data is missing or ambiguous, an **AI chat or voice
interview** asks only the questions the selected forms actually require. Two mechanical counters
and a **Missing Items** queue drive the applicant to done. A human reviewer approves, and the
platform generates the filled official PDFs plus a cover index and evidence exhibit set, exported
to Files, printed, or delivered by secure link. Nothing is auto-filed and nothing is advised.

---

## How to review this document set

- **Architecture Review Board:** read 03 → 05 → 07 → 04, then the ADRs, then 12 and **14**.
- **Security Review Board:** read 06 → 09 → 10 §10.6, then 12 §12.4, the PIA in 06 §6.11, and **14 §14.3** (the blocking findings are mostly security ones).
- **Product / Exec:** read 01 → 02 → 11 → 12 → 14 → 13.
- **Engineering intake:** read 02 → 08 → 07 → 05 → Appendix A.

Every open question is tracked in [12 — Risks & Gap Analysis](docs/12-risks-and-gap-analysis.md)
with an owner and a decision-required-by date. There are **no unowned open questions** in this
revision.

---

## What changed in Rev B

Rev A was reviewed by all 18 discipline SMEs under an instruction to assume it was wrong and find
where. They raised **41 admissible findings, of which 10 were blocking** — internal contradictions,
constructs that could not work as written, or safety claims the design did not support. All ten are
remediated here; five further findings are accepted as residual with named owners.

The most consequential:

| # | Finding | Effect on the design |
|---|---|---|
| [B-01](docs/14-sme-review-and-signoff.md#b-01--the-voice-interview-cannot-be-guardrailed-the-way-the-deliverable-claims) | Voice guardrails **cannot** be preventive — our backend is not in the media path | Redesigned to interrupt-and-correct; residual exposure window disclosed as RISK-032; voice gated on CON-1 or cut from MVP |
| [B-02](docs/14-sme-review-and-signoff.md#b-02--the-fieldvalue-unique-index-makes-the-never-overwrite-a-human-rule-unimplementable) | The `FieldValue` index made "never overwrite a human" impossible to implement | Proposal split from authoritative value |
| [B-04](docs/14-sme-review-and-signoff.md#b-04--row-level-security-enforces-tenant-isolation-only-the-deliverable-claims-more) / [B-05](docs/14-sme-review-and-signoff.md#b-05--isplatformoperation-is-a-single-boolean-that-disables-the-entire-isolation-model) | RLS enforced tenant only, and carried a boolean that disabled it globally | Folder-scope predicate added; bypass flag deleted; scoped break-glass principal |
| [B-06](docs/14-sme-review-and-signoff.md#b-06--the-processing-zone-writes-to-the-documents-store-breaking-its-own-isolation-claim) | The hostile-input zone had write access to every applicant's documents | Create-only staging container; promotion by a Core-zone service |
| [B-07](docs/14-sme-review-and-signoff.md#b-07--a-fixed-1000-prompt-corpus-with-a-zero-escape-bar-is-an-overfittable-gate) / [B-08](docs/14-sme-review-and-signoff.md#b-08--extraction-accuracy-is-measured-on-synthetic-documents-and-reported-as-if-it-were-real) | The two headline quality numbers were unfalsifiable as specified | Held-out corpus the engineers never see; consented real-document evaluation set |
| [B-09](docs/14-sme-review-and-signoff.md#b-09--phase-1-does-not-fit-in-phase-1) | Phase 1 was 17 % short, described as 18 % buffered | Rebaselined: 24 weeks, four packages, +$0.4 M — stated, not absorbed |

Six of the ten blocking findings are the same defect in different clothes: **a control described in
the confident register of something already built**. That pattern, not any individual bug, is the
finding behind the findings — see [14 §14.7](docs/14-sme-review-and-signoff.md#147-what-this-review-says-about-rev-a).

**Sign-off is conditional.** Eight conditions are attached
([14 §14.8](docs/14-sme-review-and-signoff.md#148-conditions-attached-to-sign-off)); four are Phase-0
exit blockers. Two disciplines — Agentic AI and Responsible AI — sign conditionally.

---

## Code

| Path | Contents | Status |
|---|---|---|
| [`apps/packages/ApertureKit`](apps/packages/ApertureKit) | Shared Swift package: domain types, API client + stub, design system | **Builds; 39 tests pass** |
| [`apps/ios/ApertureApp`](apps/ios/ApertureApp) | iOS applicant app, screens S-01…S-15, plus [`ApertureApp.xcodeproj`](apps/ios/ApertureApp.xcodeproj) | **Built and XCUITest-verified on iPhone Simulator** |

> **Verified August 2, 2026 with Xcode 26.6:** the package builds and its 39 Swift
> Testing cases pass; the app builds for an iPhone 17 simulator, launches, completes
> local onboarding, and restores the authenticated home screen from persisted state.
> Fifteen serial journeys in `ApertureAppUITests` now enforce onboarding/persistence,
> authenticated navigation, folder and application creation, human field confirmation,
> secure package delivery, Spanish core navigation, and accessibility XXXL primary-action
> reachability. They also verify the active accessibility profile's voice-first flow,
> enlarged controls, consent gate, locally waived voice-time budget, automated core-surface
> accessibility checks, operation with key system accessibility preferences enabled, and
> explicit offline access to capture and structured manual entry. The E-06 journey also
> verifies fail-closed package generation, attributed correction history, and relaunch
> persistence.
> The capture boundary also strips source image metadata, enforces published size/page
> limits, and retains protected local bytes until SHA-256 integrity is confirmed.
> Large queued captures wait for Wi-Fi by default on cellular or Low Data Mode, with a
> visible queue estimate and a deliberate user override.
> Applicants can also review a classification confidence band, authoritatively correct
> the document type, and retain that decision across relaunches; opened and sealed I-693
> safeguards refuse extraction by policy.
> The shared extraction-safety boundary drops unanchored engine claims, forces ambiguous
> dates and instruction-like content into explicit review, and preserves original-script
> names beside any transliteration.
> See [`apps/ios/ApertureApp/README.md`](apps/ios/ApertureApp/README.md) for the exact
> verification commands, remaining stubs, and invariants the types enforce.
> Mobile configuration and external dependencies are tracked in
> [`MOBILE_IMPLEMENTATION_LEDGER.md`](MOBILE_IMPLEMENTATION_LEDGER.md).
>
> `tools/check-swift-static.py` remains a separate source-policy gate for delimiter
> balance, banned APIs, forbidden third-party SDKs, and localisation key parity.

The macOS reviewer workbench (screens S-16–S-18) is a separate target and is not yet
scaffolded.

---

## Repository conventions

| | |
|---|---|
| **Default branch** | `main` |
| **Source of truth for documentation** | `docs/` on `main` |
| **Wiki** | A **generated mirror** of `docs/`, published by [`.github/workflows/publish-wiki.yml`](.github/workflows/publish-wiki.yml) on every push to `main`. **Do not edit the wiki directly** — edits are overwritten on the next publish. Raise a pull request against `main` instead |
| **Wiki build** | [`tools/build-wiki.py`](tools/build-wiki.py) flattens `docs/` to wiki page names and rewrites every internal link; [`tools/check-wiki-links.py`](tools/check-wiki-links.py) fails the workflow on any dead page or anchor |

Run the wiki build locally with:

```bash
git clone https://github.com/<owner>/<repo>.wiki.git /tmp/wiki
python3 tools/build-wiki.py . /tmp/wiki
python3 tools/check-wiki-links.py /tmp/wiki
```
