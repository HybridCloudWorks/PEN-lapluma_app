# Appendix A — Product Backlog

**Owner:** Senior Product Manager · Estimation: modified Fibonacci (1, 2, 3, 5, 8, 13, 21, 34)
· Team velocity assumption: 45 points/sprint/stream, 4 parallel streams, 2-week sprints.

**MVP total: 1,478 points** across E-01…E-20. At 4 streams × 45 points × 10 sprints = 1,800 point
capacity, this carries ~18 % buffer, which is appropriate given that 276 points of this backlog were
added by the design review itself ([12 §12.2](../12-risks-and-gap-analysis.md#122-missing-features-found-and-closed)).

Legend: **[R]** = added by the adversarial review · **[G]** = gates a release · **[S]** = safety-critical

---

## E-01 — Identity & Account · 55 pts

| ID | Story | Pts | Notes |
|---|---|---|---|
| US-01.01 | Register with a passkey | 8 | [ADR-011](../adr/ADR-011-passkeys-no-sms.md) |
| US-01.02 | Sign in with a passkey | 3 | |
| US-01.03 | Email OTP + TOTP fallback with `AUTH_DOWNGRADED` flag | 8 | |
| US-01.04 | Recover access without losing my case | 13 | **[S]** Annex isolation survives takeover |
| US-01.05 | See and revoke my active sessions and devices | 5 | |
| US-01.06 | Understand what happens to my data before I give any | 5 | **[R]** Pre-account disclosure |
| US-01.07 | Step-up authentication bound to purpose and resource | 8 | **[S]** |
| US-01.08 | Account deletion from Settings | 5 | |

## E-02 — Virtual Folder & Case · 89 pts

| ID | Story | Pts | Notes |
|---|---|---|---|
| US-02.01 | Create a folder | 8 | |
| US-02.02 | Rename, archive and delete a folder | 5 | |
| US-02.03 | Add a household member as a person, not a field | 13 | |
| US-02.04 | Define relationships between people | 8 | |
| US-02.05 | Adult household members control their own information | 13 | **[R][S]** Private Annex + Quiet Exit |
| US-02.06 | Invite an adult participant to hold their own credential | 8 | |
| US-02.07 | See exactly who can see what (Access tab) | 8 | **[S]** Safety surface |
| US-02.08 | Grant a helper limited, attributed access | 8 | **[R]** |
| US-02.09 | Revoke access with 60-second propagation | 5 | **[S]** |
| US-02.10 | Case state machine with audited transitions | 13 | |

## E-03 — Form Catalog & Package Selection · 76 pts

| ID | Story | Pts | Notes |
|---|---|---|---|
| US-03.01 | Browse and select a package without being advised | 8 | **[S]** [ADR-001](../adr/ADR-001-scrivener-boundary.md) |
| US-03.02 | Ingest a form and extract its field inventory | 13 | **[R]** |
| US-03.03 | Propose and two-person-approve a field map | 13 | **[R][S]** |
| US-03.04 | Requirements derived from agency instructions with citations | 13 | **[S]** |
| US-03.05 | Pin form editions at case creation | 5 | **[R]** |
| US-03.06 | Edition drift detection, quarantine and guided migration | 13 | **[R][S]** RISK-003 |
| US-03.07 | Selection attestation before a case can be created | 3 | **[S]** |
| US-03.08 | Fee and filing-address retrieval with citation | 8 | **[R]** |

## E-04 — Document Capture & Ingest · 89 pts

| ID | Story | Pts | Notes |
|---|---|---|---|
| US-04.01 | Scan with the camera and know immediately if it's good | 13 | **[R]** Highest-leverage quality control |
| US-04.02 | Multi-page capture with reorder and re-shoot | 8 | |
| US-04.03 | Import from Photos, Files, or the share sheet | 8 | Limited-access picker only |
| US-04.04 | EXIF and GPS stripped on device and server-side | 5 | **[S]** |
| US-04.05 | Upload safely on a bad connection | 13 | **[R]** Chunked, resumable, background |
| US-04.06 | Offline capture and queued upload | 13 | **[R]** |
| US-04.07 | Non-visual capture path with audio framing guidance | 13 | **[R][G]** NFR-A11Y-010 |
| US-04.08 | Wi-Fi-only default on metered connections with data estimate | 5 | |
| US-04.09 | Client-side size and page-count rejection with guidance | 3 | |
| US-04.10 | SHA-256 integrity verification before local release | 3 | |
| US-04.11 | Deduplicate by content hash within a tenant | 5 | |

## E-05 — Classification, OCR & Extraction · 110 pts

| ID | Story | Pts | Notes |
|---|---|---|---|
| US-05.01 | Sanitization pipeline: type, AV, limits, active-content strip | 21 | **[S]** [06 §6.6](../06-security-architecture.md#66-secure-document-processing-pipeline) |
| US-05.02 | Documents classify themselves with human override | 13 | |
| US-05.03 | Sealed medical detection and opaque handling | 5 | **[R][S]** FR-DOC-014 |
| US-05.04 | Extraction produces citations, not assertions | 21 | **[S]** Source anchoring mandatory |
| US-05.05 | OCR routing by document class | 13 | |
| US-05.06 | Custom neural extractors for 8 document classes | 21 | |
| US-05.07 | Names handled correctly across scripts and conventions | 8 | **[R]** |
| US-05.08 | Dates normalized with ambiguity flagged for a human | 8 | **[R]** |

## E-06 — Extraction Review Ledger · 68 pts

| ID | Story | Pts | Notes |
|---|---|---|---|
| US-06.01 | See where every value came from | 13 | **[S]** |
| US-06.02 | Confidence bands with plain-language meanings | 8 | **[S]** [ADR-010](../adr/ADR-010-confidence-banding.md) |
| US-06.03 | Nothing reaches a form without a human | 8 | **[S]** DB check constraint |
| US-06.04 | Cross-source reconciliation and discrepancy creation | 13 | |
| US-06.05 | Correct a value; correction supersedes permanently | 8 | |
| US-06.06 | Value history with attribution (temporal tables) | 8 | |
| US-06.07 | Injection detection on extracted text | 5 | **[R][S]** |
| US-06.08 | Checksum validation for structured identifiers | 5 | |

## E-07 — Dynamic Questionnaire · 76 pts

| ID | Story | Pts | Notes |
|---|---|---|---|
| US-07.01 | Ask only what the form needs | 13 | |
| US-07.02 | Conditional logic derived from agency instructions, cited | 13 | **[S]** |
| US-07.03 | Question ordering that minimizes context switching | 8 | |
| US-07.04 | Recompute dependencies within 300 ms | 8 | |
| US-07.05 | Bilingual question rendering with English form label | 8 | **[R]** |
| US-07.06 | Reading-level-appropriate phrasing with CI measurement | 13 | **[G]** |
| US-07.07 | "I have a document for that" alternative on every question | 8 | |
| US-07.08 | Skip, defer, and "I don't know" without blocking | 5 | |

## E-08 — Chat Interview · 63 pts

| ID | Story | Pts | Notes |
|---|---|---|---|
| US-08.01 | Start a person-scoped chat session | 8 | **[S]** |
| US-08.02 | Chat interview that behaves (guardrail chain) | 13 | **[S][G]** |
| US-08.03 | Structured input affordances rather than prose parsing | 13 | |
| US-08.04 | Attach a document mid-conversation as an answer | 8 | |
| US-08.05 | VoiceOver: block-level announcement, not token streaming | 8 | **[R][G]** |
| US-08.06 | Transcript retained, exportable, and attorney-visible | 5 | **[S]** |
| US-08.07 | Graceful degradation to structured questionnaire | 8 | |

## E-09 — Voice Interview · 89 pts

| ID | Story | Pts | Notes |
|---|---|---|---|
| US-09.01 | Voice interview with informed, recorded consent | 21 | **[S]** [C-07](../00-design-authority-record.md#c-07--voice-interviews-create-biometric-and-wiretap-exposure) |
| US-09.02 | Ephemeral-key broker; audio never touches our backend | 13 | **[S]** |
| US-09.03 | No voiceprint anywhere, lint-enforced | 5 | **[S][G]** |
| US-09.04 | Say it in my language (EN/ES at MVP) | 8 | |
| US-09.05 | Task-scoped sessions with a voice-minute budget | 13 | **[R]** [C-11](../00-design-authority-record.md#c-11--cost-model-for-real-time-voice-is-not-viable-as-specified) |
| US-09.06 | Live transcript always visible | 5 | **[G]** Caption requirement |
| US-09.07 | Crisis and distress detection with resource handoff | 8 | **[R][S]** |
| US-09.08 | Switch to text at any time, answers preserved | 8 | |
| US-09.09 | Voice default and budget waived in the accessibility profile | 8 | **[G]** |

## E-10 — Validation & Missing Items · 71 pts

| ID | Story | Pts | Notes |
|---|---|---|---|
| US-10.01 | Know exactly what is missing, and why, with a citation | 13 | |
| US-10.02 | Deterministic rule engine with per-rule tests and citations | 21 | **[S]** |
| US-10.03 | Cross-form and cross-document consistency rules | 13 | |
| US-10.04 | Missing items assigned to exactly one person | 8 | **[R]** |
| US-10.05 | Progress that does not lie (mechanical counters only) | 8 | **[S]** [C-20](../00-design-authority-record.md#c-20--the-completion-percentage-will-be-read-as-a-prediction) |
| US-10.06 | Batching sized for a single sitting | 8 | |

## E-11 — Notifications · 42 pts

| ID | Story | Pts | Notes |
|---|---|---|---|
| US-11.01 | Content-free push and email payloads | 8 | **[S][G]** Contract-tested |
| US-11.02 | In-app inbox as the authoritative surface | 8 | |
| US-11.03 | Per-category preferences, quiet hours, digest, global pause | 8 | |
| US-11.04 | Non-suppressible security notifications | 5 | |
| US-11.05 | Batching and de-duplication | 5 | |
| US-11.06 | Zero notifications on Quiet Exit and Private Annex ops | 3 | **[S][G]** |
| US-11.07 | Deep links that re-verify entitlement on open | 5 | |

## E-12 — Human Review Workbench (macOS) · 97 pts

| ID | Story | Pts | Notes |
|---|---|---|---|
| US-12.01 | Reviewer queue with ageing and blocking reasons | 13 | |
| US-12.02 | Review a case at speed (three-column, keyboard-first) | 21 | |
| US-12.03 | Source region auto-highlight on field selection | 13 | |
| US-12.04 | Discrepancy resolution with side-by-side sources | 13 | |
| US-12.05 | Approve a package deliberately (step-up + attestation) | 13 | **[S][G]** |
| US-12.06 | Approval auto-invalidates on any value change | 8 | **[S]** |
| US-12.07 | Restricted bulk accept with per-value audit | 8 | **[S]** Automation-bias control |
| US-12.08 | Dwell-time capture for audit and calibration | 8 | **[R]** |

## E-13 — Package Generation & Verification · 105 pts

| ID | Story | Pts | Notes |
|---|---|---|---|
| US-13.01 | Generate the official filled forms from the agency AcroForm | 21 | **[S]** [ADR-003](../adr/ADR-003-form-fidelity.md) |
| US-13.02 | Round-trip verification; mismatch fails generation | 21 | **[R][S][G]** |
| US-13.03 | Package the evidence (index, exhibits, checklist, fees) | 13 | **[R]** |
| US-13.04 | Addendum generation for field overflow | 13 | **[R]** |
| US-13.05 | Assisted-Fill-Only mode for XFA and flat forms | 13 | **[R]** |
| US-13.06 | Preparer footer with verification status | 5 | **[R][S]** |
| US-13.07 | WORM write with edition and value-set hashes | 8 | **[S]** |
| US-13.08 | Isolated PDF toolchain worker | 8 | **[S]** |
| US-13.09 | Generated text passes the UPL classifier before write | 3 | **[S][G]** |

## E-14 — Export & Delivery · 47 pts

| ID | Story | Pts | Notes |
|---|---|---|---|
| US-14.01 | Save to Files and Print | 8 | |
| US-14.02 | Deliver securely (link + second factor, expiring, revocable) | 13 | **[S]** |
| US-14.03 | Delivery access log visible to the sender | 8 | |
| US-14.04 | Revoke a delivery link within 60 seconds | 5 | **[S]** |
| US-14.05 | Never send case content as an email attachment or body | 5 | **[S][G]** |
| US-14.06 | Filing checklist shown before export | 8 | |

## E-15 — Audit, Consent & Transparency · 63 pts

| ID | Story | Pts | Notes |
|---|---|---|---|
| US-15.01 | Hash-chained append-only audit to immutable storage | 21 | **[S]** |
| US-15.02 | Audit write failure fails the originating operation | 8 | **[S]** |
| US-15.03 | My Activity Log in plain language | 13 | |
| US-15.04 | Break-glass surfaced to the affected user | 5 | **[R][S]** |
| US-15.05 | Granular versioned consent ledger with notice hashes | 13 | **[S]** |
| US-15.06 | Chain integrity verification endpoint | 3 | |

## E-16 — Data Rights & Retention · 55 pts

| ID | Story | Pts | Notes |
|---|---|---|---|
| US-16.01 | Export all my data (machine- and human-readable) | 13 | |
| US-16.02 | Delete my documents but keep my answers | 13 | **[R]** |
| US-16.03 | Retention policy engine with automated sweeps | 13 | |
| US-16.04 | Delete everything, with enumerated exceptions and a receipt | 13 | **[S]** Honest about backups |
| US-16.05 | Household-member rights exercisable independently | 3 | **[R][S]** |

## E-17 — Tenancy, Roles & Administration · 84 pts

| ID | Story | Pts | Notes |
|---|---|---|---|
| US-17.01 | Tenant model with RLS isolation | 13 | **[S][G]** Cross-tenant invariant test |
| US-17.02 | Role and ABAC policy decision point | 21 | **[S]** |
| US-17.03 | Manual KYB with bar/EOIR verification | 13 | **[R][S]** |
| US-17.04 | Unverified tenants visibly constrained | 8 | **[R][S]** |
| US-17.05 | Disclosure non-suppressible by tenant branding | 5 | **[S][G]** |
| US-17.06 | Break-glass with dual approval and time box | 13 | **[R][S]** |
| US-17.07 | Admin dashboard with no case-content capability | 8 | **[S]** |
| US-17.08 | Authorization matrix test (every role × every endpoint) | 3 | **[G]** |

## E-18 — Accessibility & Localization · 76 pts

| ID | Story | Pts | Notes |
|---|---|---|---|
| US-18.01 | VoiceOver support across all surfaces | 21 | **[G]** |
| US-18.02 | Dynamic Type to AX5 with snapshot tests | 13 | **[G]** |
| US-18.03 | Full keyboard operability (macOS/iPadOS) | 8 | **[G]** |
| US-18.04 | Plain Language mode affecting UI and AI copy together | 13 | **[R]** |
| US-18.05 | Spanish localization with bilingual form labels | 13 | |
| US-18.06 | Reduce Motion, Increase Contrast, Bold Text support | 5 | **[G]** |
| US-18.07 | ACR/VPAT generation and publication | 3 | **[G]** |

## E-19 — Platform Observability & Cost Control · 55 pts

| ID | Story | Pts | Notes |
|---|---|---|---|
| US-19.01 | OpenTelemetry tracing client-to-model | 13 | |
| US-19.02 | AI telemetry with hashes, never content | 13 | **[S]** |
| US-19.03 | Cost attribution per agent, model, case and tenant | 13 | **[R]** Day 1, not later |
| US-19.04 | Budget enforcement at four levels + circuit breaker | 13 | **[R]** |
| US-19.05 | Log deny-list with CI scanning | 3 | **[S]** |

## E-20 — Responsible AI Guardrails · 68 pts

| ID | Story | Pts | Notes |
|---|---|---|---|
| US-20.01 | The assistant cannot give legal advice | 21 | **[S][G]** [ADR-001](../adr/ADR-001-scrivener-boundary.md) |
| US-20.02 | Adversarial UPL corpus (1,000+ prompts) and CI gate | 13 | **[G]** |
| US-20.03 | Deterministic refusal library, localized | 8 | **[S]** |
| US-20.04 | Harm, PII-leakage and groundedness checks | 13 | **[S][G]** |
| US-20.05 | Production sampling with weekly Compliance report | 5 | |
| US-20.06 | Bias measurement across strata with k-anonymity | 8 | **[G]** |

---

## Phase 2 epics · 257 pts

| Epic | Pts | Headline stories |
|---|---|---|
| E-21 Search | 47 | Per-tenant index partitioning · entitlement as index filters · OCR full-text with highlighting · hashed query audit |
| E-22 Reporting & Analytics | 63 | Governed report catalog · k-anonymity enforcement · NL-to-catalog mapping · funder reports |
| E-23 RFE & Amendment Support | 76 | RFE transcription · mapping to collectible items · response assembly · strictest guardrail profile |
| E-24 Self-Serve Tenancy & Billing | 71 | Automated KYB · bar/EOIR API verification · billing · per-tenant budgets · abuse signals |

Plus Phase 2 depth: 10 additional form packages (~180 pts), 8 languages (~150 pts), multi-region
active-passive (~90 pts), performance work to the tightened SLOs (~60 pts).

## Phase 3 epics · 233 pts + gated

| Epic | Pts | Notes |
|---|---|---|
| E-25 Partner API & Integrations | 89 | Signed webhooks, replay protection, rate limiting |
| E-26 Sensitive Matters | 144 | **Gated on G3-A** ([11 §11.5](../11-roadmap.md#gate-g3-a--prerequisites-for-sensitive-matters)) |
| Per-case CMK & crypto-shred | 55 | [OPEN-01](../12-risks-and-gap-analysis.md#127-open-decisions) |
| On-device extraction pilot | 89 | [13 §13.3](../13-v2-recommendations.md#133-on-device-extraction-and-client-held-keys) |
| Additional agencies | 76 | DOL, SSA, selected state programs |

---

## Sprint sequencing — Phase 1

| Sprint | Stream A (Identity/Tenancy) | Stream B (Documents) | Stream C (AI/Interview) | Stream D (Output/Review) |
|---|---|---|---|---|
| 1–2 | E-01, E-17 core | E-04 capture | E-03 catalog ingest | Design system, E-18 foundations |
| 3–4 | E-02 folders/persons | E-05 sanitize + OCR | E-03 field maps | E-19 observability |
| 5–6 | E-02 trust boundaries | E-05 extraction | E-07 questionnaire | E-10 validation engine |
| 7–8 | E-17 KYB, roles | E-06 ledger | E-08 chat + E-20 guardrails | E-12 workbench |
| 9–10 | E-15 audit, consent | E-06 discrepancies | E-09 voice | E-13 generation |
| 11–12 | E-16 data rights | E-04 offline | E-09 voice + budgets | E-13 verification |
| 13–14 | Hardening | Hardening | E-20 corpus + gates | E-14 export |
| 15–16 | Beta support | Beta support | Beta tuning | Beta support |
| 17–18 | SOC 2 evidence | Pen test remediation | Calibration | ACR + panel testing |
| 19–20 | G1 preparation | G1 preparation | G1 preparation | G1 preparation |

**Stream D carries the critical path** through package generation. Stream C's guardrail work
(E-20) must complete before the beta opens, because the UPL gate is a beta entry condition, not an
exit condition.
