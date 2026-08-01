# 12 — Risks and Gap Analysis

**Owner:** Risk Officer · **Contributors:** every function · **Status:** For executive and board
review

This document is the output of the adversarial review. Every function was required to attack the
solution rather than defend it. What follows is what they found: the gaps that were closed, the gaps
that remain open with owners, and the risks we are choosing to carry.

---

## 12.1 How the review was run

Four rounds, each with a different frame, because the same people asking "is this good?" repeatedly
produces agreement rather than insight.

| Round | Frame | Participants | Output |
|---|---|---|---|
| **R1 — Premise attack** | "Which assumption in the brief is simply wrong?" | Exec + architecture board | 6 findings, 4 of which changed scope permanently ([C-01](00-design-authority-record.md#c-01--form-discovery-agent-as-briefed-is-unauthorized-practice-of-law), [C-02](00-design-authority-record.md#c-02--workflow-step-15-assumes-an-e-filing-capability-that-does-not-exist), [C-04](00-design-authority-record.md#c-04--asylum-and-removal-defense-cases-must-be-out-of-scope-for-v1), [C-24](00-design-authority-record.md#c-24--rejected-add-a-lawyer-marketplace-to-monetize)) |
| **R2 — Adversary simulation** | Each of the eight threat actors in [06 §6.1](06-security-architecture.md#61-threat-context--who-we-are-actually-defending-against) played by a named person against the design | Security, Privacy, Risk, AI | 11 findings; produced the attack paths in [06 §6.11](06-security-architecture.md#611-attack-path-analysis) |
| **R3 — User failure walk** | "Follow María and Danielle through every failure mode" | Product, UX, CX, Accessibility | 9 findings, including [C-12](00-design-authority-record.md#c-12--accessibility-cannot-be-a-phase-2-item-for-this-population), [C-20](00-design-authority-record.md#c-20--the-completion-percentage-will-be-read-as-a-prediction), [C-21](00-design-authority-record.md#c-21--offline-and-poor-connectivity-behavior-is-unspecified) |
| **R4 — Operate it for a year** | "It's month 11. What is broken and who is awake at 3 a.m.?" | Engineering, DevSecOps, QA, Finance | 8 findings, including [C-03](00-design-authority-record.md#c-03--pdf-generation-against-government-forms-is-harder-than-the-brief-assumes), [C-11](00-design-authority-record.md#c-11--cost-model-for-real-time-voice-is-not-viable-as-specified), [C-17](00-design-authority-record.md#c-17--twenty-three-agents-is-an-orchestration-liability-not-an-achievement) |

**34 findings. 24 became formal challenges** ([00 §0.2](00-design-authority-record.md#02-the-challenge-log)).
Ten were absorbed into design without contention and appear below as closed gaps.

---

## 12.2 Missing features found and closed

Capabilities the brief did not mention that the review determined are **not optional**.

| # | Missing capability | Why it is required | Where it now lives | Cost |
|---|---|---|---|---|
| MF-01 | **Form edition management and drift detection** | Agencies reject filings on superseded editions and change them without notice. Without this, the product silently produces rejectable filings at scale | [ADR-003](adr/ADR-003-form-fidelity.md), Form Catalog service, FR-FORM-001..003 | 34 pts |
| MF-02 | **Round-trip PDF verification** | Filling a form is not the same as filling it correctly. Truncation and encoding errors are silent | FR-FORM-005, Agent 20 | 13 pts |
| MF-03 | **Addendum generation for overflow** | Government fields have hard character limits; truncating a name or an address is a defect that reaches an adjudicator | FR-FORM-006 | 13 pts |
| MF-04 | **Filing checklist and fee sheet** | The brief ends at "generate forms," but a user with correct forms and the wrong fee or address still fails | FR-FORM-008 | 13 pts |
| MF-05 | **Per-person trust boundary and Quiet Exit** | A household folder assumes aligned interests. Family-based immigration frequently does not have them | [C-05](00-design-authority-record.md#c-05--a-household-folder-is-not-a-single-trust-boundary), [ADR-007](adr/ADR-007-household-trust-boundaries.md) | 21 pts |
| MF-06 | **Sealed medical document handling** | I-693 must never be opened; opening it invalidates it and exposes PHI | FR-DOC-014 | 5 pts |
| MF-07 | **On-device capture quality gate** | The highest-leverage quality intervention in the product, and it costs nothing at inference time | FR-DOC-003 | 21 pts |
| MF-08 | **Offline capture and resumable upload** | The target population's connectivity is genuinely bad; a design requiring connectivity to capture loses documents | [C-21](00-design-authority-record.md#c-21--offline-and-poor-connectivity-behavior-is-unspecified) | 21 pts |
| MF-09 | **Name variant model** | Names across immigration documents legitimately differ. Treating that as an error rather than a fact breaks the product for most non-Anglophone users | FR-EXT-006 | 13 pts |
| MF-10 | **Date ambiguity resolution** | DD/MM vs MM/DD is not guessable and a wrong guess is invisible until an agency notices | FR-EXT-007 | 8 pts |
| MF-11 | **Tenant KYB and provider verification** | Without it, the platform is the notario's best tool | [C-10](00-design-authority-record.md#c-10--the-platform-will-attract-bad-faith-administrator-tenants) | 21 pts |
| MF-12 | **Interpreter and preparer attestation** | The forms have certification blocks that machine translation cannot lawfully satisfy | [C-08](00-design-authority-record.md#c-08--machine-translation-cannot-be-represented-as-interpretation) | 13 pts |
| MF-13 | **Helper role with attribution** | Someone else does the tapping in a large share of real cases; unattributed answers destroy the audit trail | US-02.08 | 8 pts |
| MF-14 | **Crisis and distress handling in interviews** | An interview about family history will encounter disclosure of abuse and trauma | Agent 10 F5, Agent 11 | 8 pts |
| MF-15 | **PII minimization proxy** | Sending raw identifiers to a hosted model where the task does not require them is unnecessary exposure | [06 §6.7](06-security-architecture.md#67-secure-ai-processing-and-prompt-handling) | 21 pts |
| MF-16 | **Per-case and per-tenant AI budgets** | Without them the business model is exposed to its own users' enthusiasm | [C-11](00-design-authority-record.md#c-11--cost-model-for-real-time-voice-is-not-viable-as-specified) | 13 pts |
| MF-17 | **Catalog operations as a staffed function** | Somebody must own editions and field maps; the failure mode when nobody does is systemic | [10 §10.11](10-devsecops-and-continuity.md#1011-team-on-call-and-capability) | — |
| MF-18 | **Government-request runbook (RB-12)** | The first 30 minutes after legal process arrives determine whether the response is disciplined or improvised | [10 §10.10](10-devsecops-and-continuity.md#1010-operational-runbooks) | 5 pts |
| MF-19 | **Non-visual document capture path** | A camera-first product is unusable without one, and imports must not be the harder route | NFR-A11Y-010 | 13 pts |
| MF-20 | **Break-glass with user notification** | Support must be able to help without secretly reading files | FR-IAM-008 | 13 pts |

**Total added: 276 story points** — roughly 19 % of MVP scope, added by the review.

---

## 12.3 Missing controls found and closed

| # | Missing control | Threat addressed | Where it lives |
|---|---|---|---|
| MC-01 | Capability boundary — untrusted-reading agents hold no tools | Prompt injection driving action | [04 §4.4](04-ai-agent-architecture.md#44-trust-tiers-and-the-capability-boundary) |
| MC-02 | Processing zone with zero egress and no database route | Parser RCE → lateral movement | [06 §6.6](06-security-architecture.md#66-secure-document-processing-pipeline) |
| MC-03 | Database check constraint requiring a human confirmer | An AI writing to a form | [05 §5.3](05-data-architecture.md#53-relational-model--azure-sql) |
| MC-04 | Gateway rejection of non-human approval principals | AI reaching approval | [07 §7.2](07-api-architecture.md#72-gateway-and-edge-policy) |
| MC-05 | Private Annex as a separate RLS predicate on existence | Intimate-partner surveillance | [05 §5.4](05-data-architecture.md#54-row-level-security) |
| MC-06 | Content-free notification payloads, contract-tested | Lock-screen disclosure | NT-002 |
| MC-07 | Two-person approval on field maps + fixture tests | Right value, wrong box | Agent 08 |
| MC-08 | Deterministic refusal text | A generated refusal drifting into advice | [09 §9.3](09-responsible-ai.md#93-the-legal-advice-classifier) |
| MC-09 | Fail-closed guardrails | Safety degrading silently under load | Agents 16, 17 |
| MC-10 | Audit write failure fails the originating operation | Unaudited privileged action | Agent 22 F1 |
| MC-11 | Source anchoring mandatory for extracted values | Hallucinated field values | FR-EXT-002 |
| MC-12 | Model version pinning with automatic upgrade disabled | Silent behavior change in a certified system | [09 §9.2](09-responsible-ai.md#92-govern--accountability-and-control) |
| MC-13 | No voiceprint storage anywhere, lint-enforced | BIPA and successor statutes | [C-07](00-design-authority-record.md#c-07--voice-interviews-create-biometric-and-wiretap-exposure) |
| MC-14 | EXIF/GPS stripping on device and again server-side | Location disclosure | FR-DOC-006 |
| MC-15 | Search query strings audited as hashes | Creating a searchable record of user intent | FR-SRCH-004 |
| MC-16 | Invariant test suite that cannot be overridden | Commercial pressure eroding safety properties | [10 §10.3](10-devsecops-and-continuity.md#103-cicd-pipeline) |
| MC-17 | Catalog endpoint accepts no case data | UPL via personalization | [07 §7.8](07-api-architecture.md#78-form-catalog-apis) |
| MC-18 | `404` rather than `403` for unentitled resources | Existence disclosure | [07 §7.4](07-api-architecture.md#74-common-conventions) |

---

## 12.4 Weaknesses identified by category

### Security weaknesses

| # | Weakness | Status | Residual |
|---|---|---|---|
| SW-01 | Compelled lawful disclosure cannot be prevented | Mitigated architecturally, not eliminated | **Medium, permanent** |
| SW-02 | A coerced user can be made to show their own screen | Partially mitigated (screenshot deterrence); honestly stated as partial | Medium |
| SW-03 | Insider with a colluding approver defeats break-glass dual approval | Mitigated by user notification and post-hoc review | Medium |
| SW-04 | IaC pipeline compromise would grant infrastructure control | OIDC federation, environment approvals, drift detection | Medium |
| SW-05 | Form catalog source could be spoofed upstream of us | Hash verification, pinned roots, two-person approval | Medium |
| SW-06 | Certificate pinning creates an availability risk if rotation fails | Documented rotation + break-glass plan; tested | Low |
| SW-07 | Realtime voice regional availability conflicts with EU residency | Voice disabled for EU users until EU availability exists | Accepted (RISK-021) |

### Compliance weaknesses

| # | Weakness | Status |
|---|---|---|
| CW-01 | UPL rules vary by state and are not fully settled for software | Per-jurisdiction outside-counsel opinions; conservative uniform boundary; **RISK-002 permanent** |
| CW-02 | Immigration consultant statutes vary and some may capture our tenants | KYB, constrained capabilities, mandatory disclosure; monitored |
| CW-03 | Whether a tenant's non-attorney may approve is the tenant's supervision question, not ours | **OPEN-02**, owned by Compliance |
| CW-04 | Modified abuse monitoring approval is not guaranteed | Pre-agreed fallback: full PII minimization + written CISO acceptance |
| CW-05 | EU AI Act classification depends on our own claim that no automated decision has legal effect | True today; a standing constraint that it must remain true, re-tested at each scope change |

### Usability risks

| # | Risk | Mitigation | Residual |
|---|---|---|---|
| UR-01 | The not-a-law-firm boundary frustrates users who want an answer | Warm, specific refusals that always offer something useful; the nonprofit directory | **Medium — accepted, structural** |
| UR-02 | Review fatigue turns confirmation into clicking | Dwell-time measurement; restricted bulk accept; band retuning when dwell collapses | Medium |
| UR-03 | Users abandon at the document-collection stage | Batching, ownership assignment, honest counters, resolution paths | Medium |
| UR-04 | Voice budget exhaustion feels punitive | Honest messaging, free alternatives, accessibility waiver | Low |
| UR-05 | Bilingual labels increase visual density | Typographic hierarchy; Plain Language mode; tested with the panel | Low |
| UR-06 | The reviewer workbench is only as good as its keyboard model | Measured on cases-per-hour; iterated with real paralegals | Low |

### AI risks

| # | Risk | Mitigation | Residual |
|---|---|---|---|
| AR-01 | Hallucinated value reaching a form | Five-layer mitigation ending in human confirmation | Low |
| AR-02 | UPL escape | Classifier + corpus + gate + sampling + Compliance veto | **Low but existential if realized** |
| AR-03 | Prompt injection | Capability boundary as the primary control | Low |
| AR-04 | Calibration drift making bands meaningless | Monthly reliability reporting; bands retuned as a reviewed change | Medium |
| AR-05 | Bias against non-Latin scripts and non-Western documents | Stratified measurement, retraining, and **in-product disclosure where a gap cannot be closed** | Medium |
| AR-06 | Model provider changes behavior under us | Version pinning; abstraction layer; golden-output suite | Low |
| AR-07 | Automation bias in reviewers | Source-region display, restricted bulk accept, dwell measurement | Medium |
| AR-08 | Users attributing authority to the assistant despite disclosures | Persistent disclosure; deterministic refusals; no confident phrasing about outcomes | Medium |

### Scalability risks

| # | Risk | Mitigation | Residual |
|---|---|---|---|
| SR-01 | Document pipeline is the throughput bottleneck | KEDA queue-depth scaling; consumption profile; load tested at 8× | Low |
| SR-02 | Model provider capacity limits at peak | PTU for steady state, pay-go burst, tier cascade, honest queuing | Medium |
| SR-03 | Catalog operations does not scale linearly with forms | Automated proposal + two-person approval; tooling investment in P2 | Medium |
| SR-04 | Human review capacity is the real ceiling on organizational tenants | Throughput is a first-class metric; workbench optimized for it | **Medium — this is the business's actual constraint** |
| SR-05 | Per-tenant CMK key-count limits in Managed HSM | **OPEN-01**, owned by Cloud Architect |

### Cost risks

| # | Risk | Mitigation | Residual |
|---|---|---|---|
| CR-01 | Voice cost exceeds the price point | Budgets, task scoping, opt-in, cascade | Medium |
| CR-02 | Prompt cache hit rate below assumption | The most fragile assumption in the model; monitored weekly with a $15/case trigger | Medium |
| CR-03 | Model price increases | Abstraction layer makes a swap an evaluated change | Medium |
| CR-04 | Nonprofit tier run at cost erodes blended margin | Deliberate; accounted as distribution investment, capped as a share of volume | Low |
| CR-05 | Extraction retries from poor capture | Fixed at the camera, not the model — the cheapest possible place | Low |

### Operational risks

| # | Risk | Mitigation | Residual |
|---|---|---|---|
| OR-01 | Form edition drift outpaces daily detection | Daily check; move to change-feed detection where available | Medium |
| OR-02 | Single on-call rotation at this team size | Documented escalation, capped rotation, post-incident review for every page | Medium |
| OR-03 | Support cannot help without case access | Break-glass with dual approval and user notice | Low |
| OR-04 | Trust & safety is unstaffed until Phase 2 | Manual tenant onboarding in MVP constrains volume until the function exists | Medium |
| OR-05 | Runbooks rot | Linked from alerts, exercised in monthly game days | Low |

---

## 12.5 Consolidated risk register

Scored 1–5 on likelihood and impact; exposure = L × I. Residual is post-mitigation.

| ID | Risk | Owner | Inherent | Residual | Treatment |
|---|---|---|---|---|---|
| **RISK-001** | Compelled government disclosure of applicant data | CISO | 4×5 = **20** | 3×5 = **15** | Mitigate + accept. Board-level, reviewed quarterly with outside counsel. Permanent |
| **RISK-002** | UPL finding by a state bar or AG | Compliance | 3×5 = **15** | 1×5 = **5** | Mitigate. Architecture + gate + veto. Permanent monitoring |
| **RISK-003** | Form edition drift produces rejectable filings at scale | Catalog Ops | 4×4 = **16** | 2×4 = **8** | Mitigate. Drift monitor, pinning, quarantine, verification |
| **RISK-004** | Sensitive-matter data exposure | CISO | 3×5 = **15** | 1×5 = **5** | **Avoid** in v1–v2 via scope exclusion; gated re-entry at G3-A |
| **RISK-005** | Prompt injection drives agent action | Security Arch | 4×4 = **16** | 1×4 = **4** | Mitigate. Capability boundary |
| **RISK-006** | Wrong value reaches a filed form | Lead Backend | 4×5 = **20** | 2×5 = **10** | Mitigate. Provenance, confirmation, round-trip verification |
| **RISK-007** | Cross-tenant data exposure | Security Arch | 3×5 = **15** | 1×5 = **5** | Mitigate. RLS + invariant gate |
| **RISK-008** | AI unit cost exceeds price point | CPO/CFO | 4×3 = **12** | 2×3 = **6** | Mitigate. Budgets, cascade, telemetry |
| **RISK-009** | Intimate-partner misuse of folder access | CX Lead | 3×5 = **15** | 2×4 = **8** | Mitigate. Per-person boundary, Private Annex, Quiet Exit |
| **RISK-010** | Fraudulent tenant exploits applicants | Trust & Safety | 4×4 = **16** | 2×4 = **8** | Mitigate. KYB, constraints, footer, anomaly detection |
| **RISK-011** | Accessibility failure excludes core users | Accessibility | 3×4 = **12** | 1×4 = **4** | Mitigate. Blocking gate, panel testing, ACR |
| **RISK-012** | Bias against non-Latin scripts | RAI Lead | 4×3 = **12** | 2×3 = **6** | Mitigate + disclose where unclosable |
| **RISK-013** | Human review capacity limits growth | CPO | 4×3 = **12** | 3×3 = **9** | Mitigate. Workbench throughput; accept as the business constraint |
| **RISK-014** | Model provider outage or behavior change | CTO | 3×3 = **9** | 2×2 = **4** | Mitigate. Pinning, abstraction, degraded modes |
| **RISK-015** | Insider data access | CISO | 2×5 = **10** | 1×4 = **4** | Mitigate. Zero standing access, break-glass with notice |
| **RISK-016** | iOS-only excludes ~22 % of target users | CPO | 5×3 = **15** | 4×3 = **12** | **Accept** for v1–v2; Android evaluated in P3 |
| **RISK-017** | Agency publication access changes or terms restrict retrieval | Catalog Ops | 2×4 = **8** | 2×3 = **6** | Mitigate. Manual curation fallback |
| **RISK-018** | SOC 2 or pen test findings delay launch | DevSecOps | 3×3 = **9** | 2×2 = **4** | Mitigate. Continuous testing, early audit engagement |
| **RISK-019** | Apple App Review rejection | Lead Mobile | 2×4 = **8** | 1×3 = **3** | Mitigate. Pre-submission review at G0 |
| **RISK-020** | Modified abuse monitoring not approved | CISO | 3×3 = **9** | 1×2 = **2** | Mitigate. Identity extraction moves off the generative endpoint entirely (Path A), removing the dependency rather than contingently managing it ([14 B-10](14-sme-review-and-signoff.md#b-10--the-abuse-monitoring-fallback-does-not-cover-the-case-that-matters)) |
| **RISK-021** | Realtime voice regional availability vs. EU residency | Cloud Arch | 4×2 = **8** | 3×2 = **6** | **Accept.** Voice disabled for EU users until EU availability |
| **RISK-022** | Calibration drift makes confidence bands meaningless | CAIO | 3×3 = **9** | 2×2 = **4** | Mitigate. Monthly reliability reporting |
| **RISK-023** | Reviewer automation bias | Lead QA | 4×3 = **12** | 3×2 = **6** | Mitigate. Dwell measurement, restricted bulk accept |
| **RISK-024** | Prompt cache hit rate below assumption | Lead Backend | 3×3 = **9** | 2×3 = **6** | Mitigate. Weekly monitoring, $15/case trigger |
| **RISK-025** | Key material loss | Cloud Arch | 1×5 = **5** | 1×5 = **5** | Mitigate. HSM backup, semi-annual restore test |
| **RISK-026** | Supply-chain compromise | DevSecOps | 2×4 = **8** | 1×4 = **4** | Mitigate. SBOM, signing, admission policy, zero client deps |
| **RISK-027** | Catalog ops does not scale with form count | Catalog Ops | 3×3 = **9** | 2×3 = **6** | Mitigate. Tooling investment in P2 |
| **RISK-028** | Single-region outage in Phase 1 | Cloud Arch | 2×4 = **8** | 2×4 = **8** | **Accept** for P1; multi-region in P2 |
| **RISK-029** | Users misread readiness as approval likelihood | UX | 4×3 = **12** | 2×3 = **6** | Mitigate. Mechanical counters, no percentage, persistent statement |
| **RISK-030** | Talent: catalog ops and trust & safety are unusual roles | EM | 3×3 = **9** | 2×3 = **6** | Mitigate. Hire early, document deeply |
| **RISK-031** | Competitor with fewer scruples out-features us on advice | CPO | 4×3 = **12** | 4×2 = **8** | **Accept.** We will lose some users to products that answer the question we won't. That is the position |
| **RISK-032** | **Voice guardrails are corrective, not preventive: a 0.4–1.2 s exposure window before the interrupt lands** | Compliance Officer | 3×5 = **15** | 2×4 = **8** | **Mitigate + accept.** Interrupt-and-correct, session kill after two blocks, 100 % post-hoc classification, voice opt-in only and disabled on high advice-pull surfaces. Gated by CON-1 ([14 B-01](14-sme-review-and-signoff.md#b-01--the-voice-interview-cannot-be-guardrailed-the-way-the-deliverable-claims)) |

**Top five by residual exposure:** RISK-001 (15) · RISK-016 (12) · RISK-006 (10) · RISK-013 (9) ·
RISK-003 / RISK-009 / RISK-010 / RISK-028 / RISK-031 / **RISK-032** (8).

Two of the top five — RISK-016 (iOS-only) and RISK-031 (competitors who will advise) — are
**accepted business positions, not unfinished work**. Naming them as risks rather than pretending
they are solved is the point of the register.

---

## 12.6 Gaps we are deliberately leaving open

Not oversights. Decisions.

| Gap | Why we are leaving it | Revisit |
|---|---|---|
| No Android or web client | Focus. Doing one platform excellently, including accessibility and capture quality, beats three adequately. The excluded ~22 % is real and named as RISK-016 | Phase 3 |
| No e-filing | No lawful mechanism exists ([ADR-002](adr/ADR-002-no-efiling.md)) | Only if an agency publishes a third-party API |
| No eligibility guidance | Unlawful for us, and harmful when wrong | Never |
| No outcome prediction | Would be relied upon, would be wrong | Never |
| No evidence sufficiency judgment | Characterizing evidence is legal judgment | Never |
| No sensitive matters in v1–v2 | We are not yet good enough for the people with the most to lose | G3-A |
| Single region in Phase 1 | Meets the SLO; multi-region would cost real feature progress for a scenario the beta will not hit | Phase 2 |
| No fee payment | Handling government fees introduces money-transmission and trust-account complexity disproportionate to the benefit | Phase 3 evaluation |
| No case-management integration | The partner API is real work and the demand is unproven at MVP | Phase 3 |
| Manual tenant onboarding in MVP | Slow and correct. Automating the gate before understanding the abuse patterns builds the notario's on-ramp | Phase 2 |
| No warrant canary | Legally fragile and potentially misleading | Never |
| No user-facing confidence percentages | Manufactures false assurance | Never |

---

## 12.7 Open decisions

Four remain, each with an owner and a date. There are **no unowned open questions** in this
revision.

| ID | Decision | Positions | Owner | Due |
|---|---|---|---|---|
| **OPEN-01** | Per-case vs. per-tenant CMK for Phase 3 | CISO wants per-case crypto-shred as the strongest answer to RISK-001. Cloud Architect cites Managed HSM key-count limits and per-key cost at 50,000 cases. Middle option: per-case DEKs wrapped by a per-tenant CMK, giving case-level shred without case-level HSM keys | Principal Cloud Architect | Phase 2 design freeze |
| **OPEN-02** | May a tenant delegate approval to a non-attorney? | Compliance: the firm's own supervision rules govern; encoding them makes us the arbiter of someone else's professional responsibility. CPO: organizations will ask for a configurable approval matrix and will otherwise work around us | Compliance Officer | MVP + 60 days |
| **OPEN-03** | Post-completion retention: 90 days or 1 year? | Privacy wants 90 as the minimum defensible. CX research indicates users return for renewals and RFEs at 6–18 months, and a deleted case means re-collecting everything at the worst moment | Chief Data Officer | Beta exit |
| **OPEN-04** | Support state and county forms in Phase 2? | Product sees material TAM expansion. Backend cites [C-03](00-design-authority-record.md#c-03--pdf-generation-against-government-forms-is-harder-than-the-brief-assumes): these are frequently XFA or flat, which means Assisted-Fill-Only and a materially worse experience that may damage trust in the core product | CTO | Phase 2 planning |

---

## 12.8 What would make us stop

Pre-committed stop conditions, agreed before there is pressure to rationalize around them. Naming
them now is the only way they mean anything later.

| Condition | Action |
|---|---|
| A UPL escape reaches a real user and causes a demonstrable harm | Halt the affected surface. Full review by Compliance and the CPO before restoration. If systemic, halt generative interviewing entirely |
| A Sev-1 privacy incident involving applicant data | Halt new registrations. Notify affected users. Independent review before resuming |
| A wrong value on a filed form causes a denial or an RFE traceable to our defect | Halt generation for the affected form. Root-cause every case using that field map. Notify every affected user |
| Extraction accuracy falls below 90 % for any supported document class | Disable extraction for that class; manual entry only; disclose in-product |
| Bias disparity beyond threshold persists two consecutive months without remediation | Remove the capability for the affected population rather than continue shipping a worse experience silently |
| Modified abuse monitoring denied **and** the PII minimization proxy proves insufficient | Escalate to the board. Reconsider the hosted-model architecture |
| A regulator opens an inquiry into our UPL position | Pause marketing. Full cooperation. Outside counsel leads |
| Cost per case exceeds $15 with no credible path down | Price change or feature reduction. Do not subsidize into the wall |
| Our own trust & safety data shows the platform is being used at scale by fraudulent operators faster than we can remove them | Suspend self-serve tenancy and return to manual onboarding |

---

## 12.9 Assurance summary

What an ARB, an SRB, and a compliance reviewer should take from this document.

| Question | Answer |
|---|---|
| Was the design genuinely challenged? | 34 findings across four adversarial rounds; 24 formal challenges recorded with dissent, including four that permanently reduced scope and one the CPO proposed and had rejected |
| Were vetoes actually exercised? | Yes. CISO on sensitive matters (C-04). Compliance on form discovery (C-01) and on the referral marketplace (C-24) |
| Are the safety properties enforced or asserted? | Enforced. Database check constraints, gateway rules, RLS predicates, empty tool allowlists, and non-overridable CI gates — each stated with its enforcement point |
| Is the threat model honest about this population? | Yes. Lawful process is named as the top threat and its mitigation is architectural, not cosmetic. Intimate-partner access is named and designed for |
| Are the residual risks named rather than hidden? | Yes. RISK-001 is permanent and board-visible. RISK-016 and RISK-031 are accepted business positions stated as such |
| Are the open questions owned? | All four have a named owner and a date |
| Could this be handed to a team tomorrow? | Yes — with the caveat that OPEN-04 affects Phase 2 scope and G0 must confirm [ADR-003](adr/ADR-003-form-fidelity.md) before Phase 1 commitment |
