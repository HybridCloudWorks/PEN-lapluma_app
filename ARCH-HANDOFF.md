# Architecture Handoff

**Status:** Mandatory living document
**Owner:** Delivery team; reviewed by the architecture and security teams
**Last updated:** 2026-08-28

## Working agreement

Every feature or behavior change must update this file in the same pull request. The author must:

1. add or amend an entry in the change ledger;
2. explain the implemented client behavior and the expected cloud behavior;
3. record new data, API, identity, authorization, tenancy, retention, observability, and migration implications;
4. link a new ADR when a decision changes a trust boundary or accepted architecture rule; and
5. leave unresolved decisions explicit rather than encoding them as client assumptions.

A change is not architecture-complete when its UI works but its handoff entry is missing.

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
