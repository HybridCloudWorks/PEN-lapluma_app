# Appendix B — Requirements Traceability Matrix

**Purpose.** Demonstrate that every governing constraint, challenge outcome, and critical
requirement is realized in a design element, enforced by a named mechanism, and verified by a named
test. A row with an empty enforcement or verification column is a gap; there are none in this
revision.

**How to read the Enforcement column.** The mechanism named is the *primary* one. Where a property
is enforced at multiple layers, all are listed, most-fundamental first. "Policy" appearing alone is
a warning sign and appears nowhere in this matrix for a safety-critical property.

---

## B.1 Governing constraints

| Constraint | Requirement | Design element | Enforcement | Verification |
|---|---|---|---|---|
| **No legal advice** | FR-COMP-001..004 | [Agent 16](../04-ai-agent-architecture.md#agent-16--compliance-agent), [ADR-001](../adr/ADR-001-scrivener-boundary.md) | Form Discovery has no case-data access (architectural) · catalog API accepts no case data · classifier fail-closed · deterministic refusals · Compliance veto | `UPL-GATE` (1,000+ prompts, 0 escapes, blocking) · catalog non-personalization invariant test · 1 % production sampling |
| **No automated filing** | [ADR-002](../adr/ADR-002-no-efiling.md) | No submission integration exists | Absence of code | Integration inventory review at each gate |
| **No automated approval** | FR-COMP-005 | [Agent 19](../04-ai-agent-architecture.md#agent-19--human-review-agent) | APIM rejects non-human principals · service-level check · `ApprovalRecord.ApprovedByUserId` NOT NULL FK to UserAccount | Invariant test: agent principal → 403 + Sev-1 event |
| **Nothing model-touched reaches a form** | US-06.03, FR-EXT-005 | Extraction Ledger | `CK_FVAL_ConfirmRequiresHuman` DB check constraint · `CK_EV_ModelNeedsReview` · generation API refusal | Integration test: generate with a `PROPOSED` value → 409 |
| **Data minimization** | NFR-PRIV-001, DP-2 | Canonical Field Registry | Every canonical field traces to a form field; adding one without that trace fails review | Design review; annual field-necessity audit |
| **Accessibility is acceptance criteria** | NFR-A11Y-001..012 | [08 §8.9](../08-ux-design.md#89-accessibility-specification) | `A11Y-GATE` blocking, overridable only by the Accessibility Specialist | Automated audit + Dynamic Type snapshots + keyboard traversal + reading level, per build; disabled-user panel per release |

---

## B.2 Challenge outcomes → implementation

| Challenge | Outcome | Design element | Enforcement | Verification |
|---|---|---|---|---|
| [C-01](../00-design-authority-record.md#c-01--form-discovery-agent-as-briefed-is-unauthorized-practice-of-law) | Retrieval, not inference | Agent 07 with no case-data access; catalog API | Architectural (cannot see the person) | Catalog response independent of case data; UPL corpus |
| [C-02](../00-design-authority-record.md#c-02--workflow-step-15-assumes-an-e-filing-capability-that-does-not-exist) | No e-filing; Filing Checklist added | FR-FORM-008 | Absence of integration | Copy review: no "submit" language on any surface |
| [C-03](../00-design-authority-record.md#c-03--pdf-generation-against-government-forms-is-harder-than-the-brief-assumes) | Catalog, drift monitor, pinning, round-trip verify | FR-FORM-001..008 | `CK_Pkg_Verified` DB constraint · `UX_FV_OneCurrent` index · quarantine state | Per-form fixture test · simulated drift test at G0 · seeded-error round-trip test |
| [C-04](../00-design-authority-record.md#c-04--asylum-and-removal-defense-cases-must-be-out-of-scope-for-v1) | Sensitive matters excluded, gated | Catalog scope; G3-A | Package codes absent from the catalog | Catalog inventory review at each gate |
| [C-05](../00-design-authority-record.md#c-05--a-household-folder-is-not-a-single-trust-boundary) | Per-person boundary, Private Annex, Quiet Exit | [ADR-007](../adr/ADR-007-household-trust-boundaries.md) | Dual RLS predicates · person-scoped agent retrieval at the query layer | Household boundary invariant test: owner cannot enumerate annex; Quiet Exit → 0 notification rows |
| [C-06](../00-design-authority-record.md#c-06--sealed-medical-exams-must-never-be-ocrd) | `SEALED_MEDICAL` opaque handling | FR-DOC-014 | Deterministic pre-filter before model sees content · `CK_Doc_OpaqueNoExtract` | Test: sealed document → no OCR call, no preview, no index entry |
| [C-07](../00-design-authority-record.md#c-07--voice-interviews-create-biometric-and-wiretap-exposure) | No voiceprints; consent; transient audio | FR-VOICE-003..008 | No embedding store exists · CI lint rule on speaker-ID APIs · ephemeral-key broker | Lint gate · architecture review confirming no audio path to backend |
| [C-08](../00-design-authority-record.md#c-08--machine-translation-cannot-be-represented-as-interpretation) | Machine-assisted labelling; interpreter attestation | FR-I18N-006..010 | `machine_assisted` is part of the output type, not a UI flag | Test: no code path populates the interpreter block from Agent 12 |
| [C-09](../00-design-authority-record.md#c-09--government-and-law-enforcement-data-requests-are-the-top-of-register-risk) | Minimization, retention, crypto-shred, policy | RISK-001, [06 §6.10](../06-security-architecture.md#610-the-lawful-process-threat) | Schema absence of unneeded fields · lifecycle automation · CMK | Field-necessity audit · retention sweep verification · RB-12 tabletop |
| [C-10](../00-design-authority-record.md#c-10--the-platform-will-attract-bad-faith-administrator-tenants) | KYB, constrained tenants, package footer | FR-TEN-004..009 | `CK_Tenant_ProviderVerified` · `canSuppressNotALawFirmDisclosure` hardcoded false | Test: unverified tenant cannot brand; footer present on every generated page |
| [C-11](../00-design-authority-record.md#c-11--cost-model-for-real-time-voice-is-not-viable-as-specified) | Task-scoped voice, budgets, cascade | NFR-COST-001..005 | Budget enforced at the broker and the runtime · circuit breaker | Load test with budget exhaustion; cost telemetry per case |
| [C-12](../00-design-authority-record.md#c-12--accessibility-cannot-be-a-phase-2-item-for-this-population) | A11Y as acceptance criteria | NFR-A11Y-001..012 | `A11Y-GATE` blocking | Per-build automated + per-release manual + panel |
| [C-13](../00-design-authority-record.md#c-13--identity-verification-agent-is-under-specified-and-legally-loaded) | Renamed and narrowed to consistency checking | Agent 06 | No biometric or external-check code exists; agent cannot deny service | Agent contract review; capability inventory |
| [C-14](../00-design-authority-record.md#c-14--confidence-scores-from-a-language-model-are-not-calibrated-probabilities) | Three bands from measurable signals | [ADR-010](../adr/ADR-010-confidence-banding.md) | `CK_EV_ModelNeedsReview` · `CK_EV_ChecksumBand` DB constraints | Calibration suite; ECE ≤ 0.08; no percentage in any applicant response |
| [C-15](../00-design-authority-record.md#c-15--uploaded-documents-are-an-untrusted-code-attack-surface) | Isolated processing zone | [06 §6.6](../06-security-architecture.md#66-secure-document-processing-pipeline) | NSG deny-all egress · no data-plane role assignment · ephemeral non-root workers | Policy check on the `proc` environment; egress test from within the zone |
| [C-16](../00-design-authority-record.md#c-16--prompt-injection-via-uploaded-documents-is-a-first-class-threat) | Capability boundary | [ADR-008](../adr/ADR-008-agent-capability-boundary.md) | Tool registry refuses U0 tool binding (runtime-enforced) | Injection corpus: 300 documents, 0 tool invocations, 0 state changes, 100 % flagged |
| [C-17](../00-design-authority-record.md#c-17--twenty-three-agents-is-an-orchestration-liability-not-an-achievement) | Four implementation tiers; 3 truly agentic | [04 §4.2](../04-ai-agent-architecture.md#42-implementation-tiers) | Agent contracts declare tier; runtime binds accordingly | Contract review; latency and cost budgets per agent |
| [C-18](../00-design-authority-record.md#c-18--cosmos-db-and-azure-sql-both-in-mvp-is-premature-complexity) | SQL is the only system of record | [ADR-006](../adr/ADR-006-polyglot-persistence.md) | No FK from SQL to Cosmos; `DerivedStore` interface has no domain write path | **Quarterly drill: drop Cosmos in staging, regenerate every package** |
| [C-19](../00-design-authority-record.md#c-19--analytics-on-this-data-is-a-liability-not-an-asset) | No third-party SDKs; first-party telemetry only | [ADR-012](../adr/ADR-012-no-third-party-client-sdks.md) | SBOM policy gate · network egress test | CI: build fails on new client dependency; egress test fails on unlisted host |
| [C-20](../00-design-authority-record.md#c-20--the-completion-percentage-will-be-read-as-a-prediction) | Mechanical counters, no percentage | FR-CASE-021 | No `percentComplete` in any schema | Contract test: no response key matches `/percent\|complete(ness)?Score/i` |
| [C-21](../00-design-authority-record.md#c-21--offline-and-poor-connectivity-behavior-is-unspecified) | Offline capture; resumable upload | NFR-AVAIL-006 | Local-first store; background transfer | Airplane-mode E2E test; app-termination resume test |
| [C-22](../00-design-authority-record.md#c-22--macos-is-not-ios-on-a-bigger-screen) | Reviewer workbench as a distinct experience | [08 §8.7](../08-ux-design.md#87-macos-reviewer-workbench) | Separate target sharing `ApertureKit` | Reviewer minutes-per-package metric |
| [C-23](../00-design-authority-record.md#c-23--third-party-ai-processing-needs-explicit-contractual-and-configuration-posture) | Dedicated resource, pinning, PII proxy | [06 §6.7](../06-security-architecture.md#67-secure-ai-processing-and-prompt-handling) | Deployment configuration verified by policy-as-code | Deployment test: region pinned, version pinned, CMK present |
| [C-24](../00-design-authority-record.md#c-24--rejected-add-a-lawyer-marketplace-to-monetize) | Marketplace rejected; unranked directory only | FR-COMP-007 | Directory has no ranking or personalization code | Test: directory response identical for all principals |

---

## B.3 Threat → control → test

| Threat (STRIDE) | Control | Enforcement point | Test |
|---|---|---|---|
| S-1 Credential phishing | Passkeys primary, no SMS | [ADR-011](../adr/ADR-011-passkeys-no-sms.md) | Auth flow test; `AUTH_DOWNGRADED` population monitored |
| T-2 PDF tampering | WORM + hash in manifest | Blob immutability policy | Attempt overwrite of a package blob → fail |
| T-3 Field map corruption | Two-person approval + fixture test | `CK_FB_TwoPerson` | Per-form fixture test in CI |
| T-5 Audit tampering | Append-only, hash-chained, no UPDATE/DELETE grant | Storage immutability + SQL permissions | Chain integrity verification; attempted delete → fail |
| I-1 Compelled disclosure | Minimization, retention, crypto-shred | Schema, lifecycle, CMK | Field-necessity audit; crypto-shred procedure test |
| I-2 Household member disclosure | Per-person RLS + annex predicate | Dual RLS policies | Household boundary invariant test |
| I-3 Cross-tenant leak | RLS on every tenant-scoped table | `sec.TenantIsolation` policy | **Cross-tenant test on every build; any success fails the pipeline** |
| I-4 Notification leakage | Content-free payloads | Notification service | Contract test on APNs payload shape |
| I-6 SDK exfiltration | No third-party SDKs | SBOM gate + egress test | CI |
| I-10 Sealed medical processed | Deterministic pre-filter + DB constraint | `CK_Doc_OpaqueNoExtract` | Sealed-document pipeline test |
| D-4 AI cost exhaustion | Four-level budgets + circuit breaker | Runtime enforcement | Load test with adversarial usage |
| E-1 Agent write escalation | No DB credentials for agents; API rejects agent principals | Managed identity scope + API check | Integration test: agent principal → 403 |
| E-2 AI reaching approval | Gateway + service rejection | APIM policy + service check | Invariant test with Sev-1 assertion |
| E-3 Worker compromise → lateral movement | Zero egress, no DB route, ephemeral | NSG + UDR + role assignments | Egress test from within the zone; role inventory |
| E-4 Helper escalation | Section scoping, 60 s revocation | PDP + RLS | Authorization matrix test |

---

## B.4 Non-functional requirement verification

| NFR | Target | Verification |
|---|---|---|
| NFR-PERF-001/002 | API p95 ≤ 300/600 ms | Load test per release; production SLO monitoring with error budget |
| NFR-PERF-004 | Capture feedback ≤ 800 ms | On-device instrumentation on the reference device (iPhone 12) |
| NFR-PERF-005/006 | Extraction p95 ≤ 45 s / 5 min | Pipeline load test with the synthetic document factory |
| NFR-PERF-008 | Voice turn p95 ≤ 400 ms | Realtime session instrumentation |
| NFR-PERF-009 | Package generation p95 ≤ 90 s | Generation load test on the 6-form package |
| NFR-SCALE-002 | 15 K pages/hour sustained, 60 K burst | Soak and spike profiles |
| NFR-AVAIL-001 | 99.9 % → 99.95 % | Production SLO; error-budget policy |
| NFR-AVAIL-002/003 | RPO ≤ 5 min, RTO ≤ 4 h → 1 h | Monthly restore verification; semi-annual failover exercise |
| NFR-AVAIL-004/005 | Degraded modes preserve completion | Chaos game days, monthly |
| NFR-SEC-001..008 | See [06](../06-security-architecture.md) | SAST/DAST/SCA per build; annual pen test; authorization matrix test |
| NFR-A11Y-001..012 | WCAG 2.2 AA | `A11Y-GATE` + manual audit + disabled-user panel + published ACR |
| NFR-I18N-001..006 | Language parity | Pseudo-localization in CI; non-English completion rate ≥ 80 % → 90 % of English |
| NFR-COST-002 | ≤ $11 → $6 per case | Weekly unit-economics report from per-call cost attribution |
| NFR-PRIV-002 | Residency pinned | Deployment policy test; `dataPlane` claim check at the gateway |

---

## B.5 Gate coverage

Which tests gate which release decision.

| Gate | Composition | Override |
|---|---|---|
| `INVARIANT-GATE` | Cross-tenant · no-percentage-key · content-free notifications · non-human approval rejected · catalog non-personalization · household boundary | **None. Cannot be overridden** |
| `UPL-GATE` | Adversarial corpus (0 escapes) · false-positive budget · generated-package text scan | Compliance Officer **and** CAIO jointly; board-visible |
| `A11Y-GATE` | Automated audit · Dynamic Type snapshots · contrast · keyboard traversal · reading level | Accessibility Specialist only |
| `SEC-GATE` | SAST · SCA · secrets · IaC · container · vulnerability SLA · SBOM | CISO |
| `EVAL-GATE` | Golden extraction · fabricated-value rate · fabricated-citation rate · calibration · bias · injection | CAIO |

The `INVARIANT-GATE` is deliberately un-overridable. Every property it tests is one that, if
violated, means the product is not the product described in this deliverable.

---

## B.6 Coverage summary

| Category | Items | Traced to design | Traced to enforcement | Traced to test | Gaps |
|---|---|---|---|---|---|
| Governing constraints | 6 | 6 | 6 | 6 | **0** |
| Challenge outcomes | 24 | 24 | 24 | 24 | **0** |
| Functional requirements | 87 | 87 | 87 | 87 | **0** |
| Non-functional requirements | 54 | 54 | 54 | 54 | **0** |
| STRIDE threats | 41 | 41 | 41 | 41 | **0** |
| Risks (register) | 31 | 31 | 29 | 26 | 5 accepted without technical control (RISK-001 residual, RISK-016, RISK-028, RISK-031, and part of RISK-013) — each documented as an accepted business or structural position |
