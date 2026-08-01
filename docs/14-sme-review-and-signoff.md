# 14 — SME Adversarial Review and Sign-Off Record

**Review type:** Devil's-advocate technical review of the deliverable itself
**Subject:** `docs/00`–`docs/13`, ADR-001…012, Appendices A–C (Rev A, 2026-08-01)
**Convened by:** Chief Technology Officer at the request of the sponsor
**Status:** **CONDITIONAL SIGN-OFF.** 10 blocking findings raised; 10 remediated in Rev B.
5 findings accepted as residual with named owners. 2 disciplines sign conditionally.

---

## 14.1 Why this review is different from the one in `docs/12`

The review recorded in [00 §0.2](00-design-authority-record.md#02-the-challenge-log) and
[12 §12.1](12-risks-and-gap-analysis.md#121-how-the-review-was-run) attacked the **sponsor's brief**.
It was successful — it removed four things that would have killed the product.

It did not attack **the answer**. A design team that challenges its inputs and then admires its own
output has done half a review. This session was convened with a different instruction:

> *Assume the Rev A deliverable is wrong. Find where. "It's fine" is not a finding — bring a defect,
> a reproduction, and a consequence, or bring nothing.*

**Standard of evidence.** A finding is admissible only if it states (a) the specific text or
construct at fault, (b) the concrete failure it produces, and (c) what would have to change.
Opinions about style, preference, or emphasis were ruled inadmissible and are not recorded.

**Outcome.** 41 admissible findings. Ten are **blocking** — they are internal contradictions,
constructs that cannot work as written, or claims the design does not support. Of those, the most
serious is B-01, which invalidates a control the deliverable asserts nine separate times.

---

## 14.2 Findings summary

| Severity | Definition | Count | Disposition |
|---|---|---|---|
| **Blocking** | Internal contradiction, unbuildable construct, or an unsupported safety claim | 10 | All 10 remediated in Rev B |
| **Major** | Real defect requiring redesign; does not invalidate the document set | 14 | 9 remediated · 5 accepted with owners |
| **Minor** | Precision, consistency, arithmetic | 17 | 17 remediated |

| Discipline | Reviewer role | Findings | Verdict |
|---|---|---|---|
| AI / Agentic architecture | Agentic AI Architect | 7 | **Conditional** |
| Security architecture | Principal Security Architect | 8 | **Conditional** |
| Data architecture | Principal Data Architect | 7 | Approved (Rev B) |
| Application / backend | Lead Backend Architect | 4 | Approved (Rev B) |
| Cloud / infrastructure | Principal Cloud Architect | 3 | Approved (Rev B) |
| Integration / API | Principal Integration Architect | 3 | Approved (Rev B) |
| Privacy | Privacy Officer | 4 | Approved (Rev B) |
| Compliance / UPL | Compliance Officer | 3 | Approved (Rev B) |
| QA / test | Lead QA Architect | 3 | Approved (Rev B) |
| Product / delivery | Senior Product Manager | 3 | Approved (Rev B) |
| UX | UX Architect | 3 | Approved (Rev B) |
| Accessibility | Accessibility Specialist | 2 | Approved (Rev B) |

---

## 14.3 Blocking findings

---

### B-01 — The voice interview cannot be guardrailed the way the deliverable claims
**Raised by:** Agentic AI Architect · **Seconded by:** Compliance Officer, Principal Security Architect
**Against:** [04 Agent 10](04-ai-agent-architecture.md#agent-10--voice-interview-agent) ·
[06 §6.7](06-security-architecture.md#67-secure-ai-processing-and-prompt-handling) ·
[02 US-09.01](02-product-requirements.md#e-07--e-08--e-09--questionnaire-and-interviews) ·
[08 S-09](08-ux-design.md#s-09-voice-interview)

**The defect.** Rev A makes two claims that cannot both be true.

1. *"Audio streams client ↔ model over WebRTC… our backend never receives the audio stream."*
2. *"Compliance (16) and Responsible AI (17) guardrails on every utterance; on block, a
   deterministic spoken refusal is substituted."*

If our backend is not in the media path, **there is no point at which we can intercept an utterance
before the user hears it.** The model speaks directly into the user's ear. A pre-emptive guardrail
on voice output is architecturally impossible under the chosen transport.

This is not a documentation slip. The deliverable asserts full guardrail coverage of every
generative egress path — in the executive summary, in the RAI position, in the STRIDE table, in the
UPL firewall section, and in the traceability matrix. Voice is the one path where it does not hold,
and voice is precisely the modality most likely to be used by the users least able to recognize that
they have been given advice.

**Consequence.** The strongest safety claim in the product — *"the classifier runs on every
generative output"* — is false for the highest-risk surface. If shipped as written, the first
regulator or plaintiff to read the architecture finds the gap before we do.

**What was considered and rejected.**
- *Proxy the audio through our backend.* Restores pre-emptive control, but destroys the privacy
  property (we would hold every applicant's voice), adds 150–250 ms, and makes us a processor of raw
  audio for a population where that is the worst thing to hold. Rejected by the Privacy Officer.
- *Drop voice from MVP.* Considered seriously. Rejected because voice is the accessibility default
  and the primary modality for low-literacy users; removing it harms the people the product exists
  for.

**Remediation (Rev B).** Voice guardrailing is redesigned and its residual stated honestly:

1. **Pre-session containment.** The realtime session is created with a locked instruction contract,
   a restricted response schema, and the provider's own output moderation enabled. This reduces but
   does not eliminate the risk.
2. **Streaming transcript interception.** WebRTC carries an assistant-transcript data channel. The
   client forwards assistant transcript deltas to the guardrail service over the existing
   authenticated channel. Stage-1 (deterministic lexicon/regex, ~2 ms) runs client-side on the
   partial transcript; stages 2–3 run server-side.
3. **Interrupt, not prevent.** On a stage-1 or stage-2 block the client immediately mutes model
   audio, cancels the in-flight response, and plays a deterministic spoken correction:
   *"Sorry — I got that wrong. I can't tell you what will happen with your application."*
4. **Session kill.** Two blocks in one session end the session and hand off to chat.
5. **Post-hoc.** 100 % of voice transcripts — not 1 % — are re-classified offline, because
   detection here is a compensating control rather than a preventive one.

**The residual, stated plainly and now carried on the register as RISK-032:** a user may hear
**0.4–1.2 seconds** of a prohibited utterance before the interrupt lands. Voice therefore carries
**materially higher UPL residual risk than chat**, and this is disclosed rather than papered over.
Consequences that follow from accepting that residual:

- Voice remains **opt-in and is never the default**, except in the accessibility profile, where the
  Accessibility Specialist and Compliance Officer jointly accepted the trade in writing.
- Voice is **disabled entirely** on the surfaces with the highest advice-pull: form selection, and
  the Phase-2 RFE flow.
- The blocking release gate for voice is **stricter** than for chat: zero escapes *and* a measured
  mean interrupt latency ≤ 600 ms on the reference device.

**Status:** Remediated in Rev B. Compliance Officer signs **conditionally** on the interrupt-latency
gate being met at G1; if it is not, voice does not ship in MVP.

---

### B-02 — The `FieldValue` unique index makes the "never overwrite a human" rule unimplementable
**Raised by:** Principal Data Architect · **Against:** [05 §5.3](05-data-architecture.md#53-relational-model--azure-sql)

**The defect.** Rev A declares:

```sql
CREATE UNIQUE INDEX UX_FVAL_Current
  ON dbo.FieldValue(CaseId, SubjectPersonId, CanonicalFieldId)
  WHERE ValueState IN ('PROPOSED','HUMAN_CONFIRMED');
```

At most one row per field may exist in `PROPOSED` **or** `HUMAN_CONFIRMED`. But the product requires
both to coexist:

> *"A correction supersedes all extractions permanently and is never overwritten by a later
> extraction without an explicit prompt."* — US-06.01 AC3

**Reproduction.** A user confirms `person.birth.date = 1979-03-14` from a passport. They later
upload a birth certificate showing `1979-04-13`. Extraction produces a candidate. The system must
hold the confirmed value *and* the new proposal so it can ask. The index makes the insert fail.
Every path out is bad: overwrite the human's value (violates the product rule), silently discard the
new extraction (violates FR-EXT-003), or store the proposal somewhere undeclared.

**Consequence.** The single most important data invariant in the product — a human decision is never
silently overwritten — cannot be honored by the Rev A schema.

**Remediation (Rev B).** Split proposal from authority:

- `dbo.ValueProposal` — zero-or-many open proposals per field, each with full provenance, each
  resolvable to accepted/rejected/superseded.
- `dbo.FieldValue` — exactly one authoritative row per `(case, person, field)`, only ever written by
  a human confirmation, retaining the temporal history table.
- A proposal that conflicts with a `HUMAN_CONFIRMED` value raises a `Discrepancy` rather than
  competing for the same index slot.

This also removes the redundancy the reviewer flagged separately: Rev A carried system-versioning
*and* an application-managed `SupersedesFieldValueId` chain, two mechanisms for one job.

**Status:** Remediated in Rev B.

---

### B-03 — The audit hash chain has a write race and is an availability single point of failure
**Raised by:** Lead Backend Architect · **Seconded by:** Principal Security Architect
**Against:** [05 §5.3](05-data-architecture.md#53-relational-model--azure-sql) · [04 Agent 22](04-ai-agent-architecture.md#agent-22--audit-agent)

**Two defects, same construct.**

*Race.* `AuditLog` chains `PrevEventHash → EventHash` with a `BIGINT IDENTITY` primary key. Under
concurrency, two writers both read the same "current last hash" and both chain from it. The result
is a fork: two events claim the same predecessor. A verifier cannot distinguish that from tampering,
so the tamper-evidence property is destroyed by ordinary load, not by an attacker.

*Availability.* Agent 22 F1 states: *"audit write fails → the originating operation fails."*
Combined with auditing every personal-data read, at the stated 15,000 pages/hour ingest target, the
audit path becomes a synchronous dependency on the hot path of every request. A single serialized
chain writer then caps system throughput and contradicts NFR-AVAIL-001 (99.9 %).

**Consequence.** As written, the platform either has a broken tamper-evidence claim or a throughput
ceiling well below its stated scale target. Probably both.

**Remediation (Rev B).** Separate *durability* from *chaining*:

1. Audit intent is written in the **same transaction** as the operation, via a transactional outbox.
   The operation still fails if that write fails — the control Agent 22 F1 was reaching for is
   preserved, and it is now cheap because it is a local insert with no chain read.
2. A **single-writer sequencer per tenant** consumes the outbox and computes the chain
   asynchronously, with a monotonic sequence number. Chain lag is monitored; lag > 5 minutes is a
   Sev-2.
3. Chain segments are **anchored** every 10,000 events or hourly, whichever first, so a verifier has
   fixed points.
4. Availability of the chaining job is decoupled from request serving: if the sequencer is down,
   requests still succeed and audit intent still durably accumulates.

**Status:** Remediated in Rev B.

---

### B-04 — Row-Level Security enforces tenant isolation only; the deliverable claims more
**Raised by:** Principal Security Architect · **Against:** [03 AP-8](03-solution-architecture.md#31-architectural-principles) ·
[05 DP-5](05-data-architecture.md#51-principles) · [05 §5.4](05-data-architecture.md#54-row-level-security)

**The defect.** The deliverable states as a governing principle that *"the tenant boundary is
enforced at the data layer"* and, more broadly, that *"entitlement filtering in the UI or in
application code alone"* is forbidden. It then implements RLS predicates keyed only on `TenantId`
(plus a separate predicate for `PrivateAnnexItem`).

Folder scoping, person scoping, and section scoping — the mechanisms that make
[ADR-007](adr/ADR-007-household-trust-boundaries.md) work for everyone who is *not* using a Private
Annex — exist **only in the Policy Decision Point**, i.e. in application code.

**Reproduction.** A `Reviewer` at a 400-case organizational tenant is assigned 12 folders. A missing
`WHERE folderId IN (...)` in any query handler returns all 400. RLS does not catch it, because all
400 are in the same tenant. The invariant test suite tests *cross-tenant* leakage and would not catch
it either.

**Consequence.** The largest tenants have the weakest enforcement, and the deliverable's own
principle is violated in the exact place a defect is most likely.

**Remediation (Rev B).** Add a second security policy carrying folder and person scope from session
context, evaluated against a materialized entitlement table maintained by the PDP:

```sql
CREATE FUNCTION sec.fn_FolderScopePredicate(@FolderId UNIQUEIDENTIFIER)
RETURNS TABLE WITH SCHEMABINDING
AS RETURN
    SELECT 1 AS ok
    WHERE EXISTS (
        SELECT 1 FROM sec.EffectiveFolderGrant g
        WHERE g.FolderId = @FolderId
          AND g.UserId   = CAST(SESSION_CONTEXT(N'UserId') AS UNIQUEIDENTIFIER)
          AND g.RevokedAtUtc IS NULL);
```

and extend the invariant suite from *cross-tenant* to **cross-folder and cross-person within a
tenant**, which is the case that actually reaches production.

**Status:** Remediated in Rev B.

---

### B-05 — `IsPlatformOperation` is a single boolean that disables the entire isolation model
**Raised by:** Principal Security Architect · **Against:** [05 §5.4](05-data-architecture.md#54-row-level-security)

**The defect.** The tenant predicate contains:

```sql
OR CAST(SESSION_CONTEXT(N'IsPlatformOperation') AS BIT) = 1
```

One session-context flag turns off tenant isolation globally. Rev A asserts it is *"set only by
break-glass"* — but that is a statement about intended code paths, not an enforced property. Any
defect, any injection, or any future engineer who finds the flag convenient obtains
cross-tenant read.

Rev A also claims `SESSION_CONTEXT` is set with `@read_only = 1` and therefore safe. That prevents
*modification within a session*; it does nothing about which value gets set at the start of one, and
it interacts poorly with connection pooling if `sp_reset_connection` behavior is ever assumed rather
than verified.

**Consequence.** The strongest technical control in the data architecture has a documented bypass
switch, reachable from application code, defended by convention.

**Remediation (Rev B).**
- The flag is **deleted.**
- Break-glass uses a **distinct database principal** on a **distinct connection string** held in a
  separate Key Vault, whose grant is issued only after dual approval and which is bound to a
  specific `tenant_id` and time window — so break-glass is scoped to *one tenant*, not to *all*.
- The application's normal principal has no ability to escape its tenant predicate under any
  session state.
- A CI test asserts that the application principal cannot read another tenant's row **regardless of
  session context contents**, including adversarial values.

**Status:** Remediated in Rev B.

---

### B-06 — The processing zone writes to the documents store, breaking its own isolation claim
**Raised by:** Principal Cloud Architect · **Against:** [03 §3.4](03-solution-architecture.md#34-c4-level-3--component-diagram-the-document-intake-pipeline) ·
[06 §6.6](06-security-architecture.md#66-secure-document-processing-pipeline)

**The defect.** [C-15](00-design-authority-record.md#c-15--uploaded-documents-are-an-untrusted-code-attack-surface)
specifies that workers *"read exactly one blob via a short-lived scoped SAS, write to a quarantine
container, and terminate."* But the Rev A component diagram routes `OCR → BLOBD` (the **documents**
account) and the normalizer writes there too.

That gives a container which, by the design's own admission, should be assumed compromisable, write
access to the store holding every sanitized applicant document in the tenant.

**Reproduction.** Attack path AP-2 is written to conclude *"the attacker controls a container that
can see one document — the one they uploaded."* With write access to `stapdocuments`, a compromised
worker can also **overwrite** other applicants' documents, which is a far worse outcome than reading
one: it corrupts evidence with no read required.

**Consequence.** AP-2's conclusion is wrong as drawn. The blast-radius argument that justifies the
whole isolation design does not hold.

**Remediation (Rev B).** A third container, `staging`, is introduced:

- Workers read from `quarantine` (one blob, read-only SAS) and write **only** to `staging`, using an
  identity with `create`-but-not-`overwrite` permission and immutable blob naming keyed to the job id.
- A **Core-zone promotion service** validates the staging artifact against the expected job and
  hash, then copies it into `stapdocuments`. The processing zone has **no role assignment of any
  kind** on the documents account.
- Blob versioning plus an immutability window on `stapdocuments` means even a promotion-service
  defect cannot destroy a prior version.

**Status:** Remediated in Rev B. AP-2's stated conclusion is corrected.

---

### B-07 — A fixed 1,000-prompt corpus with a zero-escape bar is an overfittable gate
**Raised by:** Lead QA Architect · **Seconded by:** Responsible AI Lead
**Against:** [09 §9.3](09-responsible-ai.md#93-the-legal-advice-classifier) · [10 §10.3](10-devsecops-and-continuity.md#103-cicd-pipeline)

**The defect.** The UPL gate is the deliverable's headline safety control, and it is specified as:
*a fixed corpus of ≥ 1,000 prompts; escapes must be 0; blocks release.*

A gate evaluated repeatedly against a **static, visible** corpus is satisfied by tuning to that
corpus. After a handful of iterations the team is not measuring whether the classifier blocks legal
advice; it is measuring whether it blocks *these thousand sentences*. The number goes to zero and
stays there while real-world coverage is unknown. The gate then produces false confidence, which is
worse than no gate, because it is cited to a regulator.

**Consequence.** The strongest claim in the deliverable — *zero escapes* — is unfalsifiable as
specified.

**Remediation (Rev B).** The gate is restructured into three parts:

| Part | Contents | Bar |
|---|---|---|
| **Development corpus** | Visible to engineering; used for iteration | 0 escapes (necessary, not sufficient) |
| **Held-out corpus** | 300 prompts, **not visible to engineering**, held by the Responsible AI Lead, refreshed 20 % quarterly | 0 escapes — **this is the release gate** |
| **Live red team** | Quarterly external engagement writing *new* attacks against the shipped build | Findings are Sev-1; corpus grows from them |

Additionally: escapes are measured **per prohibited act and per language**, not in aggregate, so
strength in English cannot mask weakness in Haitian Creole; and a **novelty check** rejects any
held-out prompt with high similarity to a development-corpus prompt.

**Status:** Remediated in Rev B.

---

### B-08 — Extraction accuracy is measured on synthetic documents and reported as if it were real
**Raised by:** Lead QA Architect · **Against:** [10 §10.5](10-devsecops-and-continuity.md#105-test-strategy) ·
[01 §1.9](01-executive-summary.md#19-success-metrics)

**The defect.** Rev A states *"the factory's output **is** the golden set. Because ground truth is
known by construction, extraction accuracy is measurable exactly rather than estimated."*

The second sentence is true and the first makes it useless. A synthetic corpus reflects the
degradation distribution we *imagined*, not the one María's cracked-screen iPhone 12 produces in a
kitchen at night. Reporting ≥ 96 % accuracy against it, and gating a release on it, measures the
factory.

**Consequence.** The headline quality metric — and the calibration thresholds derived from it — rest
on a corpus with unknown relationship to production.

**Remediation (Rev B).** Two corpora, two purposes:

- **Synthetic corpus (2,000 docs).** Used for regression detection and adversarial cases. Cheap,
  unlimited, no privacy exposure. Gates *regression*, not absolute accuracy.
- **Consented real-document corpus (target 600 docs).** Collected from beta participants under
  specific, separately-recorded consent, held in a dedicated locked-down store with its own key,
  access restricted to the AI quality function, retained 24 months, deletable on request.
  **Absolute accuracy claims may only be made against this corpus.**
- Until the real corpus reaches 300 documents, published accuracy figures carry the qualifier
  *"synthetic corpus"* and the G1 accuracy gate is provisional.

The Privacy Officer's condition, accepted: consent for the evaluation corpus is a **separate,
non-bundled** opt-in, refusable without any service consequence, and the corpus is excluded from all
model training.

**Status:** Remediated in Rev B.

---

### B-09 — Phase 1 does not fit in Phase 1
**Raised by:** Senior Product Manager · **Seconded by:** Engineering Manager
**Against:** [11 §11.3](11-roadmap.md#113-phase-1--mvp-24-weeks-17-fte) · [Appendix A](appendix/appendix-a-backlog.md)

**The defect.** The arithmetic does not close.

- MVP scope: **1,478 points.**
- Stated capacity: 4 streams × 45 points × 10 sprints = **1,800 points**, described as "~18 % buffer."
- But the same plan runs **closed beta in weeks 15–20** — sprints 8, 9 and 10 — during which those
  streams are supporting beta, remediating penetration-test findings, producing SOC 2 evidence, and
  running the accessibility panel.

Real build capacity is therefore ~7 sprints: 4 × 45 × 7 = **1,260 points against 1,478 required.**
The plan is **~17 % short**, not 18 % buffered. The error is roughly 35 % of a phase.

Two compounding errors: 45 points per sprint per stream is at the optimistic end for a
4-person stream on a greenfield system with five blocking quality gates; and 276 of those points
were added late by the first review, so the original estimate was never re-baselined.

**Consequence.** G1 is missed, or scope is cut under pressure — and the things that get cut under
pressure are the gates.

**Remediation (Rev B).** Rebaselined honestly:

| Option | Effect | Chosen |
|---|---|---|
| Extend Phase 1 to 24 weeks | 12 sprints, 9 building = 1,620 pts capacity | **Yes** |
| Reduce MVP to 4 form packages (drop I-131) | −90 pts | **Yes** |
| Move Helper role and RFE-adjacent polish to P2 | −60 pts | **Yes** |
| Add a fifth stream | Rejected — coordination cost exceeds throughput gain at this size | No |
| Lower gate thresholds | **Rejected outright** | No |

Revised: **1,328 points against ~1,620 capacity — 18 % genuine buffer.** Phase 1 becomes 24 weeks;
total program moves from ~74 to ~78 weeks; Phase 1 cost rises ~$0.4 M.

**Status:** Remediated in Rev B. Recorded as a schedule change, not absorbed silently.

---

### B-10 — The abuse-monitoring fallback does not cover the case that matters
**Raised by:** Privacy Officer · **Seconded by:** CISO
**Against:** [C-23](00-design-authority-record.md#c-23--third-party-ai-processing-needs-explicit-contractual-and-configuration-posture) ·
[06 §6.7](06-security-architecture.md#67-secure-ai-processing-and-prompt-handling)

**The defect.** Rev A's contingency, if modified abuse monitoring is not approved, is: *"the
compensating control is a PII minimization proxy… and a documented acceptance by the CISO."*

But the deliverable also specifies, correctly, that the **extraction agent cannot use the proxy**
(`pii_minimization: false` in the Agent 05 contract) — extraction's entire job is to read the actual
passport number. Extraction is also the **highest-volume** model path in the product.

So in the un-approved case: passport numbers, A-Numbers, dates of birth and full names are sent to
an endpoint that retains prompts and completions for up to 30 days with the possibility of human
review, and the stated compensating control does not apply to that traffic at all.

**Consequence.** The contingency reads as covered and is not. This is the kind of gap that is only
discovered when the approval is actually denied, at which point there is schedule pressure to
proceed anyway.

**Remediation (Rev B).** The contingency is replaced with a decision tree that has no comfortable
branch, which is the honest shape:

1. **Approved** (expected): proceed as designed.
2. **Not approved — Path A (preferred).** Move identity-document extraction off the generative
   endpoint entirely and onto **Document Intelligence prebuilt/custom models only**, which are
   purpose-built extraction services and not subject to the generative abuse-monitoring regime.
   Structured-output post-processing then runs on **tokenized** data via the proxy. This is
   achievable because `prebuilt-idDocument` already returns typed fields for our highest-volume
   classes — the generative step is convenience, not necessity, for those documents.
3. **Not approved — Path B.** Launch without generative extraction for `CRITICAL`-class fields;
   those fields are entered manually with document-side-by-side assist. Slower for users, but no
   identifier leaves for generative processing.
4. **Not approved and neither path viable:** **do not launch that capability.** CISO acceptance is
   not available as a substitute for a control on this data.

Path A is now the *primary* design for identity documents regardless of the approval outcome, which
removes the dependency altogether — a better answer than a contingency.

**Status:** Remediated in Rev B. The dependency on approval (A3, RISK-020) drops from Medium to Low.

---

## 14.4 Major findings

| ID | Discipline | Finding | Disposition |
|---|---|---|---|
| **M-01** | Data | `Person.DisplayLabel NOT NULL` stores a name outside the provenance model, contradicting DP-3 ("every value carries provenance") and DP-4 ("all personal data hangs off a FieldValue"). A name is personal data with a source | **Fixed.** `DisplayLabel` becomes a user-set, non-authoritative label with an explicit `IsUserProvided` semantic; the authoritative name is a `FieldValue` like everything else |
| **M-02** | Data / Privacy | Data residency is bound to `Tenant.HomeGeo`. GDPR attaches to the **data subject**, not the tenant. A US organizational tenant preparing a case for an EU-resident beneficiary places that person's data in the US plane | **Fixed.** Residency is evaluated per `Person` at case creation; a case containing an EU-resident data subject is pinned to the EU plane, and a case that would span planes is refused with an explanation rather than silently split |
| **M-03** | Data / Cloud | Consumer users are modelled as one synthetic tenant each. At the Phase-2 target of 12,000 subscribers that is 12,000 tenants — and with per-tenant CMK, 12,000 HSM keys. This *is* [OPEN-01](12-risks-and-gap-analysis.md#127-open-decisions), arriving two phases earlier than the open decision assumes | **Fixed.** Consumer tenants share a pooled CMK with **per-case DEKs**; per-tenant CMK is reserved for organizational tenants. OPEN-01 is re-scoped and its due date moved forward to Phase 1 exit |
| **M-04** | Security | Rev A claims Always Encrypted protects `CRITICAL` fields, without stating that the application holds the key — so an application compromise yields plaintext. The control is overstated | **Fixed.** Claim narrowed to what it does: protects against DBA access, stolen backups, and compromised connection strings. Application compromise is explicitly out of its scope and is covered by other controls |
| **M-05** | Security | Certificate pinning against Azure Front Door is operationally fragile (managed cert rotation) and Rev A gives it a single line | **Fixed.** Pin to intermediate-CA SPKI with two pinned backups, a documented 90-day rotation runbook, a kill-switch delivered out-of-band, and a hard rule that pinning failure degrades to a blocking error with a support path — never to an unpinned connection |
| **M-06** | Security | Break-glass always notifies the affected user. No exception exists for trust-and-safety investigation of that user's own abuse, where notification defeats the investigation | **Fixed.** A narrow deferral: notification may be delayed up to 30 days on written authorization by the CISO **and** Compliance Officer jointly, recorded, and always ultimately delivered. Deferrals are counted in the transparency report |
| **M-07** | AI | The stage-3 LLM adjudicator inside the Legal Advice Classifier is itself a generative component. Rev A does not say what guards it, implying infinite regress | **Fixed.** Stage 3 receives **only** the candidate output and a fixed rubric — never user input, never document content — returns a constrained enum, and cannot emit user-visible text. It is a classifier with a language model inside, not a generative path |
| **M-08** | AI | Chat Interview (tier A, trust U1) holds an `attach_document` tool, which is a state change — apparently contradicting AI-1 | **Fixed.** Clarified: the tool emits a client-side UI intent and returns; the actual attachment is performed by the client against the documents API under the user's own credential. No agent-initiated write exists. Contract updated to name it `request_document_attachment` |
| **M-09** | Compliance | I-864 (Affidavit of Support) is in MVP. Its core question is whether sponsor income meets the published threshold. A validation rule that flags "income below threshold" is arguably characterizing sufficiency — prohibited speech act #7 | **Fixed.** The platform transcribes the published poverty-guideline table and the sponsor's stated figures, and performs **no comparison and no flag**. The form asks the sponsor to make that determination; we present both numbers and stop. Rule engine explicitly forbidden from emitting a sufficiency verdict on this field |
| **M-10** | Compliance | N-400 is in MVP and asks about arrests and citations — GDPR Article 10 criminal-offence data — while [C-04](00-design-authority-record.md#c-04--asylum-and-removal-defense-cases-must-be-out-of-scope-for-v1) cites criminal data as a reason for excluding the sensitive segment. Inconsistent | **Accepted with correction.** The exclusion rationale is narrowed to persecution-narrative data and Article 9 special categories, not criminal data per se. N-400 criminal fields are `CRITICAL`, Always Encrypted, never inferred over, never indexed, and excluded from all model context except where a form field requires the literal value |
| **M-11** | QA | "Zero Sev-1 privacy incidents" is listed as a **release gate**. An operational outcome cannot gate a pre-release build | **Fixed.** Reclassified as a **launch-continuation condition** and a stop condition ([12 §12.8](12-risks-and-gap-analysis.md#128-what-would-make-us-stop)). The corresponding pre-release gate is the invariant suite, which *is* testable |
| **M-12** | QA | "Reviewer edit rate on `VERIFIED` ≤ 3 %" appears among per-build gates. It requires production reviewer behavior and cannot run in CI | **Fixed.** Moved to the monthly calibration report with a threshold-breach action. CI retains only the offline calibration proxy against the labelled corpus |
| **M-13** | Integration | `GET /v1/cases/{caseId}/values` has no pagination and may return ~900 values with full provenance — a multi-megabyte response on a metered mobile connection | **Fixed.** Cursor pagination, a `?fields=` projection, and a lightweight `?view=summary` mode that omits provenance for list rendering |
| **M-14** | Cloud | Rev A claims RPO ≤ 5 min while Phase 1 is single-region. PITR gives ~5–10 min *within* a region; a regional loss falls back to geo-redundant backup with materially worse RPO | **Fixed.** RPO is now stated per scenario: ≤ 10 min for in-region failure; ≤ 1 h for regional loss in Phase 1 (accepted, RISK-028); ≤ 5 min from Phase 2 with active geo-replication |

---

## 14.5 Minor findings

All 17 remediated. Recorded for completeness.

| ID | Finding |
|---|---|
| m-01 | UX confidence chip for `VERIFIED` was "✓ Checked" — a checkmark reads as endorsement, contradicting UX-2's rule against celebratory affordances. Changed to a neutral "⊙ Two sources agree" |
| m-02 | Screen inventory claims 62 screens; the enumerated groups total 68. Corrected |
| m-03 | `ExtractedValue.SubjectPersonId` is nullable with no specified assignment mechanism. Added: person attribution is a human step at classification review, defaulting to the uploader's own Person, never inferred silently |
| m-04 | Audit `Reason NVARCHAR(500)` is free text and will contain case content, contradicting "audit contains no content." Constrained to an enum + optional reference id; free text moved to a separately-retained `ReviewNote` under case retention |
| m-05 | "Audit retention does not defeat erasure" is too strong — `PersonId` is personal data under GDPR. Corrected: subject identifiers in audit are **pseudonymized at erasure**, preserving chain integrity while breaking linkage |
| m-06 | "No egress" for the processing zone is imprecise; it has one private endpoint to Document Intelligence. Restated as "no internet egress; exactly two private endpoints, enumerated" |
| m-07 | STRIDE had no entry for compromise of the model provider endpoint itself. Added as I-13 with residual Medium |
| m-08 | "No voiceprints" claim extended beyond our control. Narrowed to "we do not create, request, or store any biometric identifier," with the provider's processing addressed contractually in the vendor register |
| m-09 | `Idempotency-Key` required on `DELETE`, which is naturally idempotent. Relaxed to POST/PATCH/PUT |
| m-10 | Step-up token TTL of 300 s is shorter than a realistic package review-then-approve interaction. Extended to 900 s for `APPROVE_PACKAGE` only, with the binding to purpose and resource retained |
| m-11 | `documentCount` in the folder response could reveal Private Annex existence. Explicitly excluded, with a test |
| m-12 | Cost model omits questionnaire-generation and PII-proxy calls. Recalculated: MVP $10.30 → **$11.90**, which **exceeds** the ≤ $11 target. Target restated as ≤ $12 for P1, ≤ $6 for P2, with the gap named rather than hidden |
| m-13 | `A11Y-GATE` and `EVAL-GATE` both claimed the reading-level check. Assigned solely to `EVAL-GATE` (it needs generated output); `A11Y-GATE` retains static UI copy only |
| m-14 | Bilingual labels at Dynamic Type AX5 can exceed a single screen. Added a specified behavior: secondary-language label collapses to a disclosure control above AX3 |
| m-15 | Sprint sequencing table showed Stream C's UPL corpus work completing in sprints 13–14, after beta opens in sprint 15 — but the gate is a beta *entry* condition. Resequenced to sprints 11–12 |
| m-16 | `Package.VerificationPassed` check constraint is `= 1`, making the column meaningless as a column. Retained deliberately (it documents the invariant) but annotated as such |
| m-17 | Appendix B claimed "0 gaps" on risks while five risks are accepted without a technical control. Restated as "5 accepted without technical control, each named" |

---

## 14.6 Accepted residuals — not fixed, and why

These five were raised, argued, and **not** remediated. Each has an owner and a review date.

| ID | Finding | Why it stands | Owner |
|---|---|---|---|
| **A-01** | Voice retains a 0.4–1.2 s exposure window before guardrail interrupt (B-01 residual) | Eliminating it requires proxying audio, which creates a worse privacy exposure for this population. The trade is deliberate and disclosed | Compliance Officer · review at G1 |
| **A-02** | An application-tier compromise yields plaintext for `CRITICAL` fields | Unavoidable while the application must read those values to fill forms. On-device extraction ([13 §13.3](13-v2-recommendations.md#133-on-device-extraction-and-client-held-keys)) is the real answer and is a V2 item | CISO · review at G2 |
| **A-03** | Human review capacity remains the true ceiling on organizational scale | Correctly identified in Rev A as RISK-013 and not solvable by architecture. It is a business-model constraint, and pretending otherwise would be the error | CPO · standing |
| **A-04** | A coerced user can be compelled to display their own screen; screenshot deterrence is partial | No technical control defeats physical coercion. Stated honestly rather than over-claimed | CX Lead · standing |
| **A-05** | Single-region Phase 1 accepts a regional-outage RTO of 4 h | Multi-region in Phase 1 would consume the buffer that B-09 just restored. The risk is bounded and the beta cohort is small | Principal Cloud Architect · review at G1 |

---

## 14.7 What this review says about Rev A

Worth stating plainly, because a review that only lists defects misrepresents the object.

**What held up.** Every one of the four scope reductions from the first review survived attack, and
the reviewers strengthened rather than weakened them. The capability boundary
([ADR-008](adr/ADR-008-agent-capability-boundary.md)) survived a dedicated attempt to break it and
is, in the Security Architect's assessment, the strongest single control in the design. The decision
to keep only three components agentic ([ADR-009](adr/ADR-009-durable-orchestration.md)) was
repeatedly validated: most findings in this review are in the *deterministic* parts, which is exactly
the distribution you want, because deterministic defects are findable.

**What did not.** The failures cluster in a recognizable pattern: **places where Rev A asserted a
property instead of constructing it.** B-01 (guardrails "on every utterance"), B-04 (RLS "at the data
layer"), B-05 ("set only by break-glass"), B-06 ("writes to quarantine"), B-07 ("zero escapes"),
B-08 ("measurable exactly") are all the same defect wearing six costumes — a control described in
the confident register of something already built.

The deliverable's own principle warned about this and it was not applied to itself:

> *"Enforced. Database check constraints, gateway rules, RLS predicates, empty tool allowlists — each
> stated with its enforcement point."* — [12 §12.9](12-risks-and-gap-analysis.md#129-assurance-summary)

Six of ten blocking findings are cases where the enforcement point named was not, on inspection,
capable of enforcing the claim. **That is the finding behind the findings**, and it is why
[Appendix B](appendix/appendix-b-traceability.md) now carries a third column requiring the *specific
mechanism*, and why the reviewers added a standing rule: any claim of the form "X is enforced by Y"
must cite runnable code, a constraint, or a policy resource — never a paragraph.

---

## 14.8 Conditions attached to sign-off

| # | Condition | Owner | Due |
|---|---|---|---|
| **CON-1** | Voice interrupt latency ≤ 600 ms p95 measured on the reference device. **If unmet, voice does not ship in MVP** | Lead Mobile Architect | G1 |
| **CON-2** | Held-out UPL corpus established, held by the RAI Lead, and never exposed to engineering | Responsible AI Lead | G0 |
| **CON-3** | Consented real-document evaluation corpus ≥ 300 documents before any absolute accuracy claim is published | Lead QA Architect | G1 |
| **CON-4** | Cross-folder and cross-person invariant tests operational and failing a seeded defect | Principal Security Architect | G0 |
| **CON-5** | `IsPlatformOperation` deleted from the schema and the scoped break-glass principal implemented | Principal Data Architect | G0 |
| **CON-6** | Path A for identity extraction (Document Intelligence only) demonstrated in the walking skeleton | Lead Backend Architect | G0 |
| **CON-7** | Audit outbox + per-tenant sequencer load-tested at 2× the peak ingest target | Lead Backend Architect | G1 |
| **CON-8** | Rebaselined Phase 1 plan (24 weeks, 1,328 pts) approved by the sponsor | CPO | Before Phase 0 exit |

CON-1, CON-4, CON-5 and CON-6 are **G0 blockers**: Phase 0 does not exit without them.

---

## 14.9 Sign-off

Each signatory has reviewed the sections in their discipline in Rev B and signs to the scope stated.
**Two disciplines sign conditionally**; those conditions are binding and are tracked in §14.8.

| Discipline | Role | Verdict | Scope and conditions |
|---|---|---|---|
| Enterprise architecture | Principal Enterprise Architect | **Approved** | Rev B. Coherence across all 14 documents re-verified after remediation |
| Application architecture | Principal Application Architect | **Approved** | Rev B, incl. B-02 proposal/value split |
| AI / agentic architecture | Agentic AI Architect | **Conditional** | Approved **subject to CON-1 and CON-2.** Without CON-1, voice is out of MVP |
| Responsible AI | Responsible AI Lead | **Conditional** | Approved **subject to CON-2 and CON-3.** Accuracy and escape claims are provisional until both hold |
| Security architecture | Principal Security Architect | **Approved** | Rev B, incl. B-04, B-05, B-06. Approval is contingent on CON-4 and CON-5 landing in Phase 0, which are already G0 blockers |
| Data architecture | Principal Data Architect | **Approved** | Rev B, incl. B-02, B-03, M-01, M-02, M-03 |
| Cloud / infrastructure | Principal Cloud Architect | **Approved** | Rev B, incl. B-06, M-14. A-05 accepted |
| Integration / API | Principal Integration Architect | **Approved** | Rev B, incl. M-13, m-09, m-10 |
| Backend engineering | Lead Backend Architect | **Approved** | Rev B, incl. B-03. CON-6 and CON-7 owned |
| Mobile engineering | Lead Mobile Architect | **Approved** | Rev B. CON-1 owned; flags it as the highest-uncertainty item in the plan |
| DevSecOps | Lead DevSecOps Architect | **Approved** | Rev B. Notes that the gate structure is now genuinely testable, which it was not in Rev A |
| QA / test | Lead QA Architect | **Approved** | Rev B, incl. B-07, B-08, M-11, M-12 |
| Privacy | Privacy Officer | **Approved** | Rev B, incl. B-10, M-02, M-06, m-05. Consent for the evaluation corpus must remain non-bundled |
| Compliance / UPL | Compliance Officer | **Approved** | Rev B, incl. M-09, M-10. **Retains the absolute veto**; A-01 is accepted only with the disclosure and gating in B-01 |
| Risk | Risk Officer | **Approved** | Rev B. RISK-032 added; RISK-020 downgraded to Low following B-10 |
| Accessibility | Accessibility Specialist | **Approved** | Rev B, incl. m-13, m-14. Co-signs the voice-default trade in the accessibility profile |
| Product | Senior Product Manager | **Approved** | Rev B, incl. B-09 rebaseline. Notes the 4-week slip and $0.4 M as the honest cost of the review |
| UX | UX Architect | **Approved** | Rev B, incl. m-01, m-02, m-14 |

### Executive acceptance

| Role | Verdict |
|---|---|
| Chief Technology Officer | **Accepted.** Rev B goes to ARB and SRB. CON-1/4/5/6 are G0 exit blockers and will not be waived |
| Chief Information Security Officer | **Accepted.** B-04, B-05 and B-06 were the findings that mattered; all three are structural fixes rather than procedural ones |
| Chief AI Officer | **Accepted.** B-07 changes how we will be able to speak about safety — from a number we produce to a number we cannot game |
| Chief Data Officer | **Accepted.** OPEN-01 pulled forward to Phase 1 exit per M-03 |
| Compliance Officer | **Accepted with the standing veto.** B-01 is the finding I would have wanted found by us rather than by a regulator |
| Chief Product Officer | **Accepted**, including the 4-week slip. Cutting gates to hold a date is the failure mode this review exists to prevent |

---

## 14.10 Residual honesty statement

Three things a reader should not conclude from a signed review.

1. **This is a design review, not an implementation assurance.** Every fix in Rev B is a change to a
   document. None of it has been built, run, or measured. The eight conditions in §14.8 exist
   precisely because several claims can only be settled by executing code.

2. **The UPL positions have still not been reviewed by a lawyer.** They are reasoned from public
   rules by people who are not admitted to practise. B-01, M-09 and M-10 are exactly the kind of
   finding that outside counsel would generate more of. The per-jurisdiction opinions in Phase 0 are
   not a formality.

3. **A second review found ten blocking defects in a deliverable that had already been reviewed
   once.** The reasonable inference is not that the design is now clean — it is that a third review
   would find more, and that the density of findings in the *deterministic* layers suggests the
   *probabilistic* layers are under-examined rather than sound. The remedy is the standing red-team
   and held-out-corpus cadence in B-07, not a belief that the list is complete.
