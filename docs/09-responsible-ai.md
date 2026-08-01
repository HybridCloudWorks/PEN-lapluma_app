# 09 — Responsible AI

**Owner:** Responsible AI Lead · **Accountable:** Chief AI Officer · **Contributors:** Compliance
Officer, Privacy Officer, Prompt Engineering Lead, Lead QA Architect · **Status:** For Responsible
AI board and SRB approval

Structured against the NIST AI Risk Management Framework functions — **Govern, Map, Measure,
Manage** — because a policy document that cannot be audited against a framework is a press release.

---

## 9.1 The position

Aperture uses AI to do three things: **read documents**, **ask questions**, and **check for
inconsistencies**. It does not use AI to decide anything.

That sentence is the whole policy. Everything below is the machinery that makes it structurally
true rather than aspirational.

| We use AI to | We never use AI to |
|---|---|
| Extract typed values from a document image | Decide whether a value is acceptable |
| Ask the questions a chosen form requires | Choose which form to file |
| Phrase a question in the user's language at their reading level | Interpret law and apply it to a person's facts |
| Notice that two documents disagree | Decide which document is right |
| Summarize what is missing | Judge whether evidence is sufficient or persuasive |
| Translate an interview turn | Certify an interpretation or a translation |
| Draft a report narrative over governed numbers | Characterize an individual |
| — | **Predict, estimate, or hint at any agency outcome** |
| — | **Approve anything** |

---

## 9.2 Govern — accountability and control

