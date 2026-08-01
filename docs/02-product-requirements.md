# 02 — Product Requirements Document

**Owner:** Senior Product Manager · **Contributors:** Business Analyst, UX Architect, CX Lead,
Accessibility Specialist, Compliance Officer · **Status:** Baselined for Phase 0

---

## 2.1 Executive summary

Aperture is a native Apple-platform application that helps applicants and the organizations that
serve them **prepare** immigration and government-agency applications. It ingests documents,
extracts data, interviews the applicant to fill gaps, validates completeness against the selected
forms' own published requirements, and generates a filled, human-reviewed, exportable package.

It is a preparation tool, not a representative. It does not assess eligibility, recommend a filing
strategy, predict outcomes, or submit anything to any agency.

---

## 2.2 Problem statement

### The applicant's problem

An applicant preparing a family-based adjustment package must:

- assemble 6–9 forms totalling ~900 fields, with cross-form consistency requirements that are
  nowhere stated in one place;
- locate 20–40 supporting documents, several of which they have never possessed (a parent's birth
  certificate; a 2019 tax transcript; a divorce decree from another country);
- obtain certified translations for every non-English document;
- transcribe dates, names, and numbers identically across every form, where a single inconsistency
  invites a Request for Evidence that adds 3–9 months;
- do all of this in a language they may read at a limited level, under time pressure, with
  consequences measured in years of their life.

Errors are not evenly distributed. They concentrate in transcription (dates transposed, names
rendered differently across documents, A-Numbers mistyped), in omission (a required field left
blank causes rejection, not a query), and in evidence (the right document, missing).

### The organization's problem

Nonprofit legal services organizations and small immigration practices are capacity-constrained:
the bottleneck is paralegal hours spent on intake and transcription, not on judgment. A reviewer
who spends 90 minutes retyping a client's passport data is not spending it on the parts of the case
that require a licensed human.

### Why existing solutions fall short

| Approach | Gap |
|---|---|
| Agency online filing | Interactive only, English-first, no document extraction, no offline capture, no organizational workflow, no guidance on *what is missing* |
| Practice-management suites | Built for the firm, not the applicant; desktop-web; no mobile capture; expensive per seat |
| Generic form fillers | No domain knowledge of form requirements, versions, or evidence; no validation |
| Consumer "immigration DIY" services | Frequently drift into advice; opaque about the not-a-law-firm line; weak on non-English and on accessibility |
| Unregulated intermediaries | Actively harmful; the vacuum this product should compete against |

### The problem we deliberately do **not** solve

