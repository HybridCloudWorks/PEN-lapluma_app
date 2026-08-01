# Appendix C — Glossary and Controlled Vocabulary

Terms are binding. Where a word is used in this deliverable, it carries the meaning defined here and
no other. Several entries exist specifically to prevent a word from drifting back to its colloquial
meaning under delivery pressure.

---

## C.1 Product and domain terms

| Term | Definition |
|---|---|
| **Aperture** | The platform described in this deliverable. Codename; not a committed brand. |
| **Applicant** | The person a form package is about. May or may not hold an account. |
| **Assisted Fill Only** | The handling mode for forms whose encoding (`XFA`, `FLAT`) prevents programmatic filling. Produces a data sheet and an overlay render for human transcription. Never described to a user as a filled form. |
| **Case** | One Folder bound to one form package at one pinned edition set. Has a state machine. |
| **Confidence band** | One of `VERIFIED`, `EXTRACTED`, `NEEDS_REVIEW`. Derived from measurable signals, never from a model's self-report. Never displayed to an applicant as a percentage. |
| **Discrepancy** | A recorded conflict between two sources for the same logical value. Always resolved by a human; the system never arbitrates. |
| **Edition date** | The date printed on an agency form identifying its version. The unit of pinning and drift detection. |
| **Extraction Ledger** | The authoritative store of field values with provenance, state, and discrepancies. The only source a generated PDF may read from. |
| **Field map** | The versioned, two-person-approved binding from canonical fields to a specific form edition's PDF field names. |
| **Filing Checklist** | The generated artifact stating where to file, the fee, the edition, and the wet-ink signature points — every element a cited transcription of published agency instructions. |
| **Folder** | The Virtual Applicant Folder. A container for Persons, Documents, and Cases. Holds no personal data itself. |
| **Form package** | A named set of forms filed together (e.g. `FAMILY_I130` = I-130 + I-130A). Selected by a human, never by the platform. |
| **Helper** | A person granted scoped access to assist an applicant, with recorded consent and answer attribution. |
| **Missing Item** | An actionable gap, assigned to exactly one Person, with a citation and a resolution path. |
| **Package** | The generated output: filled forms, addenda, cover index, exhibits, checklist, fee sheet. Written to WORM storage. |
| **Person** | A human a case is about. **The unit of privacy.** All personal data hangs off a Person, never off a Folder. |
| **Private Annex** | Per-person storage that the folder owner cannot enumerate — not merely cannot read, cannot see the existence of. |
| **Provenance** | The inseparable record of where a value came from: document, page, bounding polygon, engine, engine version, raw confidence — or the human who typed it. |
| **Quiet Exit** | An adult participant's ability to sever participation and erase their private annex, generating **zero notifications to any other member**. |
| **Ready to File** | The state in which every required field has a confirmed value and every required document is attached. **Not a prediction of any agency decision** — a statement that must accompany the term wherever it appears. |
| **Round-trip verification** | Re-parsing a generated PDF, re-extracting every field, and asserting equality with the source record. Any mismatch fails generation. |
| **Scrivener** | What this platform is. It transcribes and organizes information onto a form someone else chose. It does not select, assess, predict, or advise. |
| **Selection attestation** | The user's recorded confirmation that they (or their representative) chose the form package. Required before a case can exist. |
| **Sealed medical** | Document class `SEALED_MEDICAL`. Stored as an opaque encrypted blob; never OCR'd, never processed by a model, never previewed, never indexed. |

---

## C.2 Words we do not use, and why

