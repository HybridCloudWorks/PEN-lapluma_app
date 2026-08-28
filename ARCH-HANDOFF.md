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