| Mechanism | Detail |
|---|---|
| **Accountable executive** | Chief AI Officer owns model selection and agent topology. **Compliance Officer holds an absolute veto** over anything touching the scrivener boundary ([00 §0.1](00-design-authority-record.md#01-decision-rights-raci-at-the-program-level)) |
| **Responsible AI review** | Every new agent, prompt template, model version, and capability passes an RAI review before deployment. The review record is an artifact, not a conversation |
| **Blocking release gates** | UPL adversarial corpus (escapes = 0) · groundedness · calibration · bias disparity · injection · reading level. Engineering **cannot** override these; only the Compliance Officer and the Chief AI Officer jointly can, and doing so requires a written, board-visible acceptance |
| **Model change control** | Model versions are **pinned**; automatic upgrades are disabled. A model change is a release requiring the full evaluation suite |
| **Prompt change control** | Prompts are versioned code. A change requires an eval run, a behavior diff on 50 sampled inputs, and a second reviewer ([04 §4.9](04-ai-agent-architecture.md#49-prompt-engineering-standards)) |
| **Incident classification** | A UPL escape or a PII leakage by an agent is a **Sev-1**, handled under the security IR process with the same rigor as a data breach |
| **External review** | Independent Responsible AI review annually and before any scope extension into sensitive matters (gate G3-A) |
| **Vendor governance** | Model provider terms recorded in the vendor register: dedicated resource, region pinned, no training on our data, modified abuse monitoring status, sub-processor disclosure |
| **Documentation** | A public-facing AI transparency page, and internal model cards for every deployed model and every custom extractor |

---

## 9.3 The Legal Advice Classifier

The single most important control in the platform. It runs on the egress path of **every**
generative output — to a user, to a form, to a document, to a report.

> **One exception, and it matters.** On realtime voice, audio flows client↔model directly, so our
> backend is not in the media path and cannot block an utterance before it is heard. There the
> classifier runs on the streaming transcript and **interrupts** rather than prevents, leaving a
> 0.4–1.2 s exposure window. This is a genuine weakening of the control on the highest-risk
> modality, tracked as RISK-032 and gated by CON-1.
> See [04 Agent 10](04-ai-agent-architecture.md#agent-10--voice-interview-agent) and
> [14 B-01](14-sme-review-and-signoff.md#b-01--the-voice-interview-cannot-be-guardrailed-the-way-the-deliverable-claims).

### The nine prohibited speech acts

| # | Act | Example of what is blocked | What the user gets instead |
|---|---|---|---|
| **1** | **Eligibility assessment** | "Based on your marriage date, you qualify for adjustment of status." | "I can't tell you whether you qualify. I can show you what this form asks for." |
| **2** | **Outcome prediction** | "This looks like a strong case — you'll probably be approved." | "No one here can predict what an agency will decide, and it would be wrong to guess." |
| **3** | **Strategy recommendation** | "You should file the I-485 concurrently rather than waiting." | "I can't advise on how or when to file. The instructions say what the agency requires." |
| **4** | **Form or benefit selection** | "For your situation, the I-360 is the right form." | "I can't choose a form for you. Here's the catalog, and here's free legal help." |
| **5** | **Interpretation of law applied to facts** | "Under INA 245(i), your 2001 entry means…" | "I can show you what the form asks. What it means for you is a legal question." |
| **6** | **Advice on disclosure or omission** | "You don't need to mention that arrest — it was expunged." | "I can't advise on what to include. The form asks this question; a lawyer can help you answer it." |
| **7** | **Characterizing evidence sufficiency** | "Three photos should be enough to prove your marriage is genuine." | "The instructions list what to submit. I can't judge whether what you have is enough." |
| **8** | **Consequences of a filing decision** | "If you file this, you'll be barred for ten years." | "That's a legal consequence question. Please talk to a legal provider — here's a list." |
| **9** | **Implying a professional relationship** | "As your immigration assistant, my advice is…" | "I'm a form-preparation tool, not a lawyer, and I'm not representing you." |

### Implementation

```
generative output
      │
      ▼
┌─────────────────────────────────────────────┐
│ Stage 1 — deterministic pattern screen      │  fast, catches the obvious
│  banned lexicon + regex over 9 act families │  ~2 ms
├─────────────────────────────────────────────┤
│ Stage 2 — fine-tuned classifier             │  multi-label over the 9 acts
│  calibrated; threshold tuned for recall     │  ~40 ms
├─────────────────────────────────────────────┤
│ Stage 3 — LLM adjudicator (ambiguous only)  │  invoked when stage 2 is
│  strict rubric, structured verdict          │  in the uncertainty band
└─────────────────────────────────────────────┘
      │
   ALLOW ──▶ deliver
   BLOCK ──▶ deterministic substitute + log UPL_DEFLECTION
```

**Design choices that matter**

- **Recall over precision, deliberately.** The threshold is tuned so that false positives are
  common and false negatives are not. Blocking a benign sentence costs a small usability hit;
  letting one through costs the company. This trade-off is explicit and reviewed quarterly.
- **Fail closed.** If the classifier is unavailable, generative features degrade to structured,
  non-generative flows. The product still works ([04 §4.11](04-ai-agent-architecture.md#411-failure-taxonomy-and-escalation)).
- **The substitute is deterministic.** A generated refusal could itself drift into advice. Refusals
  are written, reviewed, localized, and static — marked `"deterministic": true` in the API response
  ([07 §7.11](07-api-architecture.md#711-question-and-interview-apis)).
- **Ambiguity blocks.** Stage 3 returning "unclear" is treated as a block.

### Evaluation and the release gate

| Property | Requirement |
|---|---|
| Corpus structure | **Three parts, because a fixed visible corpus is satisfied by tuning to it** ([14 B-07](14-sme-review-and-signoff.md#b-07--a-fixed-1000-prompt-corpus-with-a-zero-escape-bar-is-an-overfittable-gate)) |
| — Development corpus | ≥ 1,000 prompts, visible to engineering, used for iteration. 0 escapes is **necessary, not sufficient** |
| — **Held-out corpus** | 300 prompts held by the Responsible AI Lead, **never exposed to engineering**, 20 % refreshed quarterly, novelty-checked against the development corpus. **This is the release gate** |
| — Live red team | Quarterly external engagement writing *new* attacks against the shipped build; findings are Sev-1 and grow the corpus |
| Coverage | All nine acts × every supported language × six attack styles (direct, indirect, roleplay, hypothetical, multi-turn escalation, document-embedded) |
| **Escapes** | **0 on the held-out corpus, measured per act and per language** — never in aggregate, so strength in English cannot mask weakness in Haitian Creole. **This blocks release.** Not a target — a gate |
| False-positive budget | ≤ 8 % on a benign corpus of 2,000 legitimate turns; exceeded → tune, never by lowering recall |
| Production sampling | 1 % of allowed turns re-classified offline plus human spot-check; weekly report to Compliance |
| Escape found in production | **Sev-1.** Affected surface halted, classifier patched, full corpus re-run before restoration |
| Red team | Quarterly external engagement targeting this classifier specifically |

---

## 9.4 Map — where AI touches the system, and what could go wrong

| # | AI touchpoint | Primary risk | Severity | Control |
|---|---|---|---|---|
| 1 | Document classification | Misclassification routes a document to the wrong extractor; a sealed medical is opened | High | Deterministic pre-filter for sealed class; human override authoritative; low confidence always asked |
| 2 | OCR | Misread character in an identifier | High | Checksum validation; cross-source agreement; human confirmation; source region shown |
| 3 | Data extraction | Hallucinated value with no source | **Critical** | Source anchoring mandatory; unanchored ⇒ `NEEDS_REVIEW`; model-generated ⇒ always `NEEDS_REVIEW`; DB constraint |
| 4 | Extraction over hostile content | Prompt injection | **Critical** | Capability boundary — the agent has no tools ([04 §4.4](04-ai-agent-architecture.md#44-trust-tiers-and-the-capability-boundary)) |
| 5 | Requirement retrieval | Fabricated requirement or citation | **Critical** | Citation mandatory or the item is dropped; corpus hash-verified; **never** fall back to model memory of a form |
| 6 | Questionnaire generation | A question that constitutes advice; a question that leaks another person's data | High | UPL guardrail; person-scoped retrieval at the data layer |
| 7 | Chat interview | Advice; harm; PII leakage; injection via pasted text | **Critical** | Full guardrail chain; person scope; fail closed |
| 8 | Voice interview | As chat, plus biometric and recording-consent exposure | **Critical** | No voiceprints exist; explicit consent; audio not retained by default |
| 9 | Translation | A mistranslated legal term; machine translation passing as certified interpretation | High | Pinned glossary; back-translation check; structural machine-assisted marker |
| 10 | Discrepancy explanation | Implying which value is "right" | Medium | Presents both with sources; never arbitrates |
| 11 | Reporting narrative | Characterizing an individual; ungrounded claim | Medium | Catalog-only queries; k-anonymity; groundedness check |
| 12 | Orchestration exception routing | An unsafe routing decision | Medium | Bounded action set; cannot invent a step; two failures escalate to a human |

**Not in the map, because they do not exist:** eligibility scoring · outcome prediction · document
authenticity adjudication · face matching · risk scoring of any person · automated approval ·
automated filing. Their absence is the design.

---

## 9.5 Confidence that means something

Implements [C-14](00-design-authority-record.md#c-14--confidence-scores-from-a-language-model-are-not-calibrated-probabilities).

**The problem.** Asking a language model "how confident are you?" produces a fluent number unrelated
to accuracy. Displaying it as "94 % confident" next to someone's date of birth manufactures false
assurance exactly where verification matters most.

**What we do instead.**

| Source of confidence | Used? | Why |
|---|---|---|
| Document AI service's own per-field confidence | **Yes** | Trained and calibrated on the extraction task |
| Cross-source agreement (two documents concur) | **Yes** | Deterministic and genuinely informative |
| Checksum validation (MRZ, A-Number format) | **Yes** | Deterministic proof |
| Presence and quality of a source anchor | **Yes** | A value that cannot be located on the page is not extracted, it is invented |
| Capture-quality signals from the device | **Yes** | A user-overridden blurry capture legitimately lowers confidence |
| **A model's self-reported confidence** | **No** | Not calibrated. Not used anywhere, for anything |

### The three bands

| Band | Definition | Applicant sees | Reviewer sees |
|---|---|---|---|
| `VERIFIED` | Two independent sources agree, **or** a checksum validates, **and** engine confidence ≥ 0.95 | ⊙ Two sources agree — "Two of your documents agree on this." | Band + raw score + both sources |
| `EXTRACTED` | Single source, anchored, engine confidence ≥ 0.85 | ○ From a document — "We read this from one document. Please check it." | Band + raw score + source |
| `NEEDS_REVIEW` | Below threshold **or** conflicting **or** checksum failed **or** unanchored **or** model-generated **or** capture quality overridden | ! Needs you — "We're not sure. Please tell us the right answer." | Band + raw score + the reason it was downgraded |

Raw numeric scores are retained in the ledger for calibration analysis and shown in the reviewer
workbench — where the audience is trained and the number is actionable — but **never surfaced as a
percentage to an applicant**.

### Calibration measurement

The ground truth is **reviewer behavior**: how often does a human change a value that we banded
`VERIFIED`?

| Metric | Target P1 | Target P2 | Action if breached |
|---|---|---|---|
| Reviewer edit rate on `VERIFIED` | ≤ 3 % | ≤ 1.5 % | Raise the threshold; the band has not earned its name |
| Reviewer edit rate on `EXTRACTED` | ≤ 15 % | ≤ 10 % | Retrain the extractor for the affected class |
| Expected Calibration Error | ≤ 0.08 | ≤ 0.05 | Retune thresholds; regenerate the reliability curve |
| Values reaching a form that a user later reports as wrong | ≤ 0.5 % | ≤ 0.2 % | Root-cause every instance individually |

A monthly reliability report goes to the Chief AI Officer. Bands are **not** static configuration;
they are retuned against measured behavior, and the retuning is a reviewed change.

---

## 9.6 Hallucination mitigation

Five layers, in order of strength.

| # | Layer | Mechanism | Catches |
|---|---|---|---|
| **1** | **Source anchoring** | Every extracted value must carry a page and a non-degenerate bounding polygon. A value with no anchor is not a value | Fabricated field values — the strongest control we have |
| **2** | **Retrieval grounding** | Requirements and citations come from a hash-verified corpus. An item without a citation is dropped, not shown | Fabricated requirements and fake citations |
| **3** | **Deterministic validation** | Types, formats, checksums, ranges, and cross-field rules are code, not inference | Values that are well-formed nonsense |
| **4** | **Groundedness classification** | Agent 17 checks every factual assertion against the grounding set; an ungrounded requirement claim blocks | Narrative drift |
| **5** | **Human confirmation** | No value reaches a form without a human accepting it against the visible source | Everything the first four missed |

**Never used as a mitigation:** "we asked the model to be careful." Prompt instructions are a
usability improvement, not a control, and are not counted in the control set.

**The measurement that matters:** on the golden set, **fabricated-value rate must be 0** —
where "fabricated" means a value that appears nowhere in the source document. This is measured
separately from accuracy, because a wrong-but-present value and an invented value are different
failures with different fixes.

---

## 9.7 Explainability

Every AI-influenced element in the product answers four questions on demand, from **data, not
inference**:

| Question | Answer source |
|---|---|
| *Where did this come from?* | Document, page, highlighted region — or "you typed this on 12 July" |
| *How sure are we, and why?* | Band + the specific reason (agreement, checksum, single source, conflict) |
| *What is it for?* | The form, part, and item number it will be written to |
| *Who touched it?* | The confirming human, the time, and whether it was on someone's behalf |

Additionally:

- **Requirement explanations** quote the agency's own words with a source URL and revision date.
  We never paraphrase a requirement into our own voice.
- **Interview questions** declare which single field they are asking about and show the
  authoritative English form label.
- **Discrepancy explanations** state both values, both sources, and both confidences — and stop.
  They do not suggest which is right.
- **Full AI transcripts** are retained under case retention and exportable by the user *and* by a
  supervising attorney, so the question "what did this thing tell my client?" has an exact answer
  ([FR-COMP-006](02-product-requirements.md#28-functional-requirements)).

**Explainability is not a model-interpretability exercise here.** We do not attempt to explain a
transformer's internals. We explain the *system*: what evidence produced what value, and who
decided.

---

## 9.8 Human oversight

| Checkpoint | Enforcement |
|---|---|
| **Every value** | `HUMAN_CONFIRMED` required before it can be rendered. Enforced by a database check constraint, an API rule, and a generation-time refusal — three independent layers |
| **Every package** | Human approval with step-up re-authentication. The approval endpoint **rejects non-human principals** at the gateway and in-service; an attempt raises Sev-1 |
| **Every classification** | Human override always available and always authoritative |
| **Every discrepancy** | Human resolution; the system never arbitrates |
| **Every field map** | Two-person approval plus a passing fixture test before activation |
| **Every prompt change** | Second reviewer plus an eval run |
| **Every model change** | Full evaluation suite; blocking gates |
| **1 % of AI turns** | Sampled and reviewed by humans weekly |
| **Every guardrail block** | Reviewed in aggregate weekly; individually if novel |

**Oversight is meaningful, not ceremonial.** Three specific design choices make the difference:

1. The reviewer sees the **source region**, not just the value — so confirming is a genuine check,
   not a rubber stamp.
2. **Bulk accept is restricted** to `VERIFIED` values, capped per action, and unavailable on
   iPhone — friction is deliberately placed where automation bias is most likely.
3. **Dwell time per field is measured.** If reviewers spend 0.4 seconds on `VERIFIED` values, we
   know oversight has degraded into clicking, and the band's threshold is the problem, not the
   reviewer.

---

## 9.9 Bias and fairness

### Where bias would show up here

| Vector | Concrete failure mode |
|---|---|
| **Script and language** | OCR accuracy lower on Arabic, Devanagari, or CJK than on Latin script — meaning users from some countries do more manual correction |
| **Name structure** | Name parsing that assumes Western given/family ordering, mangling patronymics, mononyms, compound surnames, and maiden-name conventions |
| **Document provenance** | Extraction models trained mostly on US and Western European documents performing worse on documents from other regions |
| **Reading level and phrasing** | Question phrasing that is harder in one language than another, producing lower completion |
| **Refusal asymmetry** | The UPL classifier over-blocking in one language, degrading the experience for those users specifically |
| **Voice recognition** | Higher error rates on accented speech, older speakers, and speakers with speech differences |
| **Access** | Device requirements excluding lower-income users — the fairness issue that no model tuning fixes |

### Measurement

Stratified monthly, with k-anonymity ≥ 25, over: UI language · interview language · document script ·
document issuing region (coarse) · reading-level profile · accessibility-profile use · device tier.

| Metric | Disparity threshold | Action on breach |
|---|---|---|
| Extraction field accuracy | ≤ 5 pp below the overall mean | Retrain the extractor for the affected class; if not closable, **disclose the limitation in-product** for that document type |
| Reviewer edit rate | ≤ 5 pp above the mean | Investigate; adjust bands per class |
| Interview completion rate | ≤ 10 pp below the mean | Phrasing and glossary review |
| UPL classifier block rate | ≤ 3 pp above the mean | Classifier retraining; over-blocking one language is a fairness failure, not a safety success |
| Voice comprehension retry rate | ≤ 10 pp above the mean | Modality guidance; consider disabling voice for the affected language rather than shipping a worse experience silently |
| Time to `Ready to File` | ≤ 25 % above the median | Product investigation |

**The disclosure rule.** Where a disparity cannot be closed, we tell affected users about the
limitation rather than letting them experience it as their own failure. A user re-typing a
Devanagari birth certificate deserves to know our extraction is weaker there — not to conclude they
took a bad photo.

**Reporting.** Monthly to the Chief AI Officer and Responsible AI Lead, with a **required written
response** to any breach. Repeated unremediated breach removes the capability for the affected
population. Quarterly external review of the fairness program.

---

## 9.10 Consent and transparency

### Granular consent

| Purpose | Default | Withdrawable | Consequence of withdrawal |
|---|---|---|---|
| Service terms | Required | No | Account ends |
| AI processing of documents | Opt-in at case creation | Yes | Manual entry only; the product still works |
| Voice recording | Opt-in per first session | Yes | Voice interviews stop; chat continues |
| Voice clip retention | **Off** | Yes | Clips deleted |
| Analytics | **Off** | Yes | None — the product is identical |
| Helper access | Explicit grant | Yes | Access ends within 60 seconds |
| Sharing with a tenant organization | Explicit | Yes | Case leaves the organization's queue |
| Marketing | **Off** | Yes | None |

Every consent records the **exact notice text hash**, version, locale, modality, and timestamp
([05 §5.3](05-data-architecture.md#53-relational-model--azure-sql)). Every withdrawal states its
consequence *before* the user confirms.

### Transparency obligations

| Where | What is disclosed |
|---|---|
| Before any account exists | What we store, where, how long, who sees it, what we do if the government asks |
| At registration | Not a law firm; no legal advice; no filing |
| At case creation | The user chose the forms; we did not |
| At every interview start | This is an AI · it is transcribed · it is not a lawyer · you can switch to text |
| On every AI-proposed value | Its source and confidence band |
| On every generated package | Not filed; no legal advice; the preparing organization and its verification status |
| On every machine-translated string | Machine-assisted |
| In Settings | Full AI transcripts, activity log including break-glass, model and data practices |
| Publicly | AI transparency page, model cards, sub-processor register, government-request policy, semi-annual transparency report, accessibility conformance report |

**Disclosures are never suppressible by tenant branding.** They are rendered by the platform layer,
and `canSuppressNotALawFirmDisclosure` is `false` for every tenant type — visible in the admin API
so the constraint is auditable rather than merely asserted
([07 §7.14](07-api-architecture.md#714-administration-apis)).

---

## 9.11 User correction and contestation

| Capability | Behavior |
|---|---|
| Correct any value | Direct edit; supersedes all extractions permanently; attributed; never silently re-overwritten by a later extraction |
| Override any classification | Human classification is authoritative and permanent |
| Reject a proposed value | With a reason; feeds extraction quality metrics |
| Report a wrong AI response | One tap from any assistant message; routed to the RAI queue with the full turn context |
| Contest a discrepancy | Both values are presented; the human decides; the decision is recorded with a rationale where required |
| Disable AI entirely for a case | Available to attorneys and folder owners. The case proceeds with manual entry and structured questionnaires |
| Escalate to a human | Always available; never gated behind an AI interaction |
| Export the full transcript | Self-service |

**Corrections are training signal, but never automatically.** A correction feeds the extraction
quality dashboard. It never silently updates a model, because a poisoned correction stream would be
an attack path. Model and threshold changes derived from correction data go through the same
reviewed release process as any other change.

---

## 9.12 Measurement dashboard

Reviewed monthly by the Chief AI Officer; the starred rows are **release gates**.

| Metric | Target | Frequency |
|---|---|---|
| ★ UPL classifier escapes (adversarial corpus) | **0** | Every build |
| ★ UPL escapes (production sampling) | **0** | Weekly |
| ★ Fabricated-value rate (golden set) | **0** | Every build |
| ★ Fabricated citation rate | **0** | Every build |
| ★ Injection corpus: tool invocations / state changes | **0** | Every build |
| ★ Reading level of AI output | ≤ 6th grade | Every build |
| ★ Bias disparity beyond threshold | None unremediated | Monthly |
| Extraction field accuracy (golden set) | ≥ 96 % → 98 % | Every build |
| Expected Calibration Error | ≤ 0.08 → 0.05 | Monthly |
| Reviewer edit rate on `VERIFIED` | ≤ 3 % → 1.5 % | Weekly |
| Groundedness pass rate | ≥ 99 % | Every build |
| UPL false-positive rate (benign corpus) | ≤ 8 % | Every build |
| Guardrail block rate in production | Monitored for spikes | Daily |
| Reviewer dwell time per `VERIFIED` field | ≥ 1.5 s median | Weekly |
| AI cost per completed case | ≤ $11 → $6 | Weekly |
| User-reported wrong AI responses | Trend down | Weekly |

---

## 9.13 What we will not build

Recorded so that a future team understands these were decisions, not omissions, and so that
reversing one requires an explicit, documented act.

| Capability | Why not |
|---|---|
| **Eligibility assessment** | Unauthorized practice of law. Structurally impossible: the retrieval agent has no access to case data |
| **Approval-likelihood scoring** | Would be relied upon, would be wrong, and would cause real harm to people who cannot afford to be misled |
| **Automated filing** | No lawful third-party API exists; automating a user's government portal login is a terms violation and an unacceptable credential risk |
| **Automated approval of packages** | The human is the control. Removing them removes the product's defensibility |
| **Face matching or liveness** | Biometric liability, discrimination surface, and no user benefit that justifies either |
| **Voiceprints or speaker identification** | BIPA and successor statutes; no architectural place to store one exists |
| **Document authenticity or fraud adjudication** | We are not an adjudicator. A false accusation of fraud against this population is catastrophic |
| **Watchlist or sanctions screening of applicants** | Would turn a preparation tool into a screening instrument pointed at its own users |
| **Sale, sharing, or advertising use of personal data** | Never. Stated in the privacy notice as an unconditional commitment |
| **Third-party analytics or attribution SDKs** | An event stream from this population to a data broker is unacceptable at any product benefit |
| **Attorney referral marketplace with a fee** | Fee-splitting and referral-rule exposure; the referral itself would be a judgment about the user ([C-24](00-design-authority-record.md#c-24--rejected-add-a-lawyer-marketplace-to-monetize)) |
| **A "warrant canary"** | Legally fragile and potentially misleading. The transparency report is the honest mechanism |
| **Emotion or sentiment inference on users** | No legitimate purpose; substantial harm potential in an enforcement context |
| **Retention of voice audio by default** | Consent-heavy, low-value, high-exposure |
