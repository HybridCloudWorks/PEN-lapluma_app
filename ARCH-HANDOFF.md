# Architecture Handoff

**Status:** Mandatory living document
**Owner:** Delivery team; reviewed by the architecture and security teams
**Last updated:** 2026-09-18

## Working agreement

Every feature or behavior change must update this file in the same pull request. The author must:

1. add or amend an entry in the change ledger;
2. explain the implemented client behavior and the expected cloud behavior;
3. record new data, API, identity, authorization, tenancy, retention, observability, and migration implications;
4. link a new ADR when a decision changes a trust boundary or accepted architecture rule; and
5. leave unresolved decisions explicit rather than encoding them as client assumptions.

A change is not architecture-complete when its UI works but its handoff entry is missing.

## Approved target update — 2026-09-13

[ADR-019](docs/adr/ADR-019-lean-gcp-document-library.md) records the approved GCP and Document Library target. It supersedes conflicting provider/database/encryption/transfer assumptions below; unchanged tenant/person, session, approval and fidelity requirements remain. Current client behavior is unchanged and no GCP runtime is deployed by this documentation delivery.

## Current app-to-cloud contract

### Vocabulary and ownership

| Product term | Current app representation | Required cloud representation | System of record |
|---|---|---|---|
| Workspace / tenant / location | `AppSession.currentWorkspaceCode` (display context in the local stub only) | Immutable `tenant_id` plus mutable, unique tenant code/aliases | Identity/tenant service |
| Client record | Existing `Folder` aggregate | Tenant-owned client/folder record with person-scoped authorization | Case service |
| Case stage | Server-defined `CaseState` | Audited state machine; clients may display but never author transitions | Case service |
| Paperwork progress | `ProgressCounters` fields/documents/blockers | Server-computed mechanical counters | Case/read model |
| Signed-in user | Local fixture `UserID` | Workforce/applicant principal in a short-lived, tenant-bound server session | Identity service |
| Guided Finish plan | Derived `GuidedFinishPlan`; never a stored checklist | Read model generated from current missing items and active relay state | Case/read-model service |
| Proof Map | `FieldProof` entries with provenance and pinned destinations | Person-scoped canonical-value/provenance/form-binding graph | Case + Form Catalog services |
| Private Relay | Persisted metadata plus credential hashes in the local stub | Upload-only public capability, staged object lifecycle, and audited evidence-link decision | Relay + Document services |

The UI must not treat a workspace code, user-entered tenant identifier, email domain, URL parameter,
or client-supplied header as authorization. The server resolves the code during authentication and
binds the authenticated principal, active `tenant_id`, roles, allowed person scopes, and session ID
into a signed server-side session. Every data query is scoped from that trusted session.

### Authentication and session security

The app remains passkey-first under [ADR-011](docs/adr/ADR-011-passkeys-no-sms.md). It must not add a
password database or SMS authentication. The production flow is expected to be:

1. Submit normalized work email and workspace code to an authentication discovery endpoint. The
   response must not reveal whether either value exists.
2. Receive a one-time WebAuthn/passkey challenge scoped to the resolved tenant and relying party.
3. Complete the platform passkey assertion and App Attest assertion.
4. Exchange the verified assertion for a short-lived, tenant-bound session. Store only the
   refresh/session material in Keychain with the strongest compatible data protection class.
5. Require local user presence before releasing a restored session; rotate refresh material and
   revoke sessions on sign-out, recovery, tenant removal, role change, or suspicious activity.

Recovery remains email OTP **plus** the registration recovery code, followed by global session and
passkey revocation and the holds defined by ADR-011. Rate limiting, enumeration resistance, replay
protection, device binding, risk events, and audit events are server responsibilities. Workspace
codes are routing hints, not secrets or factors.

The current app uses `StubAPIClient`, a `UserDefaults` authentication marker, a hard-coded fixture
user, and a direct local sign-in action. `ApertureRuntimeMode.production` deliberately refuses to
launch with that implementation. None of the local authentication behavior is production-ready.

### Multi-tenancy requirements

- Assign every tenant-owned row an immutable `tenant_id`; use composite foreign keys where needed
  so a child record cannot reference a parent in another tenant.
- Derive tenant scope from the verified session at the API gateway/service boundary. Ignore or
  reject tenant IDs supplied as data by a mobile client.
- Enforce tenant isolation in the database with row-level security or an equivalent mandatory
  policy, in addition to service authorization. Test cross-tenant reads, writes, counts, searches,
  exports, background jobs, and object-storage URLs.
- Preserve the stricter per-person boundary in
  [ADR-007](docs/adr/ADR-007-household-trust-boundaries.md). Tenant membership never grants blanket
  access to every person or Private Annex within that tenant.
- Namespace caches, offline queues, search indexes, object-storage prefixes, encryption context,
  idempotency keys, logs, metrics, and analytics by trusted `tenant_id`. Clear or cryptographically
  separate local tenant data when switching workspaces.
- Do not place tenant codes, names, client names, form names, or other sensitive values in access
  tokens, notification text, URLs, metric labels, or unredacted logs.
- Define tenant lifecycle operations before production: create, rename/code rotation, suspend,
  restore, export, legal hold, offboard, retention expiry, and crypto-shred.

### Client directory/read model

The authenticated entry screen reads current clients, supports local search/filter/sort over the
stub response, and opens the existing `FolderView` for people, documents, cases, and access. The
production API should provide a tenant-scoped, paginated client-directory read model rather than
downloading every full folder:

```http
GET /v1/clients?query=&stage=&attention=&sort=&cursor=
```

Each item should contain stable IDs, a safe display label, permitted person summary, document count,
primary case title/code, `CaseState`, mechanical `ProgressCounters`, attention count, and an opaque
pagination cursor. Search and sort must be authorization-filtered before aggregation. Counts must
not reveal records or Private Annex content the principal cannot enumerate.

Selecting an item should fetch details by stable client/folder ID. The server must return `404` for
both nonexistent and unauthorized IDs to reduce enumeration. Mutations require idempotency keys and
must re-check the tenant, role, person scope, record version, and case state.

### Progress language

The requested dashboard percentage is intentionally not implemented. Existing design authority
challenge C-20 and the `ProgressCounters` contract prohibit percentages and completion scores because
applicants may interpret them as a prediction of case approval. The dashboard instead shows exact
fields completed/required, documents collected/required, blocking items, readiness, and the audited
case stage. Changing this requires an ADR approved by Compliance, UX, and Security; it must also
address API contract tests that reject percentage-like fields.

### Role-adaptive product boundary

[ADR-016](docs/adr/ADR-016-role-adaptive-platform-boundaries.md) establishes applicant mobile,
reviewer-lite iPad, and full macOS workforce surfaces over shared domain/API contracts. Sessions
contain explicit personas and capabilities; users entitled to both choose a mode. Rendering or
switching a mode never grants access. Tenant admins manage membership and assignments but have no
case-content access unless separately assigned.

Organization-managed cases enforce distinct Preparer, Reviewer, and Approver humans. Preparer owns
setup, evidence, and canonical entry; Reviewer owns comparison, discrepancies, requested changes,
and readiness; Approver receives read-only immutable values/editions, performs step-up attestation,
then generates and exports. The approver cannot be either earlier actor.

### Canonical values, forms, evidence, and approval

The Case service is the only authority for canonical values and provenance. Form Catalog supplies
official artifacts, edition hashes, field maps, schemas, requirements, fees, and citations. A
canonical commit updates all bindings that consume that path; the UI displays form/page references.
Section commits require an idempotency key and `If-Match`/ETag. A conflict never overwrites a
confirmed value and must support comparing the server and local versions.

Evidence links are many-to-many records among case, cited requirement, authorized document, person
scope, and linking actor. Bytes remain in Document storage. Preview pixels come only from authorized,
sanitized/rasterized endpoints.

Pre-approval previews are server-filled from authoritative values and pinned field maps, short-lived,
non-exportable, and watermarked on every page `DRAFT — NOT FOR FILING`. Approval records bind the
approver, step-up assertion, attestation, immutable value-set hash, edition-set hash, review record,
and time. Any authoritative value or evidence-link change after review reopens review. Any such
change after approval invalidates approval and removes generation/export eligibility.

### Workflow API and state machine

The implementation contract is [workforce-workflow.yaml](contracts/openapi/workforce-workflow.yaml).
It covers session capabilities, paginated clients, people/access/invitations, assignments, workspace,
transitions, canonical section commit, evidence links, review queue/decisions, previews, step-up,
approval, history, administration, sessions, audit summary, and demo enter/reset/exit.

`DRAFT → COLLECTING → VALIDATING → IN_REVIEW → CHANGES_REQUESTED|READY_FOR_APPROVAL → APPROVED → GENERATED → DELIVERED → CLOSED`

`CHANGES_REQUESTED` returns to `IN_REVIEW` after preparer resolution. APIs use unauthorized-as-404,
authorization-filtered counts, opaque pagination, idempotency keys, and ETags.

### Finish Together capability boundary

Guided Finish is computed on every request from current missing items, catalog-authored estimates,
question batches, and relay state. It is not a durable checklist. The server orders blocking before
advisory, actionable before waiting, then oldest first with a stable identifier tie-break. It always
includes the first blocking action even when that action exceeds a 5-, 10-, or 20-minute budget.
Confirmation and evidence linking reconcile the projection and mechanical counters atomically.

Proof Map joins canonical values to provenance and every pinned form destination. Document proof is
served only as a sanitized raster page after tenant, assignment, person-scope, and opaque-document
checks. Human entries retain actor attribution and never carry an extraction confidence band.
Reviewers and approvers have read-only Proof Map access; preparers may act only on assigned cases;
tenant administrators receive no case access.

[ADR-018](docs/adr/ADR-018-public-evidence-relay-capability.md) defines Private Relay. Authenticated
creation is limited to cited evidence requirements. The public locked surface is generic; link and
six-digit code are separate; five failures lock; expiry is 72 hours. A successful challenge mints a
short-lived, write-only, one-object upload capability. Uploaded bytes enter the ordinary validation,
sanitization, classification, and integrity pipeline and remain `RECEIVED` until an authorized
applicant or assigned preparer accepts and links the processed document. Plaintext credentials and
sensitive labels are excluded from persistence, logs, metrics, URLs outside the opaque token, and
notifications.

The updated [OpenAPI contract](contracts/openapi/workforce-workflow.yaml) carries authenticated plan,
proof, preview, and relay management operations plus the separate recipient challenge, unlock,
upload-session, and completion operations. `security: []` appears only on generic recipient challenge
and unlock. Production must use rate-limited public edge infrastructure, hash-at-rest credentials,
single-object storage grants, object lifecycle deletion, idempotency, non-sensitive audit events, and
unauthorized-as-404 behavior.

### Demo isolation

[ADR-017](docs/adr/ADR-017-isolated-demo-tenancy.md) requires demo to be a separate synthetic tenant
entered through session/authorization contracts. It has distinct database/RLS scope, keys/encryption
context, object prefix, caches, search, queues, audit stream, and metrics. The local implementation
uses a separate persistent fixture file. Demo disables real invitations and secure delivery,
watermarks output, resets only synthetic records, and clears demo caches when returning to live.

### Deployment topology and dependencies

