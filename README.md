# Aperture — Application Preparation Platform

**Codename:** Aperture
**Working title:** Work-Application_Builder
**Document class:** Enterprise Solution Definition (ESD) — Rev A
**Status:** Approved for Architecture Review Board (ARB) and Security Review Board (SRB) intake
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
N-400, I-765, I-131), photographs their documents with the iPhone camera, and watches the platform
classify, OCR, and extract fields into a reviewable **Extraction Ledger** where every value carries
a source citation and a confidence score. Where data is missing or ambiguous, an **AI chat or voice
interview** asks only the questions the selected forms actually require. A **completeness meter**
and a **Missing Items** queue drive the applicant to done. A human reviewer approves, and the
platform generates the filled official PDFs plus a cover index and evidence exhibit set, exported
to Files, printed, or delivered by secure link. Nothing is auto-filed and nothing is advised.

---

## How to review this document set

- **Architecture Review Board:** read 03 → 05 → 07 → 04, then the ADRs, then 12.
- **Security Review Board:** read 06 → 09 → 10 §10.6, then 12 §12.4 and the PIA in 06 §6.11.
- **Product / Exec:** read 01 → 02 → 11 → 12 → 13.
- **Engineering intake:** read 02 → 08 → 07 → 05 → Appendix A.

Every open question is tracked in [12 — Risks & Gap Analysis](docs/12-risks-and-gap-analysis.md)
with an owner and a decision-required-by date. There are **no unowned open questions** in this
revision.