We do not tell the user which benefit to seek, whether they qualify, or what will happen. That is a
licensed judgment. Attempting it is both unlawful for us and, in practice, the failure mode that
harms this population most. See [C-01](00-design-authority-record.md#c-01--form-discovery-agent-as-briefed-is-unauthorized-practice-of-law).

---

## 2.3 Business objectives

| ID | Objective | Measure | Horizon |
|---|---|---|---|
| BO-1 | Reduce applicant effort to a complete package | Median time to `Ready to File` for I-130 ≤ 3.5 h (MVP), ≤ 2 h (P2) | P1 / P2 |
| BO-2 | Reduce incompleteness-driven agency rejections | Self-reported rejection-for-incompleteness ≤ 4 % → ≤ 2 % | P1 / P2 |
| BO-3 | Multiply organizational capacity | Reviewer minutes per package ≤ 25 → ≤ 12 | P1 / P2 |
| BO-4 | Serve non-English and low-literacy users at parity | Non-English completion ≥ 80 % of English rate → ≥ 90 % | P1 / P2 |
| BO-5 | Establish a defensible trust position | SOC 2 Type I (P1) → Type II (P2); published ACR; zero UPL findings | P1 / P2 |
| BO-6 | Reach sustainable unit economics | Blended AI cost per completed case ≤ $11 → ≤ $6 | P1 / P2 |
| BO-7 | Build a recurring revenue base | 12,000 paying consumer subscriptions and 60 organizational tenants by end of P2 | P2 |

---

## 2.4 User personas

### P1 — María, self-represented applicant *(primary)*

47, born in Guatemala, in the US 11 years, works two jobs. Speaks Spanish; reads Spanish at
approximately an 8th-grade level and English at a 3rd-grade level. Owns an iPhone 12 with a cracked
screen and 4 GB free storage, on a metered prepaid plan. Uses WhatsApp fluently; has never
completed a web form on a laptop. Her documents are in a manila envelope and in photos on her
phone.

- **Goal:** get her husband's I-130 package right the first time without paying $4,000.
- **Fears:** making a mistake that gets her family noticed; being cheated by someone claiming to be a
  lawyer; the app storing information the government could take.
- **Behavior that matters:** she will scan documents standing up, in poor light, one-handed. She
  will abandon a screen with more than ~4 elements. She will answer a spoken question she would not
  answer in writing.
- **Design implications:** on-device capture quality feedback; voice-first option; Spanish-first
  with English shown alongside; explicit, plain statements about what we store and for how long;
  never more than one decision per screen.

### P2 — Danielle, paralegal at a nonprofit legal services organization *(primary)*

31, certified paralegal at an EOIR-recognized nonprofit, carries 60–80 active matters. Works on a
Mac with two displays. Fast, keyboard-driven, deeply skeptical of automation because she has
cleaned up after it.

- **Goal:** move a case from intake to attorney review without retyping anything.
- **Fears:** an automated value being wrong in a way she does not catch; being blamed for a machine's
  error; a tool that adds a system of record she has to reconcile with her case management system.
- **Design implications:** side-by-side source-and-value review; every value clickable to its source
  region on the document image; keyboard-first accept/reject; bulk operations; a clear, exportable
  record of who accepted what.

### P3 — Anand, immigration attorney and firm principal *(secondary)*

Signs the G-28 and bears the professional responsibility. Cares about: supervision, defensibility,
the audit trail, and whether the tool ever says something to his client that he did not say.

- **Design implications:** approval requires step-up auth; full immutable audit; a "what did the AI
  tell my client" transcript view; the ability to disable AI interviewing per case; firm branding
  that never suppresses the not-a-law-firm disclosure.

### P4 — Ruth, program director at a community organization *(secondary)*

Runs clinics; needs reporting for funders (cases served, demographics in aggregate, throughput),
and needs to know her volunteers cannot see cases they should not.

- **Design implications:** role-scoped access, clinic/queue constructs, aggregate reporting with
  k-anonymity, no per-case data in exports beyond what she is entitled to.

### P5 — Jorge, the applicant's adult son, helping *(tertiary)*

Bilingual, tech-fluent, does the actual tapping for his mother. Introduces a delegation problem:
he is not the applicant, may see things his mother would not choose to share, and may answer on her
behalf.

- **Design implications:** an explicit **Helper** role with recorded consent from the applicant, a
  visible "helping María" banner, per-section grants, attribution of every answer to the human who
  actually gave it, and a revocation path.

### P6 — Sam, platform operations / trust & safety *(internal)*

Investigates abuse and incidents. **Must be able to do their job without reading case content.**

- **Design implications:** break-glass access with dual approval, time boxing, and a user-visible
  notice; operational telemetry designed to be content-free.

### Anti-persona — "Notario Nick"

An unlicensed consultant who wants Aperture to make him look like a law firm. Every tenant-facing
design decision is tested against: *does this help Nick?* If yes, it is redesigned. See
[C-10](00-design-authority-record.md#c-10--the-platform-will-attract-bad-faith-administrator-tenants).

---

## 2.5 Stakeholders

| Stakeholder | Interest | Influence | Engagement |
|---|---|---|---|
| Applicants | Correct, affordable, private preparation | High (adoption) | Research panel, beta cohort, in-app feedback |
| Partner legal organizations | Capacity, defensibility | High (distribution + credibility) | Design partners from Phase 0; 3 in MVP beta |
| Immigration attorneys | Professional responsibility, supervision | High (gatekeeper) | Advisory board, quarterly |
| Outside counsel (UPL) | Regulatory boundary | **Veto** | Review at each phase gate, per-jurisdiction opinions |
| Investors / board | Return, risk | High | Quarterly, risk register standing item |
| Apple App Review | Guideline conformance (privacy labels, ATT, 5.1.1, 5.1.2) | **Gate** | Pre-submission review at Phase 0 exit |
| Azure / vendor | Capacity, Limited Access approvals | Medium | Named account team; modified-abuse-monitoring application in Phase 0 |
| Government agencies | Not a partner; a publisher of forms and instructions | Indirect | Monitored, never integrated with beyond public content |
| Community advocates / civil liberties orgs | Whether we increase or reduce harm | Medium-High (reputational) | Consulted before Phase 3 sensitive-matter gate |
| Internal: Security, Privacy, Compliance, Accessibility | Control effectiveness | **Veto** (see [00 §0.1](00-design-authority-record.md#01-decision-rights-raci-at-the-program-level)) | Embedded in delivery, not gate-at-the-end |

---

## 2.6 Epics

| Epic | Name | Outcome | Phase | Points |
|---|---|---|---|---|
| E-01 | Identity & Account | A user can create and recover an account safely with passkeys | P1 | 55 |
| E-02 | Virtual Folder & Case | A user can create and manage a folder containing people and cases | P1 | 89 |
| E-03 | Form Catalog & Package Selection | A user can find and select a form package; the platform knows its requirements and edition | P1 | 76 |
| E-04 | Document Capture & Ingest | A user can get documents into the system from any supported source, with quality assured at capture | P1 | 89 |
| E-05 | Classification, OCR & Extraction | Documents are classified and their data extracted with citations and confidence | P1 | 110 |
| E-06 | Extraction Review Ledger | Every proposed value is reviewable against its source and accepted by a human | P1 | 68 |
| E-07 | Dynamic Questionnaire | Only the questions the selected forms require are asked, in the right order | P1 | 76 |
| E-08 | Chat Interview | An applicant can complete gaps by typing, in their language | P1 | 63 |
| E-09 | Voice Interview | An applicant can complete gaps by speaking, in their language | P1 | 89 |
| E-10 | Validation & Missing Items | The platform tells the applicant exactly what is missing and why | P1 | 71 |
| E-11 | Notifications | Users are told what needs their attention, on their terms | P1 | 42 |
| E-12 | Human Review Workbench (macOS) | A reviewer can clear a case efficiently and defensibly | P1 | 97 |
| E-13 | Package Generation & Verification | Filled official PDFs, verified, with index, checklist and exhibits | P1 | 105 |
| E-14 | Export & Delivery | The package leaves the platform safely | P1 | 47 |
| E-15 | Audit, Consent & Transparency | Everything is logged; consent is a record; users can see and export it | P1 | 63 |
| E-16 | Data Rights & Retention | Export, delete, retain-by-policy, crypto-shred | P1 | 55 |
| E-17 | Tenancy, Roles & Administration | Organizations, roles, KYB, and the household trust model | P1 | 84 |
| E-18 | Accessibility & Localization | The product works for the people who need it most | P1 | 76 |
| E-19 | Platform Observability & Cost Control | We can see what the system and the models are doing, and what they cost | P1 | 55 |
| E-20 | Responsible AI Guardrails | The scrivener boundary is enforced and measured | P1 | 68 |
| E-21 | Search | A user or reviewer can find anything they are entitled to see | P2 | 47 |
| E-22 | Reporting & Analytics | Organizations get the numbers they need without content exposure | P2 | 63 |
| E-23 | RFE & Amendment Support | Respond to an agency request against an existing case | P2 | 76 |
| E-24 | Self-Serve Tenancy & Billing | Organizations onboard themselves, verified | P2 | 71 |
| E-25 | Partner API & Integrations | Case-management systems can integrate | P3 | 89 |
| E-26 | Sensitive Matters (gated) | Serve the highest-need segment safely | P3 | 144 |

**MVP total: 1,478 points across E-01…E-20.** At a normalized 45 points/sprint for the Phase-1 team,
that is ~33 team-sprints; with 4 parallel streams over 10 two-week sprints this fits the 20-week
Phase 1 with ~15 % buffer. Full backlog with story-level decomposition:
[Appendix A](appendix/appendix-a-backlog.md).

---

## 2.7 User stories and acceptance criteria

Stories use `As a <persona>, I want <capability>, so that <outcome>`. Acceptance criteria are
Given/When/Then and are directly traceable to tests
([Appendix B](appendix/appendix-b-traceability.md)). A representative subset is given here; the
complete set is in Appendix A.

---

### E-01 — Identity & Account

**US-01.01 (8 pts) — Register with a passkey**
*As María, I want to create an account without inventing a password, so that I do not lose access
and cannot be phished.*

- **AC1** Given a first-run device, when I choose *Create account*, then I am offered a passkey as
  the primary method with a one-sentence plain-language explanation, and email OTP as the fallback.
- **AC2** Given I create a passkey, then no password is ever created or stored for my account.
- **AC3** Given I register, then I am shown, before submitting, exactly what the account stores
  (email, display name, locale) and I must actively acknowledge the not-a-law-firm notice.
- **AC4** Given VoiceOver is active, then the entire flow is operable and every control announces a
  label, a role, and a hint.
- **AC5** Given the device does not support passkeys, then email OTP + TOTP enrolment is offered and
  the account is flagged `AUTH_DOWNGRADED` in the audit log.
- **AC6** Given registration, then a `ConsentRecord` row is written capturing the exact version hash
  of each notice displayed.

**US-01.04 (13 pts) — Recover access without losing my case**
*As María, I want to get back in after losing my phone, so that months of work are not gone.*

- **AC1** Given I have lost my device, when I recover with a verified email OTP plus a recovery code
  issued at registration, then I regain access to my folders.
- **AC2** Given recovery succeeds, then all existing sessions are revoked, all passkeys are
  invalidated, a new enrolment is required, and a security notification is sent to the account
  email.
- **AC3** Given recovery, then a 24-hour hold is placed on package export and on adding new
  household members, and the hold is explained on screen.
- **AC4** Given recovery is attempted and fails 5 times in 15 minutes, then the account is
  temporarily locked and a security event is raised.
- **AC5** Given a folder has other adult members, then recovery of the owner's account does **not**
  grant access to another member's Private Annex under any circumstances.

**US-01.06 (5 pts) — Understand what happens to my data before I give any**
- **AC1** Given first run, before any account is created, then a plain-language (≤ 6th grade,
  measured) summary is presented: what we store, where, for how long, who can see it, and what we
  do if the government asks.
- **AC2** Given that screen, then it is available thereafter from Settings and is versioned; the
  version acknowledged is recorded.

---

### E-02 — Virtual Folder & Case

**US-02.01 (8 pts) — Create a folder**
- **AC1** Given I am authenticated, when I create a folder, then I name it, and it is created with
  me as `FolderOwner` and one `Person` record for me.
- **AC2** Given creation, then the folder's `tenant_id` is bound and cannot be changed.
- **AC3** Given creation, then an audit event `FOLDER_CREATED` is written with actor, time, device,
  and IP class (not full IP).

**US-02.03 (13 pts) — Add a household member as a person, not a field**
- **AC1** Given a folder, when I add a spouse, child, or parent, then a distinct `Person` record is
  created with its own identifiers and relationship edges, and their data is never stored as a
  denormalized attribute of me.
- **AC2** Given a person is an adult, then I am offered to invite them to hold their own credential.
- **AC3** Given a person is a minor, then guardianship/relationship is recorded and no invitation is
  offered.
- **AC4** Given the same human appears in two roles (e.g. a child who is also a derivative
  applicant), then one `Person` exists with two role edges, not two people.

**US-02.05 (13 pts) — Adult household members control their own information**
*(Implements [C-05](00-design-authority-record.md#c-05--a-household-folder-is-not-a-single-trust-boundary).)*

- **AC1** Given I am an adult invited to a folder, when I accept, then I receive my own credential
  and a **Private Annex** scoped to me.
- **AC2** Given my Private Annex contains an item, then the folder owner cannot read it **and cannot
  see that it exists** — no count, no placeholder, no timestamp, no audit entry visible to them.
- **AC3** Given I choose **Quiet Exit**, then my participation ends, my consent is revoked, my
  Private Annex is queued for erasure, and **no notification of any kind is generated to any other
  folder member**.
- **AC4** Given Quiet Exit, then the shared folder shows only `Participant no longer active` with no
  reason and no timestamp finer than a month.
- **AC5** Given any interview agent session, then its retrieval scope is bound to a single
  `person_id` and a query for another person's answers returns empty at the data layer, not by
  prompt instruction.

**US-02.08 (8 pts) — Grant a helper limited access**
- **AC1** Given I add Jorge as `Helper`, then I select which sections he may see and whether he may
  answer on my behalf.
- **AC2** Given Jorge answers a question, then the answer records `answered_by = Jorge` and
  `on_behalf_of = María`, and this attribution appears in the review UI and the audit log.
- **AC3** Given Jorge is active, then a persistent banner shows whose case he is in.
- **AC4** Given I revoke Jorge, then his access terminates within 60 seconds across all his active
  sessions.

---

### E-03 — Form Catalog & Package Selection

**US-03.01 (8 pts) — Browse and select a form package without being advised**
- **AC1** Given the catalog, then I can search by form number, by title, and by the agency's own
  published category label, and results are identical for every user regardless of any information
  the platform holds about them.
- **AC2** Given any package, then the screen shows the form edition date, the agency source URL, the
  published fee, and the date our copy was last verified.
- **AC3** Given I search, then **no** result is ranked, highlighted, or filtered based on my profile,
  my documents, or my answers.
- **AC4** Given I ask the assistant "which form should I file", then the assistant declines,
  explains it cannot choose a form, offers the catalog and the agency's own public tools, and
  offers the nonprofit legal-provider directory. The refusal is logged as `UPL_DEFLECTION`.
- **AC5** Given I select a package, then I confirm an attestation that I (or my representative)
  chose it.

**US-03.04 (13 pts) — Requirements are derived from the agency's own instructions with citations**
- **AC1** Given a selected package, then the required field set is derived from the pinned form
  edition's field map, not from a model's memory.
- **AC2** Given a required-evidence item, then it carries a citation to the agency instruction
  document, section, and revision date, and the citation is displayed on demand.
- **AC3** Given a requirement cannot be sourced to a citation, then it is not shown.

**US-03.06 (13 pts) — Edition drift is caught before it hurts anyone**
- **AC1** Given a daily catalog check, when the agency's published PDF hash changes, then the form
  version is marked `SUPERSEDED`, a new version row is created, and all cases with an unfiled
  package on the old edition move to `QUARANTINED_FORM_DRIFT`.
- **AC2** Given quarantine, then affected users and case owners are notified within 1 hour with a
  plain explanation and a one-tap migration that re-maps answers to the new edition, flagging any
  field that no longer exists or is newly required.
- **AC3** Given a generated package, then the PDF metadata and the audit log record the exact
  edition date and source hash used.

---

### E-04 — Document Capture & Ingest

**US-04.01 (13 pts) — Scan a document with the camera and know immediately if it is good**
- **AC1** Given the camera scanner, then edges are detected, perspective corrected, and multi-page
  capture supported.
- **AC2** Given a captured frame, then on-device analysis evaluates blur, glare, resolution
  (≥ 300 dpi equivalent for the detected document size), completeness of edges, and presence of
  detectable text, **before** upload, and prompts a re-shoot with a specific reason
  ("the top edge is cut off") within 800 ms.
- **AC3** Given a re-shoot prompt, then I may override and keep the image, and the override is
  recorded so downstream confidence is adjusted.
- **AC4** Given the device is offline, then capture, enhancement, and queuing all still work.
- **AC5** Given VoiceOver is active, then a fully non-visual capture path exists with audio framing
  guidance and an alternative "import from Files" route that is never harder to reach.
- **AC6** Given capture, then no location metadata is attached, and any EXIF GPS present in an
  imported image is stripped before upload.

**US-04.03 (8 pts) — Import from Photos, Files, or another app**
- **AC1** Given the photo library, then I use the limited-access picker; the app never requests full
  library authorization.
- **AC2** Given a share-sheet import from Mail or Messages, then the file enters the same pipeline.
- **AC3** Given an unsupported type, then a clear message names the supported types.
- **AC4** Given a file > 100 MB or a PDF > 500 pages, then it is rejected client-side with an
  explanation and a suggestion to split.

**US-04.05 (13 pts) — Upload safely on a bad connection**
- **AC1** Given a queued upload, then it uses chunked, resumable background transfer and survives
  app termination.
- **AC2** Given metered cellular, then large uploads default to Wi-Fi-only with a visible, one-tap
  override, and the estimated data size is shown.
- **AC3** Given the upload completes, then the client verifies the server-computed SHA-256 matches
  its own before deleting any local copy.

---

### E-05 — Classification, OCR & Extraction

**US-05.02 (13 pts) — Documents classify themselves**
- **AC1** Given an uploaded file, then it is classified into the document taxonomy with a confidence
  band; below threshold it is routed to `NEEDS_CLASSIFICATION` and I am asked.
- **AC2** Given a classification, then I can always override it, and my override is authoritative
  and recorded.
- **AC3** Given a document classifies as `SEALED_MEDICAL`, then no OCR, no extraction, and no LLM
  processing occurs, no preview is rendered, and the checklist records possession only.
  *(Implements [C-06](00-design-authority-record.md#c-06--sealed-medical-exams-must-never-be-ocrd).)*
- **AC4** Given a document is detected as an *opened* I-693, then a warning is surfaced and
  extraction is still refused.

**US-05.04 (21 pts) — Extraction produces citations, not assertions**
- **AC1** Given an extracted value, then it stores: the value, the source `document_id`, the page,
  the bounding polygon, the extracting engine and version, the raw engine confidence, and the
  derived confidence band.
- **AC2** Given two documents provide the same logical field, then agreement promotes the value to
  `VERIFIED`; disagreement creates a `Discrepancy` and the value is `NEEDS_REVIEW` — the system
  never silently picks a winner.
- **AC3** Given a checksum-bearing field (passport MRZ check digits, A-Number format), then the
  checksum is validated and failure forces `NEEDS_REVIEW` regardless of engine confidence.
- **AC4** Given a value is model-generated rather than engine-extracted, then it is banded
  `NEEDS_REVIEW` and labelled as a suggestion.
  *(Implements [C-14](00-design-authority-record.md#c-14--confidence-scores-from-a-language-model-are-not-calibrated-probabilities).)*
- **AC5** Given extracted text contains instruction-like patterns, then the document is flagged for
  review, a security event is raised, and the text is still processed only as inert data.
  *(Implements [C-16](00-design-authority-record.md#c-16--prompt-injection-via-uploaded-documents-is-a-first-class-threat).)*

**US-05.07 (8 pts) — Names are handled correctly**
- **AC1** Given a name, then it is stored with the full original string, the script, and a
  transliteration where applicable; it is never split into first/middle/last by a heuristic without
  human confirmation.
- **AC2** Given a name differs across documents (diacritics, patronymics, maiden names, ordering,
  transliteration variants), then a `NameVariant` set is maintained and surfaced as an "other names
  used" candidate rather than treated as an error.
- **AC3** Given a form requires a specific name field, then the human chooses which variant to use.

---

### E-06 — Extraction Review Ledger

**US-06.01 (13 pts) — See where every value came from**
- **AC1** Given any field on any form preview, then tapping it shows the source document, the page,
  and the highlighted region the value came from — or states plainly "you typed this" or
  "you told this to the assistant on <date>".
- **AC2** Given a value, then its confidence band is shown with a plain-language meaning, never as a
  bare percentage in the applicant UI.
  *(Implements [C-14](00-design-authority-record.md#c-14--confidence-scores-from-a-language-model-are-not-calibrated-probabilities).)*
- **AC3** Given I correct a value, then the correction supersedes all extractions permanently, is
  attributed to me, and is never overwritten by a later extraction without an explicit prompt.

**US-06.03 (8 pts) — Nothing reaches a form without a human**
- **AC1** Given a package generation request, then it fails if any required field's current value
  has state `PROPOSED`; only `HUMAN_CONFIRMED` values may be rendered.
- **AC2** Given a bulk-accept action, then it is available only in the reviewer workbench, requires
  the values to be in band `VERIFIED`, is capped per action, and records each accepted value
  individually in the audit log.

---

### E-07 / E-08 / E-09 — Questionnaire and Interviews

**US-07.01 (13 pts) — Ask only what the form needs**
- **AC1** Given a selected package and the current extraction state, then the question set contains
  exactly the required fields not yet satisfied, ordered to minimize context switching between
  people and topics.
- **AC2** Given a conditional field (asked only if a prior answer is X), then the condition is
  derived from the form's own instructions and cited.
- **AC3** Given an answer, then dependent questions are recomputed within 300 ms.
- **AC4** Given a question, then it is presented in the user's language with the authoritative
  English form-field label available alongside.

**US-08.02 (13 pts) — Chat interview that behaves**
- **AC1** Given any assistant turn, then the output passes the guardrail chain (UPL, safety, PII
  leakage) before display; a block substitutes a deterministic, helpful refusal.
- **AC2** Given the assistant asks a question, then it maps to exactly one form field or one
  evidence item, identified in the message metadata.
- **AC3** Given VoiceOver, then streamed output is announced as a completed block via a polite live
  region, not token by token.
  *(Implements [C-12](00-design-authority-record.md#c-12--accessibility-cannot-be-a-phase-2-item-for-this-population).)*
- **AC4** Given the user asks anything outside preparation, then the assistant declines within its
  scope statement and offers the directory.
- **AC5** Given the session, then the full transcript is retained under the case's retention policy
  and is exportable by the user.

**US-09.01 (21 pts) — Voice interview with informed consent**
- **AC1** Given I start a voice session, then before any audio is captured I am told — in audio and
  on screen — that this is an AI, that it will be transcribed, that it is not a lawyer, and how to
  switch to text; and I must affirmatively consent.
- **AC2** Given consent, then a `ConsentRecord` is written with the exact disclosure version, the
  modality, the retention choice, and the jurisdiction basis.
- **AC3** Given a session, then audio is streamed client↔model over WebRTC using a short-lived
  ephemeral key minted by our backend; **our backend never receives the audio stream**.
- **AC4** Given a session, then **no voiceprint, speaker embedding, or biometric identifier is
  created or stored, anywhere, ever.**
  *(Implements [C-07](00-design-authority-record.md#c-07--voice-interviews-create-biometric-and-wiretap-exposure).)*
- **AC5** Given default settings, then audio is discarded on session end and only the transcript is
  retained; per-session opt-in retains answer clips for 30 days.
- **AC6** Given a session, then it is scoped to a specific missing-items batch, targets ≤ 7 minutes,
  and the agent closes it when the batch is resolved.
- **AC7** Given the voice minute budget is exhausted, then the user is told plainly, the session
  ends gracefully with answers preserved, and text interview remains fully available.
- **AC8** Given the accessibility profile is active, then voice is the default modality and the
  minute budget does not apply.
- **AC9** Given the user says anything indicating danger, abuse, or crisis, then the agent stops the
  interview, provides pre-approved resources, and does not attempt counselling.

**US-09.04 (8 pts) — Say it in my language**
- **AC1** Given a supported language, then questions, confirmations, and summaries are delivered in
  it, and every value written to a form field is written in the form's required language and script.
- **AC2** Given machine translation, then it is labelled machine-assisted wherever shown and never
  populates an interpreter certification.
  *(Implements [C-08](00-design-authority-record.md#c-08--machine-translation-cannot-be-represented-as-interpretation).)*
- **AC3** Given a legal term of art, then the curated glossary translation is used, not a free
  translation.

---

### E-10 — Validation & Missing Items

**US-10.01 (13 pts) — Know exactly what is missing**
- **AC1** Given a case, then the Missing Items list shows each item with: what it is, which form and
  field or which evidence requirement it satisfies, the citation for why it is required, and the
  fastest way to resolve it (scan / answer / type).
- **AC2** Given an item, then it has exactly one owning `Person` so a household can divide the work.
- **AC3** Given resolution, then the item clears within 2 seconds of the value reaching
  `HUMAN_CONFIRMED`.
- **AC4** Given a blocking item versus a recommended item, then the two are visually and
  semantically distinct, and only agency-required items are marked blocking.

**US-10.03 (13 pts) — Cross-form and cross-document consistency**
- **AC1** Given the same logical field appears on multiple forms in the package, then a single value
  drives all of them and divergence is impossible by construction.
- **AC2** Given values that must be mutually consistent (a marriage date after both birth dates; an
  entry date after a passport issue date; an address history with no gaps > 30 days where the form
  requires continuity), then a deterministic rule engine flags violations with the specific rule
  and its citation.
- **AC3** Given a rule fires, then it never auto-corrects; it asks.

**US-10.05 (8 pts) — Progress that does not lie**
- **AC1** Given the case dashboard, then progress is shown as two explicit mechanical counters —
  *form fields filled (n of m)* and *documents collected (n of m)* — and never as a single
  "% complete."
- **AC2** Given any progress display, then a persistent statement clarifies that readiness is not a
  prediction of any agency decision.
  *(Implements [C-20](00-design-authority-record.md#c-20--the-completion-percentage-will-be-read-as-a-prediction).)*

---

### E-12 — Human Review Workbench

**US-12.02 (21 pts) — Review a case at speed**
- **AC1** Given the workbench, then a case opens in a three-column layout: queue · discrepancies and
  fields · source document viewer.
- **AC2** Given a field is selected, then the source document scrolls to and highlights the
  extraction region automatically.
- **AC3** Given the keyboard, then `J`/`K` move between items, `⌘↵` accepts, `⌘⇧R` rejects with a
  reason, `⌘E` edits, and every action is undoable for 10 seconds.
- **AC4** Given a reviewer accepts a value, then the audit log records reviewer identity, value
  before and after, the confidence band at the time, and the elapsed dwell time on that field.
- **AC5** Given the case has any unresolved blocking discrepancy, then approval is disabled with the
  blocking items listed.

**US-12.05 (13 pts) — Approve a package deliberately**
- **AC1** Given approval, then the reviewer must re-authenticate (step-up, passkey or WebAuthn) and
  affirmatively attest that they have reviewed the package.
- **AC2** Given approval, then the exact form editions, the full value set, and the attestation text
  version are captured in an immutable approval record.
- **AC3** Given approval, then **no AI agent is in the approval code path** and the approval API
  rejects any non-human principal.
- **AC4** Given any value changes after approval, then the approval is automatically invalidated and
  the case returns to review with an explicit notice.

---

### E-13 — Package Generation & Verification

**US-13.01 (21 pts) — Generate the official filled forms**
- **AC1** Given an approved case, then each form is produced by filling the agency's own published
  AcroForm at the pinned edition — never by recreating the form's appearance.
- **AC2** Given generation, then a **round-trip verification** re-parses the output PDF, re-extracts
  every field, and asserts byte-equality with the source record; any mismatch **fails** generation.
  *(Implements [C-03](00-design-authority-record.md#c-03--pdf-generation-against-government-forms-is-harder-than-the-brief-assumes).)*
- **AC3** Given a form whose encoding is `XFA` or `FLAT`, then it is marked **Assisted Fill Only**
  and the platform produces a data sheet plus overlay render rather than a filled form, with the
  limitation stated on screen.
- **AC4** Given generation, then the output is written to immutable (WORM) storage with the edition
  hash, the value-set hash, and the approval record id in its metadata.
- **AC5** Given any field exceeds the form's character capacity, then an addendum sheet is generated
  in the agency's expected format and cross-referenced, rather than truncating.

**US-13.03 (13 pts) — Package the evidence**
- **AC1** Given generation, then the package includes: a cover index, the filled forms in the
  agency's stated order, tabbed/labelled evidence exhibits, translation certificates where
  applicable, and a **Filing Checklist** (where to file, fee, edition, wet-ink signature points),
  every element of which is a citation-backed transcription of published instructions.
- **AC2** Given the package, then every page carries a discreet footer identifying the preparing
  organization and its verification status.
  *(Implements [C-10](00-design-authority-record.md#c-10--the-platform-will-attract-bad-faith-administrator-tenants).)*
- **AC3** Given the package, then it contains **no** statement about likelihood of approval,
  eligibility, or strategy, verified by the UPL classifier over the generated text.

---

### E-14 — Export & Delivery

**US-14.02 (13 pts) — Deliver securely**
- **AC1** Given secure delivery, then the recipient receives a link, not an attachment; the link is
  single-recipient, expires in ≤ 7 days, is limited to 5 downloads, and requires a second factor
  (OTP to a separately-entered channel).
- **AC2** Given delivery, then every access is logged with time and IP class and is visible to the
  sender.
- **AC3** Given the sender revokes, then the link dies within 60 seconds.
- **AC4** Given any delivery, then the platform never sends case content as an email attachment or
  in an email body.

---

### E-16 — Data Rights & Retention

**US-16.02 (13 pts) — Delete my documents but keep my answers**
- **AC1** Given a case, then I can delete raw document images independently of extracted values, and
  the UI explains the consequence (values keep their citation record but the image is gone).
- **AC2** Given deletion, then blobs and all versions are removed within 30 days, the audit log
  retains the *fact* of deletion, and no case content is retained in backups beyond the stated
  backup retention.

**US-16.04 (13 pts) — Delete everything**
- **AC1** Given an erasure request, then all personal data is erased within 30 days except a minimal
  legal-hold set (defined in [05 §5.11](05-data-architecture.md#511-retention-and-lifecycle)),
  which is itself enumerated to the user.
- **AC2** Given a tenant with per-tenant CMK, then erasure additionally destroys the tenant DEK,
  rendering residual ciphertext unrecoverable, and a crypto-shred certificate is issued.
- **AC3** Given erasure, then a completion receipt is issued to the user.

---

### E-20 — Responsible AI Guardrails

**US-20.01 (21 pts) — The assistant cannot give legal advice**
- **AC1** Given any generative output, then it passes the Legal Advice Classifier before reaching a
  user, a form, or a document.
- **AC2** Given a block, then a deterministic, warm, non-templated-sounding refusal is shown that
  restates what the assistant *can* do and offers the nonprofit directory.
- **AC3** Given the adversarial UPL corpus (≥ 1,000 prompts across the nine prohibited speech acts,
  in every supported language, including indirection, roleplay, hypothetical, and multi-turn
  escalation), then escapes = 0. This gate **blocks release**.
- **AC4** Given production, then 1 % of assistant turns are sampled for offline classification and
  human spot-check, with a weekly report to Compliance.
- **AC5** Given a document-embedded instruction attempting to elicit advice, then it is neutralized
  and logged.

---

## 2.8 Functional requirements

Abbreviated register; each maps to stories in Appendix A and controls in Appendix B.

### Identity & access (FR-IAM)
| ID | Requirement | Priority |
|---|---|---|
| FR-IAM-001 | Passkey (WebAuthn/platform authenticator) as primary applicant authentication | MUST |
| FR-IAM-002 | Email OTP + TOTP fallback; SMS OTP explicitly **not** offered as a factor | MUST |
| FR-IAM-003 | Entra ID with conditional access, device compliance, and phishing-resistant MFA for all staff and reviewer accounts | MUST |
| FR-IAM-004 | Step-up re-authentication for: package approval, export, delivery, member invitation, role change, erasure, key operations | MUST |
| FR-IAM-005 | RBAC roles: `SystemAdmin`, `TenantAdmin`, `Reviewer`, `Preparer`, `Attorney`, `FolderOwner`, `Participant`, `Helper`, `ReadOnlyAuditor`, `SupportBreakGlass` | MUST |
| FR-IAM-006 | ABAC overlay: tenant, folder, person, section, document class, and case state as policy attributes | MUST |
| FR-IAM-007 | Session binding to device; concurrent-session listing and remote revocation by the user | MUST |
| FR-IAM-008 | Break-glass support access requires dual approval, a stated reason, ≤ 4 h TTL, and generates a user-visible notice | MUST |

### Folder, person, case (FR-CASE)
| ID | Requirement | Priority |
|---|---|---|
| FR-CASE-001 | A folder contains ≥ 1 `Person`; every datum belongs to a person, never to a folder directly | MUST |
| FR-CASE-002 | Relationship graph supports spouse, parent, child, sibling, guardian, sponsor, petitioner, beneficiary, derivative | MUST |
| FR-CASE-003 | Per-person access scoping with Private Annex and Quiet Exit | MUST |
| FR-CASE-004 | A case binds one folder to one form package at one pinned edition set | MUST |
| FR-CASE-005 | Case state machine: `DRAFT → COLLECTING → INTERVIEWING → VALIDATING → IN_REVIEW → APPROVED → GENERATED → DELIVERED → CLOSED`, plus `QUARANTINED_FORM_DRIFT`, `ON_HOLD`, `ABANDONED` | MUST |
| FR-CASE-006 | All state transitions are audited with actor, reason, and prior state | MUST |
| FR-CASE-021 | Progress is reported as explicit mechanical counters, never a single completion percentage | MUST |

### Documents (FR-DOC)
| ID | Requirement | Priority |
|---|---|---|
| FR-DOC-001 | Accept PDF, DOC, DOCX, PNG, JPG/JPEG, HEIC, TIFF; camera; photo library; Files; share sheet | MUST |
| FR-DOC-002 | Offline capture, enhancement, and resumable queued upload | MUST |
| FR-DOC-003 | On-device pre-flight quality gate before upload | MUST |
| FR-DOC-004 | Content type determined by magic bytes; declared type never trusted | MUST |
| FR-DOC-005 | Multi-engine malware scan; macro/JS/embedded-object stripping; archive and page limits | MUST |
| FR-DOC-006 | EXIF/GPS and all location metadata stripped on ingest | MUST |
| FR-DOC-007 | Server-side rasterized previews; client never parses an unsanitized original | MUST |
| FR-DOC-008 | SHA-256 integrity verified client→server; deduplication by content hash within a tenant | MUST |
| FR-DOC-009 | Documents are immutable; corrections create a new version, never mutate | MUST |
| FR-DOC-014 | `SEALED_MEDICAL` class: no OCR, no extraction, no LLM, no preview | MUST |
| FR-DOC-016 | Independent deletion of raw images from extracted values | MUST |

### Extraction (FR-EXT)
| ID | Requirement | Priority |
|---|---|---|
| FR-EXT-001 | Classification into the document taxonomy with human override always available and authoritative | MUST |
| FR-EXT-002 | Every extracted value carries document, page, bounding polygon, engine, engine version, raw confidence, derived band | MUST |
| FR-EXT-003 | Cross-source agreement promotes to `VERIFIED`; conflict creates a `Discrepancy`; the system never silently arbitrates | MUST |
| FR-EXT-004 | Checksum validation for MRZ and other structured identifiers | MUST |
| FR-EXT-005 | Model-generated values are always `NEEDS_REVIEW` | MUST |
| FR-EXT-006 | Name variants preserved with script and transliteration; no heuristic name splitting without confirmation | MUST |
| FR-EXT-007 | Dates normalized to ISO-8601 with the source format and any ambiguity (DD/MM vs MM/DD) recorded and resolved by a human | MUST |
| FR-EXT-008 | Prompt-injection detection on extracted text with security event and review flag | MUST |
| FR-EXT-009 | Re-extraction on engine upgrade is offered, never applied silently over human-confirmed values | SHOULD |

### Forms & packages (FR-FORM)
| ID | Requirement | Priority |
|---|---|---|
| FR-FORM-001 | Form Catalog stores form, edition date, agency, source URL, SHA-256, field map version, encoding | MUST |
| FR-FORM-002 | Daily edition-drift detection with quarantine and guided migration | MUST |
| FR-FORM-003 | Edition pinning at case creation and at generation; both recorded | MUST |
| FR-FORM-004 | Generation fills the agency AcroForm; recreation of form appearance is prohibited | MUST |
| FR-FORM-005 | Round-trip verification of every generated PDF; mismatch fails generation | MUST |
| FR-FORM-006 | Overflow produces a conforming addendum, never truncation | MUST |
| FR-FORM-007 | `XFA`/`FLAT` forms are Assisted-Fill-Only and clearly labelled | MUST |
| FR-FORM-008 | Package includes cover index, ordered forms, labelled exhibits, translation certificates, filing checklist, fee sheet | MUST |

### Compliance & Responsible AI (FR-COMP)
| ID | Requirement | Priority |
|---|---|---|
| FR-COMP-001 | Legal Advice Classifier on every generative egress path | MUST |
| FR-COMP-002 | Nine prohibited speech acts enumerated and individually tested | MUST |
| FR-COMP-003 | Not-a-law-firm disclosure at registration, at case creation, at every interview start, and on every generated package; never suppressible by tenant branding | MUST |
| FR-COMP-004 | No output may state or imply likelihood of approval, eligibility, or strategy | MUST |
| FR-COMP-005 | Human approval required before generation; no non-human principal may approve | MUST |
| FR-COMP-006 | Full AI interaction transcripts retained and exportable by the user and by the supervising attorney | MUST |
| FR-COMP-007 | Nonprofit legal-provider directory presented uniformly, unranked, unpersonalized, no fee | MUST |
| FR-COMP-008 | Tenant KYB with attorney bar / EOIR accreditation verification where legal services are claimed | MUST |
| FR-COMP-009 | Every generated page footers the preparing organization and its verification status | MUST |

### Notifications, audit, data rights
| ID | Requirement | Priority |
|---|---|---|
| FR-NOTIF-001 | Channels: in-app, APNs push, email. **No SMS** for case content | MUST |
| FR-NOTIF-002 | Notification bodies contain **no** case content, no form identifier, and no person name — only "you have an update" plus a deep link | MUST |
| FR-NOTIF-003 | Per-category preferences, quiet hours, digest mode, and a global pause | MUST |
| FR-NOTIF-004 | Quiet Exit generates no notification to any party | MUST |
| FR-AUD-001 | Append-only audit of every read and write of personal data, every AI invocation, every state change, every access grant | MUST |
| FR-AUD-002 | Audit records are tamper-evident (hash-chained) and stored in immutable storage | MUST |
| FR-AUD-003 | Users can view and export their own audit trail in plain language | MUST |
| FR-AUD-004 | AI invocations log: agent, model, model version, prompt template id, input hash, output hash, guardrail verdicts, latency, token counts, cost | MUST |
| FR-DR-001 | Machine-readable export of all personal data within 30 days, self-service where possible | MUST |
| FR-DR-002 | Erasure within 30 days with enumerated legal-hold exceptions and a completion receipt | MUST |
| FR-DR-003 | Consent is granular, versioned, timestamped, and withdrawable per purpose | MUST |

### Search (FR-SRCH) — Phase 2
| ID | Requirement | Priority |
|---|---|---|
| FR-SRCH-001 | Search within a case: documents, values, questions, notes; scoped to entitlement, enforced at the index level not the UI | MUST |
| FR-SRCH-002 | Cross-case search for tenant reviewers, scoped by role and by assignment | MUST |
| FR-SRCH-003 | Full-text over OCR'd content with source highlighting | SHOULD |
| FR-SRCH-004 | Every search query is audited with the actor and the result count | MUST |
| FR-SRCH-005 | Search indexes are per-tenant partitioned; a cross-tenant result is a Sev-1 by definition | MUST |
| FR-SRCH-006 | Search supports diacritic-insensitive and transliteration-aware name matching | SHOULD |

---

## 2.9 Non-functional requirements

### Performance
| ID | Requirement | Target |
|---|---|---|
| NFR-PERF-001 | API p95 latency, read | ≤ 300 ms |
| NFR-PERF-002 | API p95 latency, write | ≤ 600 ms |
| NFR-PERF-003 | App cold start to interactive (iPhone 12) | ≤ 1.8 s |
| NFR-PERF-004 | Capture quality feedback | ≤ 800 ms on-device |
| NFR-PERF-005 | Single-page document → extracted values available | p50 ≤ 12 s, p95 ≤ 45 s |
| NFR-PERF-006 | 40-page PDF → extracted values | p95 ≤ 5 min |
| NFR-PERF-007 | Chat assistant first token | ≤ 1.2 s |
| NFR-PERF-008 | Voice turn latency (speech in → speech out) | ≤ 400 ms p95 |
| NFR-PERF-009 | Package generation (6-form package) | p95 ≤ 90 s |
| NFR-PERF-010 | Reviewer workbench field navigation | ≤ 100 ms |

### Scalability
| ID | Requirement | Target |
|---|---|---|
| NFR-SCALE-001 | Concurrent active cases | 50,000 (P2) |
| NFR-SCALE-002 | Document ingest throughput | 15,000 pages/hour sustained, 60,000 burst |
| NFR-SCALE-003 | Peak-to-mean ratio absorbed without queue growth | 8× for 60 min |
| NFR-SCALE-004 | Tenants | 2,000 (P2) |
| NFR-SCALE-005 | Largest single tenant | 10,000 active cases without noisy-neighbour impact |

### Availability & continuity
| ID | Requirement | Target |
|---|---|---|
| NFR-AVAIL-001 | Core API monthly availability | 99.9 % (P1) → 99.95 % (P2) |
| NFR-AVAIL-002 | RPO | ≤ 5 min (SQL PITR + geo-redundant blob) |
| NFR-AVAIL-003 | RTO | ≤ 4 h (P1) → ≤ 1 h (P2 active-passive) |
| NFR-AVAIL-004 | Degraded mode: AI services unavailable | Capture, manual entry, review, and generation of already-confirmed values all continue |
| NFR-AVAIL-005 | Degraded mode: document AI unavailable | Upload queues and drains; user is told plainly |
| NFR-AVAIL-006 | Offline client capability | Capture, enhance, manual entry, review cached content |

### Security *(full detail in [06](06-security-architecture.md))*
| ID | Requirement |
|---|---|
| NFR-SEC-001 | TLS 1.3 minimum in transit; certificate pinning in the client with a documented rotation plan |
| NFR-SEC-002 | AES-256 at rest; customer-managed keys on every store holding personal data |
| NFR-SEC-003 | Zero standing credentials; managed identity for all service-to-service auth |
| NFR-SEC-004 | Private endpoints for every PaaS data service; no public data-plane exposure |
| NFR-SEC-005 | Annual third-party penetration test plus continuous automated testing; all highs closed before release |
| NFR-SEC-006 | Client stores case data under `NSFileProtectionComplete`; keys in Secure Enclave; jailbreak/root signal degrades to no-local-cache |
| NFR-SEC-007 | Screenshot/screen-recording deterrence on document viewers; no case content in the app switcher snapshot |
| NFR-SEC-008 | No third-party analytics, ads, attribution, or crash SDKs in the client, enforced by SBOM gate and egress test |

### Privacy & compliance
| ID | Requirement |
|---|---|
| NFR-PRIV-001 | Privacy by design and by default; data minimization is an architectural constraint, verified at design review |
| NFR-PRIV-002 | Data residency: US data stays in US regions; EU data in EU regions; no cross-geo AI routing |
| NFR-PRIV-003 | GDPR, CCPA/CPRA, and state privacy law rights implemented as product features, not manual processes |
| NFR-PRIV-004 | DPIA completed and maintained; re-run on every material scope change |
| NFR-PRIV-005 | Sub-processor register published; DPAs in place with every sub-processor |
| NFR-PRIV-006 | Published government-request policy and semi-annual transparency report |

### Accessibility
| ID | Requirement |
|---|---|
| NFR-A11Y-001 | WCAG 2.2 Level AA across all surfaces; Section 508 conformance documented in an ACR |
| NFR-A11Y-002 | Full VoiceOver support with correct labels, traits, hints, and reading order; verified by manual audit each release |
| NFR-A11Y-003 | Dynamic Type through accessibility sizes with no truncation or overlap; snapshot-tested at XXXL |
| NFR-A11Y-004 | Contrast ≥ 4.5:1 text, ≥ 3:1 non-text; never color alone to convey meaning |
| NFR-A11Y-005 | Full keyboard operability (macOS/iPadOS); visible focus; logical order; no traps |
| NFR-A11Y-006 | Voice Control and Switch Control verified on primary flows |
| NFR-A11Y-007 | Reduce Motion, Increase Contrast, Reduce Transparency, Bold Text honored |
| NFR-A11Y-008 | AI text ≤ 6th-grade reading level (measured in CI); Plain Language mode ≤ 4th grade |
| NFR-A11Y-009 | No time limits on any interview or form interaction |
| NFR-A11Y-010 | Non-visual document capture path with audio framing guidance |
| NFR-A11Y-011 | Captions/transcript for every audio interaction, live |
| NFR-A11Y-012 | Accessibility acceptance criteria on every story; `A11Y-GATE` blocks the build |

### Localization
| ID | Requirement |
|---|---|
| NFR-I18N-001 | MVP UI languages: English, Spanish. P2: + Haitian Creole, Simplified Chinese, Vietnamese, Tagalog, Arabic, Portuguese, Russian, French |
| NFR-I18N-002 | Interview languages exceed UI languages via translation, always labelled machine-assisted |
| NFR-I18N-003 | Full RTL layout support (Arabic) including document viewer chrome |
| NFR-I18N-004 | Unicode throughout; correct rendering and input of CJK, Arabic, Cyrillic, Devanagari |
| NFR-I18N-005 | Locale-correct dates, numbers, names, and address formats; form output always in the agency's required format |
| NFR-I18N-006 | Curated legal-glossary translations pinned; never free-translated |

### Cost
| ID | Requirement | Target |
|---|---|---|
| NFR-COST-001 | Per-case AI cost telemetry from Day 1, attributable to agent, model, and tenant | Mandatory |
| NFR-COST-002 | Blended AI cost per completed case | ≤ $11 (P1) → ≤ $6 (P2) |
| NFR-COST-003 | Per-case and per-tenant voice-minute budget with soft warning and hard stop | Mandatory |
| NFR-COST-004 | Model-tier cascade routing with per-turn logging of the tier chosen and why | Mandatory |
| NFR-COST-005 | Prompt caching for the stable system/instruction prefix | ≥ 60 % cache hit rate |

---

## 2.10 Accessibility requirements

Consolidated in NFR-A11Y-001…012 above, plus these product-level commitments arising from
[C-12](00-design-authority-record.md#c-12--accessibility-cannot-be-a-phase-2-item-for-this-population):

1. **Accessibility is a Definition-of-Done item on every story.** A story without accessibility
   acceptance criteria is not ready for development.
2. **The AI interface is the hardest accessibility problem in the product** and gets specific
   treatment: block-level announcement, no token streaming to assistive tech, a persistent
   "what is happening" status region, and a hard rule that no interaction has a time limit.
3. **Plain Language mode** is a first-class user setting, not a fallback, and changes AI system
   instructions, UI copy, and question phrasing together.
4. **Cognitive accessibility**: one primary decision per screen, no unexplained jargon, every agency
   term glossed on first use, progress always resumable, and no destructive action without a
   two-step confirmation that states the consequence in plain terms.
5. **An ACR/VPAT is a release artifact** from MVP, published, and updated each release.
6. **Testing includes disabled users**, not only automated checks: a paid panel of VoiceOver,
   Switch Control, and low-vision users tests each release candidate.

---

## 2.11 Analytics requirements

Constrained by [C-19](00-design-authority-record.md#c-19--analytics-on-this-data-is-a-liability-not-an-asset).

| ID | Requirement |
|---|---|
| AN-001 | First-party telemetry only, to our own endpoint, over the authenticated channel. No third-party SDK of any kind |
| AN-002 | Analytics consent is separate from service consent and **defaults to off**; the product must be fully functional without it |
| AN-003 | Events carry no case content, no form identifier, no person name, no free text. Form identity is bucketed to a coarse `package_family` |
| AN-004 | Analytics user identifiers are per-install, rotating, and unlinkable to the account without a re-identification key held under CDO control and used only with a logged, approved reason |
| AN-005 | No metric is exposed in any dashboard below k-anonymity of 25 |
| AN-006 | IP addresses truncated (/24, /48) and never retained beyond 7 days |
| AN-007 | Event schema is reviewed by the Privacy Officer before any new event ships; unreviewed events are dropped at the collector |
| AN-008 | Retention: raw events 90 days, aggregates 25 months |
| AN-009 | Instrumented: funnel stage transitions, capture retry rate and reason, extraction accept/edit/reject rate by band, interview modality and completion, missing-item resolution latency, review throughput, error and crash class, AI cost and latency by agent |
| AN-010 | Explicitly **not** instrumented: anything that reveals which benefit a user is seeking, any document content, any answer text, any location |

---

## 2.12 Reporting requirements

| ID | Audience | Report | Notes |
|---|---|---|---|
| RPT-001 | Applicant | My Case Report — status, what's missing, what's been done, who accessed my data | Plain language, exportable PDF |
| RPT-002 | Applicant | My Data Report — everything held about me, in machine-readable and human-readable form | Satisfies DSAR self-service |
| RPT-003 | Reviewer | Queue metrics — cases by state, ageing, blocked reasons, personal throughput | |
| RPT-004 | Tenant Admin | Operational — volume, cycle time by stage, first-pass yield, reviewer utilization, extraction accept rate | |
| RPT-005 | Tenant Admin | Compliance — approvals with attester, edition versions used, consent status, access grants, break-glass events | Immutable source |
| RPT-006 | Program Director | Funder report — cases served, throughput, languages served, aggregate demographics | k ≥ 25; no per-case rows |
| RPT-007 | Compliance Officer | UPL surveillance — deflections, classifier blocks, sampled-turn review results | Weekly |
| RPT-008 | Chief AI Officer | Model performance — extraction accuracy by document type and language, calibration curve and ECE, reviewer edit rate by band, drift indicators | Monthly |
| RPT-009 | CISO | Security posture — auth anomalies, break-glass, DLP, injection detections, vulnerability SLA | Weekly |
| RPT-010 | CFO / CPO | Unit economics — AI cost per case by agent and model, per tenant, margin by plan | Weekly |
| RPT-011 | Public | Transparency report — government requests received, complied with, challenged | Semi-annual |

All reports honor entitlement at the query layer; no report bypasses row-level security. Scheduled
report delivery uses secure links, never attachments.

---

## 2.13 Notification requirements

| ID | Requirement |
|---|---|
| NT-001 | Channels: in-app inbox, APNs push, email. SMS is **not** used for case content or links |
| NT-002 | Push and email bodies contain no case content, no person name, no form identifier — "You have an update in Aperture" plus a deep link |
| NT-003 | Categories: action required · document processed · discrepancy found · review status · package ready · security · form edition change · system |
| NT-004 | Per-category channel preferences, quiet hours, daily/weekly digest, and a global pause |
| NT-005 | Every notification is deep-linked to the exact item requiring action |
| NT-006 | Batching and de-duplication: no more than one push per category per hour; batch document-processed events |
| NT-007 | Security notifications (new device, recovery, role change, break-glass) are non-suppressible |
| NT-008 | Quiet Exit and Private Annex operations generate **no** notification to other members |
| NT-009 | Notification delivery, open, and action are audited |
| NT-010 | Emails are DMARC/DKIM/SPF-aligned, contain no tracking pixels, and are sent from a dedicated subdomain |
| NT-011 | Full localization including RTL, and respect for the user's chosen language over the device language |

---

## 2.14 Search requirements

See FR-SRCH-001…006 (§2.8). Additional constraints:

- Search is **Phase 2**; MVP provides within-case filtering only.
- The index is partitioned per tenant; entitlement filters are applied as index filters, not as
  post-query pruning. A cross-tenant leak in search is a Sev-1 by definition.
- Private Annex content is indexed in a separate per-person index that no other principal can query.
- `SEALED_MEDICAL` content is never indexed.
- Search over OCR text returns highlighted source regions.
- Query strings are audited but **hashed**, not stored in plaintext, to avoid creating a searchable
  record of what a user was looking for.

---

## 2.15 Audit requirements

See FR-AUD-001…004 (§2.8). Additionally:

- **What is audited:** authentication and authorization decisions (including denials), every read
  and write of personal data, every AI invocation with its full metadata, every state transition,
  every consent event, every access grant/revocation, every export and delivery, every break-glass
  session, every administrative action, every key operation.
- **Structure:** `(event_id, occurred_at, actor_id, actor_type, on_behalf_of, tenant_id, folder_id,
  person_id, subject_type, subject_id, action, outcome, reason, before_hash, after_hash, source_ip_class,
  device_id, correlation_id, prev_event_hash, event_hash)`.
- **Integrity:** hash-chained per tenant, periodically anchored; written to append-blob storage with
  an immutability policy. No principal — including `SystemAdmin` — can delete or modify an audit
  record.
- **Retention:** 7 years for audit metadata. Audit records contain **no case content**, only
  identifiers and hashes, so audit retention does not defeat data-deletion rights.
- **Access:** users see their own trail in plain language; tenant admins see their tenant's;
  auditors have a read-only role; every audit *read* is itself audited.

---

## 2.16 Data retention requirements

Full lifecycle in [05 §5.11](05-data-architecture.md#511-retention-and-lifecycle). Product-level:

| Data | Default | User control | Hard maximum |
|---|---|---|---|
| Raw document images | 90 days after case close | Delete anytime; extend to 1 yr | 2 years |
| Extracted values | Case retention | Delete with case | 2 years |
| Generated packages | 1 year after generation | Download and delete anytime | 2 years |
| Chat transcripts | 90 days after case close | Delete anytime | 1 year |
| Voice audio | **Discarded at session end** | Opt-in 30-day retention | 30 days |
| Voice transcripts | Same as chat | Delete anytime | 1 year |
| Agent execution traces | 90 days | — | 90 days |
| Consent records | 7 years | — | 7 years |
| Audit metadata | 7 years | — | 7 years |
| Analytics raw | 90 days | Opt out entirely | 90 days |
| Security logs | 1 year | — | 1 year |
| Backups | 35 days PITR + 12 monthly LTR | — | 12 months |

Deletion is honored in backups by policy (backups expire) and by crypto-shred where per-tenant keys
are in use. Users are told this plainly rather than being promised instantaneous backup erasure.

---

## 2.17 Scope by phase

### MVP (Phase 1) — E-01…E-20
Five form packages · EN/ES UI · EN/ES voice · chat in 8 interview languages via translation ·
iPhone/iPad applicant + Mac reviewer · manual tenant onboarding · export and secure delivery ·
full audit, consent, and data rights · SOC 2 Type I · published ACR.

### Phase 2 — E-21…E-24 plus depth
15 form packages · 10 UI languages · voice in 6 · self-serve tenants with automated KYB · search ·
reporting and analytics · RFE and amendment support · multi-region active-passive · Apple Watch
reminders · Shortcuts/Siri intents for status · SOC 2 Type II · penetration test published to
customers under NDA.

### Phase 3 — E-25…E-26 plus platform
Sensitive matters behind gate **G3-A** ([C-04](00-design-authority-record.md#c-04--asylum-and-removal-defense-cases-must-be-out-of-scope-for-v1)) ·
per-case CMK and crypto-shred · partner API and webhooks for case-management integration ·
additional agencies (state benefits, DOL, SSA) · Android and web clients evaluated ·
on-device extraction for the highest-sensitivity classes ([13](13-v2-recommendations.md)).

---

## 2.18 Future roadmap themes

1. **Evidence sufficiency without advice** — helping a user see that they have *fewer* documents of
   a type the instructions list, without characterizing whether their evidence is persuasive.
2. **Renewal and lifecycle** — most immigration journeys are multi-step; a case that knows a
   green card expires in 2029 can remind, with consent, without predicting.
3. **Community-organization tooling** — clinic-day workflows, volunteer supervision, offline-first
   group intake.
4. **On-device extraction** — Apple silicon is fast enough to make "your passport never left your
   phone" a real claim for the highest-sensitivity documents. See [13 §13.3](13-v2-recommendations.md).
5. **Verifiable provenance** — signed, verifiable claims about what was extracted from what,
   so a downstream reviewer can verify without trusting us.
6. **Multi-jurisdiction** — Canada (IRCC) and UK (Home Office) have similar structural problems and
   materially different regulatory boundaries.

---

## 2.19 Success metrics

See [01 §1.9](01-executive-summary.md#19-success-metrics). Restating the two that are gates rather
than targets:

- **Zero UPL classifier escapes** on the adversarial corpus. Blocks release.
- **Zero Sev-1 privacy incidents.** Any occurrence triggers a full stop-and-review with the CISO and
  Privacy Officer before further release.

---

## 2.20 Assumptions, dependencies and constraints

**Assumptions**
- A1 — Target users own an iPhone running iOS 18 or later. *(Validated at ~78 % of the surveyed
  population; the ~22 % gap is the strongest argument for the Android client in Phase 3 and is
  tracked as RISK-016.)*
- A2 — Agency forms and instructions remain publicly retrievable and their terms permit programmatic
  retrieval for this purpose. *(RISK-017; a manual-curation fallback exists.)*
- A3 — Modified abuse monitoring is approvable for our use case. *(If not, the PII minimization
  proxy plus CISO-accepted risk is the fallback — see [C-23](00-design-authority-record.md#c-23--third-party-ai-processing-needs-explicit-contractual-and-configuration-posture).)*
- A4 — Partner organizations will provide the human review capacity for the beta cohort.

**Dependencies**
- D1 — Azure OpenAI capacity and Limited Access approvals.
- D2 — Realtime voice model regional availability (East US 2 / Sweden Central) versus our data
  residency commitments — this is a genuine tension, tracked as RISK-021 and resolved by pinning
  voice to a US region for US users and disabling voice for EU users until EU realtime availability
  exists.
- D3 — Apple Developer Program, App Review, and Push/APNs.
- D4 — Outside counsel per-jurisdiction UPL opinions before any state-specific marketing.

**Constraints**
- C1 — No legal advice. Absolute.
- C2 — No automated filing. Absolute.
- C3 — No automated approval. Absolute.
- C4 — Apple platforms only through Phase 2.
- C5 — US data residency for US users; EU for EU users; no cross-geo AI inference.