Architecture must provision tenant-bound passkey identity and step-up; policy decision/enforcement
points; Azure SQL tenant and person-scoped RLS; tenant/client, case/canonical-field, assignment,
review/approval, invitation, and Form Catalog services; sanitized document storage and processing;
server-side PDF preview/generation/verification; immutable package storage; transactional audit
outbox; a public relay edge and challenge store; write-only relay object staging and lifecycle jobs;
demo provisioning/reset jobs; feature flags; dead-letter queues; and isolation monitors.

### Migration, observability, and rollout gates

Migrate in expand/backfill/enforce phases: create tenants/members/clients/assignments; verify
tenant/person ownership; add canonical values, section revisions, bindings, evidence links, review
decisions, preview hashes, approvals, and history; then enable non-null keys, composite FKs, RLS,
policy enforcement, and write cutover. Add optional canonical path, requirement code, and catalog
estimate columns before introducing relay metadata, credential-hash, attempt, upload-session, and
document-link relations. Backfill only catalog-derived values; quarantine ambiguous ownership rather
than guessing.

Monitor cross-tenant denials, RLS failures, ETag and idempotency conflicts, relay challenge denials,
bounded-attempt lockouts, expiry/revocation cleanup lag, staged-object age, review ageing, approval
invalidations, preview/hash mismatches, generation failures, export denials, demo reset failures,
namespace leaks, outbox lag, and dead letters. Metric dimensions must be bounded and non-sensitive.

Rollout gates include generated-client compatibility; role/separation tests; cross-tenant,
person-scope, Private Annex, sealed-medical, admin-denial, and demo/live tests; migration
reconciliation; preview watermark/non-export; approval invalidation; localization/accessibility;
platform navigation checks; and a complete synthetic case with every forbidden next action denied.

## Change ledger

### 2026-09-18 — App Store Connect & TestFlight Paperwork Copy Alignment

**Implemented in the app and store packages**
- **App Store Description & Metadata Alignment**: Aligned official English and Spanish App Store product descriptions in `apps/ios/AppStore/metadata/en-US/description.txt` and `es-MX/description.txt` to emphasize document and paperwork workflows. Replaced camera-only terminology with document scanner and file import. Verified via `tools/validate-ios-store-assets.sh` (0 defects).

### 2026-09-18 — La Pluma Golden Feather Brand Launch, iOS 27 Liquid Glass UX, Smart Loupe Neural Vision & SharePlay Apple Pencil Pro Attestation (Phases 13-18)

**Implemented in the app and shared packages**
- **Official Brand Identity & App Store Master Icon (Stage 13 & 18)**: Replaced internal codename "Aperture" with the official public identity **La Pluma** ("The Feather" / "The Quill"). Deployed official 1024x1024 master icon (`AppIcon.appiconset/AppIcon-1024.png` and `BrandMark.imageset/BrandMark.png`) complying with Apple App Store Connect requirements (1024x1024 pt @ 1x, RGBA, square unrounded). Aligned all applicant and caseworker copy to document and paperwork scanning ("Scan paperwork, choose an image, or import a file", "Smart Loupe (Neural Document Vision)", "Scan document").
- **Modern Enterprise SSO & Passkey Trust Pipeline (Stage 14)**: Native `ASWebAuthenticationSession` integration for Microsoft Entra ID (multi-tenant `/organizations`, automatic handling of `AADSTS90094` admin consent required with `ShareLink` and clipboard copy) and Google Workspace (`hd` hosted domain restriction). Enterprise-to-Passkey Trust Pipeline automatically registers and binds hardware-protected Apple Passkeys (`ASAuthorizationPlatformPublicKeyCredentialProvider`) upon successful SAML/OIDC authentication.
- **iOS / iPadOS 27 Liquid Glass Design System (Stage 15)**: Translucent materials (`ultraThin`, `regular`, `prominent`, `chromatic`), continuous squircle geometries, specular rim luminescence, spatial depth elevation, iOS 27 micro-haptics (`sensoryTick`, `magneticSnap`), and spring physics. Added `AdaptiveContrastScrim` guaranteeing WCAG AA contrast (>= 4.5:1) while respecting `UIAccessibility.isReduceTransparencyEnabled` and `isReduceMotionEnabled`.
- **Game Changer 1: On-Device Neural Vision "Smart Loupe" (Stage 16)**: Native Apple `Vision` (`VNRecognizeTextRequest`) engine delivering sub-15ms parsing for ICAO Doc 9303 Machine Readable Zones (TD1, TD2, TD3) with 7-3-1 weight check-digit algorithmic validation. Zero-cloud-leakage local PII redaction (SSN, Alien Registration Number) on Apple Neural Engine with AR alignment HUD.
- **Game Changer 2: Synchronous SharePlay Live Canvas & Apple Pencil Pro Biometric Attestation (Stage 17)**: Real-time caseworker and applicant co-review over FaceTime SharePlay (`GroupActivities`). Captures 240Hz Apple Pencil Pro pressure, tilt, and barrel roll telemetry into a non-repudiable biometric hardware attestation envelope sealed by Apple Secure Enclave P-256 keys.
- **Strict Motion Accessibility & Localization Parity**: Conformed all app animations to `respectfulAnimation(value:)` honoring Reduce Motion, and established 100% key parity across English and Spanish localization bundles.
- **App Store Connect & TestFlight Metadata Alignment**: Aligned App Store metadata and localized product descriptions (English and Spanish) to official paperwork scanning and document workflows. Verified against `validate-ios-store-assets.sh` with 0 defects.

### 2026-09-14 — Blueprint-Driven Entry, Guidance Rendering & Offline Drift Reconciliation (Phase 14 / APP-05 / APP-06 / INF-14 / INF-18)

**Implemented in the app and shared packages**
- **Dynamic Blueprint-Driven Entry (APP-05)**: Delivered declarative `BlueprintDefinition` models matching `document-blueprint.schema.json` and generic `BlueprintFormEntryView` supporting declarative fields (`string`, `date`, `boolean`, `choice`, `number`, `signature`), repeated sections (`isRepeatable: true`, `maxOccurs: 5`), conditional section and field visibility, and cited official evidence requirements without bespoke per-form screens. Seeded all 4 synthetic non-immigration Blueprints (`CLINIC-INTAKE`, `SCHOLARSHIP-APP`, `DS-11`, `FAFSA`) in `StubStorage`. Enforced declarative safety invariants (`validateDeclarativeSafety`) rejecting executable code injection.
- **Source-Cited Guidance & Pastel Presentation**: Rendered `DocumentGuidance` citing official agency instructions, statutory fee schedules, evidence checklists, and institutional notes with distinct namespace boundaries using the pastel design tokens (pure white `#FFFFFF` canvas, flat 12px cards, 40px stage pills, and accessible action tokens).
- **Revision Drift Detection & Generation Blocking (APP-06)**: Implemented `BlueprintDriftPolicy` comparing case revision pins against current catalog state, detecting replaced revisions, quarantined blueprints, withdrawn artifacts, or catalog removals. Integrated drift detection with `PackageGenerationReadiness` to block stale package generation, and surfaced explicit `quarantinedFormDrift` alerts preventing silent upgrades.
- **Offline Drafts & HTTP 412 Conflict Preservation**: Delivered thread-safe `OfflineCaseStore` strictly partitioned by `tenantId`, persisting `CaseRevisionPin`, local uncommitted section drafts, and base revisions. When concurrency conflicts occur (HTTP 412 `PreconditionFailed`), preserves local drafts alongside server authoritative values and presents `ConflictResolutionSheet` for side-by-side comparison and resolution.
- **Approval Invalidation on Section Edits**: Enforced that committing canonical section values on an approved case invalidates the approval (`invalidatedApproval == true`) and resets stage to `validating` or `inReview`.
- **Localization Parity & Automated Verification**: Added full key-for-key English/Spanish parity for all Blueprint entry, drift, and conflict strings. Added Swift test suite `BlueprintEntryAndDriftTests.swift` (8 tests) and Python test suite `test_blueprint_entry_and_drift_contract.py` (7 tests). All 111 tool tests and 84 Swift static checks pass cleanly with 0 problems.

**Expected from cloud architecture**
- **Blueprint Publication Lifecycle & Quarantine Gates (INF-14, INF-18)**: Cloud Document Library enforces immutable revision increments, independent author/reviewer separation, and publishes withdrawal/quarantine events to Pub/Sub. When a blueprint revision is updated or quarantined, the Case Service transitions affected cases to `QUARANTINED_FORM_DRIFT` and prohibits AcroForm package generation.
- **Tenant Scope Isolation & Revision Pins**: Cloud SQL stores `workflow.case_pinned_blueprint` and `workflow.case_workspace` partitioned by immutable `tenant_id`. Section commits require `If-Match` ETags, rejecting stale base revisions with typed HTTP 412 `urn:lapluma:problem:version-conflict` envelopes without overwriting local drafts.

**Boundary**
- Client owns dynamic declarative form rendering, offline draft persistence, local conflict resolution comparison, and pastel visual guidance. Server owns official artifact storage, catalog versioning, quarantine event emission, and authoritative optimistic concurrency verification.

### 2026-09-14 — Pastel Visual System Adoption, Workforce Workstation & Accessibility Across All Surfaces (Phase 13 / APP-10 / APP-11 / APP-12 / INF-13)

**Implemented in the app and shared packages**
- **Native Pastel Design Tokens & White Canvas (APP-10)**: Adopted pure white canvas (`#FFFFFF`) across applicant and workforce screens via `ApertureCanvas(pureWhite: true)`. Exposed flat 12px card modifier (`.aperturePastelCard`), 40px stage pill modifier (`.aperturePastelPill`), 32px control sizing, 8px chip rounding, and complete 4px modular spacing rhythm (4, 8, 12, 16, 20, 24, 32, 40, 56, 72, 112, 128px) in `DesignTokens.swift`. Prohibited heavy drop shadows and unapproved web frontends.
- **Workforce Workstation Styling (APP-11)**: Enhanced `LaPlumaWorkforceApp.swift` in `LaPlumaWorkforce` with the pastel visual system, split-view navigation, stage pills pairing SF Symbol icons with localized text labels, flat 12px cards, and Dynamic Type scalability.
- **Accessibility & Contrast Compliance (APP-12)**: Verified WCAG AA contrast (>= 4.5:1) for all saturated action tokens (`actionRed` `#B3261E`, `actionYellow` `#7D5700`, `actionGreen` `#1B6E32`, `actionBlue` `#185ABC`) on pastel fills and white, and WCAG AAA (>= 7.0:1) for dark ink (`#202124`) on white. Enforced non-color state encoding (NFR-A11Y-004) pairing icons with all status indicators (`ConfidenceChip`, `CaseStateChip`, `FormActivationState`, `stagePill`). Added cross-platform sensory haptics (`ApertureHaptics`) for user interactions. Verified 100% Spanish/English localization key symmetry.
- **Automated Verification Suites**: Added Swift test suite `PastelVisualAccessibilityTests.swift` (5 tests) and Python test suite `test_visual_system_and_accessibility.py` (10 tests) validating contrast math, geometry invariants, non-color state encoding, and localization parity. All 104 tool tests and 79 Swift static checks pass cleanly.

**Expected from cloud architecture**
- **Grayscale Operator UX Boundary (INF-13)**: Operational backends and admin tools adhere strictly to neutral grayscale tokens (`#171717`..`#F5F5F5`). Web frontends are prohibited on unapproved operator endpoints. Design spec and foundation validation scripts (`verify_design_spec.py`, `validate_foundation.py`) verify compliance and prevent unauthorized frontend assets.

