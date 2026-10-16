---
title: LaPluma solution definition
---

# LaPluma solution definition

LaPluma (internal codename **Aperture**) is a native Apple-platform application that helps
applicants and administrators **prepare** immigration-related and government-agency
applications: it collects information, extracts data from the user's own documents, fills the
official agency forms, and produces a reviewable, exportable package that the human files.

This site publishes the Enterprise Solution Definition (**Rev B**, 2026-08-01) and its
Architecture Decision Records. [ADR-019](adr/ADR-019-lean-gcp-document-library.md)
(2026-09-13) has since replaced the Azure platform choices with a lean GCP architecture and
the Document Library; where documents 00–14 still describe Azure, ADR-019 takes precedence.

> **LaPluma is not a law firm and does not give legal advice.** It is a scrivener-class tool:
> it organizes information the user supplies and transcribes it onto the official form the
> user, or their authorized legal representative, selected. See
> [09 Responsible AI](09-responsible-ai.md).

Start with [00 Design Authority Record](00-design-authority-record.md) for decision rights and
[14 SME Review & Sign-Off](14-sme-review-and-signoff.md) for the conditions attached to
sign-off.

## On this site

**Governance**

- [00 Design Authority Record](00-design-authority-record.md)
- [14 SME Review & Sign-Off](14-sme-review-and-signoff.md)

**Product**

- [01 Executive Summary](01-executive-summary.md)
- [02 Product Requirements](02-product-requirements.md)
- [11 Roadmap](11-roadmap.md)
- [12 Risks & Gap Analysis](12-risks-and-gap-analysis.md)
- [13 V2 Recommendations](13-v2-recommendations.md)

**Architecture**

- [03 Solution Architecture](03-solution-architecture.md)
- [04 AI Agent Architecture](04-ai-agent-architecture.md)
- [05 Data Architecture](05-data-architecture.md)
- [07 API Architecture](07-api-architecture.md)

**Assurance**

- [06 Security Architecture](06-security-architecture.md)
- [09 Responsible AI](09-responsible-ai.md)
- [10 DevSecOps & Continuity](10-devsecops-and-continuity.md)

**Design**

- [08 UX Design](08-ux-design.md)

**[Architecture Decision Records](adr/README.md)**

- [019 Approved GCP and Document Library](adr/ADR-019-lean-gcp-document-library.md)
- [001 Scrivener Boundary](adr/ADR-001-scrivener-boundary.md)
- [002 No E-Filing](adr/ADR-002-no-efiling.md)
- [003 Form Fidelity](adr/ADR-003-form-fidelity.md)
- [004 Backend Runtime](adr/ADR-004-backend-runtime.md)
- [005 Compute Platform](adr/ADR-005-compute-platform.md)
- [006 Polyglot Persistence](adr/ADR-006-polyglot-persistence.md)
- [007 Household Trust](adr/ADR-007-household-trust-boundaries.md)
- [008 Capability Boundary](adr/ADR-008-agent-capability-boundary.md)
- [009 Durable Orchestration](adr/ADR-009-durable-orchestration.md)
- [010 Confidence Banding](adr/ADR-010-confidence-banding.md)
- [011 Passkeys, No SMS](adr/ADR-011-passkeys-no-sms.md)
- [012 No 3rd-Party SDKs](adr/ADR-012-no-third-party-client-sdks.md)
- [013 Alpha 0.2 Boundaries](adr/ADR-013-alpha-02-platform-boundaries.md)
- [014 Delivery-Anchored Retention](adr/ADR-014-delivery-anchored-retention.md)
- [015 LaPluma Name & Repo Boundary](adr/ADR-015-lapluma-name-and-repository-boundary.md)
- [016 Role-Adaptive Boundaries](adr/ADR-016-role-adaptive-platform-boundaries.md)
- [017 Isolated Demo Tenancy](adr/ADR-017-isolated-demo-tenancy.md)
- [018 Public Evidence Relay](adr/ADR-018-public-evidence-relay-capability.md)

**Appendices**

- [A — Backlog](appendix/appendix-a-backlog.md)
- [B — Traceability](appendix/appendix-b-traceability.md)
- [C — Glossary](appendix/appendix-c-glossary.md)

---

This site is built from `docs/wiki/` on the `main` branch of
[PEN-lapluma_app](https://github.com/HybridCloudWorks/PEN-lapluma_app). Edit the files there
through a pull request, not the site.