Enforced by a copy lint rule in CI over all applicant-facing text
([08 §8.8](../08-ux-design.md#88-design-system)).

| Prohibited | Reason | Say instead |
|---|---|---|
| *approved*, *denied* (of an application) | Implies we know or can influence an outcome | "your package is ready to file" |
| *qualify*, *eligible* | Eligibility assessment — prohibited speech act #1 | "this form asks for…" |
| *guaranteed*, *likely*, *chances* | Outcome prediction — prohibited speech act #2 | Nothing. Decline. |
| *you should file*, *your best option* | Strategy recommendation — act #3 | "I can't advise on that." |
| *strong case*, *weak evidence*, *enough proof* | Evidence sufficiency — act #7 | "the instructions list six kinds of evidence; you've attached two" |
| *your immigration assistant*, *we'll help you win* | Implies a professional relationship — act #9 | "a form-preparation tool" |
| *% complete* | Reads as a prediction of approval | "174 of 218 form fields filled" |
| *submit*, *file for you*, *we'll send it* | We do not file. [ADR-002](../adr/ADR-002-no-efiling.md) | "ready to file" / "you file this yourself" |
| *verified identity* | We do not verify identity against any authority | "these documents agree with each other" |
| *certified translation* (of our output) | Machine translation is not certified | "machine-assisted translation" |
| *confidence: 94 %* | Manufactures false precision | "Checked" / "From a document" / "Needs you" |

---

## C.3 AI and agent terms

| Term | Definition |
|---|---|
| **Agent** | One of the 23 named roles. **Not necessarily an LLM** — 8 of 23 are ordinary deterministic code. |
| **Agentic (tier A)** | Multi-turn, tool-using, may loop within a budget. Only three components qualify: Executive Orchestrator, Voice Interview, Chat Interview. |
| **Capability boundary** | The rule that an agent may never hold untrusted content in context *and* possess a state-changing tool. Enforced by the runtime tool registry, not by prompts. |
| **Content trust level** | `U0` hostile · `U1` semi-trusted · `U2` curated · `U3` system. Inversely constrains capability. |
| **Deterministic (tier D)** | Ordinary code. No model call. |
| **Groundedness** | Whether a factual assertion traces to a citation or a ledger value. Ungrounded requirement claims block. |
| **Guardrail (tier G)** | A component that runs on another's egress path and can only allow, block, or annotate. |
| **Legal Advice Classifier** | The three-stage classifier enforcing the nine prohibited speech acts on every generative egress path. Fail-closed. |
| **Model-invoking (tier M)** | A single bounded, schema-constrained model call. No tools, no autonomy, no looping. |
| **Nine prohibited speech acts** | The enumerated categories the Legal Advice Classifier blocks ([09 §9.3](../09-responsible-ai.md#93-the-legal-advice-classifier)). |
| **PII Minimization Proxy** | Tokenizes direct identifiers before a model call and rehydrates after. Applied by default; disabled per-agent only with written justification. |
| **Prompt registry** | The versioned, hashed store of prompt templates. No inline prompt strings exist in application code. |
| **Source anchor** | The page and bounding polygon locating an extracted value in its source document. A value without one is not a value. |
| **UPL deflection** | A logged instance of the assistant declining a request that would constitute legal advice. Counted as a demand signal, never as a problem to solve by relaxing the boundary. |

---

## C.4 Security and privacy terms

| Term | Definition |
|---|---|
| **ABAC** | Attribute-based access control. Overlays RBAC with tenant, folder, person, section, class, and state attributes. |
| **Break-glass** | Time-boxed emergency access requiring dual approval, a stated reason, and a **user-visible notice**. |
| **Crypto-shred** | Rendering data unrecoverable by destroying its key. The only mechanism that makes a deletion promise true in the presence of backups. |
| **Data plane** | `US` or `EU`. A residency boundary. Data never crosses one, including during a regional outage. |
| **Lawful process (TA-1)** | The top-of-register threat: a valid legal demand for applicant data. Mitigated architecturally, never eliminated. |
| **Processing zone** | The isolated Container Apps environment that parses untrusted content. No internet egress, no database route, ephemeral non-root workers. |
| **Step-up authentication** | Re-authentication bound to a specific purpose and resource, valid ≤ 5 minutes. |
| **Trust zone** | `Z1` client · `Z2` core (privileged, never parses untrusted content) · `Z3` processing (hostile input, zero privilege) · `Z4` AI (no write authority). |
| **WORM** | Write-once-read-many. Immutability policy applied to generated packages and audit storage. |

---

## C.5 Immigration and agency terms

Included because engineers and designers will encounter them and guessing at their meaning produces
defects.

| Term | Definition |
|---|---|
| **A-Number** | Alien Registration Number. A `CRITICAL`-sensitivity identifier; Always Encrypted. |
| **Accredited representative** | A non-attorney authorized under 8 C.F.R. part 1292 subpart B to represent people before immigration authorities, through a recognized organization. **This status does not extend to software vendors.** |
| **Adjustment of status** | The process of applying for permanent residence from within the United States. A term of art; pinned in the translation glossary, never free-translated. |
| **Beneficiary** | The person for whom a petition is filed. May have interests adverse to the petitioner — the basis of [ADR-007](../adr/ADR-007-household-trust-boundaries.md). |
| **CEAC** | The Department of State's Consular Electronic Application Center. Interactive-only; no third-party API. |
| **Derivative** | A family member who may obtain a benefit through a principal applicant. |
| **EOIR** | Executive Office for Immigration Review. Recognizes organizations and accredits representatives. |
| **G-28** | The form by which an attorney or accredited representative enters an appearance. Signed by a licensed human, never by us. |
| **I-693** | Report of Immigration Medical Examination. Delivered **sealed**; opening it invalidates it. Document class `SEALED_MEDICAL`. |
| **Interpreter certification** | The block on a form in which a **named human** certifies fluency in both languages and that they read the form to the applicant. Machine translation can never populate it. |
| **MRZ** | Machine Readable Zone on a passport. Carries check digits, which is why passport extractions can reach `VERIFIED` deterministically. |
| **myUSCIS** | The USCIS online account system. Human-interactive; not machine-accessible to vendors. |
| **Notario fraud** | The exploitation of applicants by unlicensed intermediaries presenting themselves as legal professionals. The harm this product exists to reduce, and the failure mode it must never become. |
| **Petitioner** | The person filing on behalf of a beneficiary. Frequently holds practical leverage over them. |
| **Preparer block** | The section of a form identifying who prepared it. Populated with the human preparer or "self-prepared", never with the platform as an advisor. |
| **RFE** | Request for Evidence. An agency request for more information. The moment applicants are most frightened and most vulnerable to bad actors — which is why the Phase 2 RFE feature carries the strictest guardrail profile in the product. |
| **UPL** | Unauthorized practice of law. Engineered here as a security control, not merely a compliance topic ([06 §6.8](../06-security-architecture.md#68-the-upl-firewall-as-a-security-control)). |

---

## C.6 Status and state vocabularies

**Case state:** `DRAFT` · `COLLECTING` · `INTERVIEWING` · `VALIDATING` · `IN_REVIEW` · `APPROVED` ·
`GENERATED` · `DELIVERED` · `CLOSED` · `QUARANTINED_FORM_DRIFT` · `ON_HOLD` · `ABANDONED`

**Value state:** `PROPOSED` · `HUMAN_CONFIRMED` · `REJECTED` · `SUPERSEDED`

**Document processing state:** `UPLOADED` · `SCANNING` · `QUARANTINED` · `SANITIZED` ·
`CLASSIFYING` · `NEEDS_CLASSIFICATION` · `EXTRACTING` · `EXTRACTED` · `EXTRACTION_FAILED` ·
`OPAQUE_STORED` · `DELETED`

**Form version status:** `DRAFT` · `CURRENT` · `SUPERSEDED` · `WITHDRAWN`

**Tenant verification status:** `UNVERIFIED` · `PENDING` · `VERIFIED` · `REVOKED`

**Incident severity:** `Sev-1` (confirmed personal-data exposure, UPL escape in production, audit
chain break, AI reaching approval) · `Sev-2` (control failure without confirmed exposure; integrity
failure) · `Sev-3` (degraded control) · `Sev-4` (informational)

---

## C.7 Document abbreviations used in this deliverable

| Abbrev | Meaning |
|---|---|
| ACR / VPAT | Accessibility Conformance Report / Voluntary Product Accessibility Template |
| ADR | Architecture Decision Record |
| ARB / SRB | Architecture Review Board / Security Review Board |
| CMK / DEK | Customer-Managed Key / Data Encryption Key |
| DPIA / PIA | Data Protection Impact Assessment / Privacy Impact Assessment |
| ECE | Expected Calibration Error |
| KYB | Know Your Business |
| PDP | Policy Decision Point |
| PTU | Provisioned Throughput Unit |
| RLS | Row-Level Security |
| RPO / RTO | Recovery Point Objective / Recovery Time Objective |
| SBOM | Software Bill of Materials |
| SLO / SLI | Service Level Objective / Indicator |