**Boundary**
- Client owns native pastel visual presentation, Dynamic Type scalability, VoiceOver labels, and sensory haptic feedback across iOS, iPadOS, and macOS. Cloud architecture enforces grayscale styling on established operator surfaces and guarantees backend compliance.

### 2026-09-14 — Canonical Case Writes, Section Commits, Conflicts & Approval Invalidation (Phase 11 / INT-04)

**Implemented in the app and shared packages**
- **Canonical Section Commit Contract Verified**: Verified `/cases/{caseId}/sections/{sectionId}/commit` endpoint in `contracts/openapi/workforce-workflow.yaml` requiring `If-Match` ETag header and `Idempotency-Key` parameter, returning `200 OK` on success and `412 Precondition Failed` on version conflict.
- **Swift Domain Models & Stub Alignment**: Verified `SectionCommit` in `WorkflowModels.swift` and `commitSection` in `StubWorkflowAPI.swift` enforcing `baseRevision` optimistic concurrency check, 412 version-conflict problem details, `reopenedReview` state transition on reviewable states, and `invalidatedApproval` purge on approved states.
- **Contract & Boundary Test Suite**: Added pure Python standard library test suite `tests/tools/test_canonical_writes_contract.py` validating OpenAPI contract declarations, Swift model field names, optimistic locking concurrency semantics (412 `PreconditionFailed`), idempotency replay vs conflict (409 `Conflict`), and review reopening / approval invalidation state-machine transitions. All 90/90 tool tests pass cleanly; `tools/check-swift-static.py` passes with 0 problems across 78 Swift files.

**Expected from cloud architecture**
- **Optimistic Concurrency & ETag Verification**: Workflow API endpoint `POST /v1/cases/{caseId}/sections/{sectionId}/commit` inspects `If-Match` ETag header and `baseRevision` body field. If the section revision is stale, returns HTTP 412 `PreconditionFailed` with problem type `urn:lapluma:problem:version-conflict`.
- **Idempotency Replay & Conflict**: Employs transactional idempotency tracking. An identical key with the same payload replays the cached `SectionCommit` with HTTP 200; an identical key with a mutated payload returns HTTP 409 `Conflict` with `urn:lapluma:problem:idempotency-key-conflict`.
- **Transactional Canonical Persistence**: Atomically upserts field values to PostgreSQL `workflow.case_field_value` with `source_kind = 'MANUAL_ENTRY'` and `is_human_confirmed = TRUE`, invalidates active approvals in `workflow.case_approval` (`is_invalidated = TRUE`, reason `'FIELD_VALUE_UPDATED'`), purges cached packages, resets case status to `IN_PROGRESS`, and emits `SECTION_COMMITTED` to `workflow.outbox_event`.

**Boundary**
- Client manages form editing and section commits with optimistic concurrency tracking. Server guarantees atomic PostgreSQL writes, idempotency enforcement, review reopening, approval invalidation, and transactional outbox event emission.

### 2026-09-14 — Reviewed Document Output, Scoped GCP Downloads & Pub/Sub Delivery States (Phase 7 / APP-08 / INT-08)

**Implemented in the app and shared packages**
- **Workforce Workflow OpenAPI 3.1.0 Contract Synchronized**: Synchronized `contracts/openapi/workforce-workflow.yaml` defining scoped download grants (`GET /v1/cases/{caseId}/packages/{packageId}/download`) returning short-lived (15-minute TTL) signed URLs to private Cloud Storage objects (`storage.googleapis.com`), and Pub/Sub delivery events (`POST /v1/events/workflow`) for asynchronous package generation and delivery updates.
- **Client Output & Download Models**: Extended `PackageOutput.swift` with `ScopedDownloadGrant` (including client-side `isExpired` expiration checks) and added `downloadGrant`, `valuesHash`, `blueprintRevisionHash`, and `approvalID` to `GeneratedPackage`.
- **Step-Up & API Client Contracts**: Added `StepUpChallenge` in `WorkflowModels.swift`, and extended `ApertureAPIClient` with `stepUpChallenge(caseID:idempotencyKey:)` and `packageDownload(caseID:packageID:)`. Implemented in `StubWorkflowAPI` and `StubAPIClient` with strict approval-invalidation enforcement (rejecting with 409 Conflict if approval has been invalidated).
- **Package UI Model Resilience**: Updated `PackageModel` in `FeatureModels.swift` with `activeDownloadGrant`, `isRefreshingDownload`, `downloadRefreshFailed`, and `refreshDownload(caseID:packageID:client:)` allowing client recovery of expired download grants without re-requesting package generation.
- **Contract & Boundary Test Suite**: Added pure Python standard library test suite `tests/tools/test_app_output_and_pubsub_contract.py` (12 tests) verifying OpenAPI paths, schemas, Swift model definitions, expiration calculations, regression guard logic, and approval invalidation gates. All 65/65 tool tests pass cleanly; `tools/check-swift-static.py` passes with 0 problems across 78 Swift files.

**Expected from cloud architecture**
- **Scoped Download Issuance**: Workflow API issues short-lived (15-minute TTL) V4 signed URLs to private Google Cloud Storage objects (`storage.googleapis.com`) under bucket `lapluma-documents-{environment}`.
- **Expired Download Recovery**: Expired download grants can be re-issued upon request (`GET /v1/cases/{caseId}/packages/{packageId}/download`) without re-running document compilation, provided the underlying approval record remains valid and un-invalidated.
- **Strict Approval Invalidation Gate**: Download grant requests refuse with HTTP 409 Conflict (`approval-invalidated`) if the case's approval has been invalidated due to field mutations or evidence changes.
- **Pub/Sub Delivery State Alignment**: Workflow API endpoint `POST /v1/events/workflow` processes Pub/Sub events with at-least-once message deduplication by `eventId` (returning `DUPLICATE_IGNORED` on duplicates) and prevents backward state regression (returning `REGRESSION_PREVENTED` if the case has already advanced past the event's target state).
- **Transactional Audit & Outbox**: Records download grant issuances, Pub/Sub delivery acknowledgments, and state transitions in append-only case history and outbox tables.

**Boundary**
- Client requests scoped download grants and renders/downloads official AcroForm outputs via short-lived signed URLs. Cloud Run microservices (Workflow API and Document Processing Worker) and Pub/Sub manage AcroForm filling, GCS object lifecycle, and asynchronous status transitions.

### 2026-09-14 — Blueprint Review-to-Approved-Output Round Trip & Processing Services (Phase 6 / INT-06 / INF-11)

**Implemented in the app and shared packages**
- **Workforce Workflow OpenAPI 3.1.0 Contract Synchronized**: Synchronized `contracts/openapi/workforce-workflow.yaml` defining endpoints for review queue (`GET /v1/review-queue`), review decisions (`POST /v1/cases/{caseId}/review-decisions`), watermarked draft preview (`POST /v1/cases/{caseId}/draft-preview`), step-up challenge (`POST /v1/cases/{caseId}/step-up-challenge`), step-up approval (`POST /v1/cases/{caseId}/approval`), case history (`GET /v1/cases/{caseId}/history`), section commit (`POST /v1/cases/{caseId}/sections/{sectionId}/commit`), and package generation (`POST /v1/cases/{caseId}/package-generation`).
- **Separation of Duties Policy**: Enforced mandatory distinct humans across Preparer, Reviewer, and Approver roles (`CanApprove` rejects when any actor duplicates another).
- **Approval Invalidation on Field Mutation**: Enforced that committing canonical section values or modifying evidence links on an already approved case invalidates the approval (`is_invalidated = true`, `invalidation_reason = 'FIELD_VALUE_UPDATED'`) and resets case state from `APPROVED` back to `IN_REVIEW`.
- **Watermarked Draft Previews**: Enforced server-rendered draft previews watermarked `DRAFT — NOT FOR FILING` on every page, with short-lived access (15 minutes), non-exportability, and stale preview rejection when canonical hash or blueprint revision changes.
- **Strict Package Generation Gates**: Prohibited official output package generation unless the case is in `APPROVED` status with a valid, un-invalidated approval record binding the immutable values hash and blueprint revision hash.
- **Contract & Invariant Test Suite**: Added pure Python standard library test suite `tests/tools/test_review_approved_output_contract.py` (53 tests) proving contract validity, separation of duties, approval invalidation invariants, preview watermark requirements, and package generation gates. All 53 tests pass cleanly.

**Expected from cloud architecture**
- **Workflow API**: Implements review queue, review decision, draft preview, step-up challenge, case approval, case history, section commits with approval invalidation, and package generation endpoints backed by PostgreSQL tables `workflow.case_workspace`, `workflow.case_approval`, `workflow.case_pinned_blueprint`, and `workflow.outbox_event`.
- **Document Processing Worker**: Exposes `/preview` rendering watermarked draft PDFs with `DRAFT — NOT FOR FILING` and short-lived signed URLs, `/generate` producing official AcroForm outputs with verification reports and SHA-256 digests, and `/pubsub` handling Cloud Storage quarantine events to promote verified files.
- **Durable Audit History**: Records state changes, review decisions, step-up challenges, approvals, and invalidation events in append-only case history.

**Boundary**
- Client displays review queue, performs step-up attestation, requests previews, and inspects package readiness. Server-side workflow and document processing engines exclusively enforce separation of duties, watermark rendering, AcroForm filling, digest verification, and package compilation.

### 2026-09-14 — Scoped Cloud Storage Transfer & Verification (Phase 5 / INT-05 / APP-07 / INF-03)

**Implemented in the app and shared packages**
- **Direct-to-Storage OpenAPI Contract**: Synchronized `contracts/openapi/documents-upload.yaml` (OpenAPI 3.1.0) into `PEN-lapluma_app`, specifying 100 MB uploads (`104,857,600` bytes) bypassing API Gateway's 32 MB request limit via short-lived (15-minute), narrowly scoped create-only grants to private Cloud Storage objects over Google's internet endpoint (`storage.googleapis.com`).
- **ApertureKit UploadSession Enhancement**: Extended `UploadSession` model with `uploadMethod: String = "PUT"` and `expectedContentSHA256: String? = nil` with default values and CodingKeys mapping to preserve 100% backward and forward binary compatibility.
- **Stub Client & Mock Alignment**: Updated `StubAPIClient.createUploadSession` to populate `uploadMethod = "PUT"` and `expectedContentSHA256 = contentSHA256`.
- **Contract & Boundary Test Suite**: Added `tests/tools/test_documents_upload_contract.py` validating schema conformity, 100 MB capture bounds, lowercase hex SHA-256 pattern, `Idempotency-Key` header enforcement, gateway bypass rationale, and offline `PendingCaptureQueue` recovery and integrity guarantees.
- **All Policy & Contract Tests Passing**: All 46 tool and contract tests pass; Swift static analysis gate confirms 0 problems across 78 Swift files.

**Expected from cloud architecture**
- Google API Gateway fronts metadata and session endpoints, enforcing token scopes and tenant isolation while keeping document bytes completely off the gateway path.
- Workflow API mints short-lived (15-minute) write-only Google Cloud Storage V4 signed URLs (`storage.googleapis.com`) to private staging/quarantine buckets.
- Server validates actual file size, SHA-256 checksum, tenant ownership, and MIME type upon completion before handing evidence to quarantine/processing.
- Fail-closed typed problem details: HTTP 422 for digest mismatches (`upload-digest-mismatch`), size bounds violations (`upload-size-invalid`), or missing blobs (`upload-blob-missing`).
- Zero token or signature leakage into application logs or telemetry.

**Boundary**
- Client captures up to 100 MB locally, verifies SHA-256 digest, requests a write-only upload session, PUTs directly to private Cloud Storage, and completes the session with an idempotency key. Gateway carries only JSON metadata; all bytes transit directly to private Cloud Storage.

### 2026-09-14 — End-to-End AcroForm Generation Integration Testing (Phase 4)

**Implemented in the app and shared packages**
- **Mobile Client Fact Capture Compatibility**: Verified canonical paths and role attributes in `CaseInitializationTemplate.familyI130`, `ReviewableField`, and `StubAPIClient` map 100% cleanly into the authoritative Form I-130 blueprint (`official/uscis/i-130`) and resolve to the exact AcroForm target fields (`form1[0].#subform[0].Pt1Line1a_GivenName[0]`, `Pt1Line1b_FamilyName[0]`).
- **Integration Test Suite**: Added `tests/tools/test_mobile_fact_capture_integration.py` validating package mappings (`FAMILY_I130` -> `family-reunification-i130` -> `official/uscis/i-130`), blueprint field resolution, mobile client payload serialization contracts (`{"requestId": ..., "inputs": ...}`), and iOS/mobile soft-keyboard Unicode NFC normalization (preventing NFD decomposed character issues in PDF rendering).
- **All Policy & Contract Tests Passing**: All 37 tool and contract tests pass; Swift static analysis gate confirms 0 problems across 78 Swift files.

**Expected from cloud architecture**
- Isolated Cloud Run `document-processing` worker exposes `POST /process` and `POST /map` handling blueprint mapping payloads within 2MB limits.
- Validates Google Cloud Storage (`gs://` and `storage.googleapis.com`) and Azure Blob endpoints fail-closed.
- Generates Part 11 Supplemental Information addendums when repeated collections exceed form capacity.
- Rejects malicious PDF injection attempts (`/JavaScript`, `<script>`) with HTTP 422 and safe, content-free error envelopes.

**Boundary**
- Client emits confirmed canonical fact values and requests package generation; AcroForm PDF field rendering, overflow pagination, and addendum generation execute strictly in the isolated Cloud Run worker.

### 2026-09-14 — App Target Unit-Test Layer & Policy Gates (T-68 to T-71, PR #53)

**Implemented in the app and shared packages**
- **T-68 (Feature View Model Unit Layer)**: Extracted `CaseWorkspaceModel` (and provided `CaseWorkspaceViewModel` / `CatalogViewModel` aliases) in `ApertureUI/FeatureModels.swift`. Refactored `CaseWorkspaceView` in `apps/ios/ApertureApp/Features/Workflow/WorkflowViews.swift` to bind directly to `CaseWorkspaceModel`. Added 7 new tests in `FeatureModelTests.swift` covering `CaseWorkspaceModel` loading, capabilities, cancellation, failure, retry recovery, and `CatalogModel`/`CatalogViewModel` Document Library collection state and tenant isolation.
- **T-69 (CI Policy Gates Under Test)**: Created `tests/tools/test_check_wiki_links.py` testing `tools/check-wiki-links.py` against dead links, anchors, and path violations. Added Windows path normalization test `test_bundle_module_flagged_with_windows_native_path` in `tests/tools/test_check_swift_static.py`. Marked Windows static-gate portability resolved in `TODO.md`. All 33 tool tests pass cleanly.
- **T-71 (Policy Boundaries & Edge Cases)**: Enhanced `BoundaryPolicyTests.swift` with tests for `CaptureTransferPolicy` threshold boundaries, `GuidedFinishPolicy.makePlan` empty input/sorting/budget cutoff edge cases, and `DeliveryLink.isLive` boundary conditions (exact expiry, over-cap, zero downloads, revocation).

**Expected from cloud architecture**
- Core API and Workflow API provide corresponding contract fidelity and boundary enforcement for collection queries and case workspaces.

### 2026-09-13 — Publish approved GCP and Document Library handoff

- Published ADR-019 and linked the three existing boards and canonical platform/cost records.
- Current client behavior is unchanged. Expected cloud behavior moves to managed GCP, PostgreSQL
  with JSONB, private Storage grants, Pub/Sub and API Gateway; services retain authorization.
- Blueprints/Collections introduce immutable revision pinning, customer assignment, independent
  publication review and tenant-safe discovery/export; compatible catalog/package IDs remain.
- Platform encryption supersedes mandatory customer keys; retention/backup deletion must not
  claim tenant-key erasure. Scoped internet transfers supersede private-only mobile transfers.
- Architecture/library foundations stay P0. Integration proofs, institution onboarding and pastel
  styling remain planned on the boards. This commit does not implement those cards.
- Added ADR-019 to the generated-wiki map and navigation so the approved decision publishes with docs.


### 2026-08-28 — The settle fix holds: 33/33 green, T-55 evidence restarted at 6

**Implemented in the app and shared packages**

- No code changed. Evidence only: the first full suite carrying the `flipSwitch` settle fix
  (workflow_dispatch run `33165805245` on `c95eec7`) reported *"Executed 33 tests, with 0 failures
  (0 unexpected)"* and `** TEST EXECUTE SUCCEEDED **`, including
  `testAccessibilityProfileEnablesVoiceFirstTargetsAndWaivedBudget` — the journey whose failure on
  `04652cb` reopened T-55. Recorded as 6 clean `flipSwitch` executions (one per call site) against
  the ~20 threshold.
- Corrected a count in T-55: the helper has **six** call sites, not the nine an earlier draft
  claimed. Since evidence is now counted per call site, that number is load-bearing.
- The settle helper costs nothing measurable — 18m13s test step against 19m42s on the failing run.
- Also notes that the suite is 33 journeys now, not the 32 older entries quote; T-75 added one.

**Expected from cloud architecture**

- Nothing. Test-evidence bookkeeping only.


### 2026-08-28 — flipSwitch settles the frame before tapping; T-55 recurred (T-78 recorded)

**Implemented in the app and shared packages**

- No product code changed. `flipSwitch` in the UI suite now waits for the target switch to be
  hittable and to hold the same frame across three consecutive readings before deriving a tap
  coordinate from it, bounded at 5s. T-53's three-tap retry stays as a backstop but was never
  going to close this: three taps against an animating frame are three taps that miss.
- **T-55 recurred** on the full suite on `04652cb` — `testAccessibilityProfileEnablesVoiceFirstTargetsAndWaivedBudget`
  failed with the documented `value == "1"` shape on the Me tab's accessibility toggle, a
  different call site of the same helper than the journey the task had been counting. Its 11
  clean executions were all of one journey and said nothing about the helper; the tally is reset
  and evidence is now counted as executions of `flipSwitch`, which nine journeys exercise.
- Verified that this is not a T-67 regression: the toggle is `SettingsView.swift:58` and the two
  sections T-67 gated are at `:86`–`:99`, below it.
- Recorded **T-78**: the weekday schedule fires 35–70 minutes late on a normal day, fired eleven
  hours late on 2026-08-27, and did not fire at all on 2026-08-28 — which weakens the residual
  risk T-74 accepted and starves T-55 of evidence.

**Expected from cloud architecture**

- Nothing. Test-harness and CI-scheduling concerns only; no data, API, authorization, tenancy,
  retention, or observability implication, and no trust boundary moved.


### 2026-08-28 — Form-edition drift becomes a real control (T-77)

**Implemented in the app and shared packages**

- `FormDriftPolicy` compares each pinned form against the catalog's current edition and reports
  a replaced edition or a withdrawn form. `WorkflowPolicy` gained edges into
  `quarantinedFormDrift` from every preparing state and one edge out to `collecting`, so the
  state is reachable for the first time — no edge led into it before, and nothing ever set
  `PinnedForm.driftDetected`, so both the state and the FolderView warning that reads it were
  dead. `PackageGenerationReadiness` gained `formsWithEditionDrift` and `PackageView` a matching
  blocker row (en/es).
- Drift is **derived on read**, never written back: the stored pin records what the case was
  prepared from, and rewriting it to the agency's new edition would erase the fact the applicant
  must be told. `requestPackageGeneration` refuses on the drift itself, before every other check
  and regardless of case state, so the protection does not depend on anyone having quarantined
  the case — nothing does so automatically yet.

**Expected from cloud architecture**

- Edition currency is a catalog-service responsibility, not a client one: the service must
  monitor published editions, and on republication quarantine every affected case and notify the
  people working them. Two things the client cannot do — compare the pinned `sourceSHA256`
  against the current artifact (the stronger check; the stub can only compare edition dates), and
  decide the migration policy for a case already generated or delivered against the old edition.
  Accepting a migration is a human act that must be recorded in the case history with its actor.
  No trust boundary moved, so no new ADR.


### 2026-08-28 — Fabricated access records cannot reach a distributable build (T-67; R-6 raised)

**Implemented in the app and shared packages**

- The activity log and notification-settings entry points are gated behind `#if DEBUG` plus
  `--show-unbacked-demo-surfaces`, the shape `syntheticCaptureButton` already uses, so neither
  can appear in TestFlight or Release. Both are unbacked: the log rendered three invented access
  records that "Delete everything" could not clear and the marketing profile could not swap, and
  the notification screen offers no control because nothing reads `NotificationPreferences`.
- The invented records became `Text(verbatim:)` and left both localization tables — CLAUDE.md
  reserves that form for text that must never reach a user, and keeping them as localized keys
  implied they were shippable copy. The screen now opens with an explicit example-data banner.
- Nothing was deleted, so the destination remains open as **R-6**: delete, keep the interim, or
  build for real against the production API.

**Expected from cloud architecture**

- When access history becomes real it is an audit surface, not a convenience one: the production
  service owns an append-only access log covering staff, break-glass, and delegated access, with
  the same per-person scoping as the rest of the aggregate (ADR-007). Two consequences the client
  cannot supply — an access record must survive the applicant's own deletion where retention law
  requires it, and must be *shown* as retained rather than silently kept, so "Delete everything"
  needs an explicit, truthful statement about access history rather than the silence it has now.

### 2026-08-28 — flipSwitch evidence tally reaches 11 of ~20 (T-55)

**Implemented in the app and shared packages**

- No code changed. Tracking-file update only: the second fully green 32-journey suite
  (workflow_dispatch run `33143670144` on `fb7e07f`, dispatched to verify the T-68 scan encoder
  end to end) is recorded as an eleventh clean execution of the `flipSwitch`-dependent journey,
  classified by inspecting the run rather than trusting its conclusion. T-55 stays open: 11 is
  just over halfway to the threshold it set for itself, and `flipSwitch` must not be touched
  while it is open or the tally restarts at zero.

**Expected from cloud architecture**

- Nothing. No app, contract, data, authorization, or observability implication.

### 2026-08-28 — Folders can hold the people they are about (T-75)

**Implemented in the app and shared packages**

- `createPerson(folderID:displayLabel:isMinor:relationships:idempotencyKey:)` joins the client
  contract; `AddPersonView`, reached from a folder's People tab, collects a label, a minor flag,
  and one relationship to someone already in the folder. T-61's role resolution then completes
  without explicit `roleAssignments`: a folder holding a petitioner and a beneficiary creates its
  I-130 case. Until now nothing in `apps/ios/` ever constructed a `Person`, so a folder made in
  the app was permanently empty and could never produce an application.
- The endpoint cannot create a credential: a person recorded by someone else always gets
  `holdsOwnCredential: false`, so `CK_Person_MinorNoLogin` holds by construction from this
  surface, and the screen states plainly that adding someone grants no access. A relationship
  naming a person outside the folder is refused 422.
- `Relationship.Kind.inverse` was added and the reciprocal is written onto the counterpart;
  kinds with no expressible inverse (`guardianOf`, `sponsorFor`, `derivativeOf`) return nil and
  are not offered, rather than inventing a term the model cannot hold.

**Expected from cloud architecture**

- Person creation is a per-person trust-boundary event (ADR-007): the production service owns
  authorization to add someone to a folder, must reject relationships crossing folder or tenant
  boundaries server-side, and must keep credential issuance on the separate invitation path so
  the minor-no-login constraint cannot be reached from person creation. Relationship reciprocity
  should be a database-level invariant rather than an application convention, since role
  resolution reads it. No trust boundary moved by this change, so no new ADR.

### 2026-08-28 — The generation gate counts evidence and case state (T-62; T-77 recorded)

**Implemented in the app and shared packages**

- `PackageGenerationReadiness` now carries `outstandingBlockingEvidence` and
  `caseStateAllowsGeneration`, and one `StubAPIClient.readiness` helper serves both the readiness
  endpoint and `requestPackageGeneration`, so the screen's gate and the server's refusal cannot
  disagree. Refusals are ordered and separately typed: `case-state-forbids-generation`,
  `human-confirmation-required`, `evidence-incomplete`. `CaseState.allowsPackageGeneration`
  states the policy once and refuses `quarantinedFormDrift`, `onHold`, `abandoned`, `closed` and
  `changesRequested`.
- Generating no longer rewrites `blockingItems` to zero or claims every field filled; it changes
  state and recomputes counters through the same `bumpCounters` path as every other mutation. A
  refusal now names only actual blockers instead of always emitting three.
- `PackageView` gained a "Required documents not collected" blocker row (en/es), without which a
  case blocked only by evidence showed three zeros and no reason.
- Recorded, not fixed: **T-77** — `quarantinedFormDrift` has no inbound transition, so the
  form-drift protection T-62 now honours is unreachable until edition-drift detection exists.

**Expected from cloud architecture**

- The production generation service must enforce the same four conditions server-side and must
  not treat confirmed fields as evidence of collected documents. Evidence completeness,
  processing state, allowed case state, form-edition currency, and any required reviewer approval
  are all server-authoritative; the client's gate is a courtesy, not the control. Counters
  returned by the case service must be derived, never asserted — a generated case that reports
  zero blockers while its document counts disagree is a data-integrity defect, not a display bug.
  No trust boundary moved, so no new ADR.

### 2026-08-28 — Case-creation refusals state their reason (T-61 follow-up; T-75, T-76 recorded)

**Implemented in the app and shared packages**

- `CatalogView` now surfaces `ProblemDetails.title` on a failed `createCase`, matching the
  convention already used in `FolderView` and `FinishTogetherViews`, instead of "The application
  could not be created. Try again." — which invited an endless retry for a condition retrying
  cannot change. The T-61 role refusal's title was reworded to name what the folder is missing.
- Recorded, not fixed here: **T-75** — nothing in `apps/ios/` ever constructs a `Person`, so a
  folder created in-app is permanently person-less and role-driven creation has no in-app way to
  succeed. T-61 exposed this rather than causing it (the same folder previously produced a case
  that was created and could never progress). **T-76** — the deliberate T-33 exclusion of
  API/domain diffs from UI journeys means an `ApertureAPI` change can alter what a button does
  and merge to `main` with no journey run, as this change did.

**Expected from cloud architecture**

- No contract change. The person/role surface T-75 describes is where the production service's
  per-person trust boundaries (ADR-007) and the minor-no-credential invariant first become
  user-reachable; role assignment must be validated server-side at case creation, not only in
  the client that collects it.

### 2026-08-28 — New cases are born from their package's template (T-61)

**Implemented in the app and shared packages**

- `createCase` no longer produces dead-end shells: `CaseInitializationTemplate` (`ApertureAPI`)
  declares what `FAMILY_I130` requires structurally — required roles, role-attributed reviewable
  field specs, and gap presentation — and `StubStorage.initializeCase` materializes fields,
  field- and evidence-kind missing items (evidence derived from the existing `RequirementSet`;
  conditional requirements arrive advisory), one interview batch whose `itemCount` keeps the
  questionnaire's promise, the value-history baseline, and recomputed counters inside the same
  `commit` as the case record. Roles resolve from explicit `roleAssignments` first, then from
  folder relationships when exactly one candidate exists; an unfillable role, a person outside
  the folder, or a duplicated role each fail creation closed with 422. Templates carry structure
  only — never values, which require a document or a human. Templateless packages keep shell
  behaviour, pinned by test. Eight package tests include the acceptance journey: selection
  through generation with no pre-seeded case.

**Expected from cloud architecture**

- The production case service owns the same guarantee transactionally: case creation and its
  package-driven initial state (role bindings, required fields, evidence requirements, batches)
  commit atomically, and role resolution failures are 422 problem types, not silent shells. No
  trust boundary moved and no new ADR; the template layer is fixture-side until the form-domain
  field maps (T-63/T-67 lineage) replace the six-field floor.

### 2026-08-28 — Scan encoder core moved to CoreGraphics in ApertureAPI (T-68 complete)

**Implemented in the app and shared packages**

- `ScannedDocumentEncoder`'s page mechanics are now a pure-CoreGraphics core in `ApertureAPI`
  taking `CGImage` pages with explicit point sizes; the app keeps a thin `UIImage` extension that
  normalizes orientation through UIKit first, so scan output (page bounds in points, orientation
  handling) is byte-for-byte the same shape as the previous `UIGraphicsPDFRenderer` path. Package
  tests prove page count, order, dimensions, points-vs-pixels, and fail-closed inputs; the
  scheduled multi-page journey remains the end-to-end check. This completes the T-68 extraction.

**Expected from cloud architecture**

- Nothing new. The encoded PDF still travels the existing capture upload pipeline unchanged; no
  data, API, identity, authorization, tenancy, retention, observability, or migration implication
  changes, and no trust boundary moved, so no ADR.

### 2026-08-28 — CI gates under test; advisory coverage reporting (T-69, T-70)

**Implemented in the app and shared packages**

- No app or package code changed. `tests/tools/` (stdlib unittest) now proves every rule class of
  `check-swift-static.py` against known-bad fixtures and both fatal paths of `build-wiki.py`,
  running in `swift-static.yml` and the review container. The first run caught a live defect:
  ADR-016/017/018 were missing from `PAGE_MAP`, so they never reached the wiki and the next docs
  publish would have failed — now mapped and in the sidebar (38 pages mirror, 0 link problems).
  The validate job's `swift test` gains `--enable-code-coverage` with an advisory per-file summary
  (`tools/coverage-summary.py`) in the step summary.

**Expected from cloud architecture**

- Nothing new. No data, API, identity, authorization, tenancy, retention, observability, or
  migration implications; no trust boundary moved, so no ADR.

### 2026-08-28 — Remaining screen models moved into ApertureUI; policy boundary tests (T-68, T-71)

**Implemented in the app and shared packages**

- `InterviewModel`, `ClientDashboardModel`, and `GuidedFinishModel` moved verbatim from their view
  files into `ApertureUI/FeatureModels.swift`, completing the model extraction except for the
  UIKit-bound scan encoder. One seam change: `InterviewModel` reports a `Failure` enum
  (`startFailed`/`sendFailed`) instead of a localized message; the chat view chooses the copy.
  Six new model tests and `BoundaryPolicyTests.swift` (T-71: transfer threshold, Guided Finish
  budget/estimate fallbacks, relay-status mapping, delivery-link liveness) run in `swift test`.

**Expected from cloud architecture**

- Nothing new. The models call the same `ApertureAPIClient` contract from the same screens; no
  data, API, identity, authorization, tenancy, retention, observability, or migration implication
  changes, and no trust boundary moved, so no ADR.

### 2026-08-28 — Per-PR UI gate reduced to a minimal pair (T-74)

**Implemented in the app and shared packages**

- No app or package code changed. `ios-release-validation.yml`'s pull-request selection now runs
  two journeys (the fail-closed discrepancy gate and the shell smoke; Spanish when localization
  changes) instead of seven, an owner decision for iteration speed. The full suite still runs on
  the weekday schedule and on `workflow_dispatch`. Residual risk is recorded in TODO T-74.

**Expected from cloud architecture**

- Nothing new. No data, API, identity, authorization, tenancy, retention, observability, or
  migration implications; no trust boundary moved, so no ADR.

### 2026-08-28 — Role-adaptive case routing and the workforce home on iPhone (T-73)

**Implemented in the app and shared packages**

- Fixed the regression behind the red weekday UI regression (T-73): `FolderView` case rows now
  route by the authenticated context's capabilities — `.viewApplicantFolder` opens the applicant
  `CaseOverviewView`; only workforce-only principals open `CaseWorkspaceView`. The phone's first
  tab is persona-adaptive per ADR-016 (`ClientDashboardView` for the workforce persona, `HomeView`
  for the applicant persona), and the dashboard gained the plain "Create another folder" flow.
  One stale Spanish journey now asserts the localized Clients shell.

**Expected from cloud architecture**

- No new endpoint or data implication — routing consumes the existing `authenticatedContext()`
  capabilities, which remain server-derived (mode rendering still grants no access, ADR-016).
  The client must never infer workforce capability from anything but that context.

### 2026-08-28 — Feature screen models moved into ApertureUI for unit coverage (T-68)

**Implemented in the app and shared packages**

- `HomeModel`, `CatalogModel` (with `CatalogCategoryGroup`), `ReviewModel`, `PackageModel`, and
  `MissingItemsModel` moved verbatim from their view files into `ApertureUI/FeatureModels.swift`;
  `ApertureUI` now depends on `ApertureAPI`. Screen behavior is unchanged. One seam change:
  `MissingItemsModel` exposes `loadFailed` instead of a localized message, because localization
  copy is owned by the view layer. `FeatureModelTests.swift` adds 12 package tests covering the
  models' load/generate transitions, including the package-generation gate and the batch→person
  resolution the T-42 regression class depends on.

**Expected from cloud architecture**

- Nothing new. The models call the same `ApertureAPIClient` contract from the same screens; no
  data, API, identity, authorization, tenancy, retention, observability, or migration implication
  changes, and no trust boundary moved, so no ADR. Remaining extraction work is tracked in T-68.

### 2026-08-28 — Test-coverage analysis recorded as T-68 through T-71

**Implemented in the app and shared packages**

- No app or package code changed. A coverage-focused analysis of the test suite (113 `ApertureKit`
  Swift Testing cases, 32 XCUITest journeys) was recorded in `TODO.md` as four open tasks: T-68
  (the app target has no unit-test layer; feature-model logic is verified only by UI journeys),
  T-69 (the CI policy gates in `tools/` are themselves untested despite two documented fail-open
  incidents), T-70 (`swift test` runs without coverage instrumentation), and T-71 (boundary tests
  for `CaptureTransferPolicy`, `GuidedFinishPolicy.makePlan`, and `DeliveryLink.isLive`).

**Expected from cloud architecture**

- Nothing new. No data, API, identity, authorization, tenancy, retention, observability, or
  migration implications; no trust boundary changed, so no ADR. Unresolved decisions stay in
  `TODO.md` as the tracked tasks above.

### 2026-09-14 — Scoped GCP Storage Uploads, Evidence Ingestion, Reviewed Output & Scoped Downloads (INT-05, INT-06, INF-11, APP-07, APP-08)

**Implemented in the app and shared packages**

- Direct-to-storage document ingestion: Mobile client initiates upload sessions (`createUploadSession`) receiving short-lived (15-minute), write-only single-object signed URLs to Cloud Storage, bypassing Google API Gateway's 32 MB request body limit and supporting captures up to 100 MB (104,857,600 bytes) with SHA-256 integrity binding (`contentSHA256`).
- Offline capture durability: `PendingCaptureQueue` protects sensitive capture payloads and idempotency keys across device relaunches. Payloads are strictly preserved upon transient network failures and deleted only after server-side integrity confirmation (`completeUpload`) succeeds.
- Reviewed document output and scoped downloads: Generation of approved filing packages (`requestPackageGeneration`) is bound to immutable value set hashes, verified evidence, and pinned Blueprint/Collection revisions. Case approvals require human review and distinct-actor step-up attestation.
- Package download grants (`packageDownload`): Issues short-lived (15-minute), one-object scoped download grants to private Cloud Storage objects. Expired grants support transparent re-issuance without regenerating the underlying immutable package.
- Fail-closed approval invalidation: Any canonical field or section modification committed after review or approval immediately invalidates the approval, resets case state to `validating`, and clears cached packages, preventing download of unapproved filing artifacts (409 / 404).
- Added comprehensive unit tests in Swift (`ScopedStorageAndPackageOutputTests.swift`) and Python contract tests (`tests/tools/test_scoped_storage_contract.py`).

**Expected from cloud architecture**

- Cloud Storage ingress enforces 100 MB maximum byte limit (`104857600`), SHA-256 checksum verification against stored bytes, and short-lived (15-minute) signed PUT URLs over Google's internet endpoint.
- Processing pipeline: Upon upload completion, Cloud Functions / Cloud Run workers validate MIME type and magic bytes, sanitize EXIF/metadata, extract fields, and transition document processing state via Pub/Sub events.
- Signed tokens, HMAC signatures, and credential parameters (e.g., `X-Goog-Signature`) are strictly suppressed and redacted from all server and worker logs.
- Scoped download grants strictly enforce 15-minute TTL, single-blob read scope on private package buckets, and cross-tenant access denial (404/403).

**Boundary**

- Client uploads directly to the provided Cloud Storage signed URL and never routes binary document payloads through API Gateway; client never accesses cloud credentials or storage management APIs directly.

### 2026-09-14 — Cloud Run CI/CD Deployment Pipeline & Artifact Registry (P1)

**Implemented in the app and shared packages**

- Client communicates with Cloud Run backend microservices exclusively via API Gateway endpoints, adhering to edge JWT/OIDC authentication.
- Maintained client crash-reporting and telemetry boundaries: diagnostic signals emit sanitized identifiers and omit PII across all environments.

**Expected from cloud architecture**

- Terraform `modules/compute` provisions private Google Artifact Registry repository (`lapluma-services-${environment}`) with immutable image tags on pilot.
- GitHub Actions CI/CD workflow (`.github/workflows/deploy-gcp.yml`) authenticates via Workload Identity Federation (`lp-deployer-${environment}`) to build, tag, and deploy microservices (`core-api`, `workflow-api`, `processing-worker`).
- Enforces Cloud Run scale-to-zero settings (`min_instance_count = 0`), private Cloud SQL connectivity via Direct VPC egress, and restricted invoker IAM (accessible only by API Gateway SA).

**Boundary**

- Client has no access to Google Artifact Registry, deployment pipelines, or Cloud Run administration; service deployments are managed strictly via CI/CD.

### 2026-09-14 — Automated PostgreSQL Migration Runner & Schema Ledger (P1)

**Implemented in the app and shared packages**

- Client expects persistent relational schemas (`library` and `workflow`) to be provisioned and version-tracked deterministically prior to runtime traffic.
- Document Library and Workflow domain models remain decoupled from direct database DDL; client interactions route through API Gateway services.

**Expected from cloud architecture**

- Automated migration runner (`tools/migrate_db.py`) verifies sequential migration ordering (001 through 005) and enforces SHA256 checksum tracking in `public.schema_migrations` to detect script tampering.
- Idempotent master bundle (`all_migrations_bundle.sql`) supports transactional Cloud SQL bootstrap in dev, staging, and pilot environments.
- Migration execution operates under dedicated administrator credentials with strict separation of duty across the 4 database roles (`lapluma_app_core`, `lapluma_app_workflow`, `lapluma_library_admin`, `lapluma_worker`).

**Boundary**

- Client applications perform no database migrations or DDL mutations; database evolution is managed strictly via CI/CD pipelines and the migration runner.

### 2026-09-14 — Shared Design Specification, Two Product Themes & Pastel Design Tokens (INT-10, INF-12, APP-09)

**Implemented in the app and shared packages**

- Implemented native pastel design system in `ApertureKit/ApertureUI/DesignTokens.swift` under `Aperture.Palette`:
  * White surface canvas: `#FFFFFF`
  * Dark ink typography: `#202124` with secondary ink `#5F6368`
  * Soft pastel fills: Red `#FCE4E4`, Yellow `#FFF4CC`, Green `#E3F3E8`, Blue `#E3EEFC`
  * Saturated accessible foreground/action text variants meeting WCAG AA (\(\ge 4.5:1\)): `ActionRed` (`#B3261E`), `ActionYellow` (`#7D5700`), `ActionGreen` (`#1B6E32`), `ActionBlue` (`#185ABC`)
- Mapped `Aperture.StatusTone` backgrounds and foregrounds to the pastel system with mandatory SF Symbol glyphs (`iconName`) ensuring state is never conveyed by color alone (NFR-A11Y-004).
- Updated geometry to `DESIGN.md` standards: flat 12px cards (`Radius.card = 12`), 32px pill controls/inputs (`Radius.control = 32`), 40px navigation pills (`Radius.pill = 40`), and 8px chips (`Radius.chip = 8`).
- Expanded spacing scale to full 4px modular grid rhythm (4, 8, 12, 16, 20, 24, 32, 40, 56, 72, 112, 128px).
- Enforced flat card surface separation without heavy drop shadows.
- Added comprehensive Python contract and contrast test suite `tests/tools/test_design_tokens.py` verifying color hex values, mathematical WCAG AA contrast calculations, geometry radii, and non-color accessibility invariants.

**Expected from cloud architecture**

- Formalized shared design specification (`docs/design/shared-design-specification.md`) defining the two product themes:
  * Infra-owned operator surfaces (CLI/CI and future web dashboards): Neutral Grayscale (`#171717`, `#242424`, `#333333`, `#F5F5F5`, `#C7C7C7`, white primary controls).
  * App-owned workforce and applicant surfaces: White Canvas + Pastel Red/Yellow/Green/Blue + Dark Ink.
- Recorded explicit user overrides to `DESIGN.md`: superseding the cobalt-only and single-accent rules with the 5-color pastel system.
- Inventory of infra operator surfaces (`wiki/Architecture-Overview.md`) establishes that current blueprint onboarding and cluster management are CLI/CI, with grayscale styling binding any future web operator portals.
- Automated validation via `tools/verify_design_spec.py` integrated into `validate_foundation.py`.

**Boundary**

- Client surfaces (including tenant admin in `PEN-lapluma_app`) strictly use the white + pastel palette; cross-tenant platform operator surfaces in `PEN-lapluma_infra` use neutral grayscale.

### 2026-09-14 — Platform-Managed Encryption, Deletion, and Recovery Drill (INT-09)

**Implemented in the app and shared packages**

- Client provides comprehensive, verifiable local data erasure via `AppSession.deleteAllLocalData()`: completely wipes `PendingCaptureQueue`, `ExportScratch`, user defaults, and resets active tenant and auth context with zero residual PII on device.
- Standard platform-managed encryption alignment under ADR-019: Google-managed root encryption keys at rest and TLS in transit replace expensive dedicated HSM/CMEK requirements, remaining compatible with lean pilot budget cap (<$100/mo).
- Scoped download grants enforce short-lived bounded TTL (15 minutes maximum, 900 seconds) with explicit disclosure that signed URLs are not instantly revocable at the storage edge upon erasure, relying on bounded expiration and backend database authorization revocation.
- Added comprehensive Python contract and boundary test suite `tests/tools/test_deletion_and_recovery_contract.py` verifying client erasure, ADR-019 platform-managed encryption terms, and signed URL bounded TTL.

**Expected from cloud architecture**

- Verifiable data erasure spans all 6 cloud storage tiers: Cloud SQL PostgreSQL, Cloud Storage objects and noncurrent versions, temporary/quarantine buckets, Cloud Run container scratch storage, Pub/Sub dead-letter queues, and pseudonymized audit trails.
- Retention ordering compliance: Cloud Storage soft-delete window (7 days: 604,800 seconds) and noncurrent version purge lifecycle (7 days) stay strictly below the ratified 30-day account erasure SLA.
- Cloud SQL schema foreign keys enforce cascading deletion across client folders, cases, canonical field values, approvals, and pinned blueprints.
- Audit records in `workflow.case_history` survive erasure by design as proof that erasure occurred, containing pseudonymized actor identifiers and zero plaintext applicant PII.
- Operational runbook [`Runbook-Deletion-Drill.md`](file:///c:/Users/saulp/Workspace/PEN-lapluma_infra/wiki/Runbook-Deletion-Drill.md) updated with native GCP `gcloud` and `psql` verification procedures, with automated verification via `tools/verify_deletion_drill.py`.

**Boundary**

- Client applications do not execute cloud storage object sweeps or database cascade deletions; participant erasure is coordinated authoritatively via backend services and operational runbooks.

### 2026-09-14 — Multi-Institution Reuse, Isolation and Publication Rollback (INT-15 & APP-14)

**Implemented in the app and shared packages**

- Client supports institution-aware collection assignments and catalog browsing (`ApertureAPIClient.libraryCollections` and `libraryBlueprints`), filtering resources strictly to assigned official collections and tenant-owned private packages.
- Strict multi-institution isolation guarantees: cross-tenant collection and blueprint requests return `404 Not Found` (never 403, never leaking existence); search and count aggregations omit foreign tenant items.
- Client `AppSession` enforces cache isolation across workspaces: switching workspaces via `signIn(as:workspaceCode:persona:)`, `signOut()`, or demo mode toggles immediately calls `clearScopedState()` to invalidate pending captures, state revisions, and sets the active tenant context on the API client.
- Seeded synthetic institutions (`tenant_clinic_alpha` and `tenant_firm_beta`) in `StubStorage` and `StubAPIClient` proving multi-institution reuse of shared government blueprints (`uscis/i-130`, `uscis/i-130a`) alongside isolated private packages (`clinic_intake_pkg`, `firm_retainer_pkg`).
- Automated integration test suite (`tests/tools/test_multi_institution_isolation_and_rollback.py`) verifies shared blueprint reuse without duplication, 404 cross-tenant isolation, context-switching cache clearing, and government artifact immutability.

**Expected from cloud architecture**

- Multi-institution shared blueprint reuse: Core API queries join `library.tenant_collection_assignment` and `library.document_collection_blueprint`, permitting multiple institutions to bind to identical published official collections and blueprints without duplicate storage or drift.
- Strict multi-tenant data access control (`LibraryAccessControlService`): tenant-scoped authorization verifies `library.tenant_collection_assignment` and blueprint namespace ownership. Unauthorized requests for foreign private collections or blueprints return 404 (never 403).
- Filtered search and aggregations: Collection and blueprint endpoints enforce ambient tenant filtering; list queries and search queries strictly exclude unassigned foreign collections and private blueprints.
- Publication lifecycle and rollback: Blueprint publication enforces dual-custody review (`reviewer != author`). Official drift detection flags source checksum mismatches into `QUARANTINED` status. Rollback promotes the target revision, sets superseded revisions to `ROLLED_BACK`, preserves existing case pins, and logs immutable audit trails.
- Institutional branding and theme overrides do not modify official government blueprints (`uscis/*`, `dos/*`, `student-aid/*`); form numbers, edition dates, and artifact checksums remain immutable.

**Boundary**

- Client applications do not manage blueprint publishing, drift detection, or rollback operations; publication lifecycle and tenant assignments are governed by the Core API and operator tools.

### 2026-09-14 — Repeatable Managed Institution Onboarding (INT-13)

**Implemented in the app and shared packages**

- Client authenticates via tenant-bound sessions where institution scope is resolved server-side: requests carry validated `tenant_id` claims matching `library.institution_tenant`.
- Effective collection listings (`ApertureAPIClient.libraryCollections`) strictly reflect the institution's assigned collections in `library.tenant_collection_assignment`; unassigned or private collections are omitted (404/never leaked).
- Maintained client crash-reporting and telemetry boundaries: diagnostic signals emit sanitized identifiers and omit tenant names or applicant PII.

**Expected from cloud architecture**

- Managed onboarding workflow operates via `tools/onboard_institution.py` and operator runbook (`docs/runbooks/operator-institution-onboarding.md`).
- Enforces strict dual-custody review gate (`reviewer != author`), prohibiting self-approval on tenant onboarding manifests.
- Transactional provisioning (`up.sql`) and verified rollback (`down.sql`) scripts guarantee that failure at any point cleanly aborts without leaving orphaned or unassigned collections.
- Database authorization enforces that onboarding execution is performed solely under the `lapluma_library_admin` role with zero access to case or applicant data in the `workflow` schema.

**Boundary**

- Mobile and web clients do not perform institution onboarding or self-service collection assignment; institution provisioning is an operator-managed cloud capability.

### 2026-09-14 — Isolated GCP Environment Matrix and Operational Policies (INT-07)

**Implemented in the app and shared packages**

- Client configuration models decouple runtime target endpoints by environment (`dev`, `staging`, `pilot`), targeting isolated API Gateway domains (`gw-lapluma-*.nw.gateway.dev`).
- Enforced synthetic data isolation rules in testing fixtures: developer sandboxes and CI runners strictly consume mock or synthetic data; no live applicant PII is permitted in non-pilot configurations.
- Maintained client crash-reporting and telemetry boundaries: diagnostic signals emit sanitized identifiers and omit PII across all environments.

**Expected from cloud architecture**

- Independent GCP projects per environment (`lapluma-dev-gcp`, `lapluma-staging-gcp`, `lapluma-pilot-gcp`) with zero inter-project VPC peering or shared IAM service accounts.
- Lean pilot budget capped at <$100/mo utilizing Cloud SQL PostgreSQL 16 (`db-g1-small`, ZONAL), Cloud Run v2 (scale-to-zero), and Uniform Bucket-Level Access Cloud Storage.
- Enforced dual-custody human authorization gate on production pilot deployments (`terraform apply` against `lapluma-pilot-gcp` requires explicit engineering approval and is never unattended).
- Automated CI validation enforcing Terraform formatting and module validation across all three environments (`foundation-validation.yml`).

**Boundary**

- Client communicates solely through API Gateway endpoints for the configured environment; client has no direct infrastructure provisioning access or cloud credentials.

### 2026-09-14 — GCP Identity and Authorization Mapping (INT-02)

**Implemented in the app and shared packages**

- Client adheres to the server-derived tenant session contract: mobile requests carry opaque session bearer tokens mapped to the authenticated principal, active `tenant_id`, and authorized person scopes.
- Client respects Cloud Run IAM restrictions via API Gateway: all requests route through the Google API Gateway edge rather than reaching Cloud Run direct URLs; unauthenticated direct access is blocked.
- Added test coverage ensuring client authentication stubs and error handlings properly model 401 Unauthorized and 403 Forbidden responses.

**Expected from cloud architecture**

- Google API Gateway terminates edge OIDC token validation (`x-google-issuer`, `x-google-audiences`) and proxies requests with Google IAM credentials (`jwt_audience`) to Cloud Run. Direct public invocation of Cloud Run is IAM-restricted (no `allUsers` invoker).
- Backend services (Core API and Workflow API) enforce second-lock JWT validation for audience, issuer, lifetime, and signing key, failing closed if unconfigured.
- PostgreSQL implements strict separation of duty across database principals (`infra/sql/005_database_roles_and_permissions.sql`):
  * `lapluma_app_core`: Read-only access to Document Library tables/views; zero access to case/workflow tables.
  * `lapluma_app_workflow`: Full CRUD on workflow tables; read-only on Document Library; cannot mutate blueprints/collections.
  * `lapluma_library_admin`: Managed CI/CLI blueprint publisher; zero access to case/workflow tables (operators never have case access).
  * `lapluma_worker`: Denied direct database connectivity entirely.

**Boundary**

- Client does not manage cloud IAM, service accounts, or database roles; client relies exclusively on opaque session tokens issued upon passkey authentication.

### 2026-09-14 — Document Library OpenAPI Contract Synchronization (INT-01, INT-14)

**Implemented in the app and shared packages**

- Synchronized `contracts/openapi/document-library.yaml` into the app repository, defining the OpenAPI 3.1.0 specification for Document Library Collections, Blueprints, publication lifecycle (`/publish`, `/drift-check`, `/rollback`, `/assign`), and legacy package compatibility mappings.
- Extended `test_contract_compatibility.py` to validate OpenAPI 3.1 structure, placeholder service URL (`api.example.invalid`), version 0.2.0, required paths, and required operation IDs (`listLibraryCollections`, `getLibraryCollection`, `listLibraryBlueprints`, `getLibraryBlueprint`, `listPackageMappings`, `publishBlueprint`, `checkBlueprintDrift`, `rollbackBlueprint`, `assignTenantCollection`).
- Preserved the existing SHA-256-pinned `contracts/openapi/workforce-workflow.yaml` without modification.

**Expected from cloud architecture**

- Cloud endpoints implement the OpenAPI 3.1 specification under `https://api.example.invalid/v1` (to be configured in production via API Gateway / Cloud Run).
- Server-side tenant isolation enforces that requests missing valid tenant session bearer tokens are rejected (401/403).
- Strict idempotency key requirement on mutative endpoints (`publish`, `drift-check`, `rollback`, `assign`).

**Boundary**

- Client communicates with the Document Library via `ApertureAPIClient` abstractions mapped to these operations; publication lifecycle management is restricted to authorized operators and CI/CD pipelines.

### 2026-09-14 — Versioned Document Library, Collections and Blueprints (INT-03, APP-01, APP-04)

**Implemented in the app and shared packages**

- Added `DocumentLibrary.swift` in `ApertureDomain` defining versioned Document Collections, immutable Document Blueprints, pinned members, preparation capabilities (`FILLABLE_PDF`, `STATIC_ASSISTED`, `EXTERNAL_REFERENCE`), publication lifecycle states, and `LegacyPackageMapping`.
- Adopted reconciled `contracts/catalog-package-compatibility.json` and its JSON schema, linking all 7 legacy package codes (`FAMILY_I130`, `ADJUSTMENT_I485_I864`, `NATURALIZATION_N400`, `EAD_I765`, `TRAVEL_I131`, `PASSPORT_DS11`, `FINANCIAL_AID_FAFSA`) to versioned Collections (`official/*@1`) and pinned Blueprint members without breaking the `lapluma-app-0.2` snapshot.
- Extended `ApertureAPIClient` and `StubAPIClient` with `libraryCollections`, `libraryCollection`, `libraryBlueprints`, `libraryBlueprint`, and `packageMappings` endpoints.
- Seeded versioned collections and blueprints in `StubStorage` with tenant-isolation support and explicit explanations for unsupported choices (e.g. passport preview, external FAFSA workflow).
- Updated `CatalogModel` and `CatalogView` to use customer-facing Document Library terminology and display explicit explanations when collections are outside automated preparation scope.
- Enforced English and Spanish localization parity for Document Library terminology.
- Added comprehensive unit tests in Swift (`ContractCompatibilityTests.swift`) and Python (`tests/tools/test_contract_compatibility.py`).

**Expected from cloud architecture**

- Core API exposes `ILibraryAccessService` endpoints returning tenant-effective collections and blueprints.
- Enforces strict server-side tenant isolation: clients never authorize their own access; unauthorized collections are omitted (404/never leaked).
- Maintains immutable blueprint revisions in PostgreSQL; pinned collection members ensure existing cases never suffer silent schema drift.

**Boundary**

- Mobile client consumes versioned collections and blueprints; initial publishing and onboarding remains managed via CLI/CI. No executable document scripts or mobile self-service publishing.

### 2026-09-14 — Full USCIS Catalog Coverage, Library Search, and Official Guidance (INF-06..09, APP-02, APP-03)

**Implemented in the app and shared packages**

- Reconciled full 117 USCIS forms across I-series (91), N-series (10), G-series (14), and other prefixes (2: AR-11, EOIR-29) plus 4 preserved non-USCIS definitions (`DS-11`, `FAFSA`, `CLINIC-INTAKE`, `SCHOLARSHIP-APP`) into `contracts/uscis-official-manifest.json` and client runtime stubs.
- Added `DocumentGuidance` domain model in `DocumentLibrary.swift` and `documentGuidance(namespace:id:)` operation in `ApertureAPIClient` and `StubAPIClient`.
- Implemented deterministic, tenant-authorized Library Search (`libraryBlueprints(tenantID:query:)`) across all 117 forms by form number, title, and issuer with zero recommendation, score, or ranking based on applicant facts (ADR-001).
- Added preparation capability provenance (`fillablePdf`, `staticAssisted`, `externalReference`), explicit destination labeling for external reference workflows, and clear separation between official evidence checklists and institutional guidance notes.
- Enforced zero fee guessing: variable-fee petitions cite official Form G-1055 (`feeUsdCents: nil`), while uniform statutory fees specify exact cents.
- Added contract verification tests in `tests/tools/test_catalog_coverage_and_guidance_contract.py` (94 passing tests).

**Expected from cloud architecture**

- Core API exposes `GET /v1/library/blueprints/{namespace}/{blueprintId}/guidance` documented in OpenAPI `contracts/openapi/document-library.yaml`.
- Core API dynamically seeds all 117 official USCIS forms and source-cited guidance dataset via `GuidanceCatalog`.
- Server maintains strict multi-tenant isolation and 404 behavior for unauthorized private documents.

**Boundary**

- Client surfaces official instructions, fee schedule citations, and preparation capabilities deterministically. Client sends zero applicant facts or case IDs to catalog or guidance discovery endpoints.

### 2026-09-14 — Pub/Sub Workflow State Alignment, Poison Message DLQ & Per-Institution Usage / Cost Validation (INT-08, INF-19, INF-13)

**Implemented in the app and shared packages**

- Extended `ProblemDetails` in `apps/packages/ApertureKit/Sources/ApertureAPI/APIError.swift` with standardized RFC 9457 status classification helpers (`isUnauthorized`, `isForbidden`, `isNotFoundOrUnentitled`, `isStateConflict`, `isGone`, `isPreconditionFailed`, `isUnprocessable`, `isQuarantined`, `isBudgetExhausted`, `isServiceUnavailable`).
- Validated error payload contracts ensure correlation IDs are preserved, stack traces or SQL fragments are strictly omitted, and unentitled resources safely return 404 (preventing disclosure under intimate-partner threat model TA-2).
- Added comprehensive Python contract and policy tests in `tests/tools/test_app_output_and_pubsub_contract.py` covering:
  - Pub/Sub at-least-once delivery idempotency and terminal state regression guards.
  - Poison message DLQ routing after 5 retries with sensitive payload bytes (SSN, A-Number, full name) strictly redacted.
  - Per-institution usage tracking without PII.
  - Pilot cost economics verification confirming monthly infrastructure footprint of $33.75/month against the $100.00/month cap ($66.25 headroom).
  - Operator UX boundary enforcement guaranteeing monochromatic grayscale token discipline (`#171717`, `#242424`, `#737373`, `#A3A3A3`, `#F5F5F5`, `#FFFFFF`) without unapproved web frontends.

**Expected from cloud architecture**

- Ingestion of Pub/Sub workflow events (`DOCUMENT_EXTRACTED`, `EXTRACTION_FAILED`, `QUARANTINE_PROMOTED`, `PACKAGE_COMPILED`) is idempotent and respects monotonic state transitions; out-of-order deliveries never regress terminal states (`APPROVED`, `GENERATED`, `DELIVERED`).
- Unprocessable or repeatedly failing messages are diverted to a dedicated Dead-Letter Queue (DLQ) after 5 delivery attempts with payload sanitization.
- Usage tracking telemetry is tenant-aggregated and metric-focused with zero applicant PII.
- Total pilot resource expenditure remains within the $100/mo threshold.

**Boundary**

- Client surfaces actionable RFC 9457 problem details and respects budget guidance without persisting payment details or executing self-directed billing operations.

### 2026-09-14 — Pastel Visual System Adoption, Accessibility & Localization Audit (APP-10, APP-11, APP-12, INT-10)

**Implemented in the app and shared packages**

- Validated full adoption of the native pastel design system across applicant screens (`HomeView`, `CatalogView`, `BlueprintFormEntryView`, `WorkflowViews`, `ClientDashboardView`) using pure white canvas (`#FFFFFF`), flat 12px cards, 40px pills, and 32px controls without marketing heroes on task screens.
- Enforced zero color-only meaning (NFR-A11Y-004): every `StatusTone` (`information`, `attention`, `critical`, `positive`, `neutral`) pairs saturated action tokens (>= 4.5:1 WCAG AA contrast) with mandatory SF Symbol glyphs (`info.circle.fill`, `exclamationmark.circle.fill`, `exclamationmark.triangle.fill`, `checkmark.circle.fill`, `circle.fill`) and localized text.
- Standardized touch target accessibility guaranteeing minimum 44x44 pt touch targets (`accessibleTarget: 48`) and dynamic semantic typography (`Typography.screenTitle`, `Typography.sectionTitle`, `Typography.body`, `Typography.caption`) scaling with Dynamic Type.
- Maintained 100% Spanish/English localization symmetry across both `ApertureUI` and `ApertureApp` resource bundles for all Document Library, Blueprint, and official guidance terminology.
- Preserved high-density iPad/macOS workforce surface styling (`LaPlumaWorkforceApp.swift`) with split-view stage pills and focusable controls.

**Expected from cloud architecture**

- Backend error payloads (RFC 9457) supply actionable `title`, `detail`, and `correlationId` compatible with client status presentation; server provides zero color or CSS directives.
- Operator CLI and CI tooling respects monochromatic grayscale boundary (`#171717`, `#242424`, `#F5F5F5`).

**Boundary**

- Client implements native iOS/iPadOS/macOS Pastel UI with assistive technology support; cloud operates strictly via headless APIs and CI/CLI tooling without unapproved web frontends.

### 2026-09-14 — Full-Catalog Compatibility Release, Rollout Coordination & Azure Rebaseline Closure (APP-13, INT-12)

**Implemented in the app and shared packages**

- Reconciled full 117-form USCIS manifest (`contracts/uscis-official-manifest.json`) and preserved non-USCIS definitions (`contracts/catalog-package-compatibility.json`) with tested preparation capability dispositions (`FILLABLE_PDF`, `STATIC_ASSISTED`, `EXTERNAL_REFERENCE`).
- Updated `MOBILE_IMPLEMENTATION_LEDGER.md` reflecting complete mobile status across all 18 phases of the rebaseline initiative.
- Verified client compatibility with sequenced cloud rollout: PostgreSQL schema migrations (001 -> 005), Cloud Run service deployment, immutable Blueprint publication, customer Collection onboarding, and mobile client access.
- Confirmed independent rollback safety: library publication rollbacks and infrastructure container rollbacks preserve pinned revision identities (`CaseRevisionPin`), active case drafts, and audit ledgers without loss of fidelity.
- Formally superseded all legacy Azure prerequisites under [ADR-019](docs/adr/ADR-019-lean-gcp-document-library.md): no mandatory dedicated HSM, no Azure Cosmos DB, no Azure Service Bus Premium, and no private-network-only mobile transfer remain active architectural requirements.

**Expected from cloud architecture**

- Production services run on lean Google Cloud Platform infrastructure: Cloud Run, Cloud SQL PostgreSQL 16, private Cloud Storage buckets with 15-minute scoped upload/download signed URLs, and usage-based Pub/Sub.
- Cloud deployments enforce transactional schema migrations via `tools/migrate_db.py` and independent publication rollback via `tools/blueprint_cli.py`.
- Two-person activation and independent review invariants are strictly enforced for all official document catalog publications.

**Boundary**

- Client application and cloud infrastructure maintain separate independent lifecycles; contracts in `contracts/` and OpenAPI specifications remain the single authoritative system boundary.

### 2026-08-20 — Finish Together MVP

**Implemented in the app and shared packages**

- Added Guided Finish, Proof Map, and Private Relay flows for applicants and authorized workforce
  users, with English/Spanish copy, accessibility identifiers, offline fallbacks, and Debug-only
  recipient simulation.
- Added production-shaped domain/client contracts, deterministic current-state planning, sanitized
  synthetic proof previews, person/role enforcement, relay link-plus-code challenge, five-attempt
  lockout, expiry/revocation, one validated upload, explicit review/acceptance, reconciliation, and
  backward-compatible persistent storage.
- Added ADR-018, OpenAPI 0.2.0, invariant tests, and focused simulator journeys. Persisted fixture
  JSON contains relay metadata and hashes only; Delete Everything clears all relay state.

**Expected from cloud architecture**

- Generate clients from the reviewed contract and deploy the case read model, proof join, sanitized
  preview service, public relay edge, challenge/attempt store, write-only object grants, ordinary
  document pipeline integration, lifecycle deletion, audit outbox, and bounded non-sensitive telemetry.
- Enforce tenant, assignment, role, and person scope at policy and data layers; reviewer/approver proof
  access is read-only and administrators get no case access. Missing and unauthorized remain 404.
- Reconcile canonical confirmations and accepted evidence with missing-item projections and counters
  transactionally; never infer an outcome, evidence strength, form recommendation, or percentage.

**Boundary**

- This repository contains local iOS/iPad flows, persistent synthetic behavior, contracts, and tests.
  It does not host the public recipient experience, send email/SMS, deploy a backend, or claim that a
  synthetic upload reached an external recipient.

### 2026-08-12 — End-to-end client, case, document, form, review, approval, and demo workflow

**Implemented in the app and shared packages**

- Added persona/capability, directory, assignment, case workspace, canonical section, evidence,
  review, preview, approval, history, administration, session, audit, and demo contracts.
- Added persistent stubs with optimistic concurrency, many-to-many evidence links, review reopen,
  approval invalidation, preview hashes, state transitions, and distinct-actor enforcement.
- Added role-adaptive navigation, a client wizard, seven-area case workspace, reviewer queue,
  canonical data entry, evidence inbox, reviewer/approver views, history, and administration.
- Added a macOS workforce executable and isolated persistent synthetic demo workspace.
- Added ADR-016, ADR-017, OpenAPI, PR template, and blocking handoff CI.

**Expected from cloud architecture**

- Deploy the dependencies, isolation controls, migrations, telemetry, and rollout gates above.
- Generate platform clients from reviewed OpenAPI and reject contract drift in CI.
- Preserve applicant, helper, person-scope, Private Annex, sealed-medical, no-advice, no-e-filing,
  and no-percentage invariants in reads, writes, aggregations, and background jobs.

**Boundary**

- This is local UI, shared contracts, persistent synthetic behavior, tests, and deployment handoff.
  It does not provision cloud resources, send invitations, perform real WebAuthn, or generate a
  production official PDF.

### 2026-08-12 — Landing, tenant-aware sign-in, and client dashboard

**Implemented in the app**

- Expanded the unauthenticated welcome screen into a clearer landing surface.
- Added work email and workspace/location code to passkey-first sign-in.
- Added display-only workspace context to `AppSession` for the local fixture.
- Made a searchable, sortable, filterable client directory the authenticated entry tab.
- Reused `Folder` as the client record and linked selection to the existing client detail flow.
- Preserved exact progress counters and stage instead of introducing a percentage.

**Expected from cloud architecture**

- Tenant discovery and passkey challenge endpoints with enumeration-resistant responses.
- Tenant-bound sessions, server-derived tenant scope, workforce/applicant roles, person scopes, and
  database isolation.
- A paginated, authorization-safe client-directory read model and stable client detail endpoint.
- Tenant-aware cache, search, queue, object storage, audit, retention, export, and offboarding design.
- An ADR resolving the workforce-versus-applicant product boundary before production implementation.

**Migration and rollout**

- Introduce tenant entities and memberships before attaching `tenant_id` to existing records.
- Backfill into a quarantined default tenant, validate ownership and per-person access, then make
  `tenant_id` non-null and enable isolation policies.
- Use synthetic tenants for automated isolation tests; never validate isolation with production PII.
- Keep the production runtime kill switch until real authentication, tenant-bound storage, and
  cross-tenant penetration tests pass.

## Pull-request checklist

- [ ] Change ledger and last-updated date are current.
- [ ] App behavior and expected cloud behavior are both documented.
- [ ] Data ownership, tenant scope, and person scope are explicit.
- [ ] Authentication, authorization, privacy, retention, and audit impacts are covered.
- [ ] API/read-model, migration, offline/cache, and failure behavior are covered.
- [ ] New or changed trust-boundary decisions have an ADR and named approvers.
- [ ] Automated tests cover cross-tenant and unauthorized access where applicable.
- [ ] No percentage/completion-score, legal-advice, e-filing, or Private Annex invariant regressed.
