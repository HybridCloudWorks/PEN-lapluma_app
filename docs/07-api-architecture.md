# 07 — API Architecture

**Owner:** Principal Integration Architect · **Contributors:** Lead Backend Architect, Lead Mobile
Architect, Principal Security Architect · **Status:** For ARB approval

---

## 7.1 API principles

| # | Principle | Consequence |
|---|---|---|
| **API-1** | Resource-oriented REST over HTTPS/JSON. Actions that are not CRUD are modelled as sub-resources or explicit action endpoints, never as verbs in a query string | `POST /cases/{id}/approvals`, not `POST /case?action=approve` |
| **API-2** | **Contract first.** OpenAPI 3.1 is the source of truth; server stubs and the Swift client are generated from it. Hand-written clients are not permitted | Drift between doc and behavior is impossible |
| **API-3** | **Every mutation is idempotent.** `Idempotency-Key` is required, enforced at the gateway | Safe retry on a train, in a basement, on 2 bars of signal |
| **API-4** | **Deny by default.** Every endpoint declares its required scope, role, and step-up level in the contract; APIM enforces before the service is reached | No unprotected endpoint can exist |
| **API-5** | **Responses never contain more than the caller is entitled to.** Filtering happens at the data layer, and the shape of the response does not reveal what was filtered | A folder owner's response does not contain a `privateAnnexCount: 3` |
| **API-6** | **Errors are actionable and safe.** RFC 9457 Problem Details with a stable `type`, a localized `title`, and never a stack trace, a SQL fragment, or another user's data | |
| **API-7** | **Pagination, filtering and sorting are uniform** across every collection | Cursor-based, opaque cursors |
| **API-8** | Long-running work returns `202` with an operation resource. **Nothing blocks for more than 5 seconds** | Extraction, generation, bulk operations |
| **API-9** | **Versioned in the path.** Breaking changes mint a new major version; N-2 is supported for at least 12 months | Mobile clients live a long time in the wild |
| **API-10** | **No API returns a value that has not been through its entitlement check on this request.** Caching never bypasses authorization | ETags are per-principal |

---

## 7.2 Gateway and edge policy

```
Client → Front Door (WAF, DDoS, TLS 1.3, geo) → API Management (internal VNet) → Container Apps
```

APIM policies applied to every operation, in order:

| Order | Policy | Behavior |
|---|---|---|
| 1 | `validate-jwt` | Entra token, audience, issuer, signature, expiry, required scope |
| 2 | Data-plane check | Token's `dataPlane` claim must match the region; a US token cannot reach the EU plane |
| 3 | `validate-content` | Request body validated against the OpenAPI schema; unknown properties rejected (not ignored) |
| 4 | Size limits | Body ≤ 1 MB for JSON operations; uploads use a separate SAS path, never the API |
| 5 | Idempotency | `Idempotency-Key` required on POST/PATCH/PUT/DELETE; missing → `400` |
| 6 | Rate limit | Per subscription, per tenant, per user, per IP; separate buckets for AI-invoking operations |
| 7 | Step-up assertion | For flagged operations, the token must carry `acr=stepup` with `auth_time` within 5 minutes |
| 8 | Correlation | `X-Correlation-Id` generated if absent, propagated everywhere |
| 9 | Response validation | Response validated against the schema in non-production; sampled in production |
| 10 | Header hygiene | Strip server/framework headers; add security headers |

**Two policies exist purely to enforce architectural invariants:**
- Any request to `POST /cases/{id}/approvals` from a principal whose token carries `principal_type`
  other than `user` is rejected at the gateway with `403` and raises a Sev-1 security event
  ([AI-2](04-ai-agent-architecture.md#41-design-philosophy)).
- Any request to write a `FieldValue` with `state=HUMAN_CONFIRMED` from a service or agent principal
  is rejected ([AI-1](04-ai-agent-architecture.md#41-design-philosophy)).

---

## 7.3 Versioning strategy

| Aspect | Approach |
|---|---|
| Scheme | `/v1/…` in the path. Major version only |
| Breaking change | New major version. Old version supported ≥ 12 months with a documented sunset date returned in a `Sunset` header |
| Non-breaking | Additive only within a version: new optional fields, new endpoints, new enum values **only where the client contract documents forward-compatible handling** |
| Enum evolution | Clients must treat unknown enum values as `UNKNOWN` and degrade gracefully; this is a generated-client behavior, tested |
| Deprecation | `Deprecation` and `Sunset` headers, plus a `warning` array in the response envelope, plus 90 days' notice |
| Client support | Server supports N-2 client versions. Forced upgrade exists **only** for security-critical releases, with a 30-day grace period and an in-app explanation |
| Internal APIs | Versioned independently; service-to-service contracts are consumer-driven with contract tests in CI |

---

## 7.4 Common conventions

### Request headers
```http
Authorization: Bearer <jwt>
Idempotency-Key: 01JQ8K2M4N5P6R7S8T9VABCDEF     # required on mutations
X-Correlation-Id: 7f3e…                          # optional; generated if absent
Accept-Language: es-MX                           # drives localized titles and messages
X-Client-Version: ios/1.4.2 (18.2; iPhone14,5)
If-Match: "W/\"a1b2c3\""                         # optimistic concurrency on updates
```

### Response envelope — collections
```json
{
  "data": [ … ],
  "pagination": { "nextCursor": "eyJvIjoxMDB9", "hasMore": true, "pageSize": 50 },
  "warnings": []
}
```

Single resources are returned bare (no envelope) with an `ETag`.

### Errors — RFC 9457 Problem Details
```json
{
  "type": "https://api.aperture.app/problems/value-not-confirmed",
  "title": "Some values still need your confirmation",
  "status": 409,
  "detail": "3 required values are still proposed and must be confirmed before this package can be generated.",
  "instance": "/v1/cases/3f2b.../packages",
  "correlationId": "7f3e...",
  "errors": [
    { "field": "person.birth.date", "personId": "7d4e...", "reason": "PROPOSED",
      "resolutionPath": "/v1/cases/3f2b.../values/7d4e.../person.birth.date" }
  ]
}
```

`title` and `detail` are localized per `Accept-Language`. `type` is stable, machine-readable, and
documented. Errors never contain another person's data, a stack trace, or an internal identifier
that is not already known to the caller.

### Status codes used

| Code | Meaning here |
|---|---|
| `200` / `201` / `204` | Standard |
| `202` | Accepted; an operation resource is returned in `Location` |
| `400` | Schema violation, missing idempotency key |
| `401` | Missing/invalid token |
| `403` | Authorized principal, insufficient entitlement — **including the two architectural invariants** |
| `404` | Not found **or not entitled** (we do not distinguish; existence is itself information) |
| `409` | State conflict (unconfirmed values, invalidated approval, ETag mismatch) |
| `410` | Sunset version, or a revoked delivery link |
| `422` | Semantically invalid (e.g. a value failing a form's format rule) |
| `423` | Locked (case quarantined by form drift) |
| `429` | Rate or budget limit; `Retry-After` and a `budget` object are returned |
| `451` | Withheld for legal reasons |
| `503` | Dependency unavailable; `Retry-After` supplied |

Note `404` for unentitled resources: returning `403` would confirm that a folder exists, which in
the TA-2 threat model is itself a disclosure.

---

## 7.5 Authentication APIs

Credential handling is delegated to Microsoft Entra External ID; these endpoints manage the
platform's own session and consent semantics around it.

```http
POST /v1/auth/passkey/registration/options
POST /v1/auth/passkey/registration
POST /v1/auth/passkey/assertion/options
POST /v1/auth/passkey/assertion
POST /v1/auth/otp/request
POST /v1/auth/otp/verify
POST /v1/auth/token/refresh
POST /v1/auth/stepup                 # elevates the current session
GET  /v1/auth/sessions               # user's own active sessions
DELETE /v1/auth/sessions/{sessionId} # remote revocation
POST /v1/auth/recovery/initiate
POST /v1/auth/recovery/complete
POST /v1/auth/logout
```

**`POST /v1/auth/passkey/registration`**
```json
{
  "attestationResponse": { "id": "…", "rawId": "…", "response": { … }, "type": "public-key" },
  "deviceName": "María's iPhone",
  "deviceAttestation": "<App Attest assertion>",
  "acknowledgedNotices": [
    { "noticeType": "NOT_A_LAW_FIRM", "version": "2026.03", "sha256": "…" },
    { "noticeType": "PRIVACY", "version": "2026.03", "sha256": "…" }
  ]
}
```
```json
201 Created
{
  "userId": "u_01JQ8K2M4N5P6R7S8T9V",
  "credentialId": "c_01JQ8K…",
  "recoveryCode": "APER-7F3E-9K2M-4N5P",
  "recoveryCodeNotice": "This is shown once. Store it somewhere safe.",
  "authAssurance": "PASSKEY",
  "consentRecordIds": ["cr_01JQ…", "cr_01JQ…"]
}
```

**`POST /v1/auth/stepup`** — required before approval, export, invitations, role changes, erasure,
and reading `CRITICAL` values.
```json
{ "method": "PASSKEY", "assertionResponse": { … }, "purpose": "APPROVE_PACKAGE",
  "resourceId": "case_3f2b…" }
```
```json
200 OK
{ "stepUpToken": "eyJhbGciOi…", "expiresInSeconds": 300, "purpose": "APPROVE_PACKAGE",
  "boundResourceId": "case_3f2b…" }
```
The step-up token is **bound to a purpose and a resource** — it cannot be minted for one action and
replayed against another.

---

## 7.6 User and consent APIs

```http
GET    /v1/me
PATCH  /v1/me
GET    /v1/me/preferences
PATCH  /v1/me/preferences              # language, reading level, accessibility, notifications
GET    /v1/me/consents
POST   /v1/me/consents                 # grant
DELETE /v1/me/consents/{purpose}       # withdraw
GET    /v1/me/audit                    # own audit trail, plain language
POST   /v1/me/data-export              # 202 → operation
POST   /v1/me/erasure                  # 202 → operation; step-up required
GET    /v1/me/devices
DELETE /v1/me/devices/{deviceId}
```

**`GET /v1/me/consents`**
```json
{
  "data": [
    { "purpose": "SERVICE_TERMS", "granted": true, "noticeVersion": "2026.03",
      "grantedAtUtc": "2026-06-14T18:22:03Z", "withdrawable": false,
      "withdrawalConsequence": "Withdrawing ends your account." },
    { "purpose": "VOICE_RECORDING", "granted": true, "noticeVersion": "2026.03",
      "grantedAtUtc": "2026-07-02T14:10:55Z", "modality": "BOTH",
      "jurisdictionBasis": "ALL_PARTY_CONSENT_STATE", "withdrawable": true,
      "withdrawalConsequence": "Voice interviews stop. Chat interviews continue." },
    { "purpose": "VOICE_CLIP_RETENTION", "granted": false, "withdrawable": true },
    { "purpose": "ANALYTICS", "granted": false, "withdrawable": true,
      "withdrawalConsequence": "None. The product works identically." }
  ]
}
```

Every consent carries its **consequence of withdrawal** in plain language. Analytics defaults to
`false` and says so.

**`POST /v1/me/erasure`**
```json
{ "scope": "ALL", "reason": "USER_REQUEST", "confirmationPhrase": "DELETE MY DATA" }
```
```json
202 Accepted
Location: /v1/operations/op_01JQ8K…
{
  "operationId": "op_01JQ8K…",
  "estimatedCompletionUtc": "2026-08-31T00:00:00Z",
  "retainedExceptions": [
    { "type": "CONSENT_RECORDS", "reason": "Proving we had your permission", "retentionYears": 7 },
    { "type": "AUDIT_METADATA", "reason": "Identifiers and timestamps only — no content", "retentionYears": 7 }
  ],
  "backupStatement": "Your data is removed from our live systems within 30 days and expires from encrypted backups within 12 months.",
  "cryptoShredAvailable": false
}
```
The response enumerates exactly what survives and tells the truth about backups
([05 §5.11](05-data-architecture.md#511-retention-and-lifecycle)).

---

## 7.7 Folder, person and membership APIs

```http
GET    /v1/folders
POST   /v1/folders
GET    /v1/folders/{folderId}
PATCH  /v1/folders/{folderId}
DELETE /v1/folders/{folderId}

GET    /v1/folders/{folderId}/persons
POST   /v1/folders/{folderId}/persons
GET    /v1/folders/{folderId}/persons/{personId}
PATCH  /v1/folders/{folderId}/persons/{personId}
POST   /v1/folders/{folderId}/persons/{personId}/invite      # adult only; step-up
POST   /v1/folders/{folderId}/persons/{personId}/quiet-exit  # self only

GET    /v1/folders/{folderId}/relationships
POST   /v1/folders/{folderId}/relationships
DELETE /v1/folders/{folderId}/relationships/{relationshipId}

GET    /v1/folders/{folderId}/memberships
POST   /v1/folders/{folderId}/memberships                    # step-up
PATCH  /v1/folders/{folderId}/memberships/{membershipId}
DELETE /v1/folders/{folderId}/memberships/{membershipId}

GET    /v1/me/private-annex                                  # ONLY the owner can call this
POST   /v1/me/private-annex/items
DELETE /v1/me/private-annex/items/{itemId}
```

**`POST /v1/folders/{folderId}/memberships`** — granting a Helper
```json
{
  "userEmail": "jorge@example.com",
  "memberRole": "HELPER",
  "scopedPersonIds": ["p_7d4e…"],
  "scopedSections": ["DOCUMENTS", "BASIC_INFO"],
  "canAnswerOnBehalf": true,
  "expiresAtUtc": "2026-12-31T00:00:00Z"
}
```
```json
201 Created
{
  "membershipId": "m_01JQ8K…",
  "memberRole": "HELPER",
  "scopedPersonIds": ["p_7d4e…"],
  "scopedSections": ["DOCUMENTS", "BASIC_INFO"],
  "canAnswerOnBehalf": true,
  "invitationSent": true,
  "notice": "Jorge will see a banner showing whose case he is helping with. Every answer he gives will be recorded as given by him on your behalf."
}
```

**`POST /v1/folders/{folderId}/persons/{personId}/quiet-exit`** — the safety endpoint
```json
{ "erasePrivateAnnex": true, "confirmationPhrase": "END MY PARTICIPATION" }
```
```json
200 OK
{
  "participationState": "INACTIVE",
  "privateAnnexErasureOperationId": "op_01JQ8K…",
  "notificationsGenerated": 0,
  "visibleToOthersAs": "Participant no longer active",
  "reasonDisclosed": false
}
```
`notificationsGenerated: 0` is contractual, not incidental. A test asserts that no notification row
exists for any other member after this call
([C-05](00-design-authority-record.md#c-05--a-household-folder-is-not-a-single-trust-boundary)).

**`GET /v1/folders/{folderId}` — response shape for a folder owner**
```json
{
  "folderId": "f_3f2b…",
  "name": "Familia Ramírez",
  "status": "ACTIVE",
  "persons": [
    { "personId": "p_5a1c…", "displayLabel": "María R.", "isMinor": false,
      "participationState": "ACTIVE", "holdsOwnCredential": true },
    { "personId": "p_7d4e…", "displayLabel": "Carlos R.", "isMinor": false,
      "participationState": "ACTIVE", "holdsOwnCredential": true }
  ],
  "cases": [ { "caseId": "c_9b2f…", "packageCode": "FAMILY_I130", "state": "COLLECTING" } ],
  "documentCount": 14,
  "_etag": "W/\"a1b2c3\""
}
```
Note what is absent: **no private-annex count, no private-annex placeholder, nothing**. The response
for a folder containing three annex items is byte-identical to one containing none
([API-5](#71-api-principles)).

---

## 7.8 Form catalog APIs

```http
GET  /v1/catalog/agencies
GET  /v1/catalog/forms
GET  /v1/catalog/forms/{formNumber}
GET  /v1/catalog/forms/{formNumber}/versions
GET  /v1/catalog/packages                       # curated multi-form packages
GET  /v1/catalog/packages/{packageCode}
GET  /v1/catalog/packages/{packageCode}/requirements
```

**`GET /v1/catalog/packages?q=spouse`** — the search that must not personalize
```json
{
  "data": [
    {
      "packageCode": "FAMILY_I130",
      "title": "Petition for Alien Relative",
      "agency": "USCIS",
      "agencyCategoryLabel": "Family-based petitions",
      "forms": [
        { "formNumber": "I-130", "editionDate": "2025-11-04", "encoding": "ACROFORM",
          "fillMode": "ACROFORM_FILLED" },
        { "formNumber": "I-130A", "editionDate": "2025-11-04", "encoding": "ACROFORM",
          "fillMode": "ACROFORM_FILLED" }
      ],
      "feeUsdCents": 67500,
      "feeCitationUrl": "https://…",
      "sourceUrl": "https://…",
      "lastVerifiedUtc": "2026-07-31T04:12:00Z"
    }
  ],
  "pagination": { "hasMore": false },
  "notice": "This catalog is identical for everyone. We do not recommend forms and we cannot tell you which one applies to you. If you need help deciding, see the directory of nonprofit legal providers."
}
```
The catalog endpoint **takes no principal-specific input beyond locale** and its response is
independent of any case data. This is the API-level expression of
[C-01](00-design-authority-record.md#c-01--form-discovery-agent-as-briefed-is-unauthorized-practice-of-law):
personalization is impossible because the personalizing input is not accepted.

**`GET /v1/catalog/packages/FAMILY_I130/requirements`**
```json
{
  "packageCode": "FAMILY_I130",
  "pinnedEditions": [ { "formNumber": "I-130", "editionDate": "2025-11-04",
                        "sourceSha256": "9f2c…" } ],
  "fields": [
    { "canonicalPath": "person.name.family", "personRole": "PETITIONER", "required": true,
      "formRefs": [ { "formNumber": "I-130", "partLabel": "Part 1, Item 1.a", "maxLength": 40 } ] }
  ],
  "evidence": [
    { "code": "PROOF_OF_STATUS", "personRole": "PETITIONER", "required": true,
      "conditional": false,
      "description": "Evidence of your U.S. citizenship or lawful permanent resident status",
      "citation": { "sourceUrl": "https://…", "documentTitle": "Instructions for Form I-130",
                    "sectionRef": "What Evidence Must You Submit", "revisionDate": "2025-11-04",
                    "retrievedAtUtc": "2026-07-31T04:12:00Z" } },
    { "code": "PRIOR_MARRIAGE_TERMINATION", "personRole": "BOTH", "required": true,
      "conditional": true,
      "conditionText": "If you or your spouse were previously married, submit copies of documents showing that all prior marriages were legally terminated.",
      "description": "Documents terminating any prior marriage",
      "citation": { … } }
  ]
}
```
`conditionText` is the agency's own language, verbatim. We do not resolve the condition for the user
and we do not paraphrase it.

---

## 7.9 Case APIs

```http
GET    /v1/cases
POST   /v1/cases
GET    /v1/cases/{caseId}
PATCH  /v1/cases/{caseId}
DELETE /v1/cases/{caseId}
GET    /v1/cases/{caseId}/progress
GET    /v1/cases/{caseId}/missing-items
GET    /v1/cases/{caseId}/discrepancies
POST   /v1/cases/{caseId}/discrepancies/{id}/resolve
GET    /v1/cases/{caseId}/values
GET    /v1/cases/{caseId}/values/{personId}/{canonicalPath}
PUT    /v1/cases/{caseId}/values/{personId}/{canonicalPath}
POST   /v1/cases/{caseId}/values/confirm            # batch confirm
POST   /v1/cases/{caseId}/validate                  # 202
POST   /v1/cases/{caseId}/form-drift/migrate        # accept migration to a new edition
```

**`POST /v1/cases`**
```json
{
  "folderId": "f_3f2b…",
  "packageCode": "FAMILY_I130",
  "personRoleAssignments": [
    { "personId": "p_5a1c…", "role": "PETITIONER" },
    { "personId": "p_7d4e…", "role": "BENEFICIARY" }
  ],
  "selectionAttestation": {
    "attested": true,
    "attestationVersion": "2026.03",
    "text": "I chose this form package myself, or my legal representative chose it for me. Aperture did not choose it for me and cannot tell me whether it is right for my situation."
  }
}
```
```json
201 Created
{
  "caseId": "c_9b2f…",
  "state": "DRAFT",
  "pinnedForms": [
    { "formVersionId": "fv_2a…", "formNumber": "I-130", "editionDate": "2025-11-04",
      "sourceSha256": "9f2c…", "pinnedAtUtc": "2026-08-01T09:14:22Z" }
  ],
  "collectionPlan": { "estimatedFields": 218, "estimatedDocuments": 11,
                      "orderedSteps": [ … ] }
}
```
`selectionAttestation` is **required** — a case cannot be created without a human attesting they
chose the package.

**`GET /v1/cases/{caseId}/progress`** — the endpoint that must not lie
```json
{
  "caseId": "c_9b2f…",
  "state": "COLLECTING",
  "counters": {
    "fieldsFilled": 174,
    "fieldsRequired": 218,
    "documentsCollected": 7,
    "documentsRequired": 11
  },
  "blockingItems": 6,
  "advisoryItems": 3,
  "readinessStatement": "6 required items still need your attention.",
  "disclaimer": "These counters show how much of the paperwork is filled in. They are not a prediction of any decision by any government agency."
}
```
There is **no `percentComplete` field in the schema**. It was removed deliberately
([C-20](00-design-authority-record.md#c-20--the-completion-percentage-will-be-read-as-a-prediction)),
and a contract test asserts that no response body anywhere in the API contains a key matching
`/percent|complete(ness)?Score/i`.

**`GET /v1/cases/{caseId}/values/{personId}/person.birth.date`** — provenance on every value
```json
{
  "canonicalPath": "person.birth.date",
  "personId": "p_7d4e…",
  "value": "1979-03-14",
  "valueState": "PROPOSED",
  "confidenceBand": "NEEDS_REVIEW",
  "confidenceExplanation": "Two of your documents disagree about this date. Please tell us which is right.",
  "origin": { "type": "EXTRACTION", "originRefId": "ev_4c1a…" },
  "provenance": {
    "documentId": "d_8e2b…",
    "documentName": "Passport (Guatemala)",
    "pageNumber": 2,
    "boundingPolygon": [[0.14,0.31],[0.48,0.31],[0.48,0.35],[0.14,0.35]],
    "engine": "azure-document-intelligence",
    "engineVersion": "prebuilt-idDocument@2024-11-30",
    "rawConfidence": 0.9412,
    "checksumValid": true,
    "normalizationNote": "Source format DD/MM/YYYY; normalized to ISO-8601."
  },
  "discrepancy": {
    "discrepancyId": "disc_1f9c…",
    "type": "DATE_CONFLICT",
    "severity": "BLOCKING",
    "alternative": { "value": "1979-04-13", "documentId": "d_2c7f…",
                     "documentName": "Birth certificate", "pageNumber": 1, "rawConfidence": 0.8871 }
  },
  "formRefs": [ { "formNumber": "I-130", "partLabel": "Part 2, Item 8" } ],
  "_etag": "W/\"9f1a\""
}
```

**`POST /v1/cases/{caseId}/values/confirm`** — the human-in-the-loop endpoint
```json
{
  "confirmations": [
    { "personId": "p_7d4e…", "canonicalPath": "person.birth.date", "value": "1979-03-14",
      "etag": "W/\"9f1a\"", "resolvesDiscrepancyId": "disc_1f9c…" },
    { "personId": "p_7d4e…", "canonicalPath": "person.name.family", "value": "Ramírez",
      "etag": "W/\"3b2e\"" }
  ],
  "confirmedOnBehalfOfPersonId": null
}
```
```json
200 OK
{
  "confirmed": 2, "rejected": 0,
  "results": [
    { "canonicalPath": "person.birth.date", "valueState": "HUMAN_CONFIRMED",
      "confirmedByUserId": "u_01JQ…", "confirmedAtUtc": "2026-08-01T11:02:31Z" },
    { "canonicalPath": "person.name.family", "valueState": "HUMAN_CONFIRMED", … }
  ],
  "progressDelta": { "fieldsFilled": 176 },
  "unlockedItems": ["mi_0143"]
}
```

**`GET /v1/cases/{caseId}/missing-items`**
```json
{
  "data": [
    {
      "missingItemId": "mi_0141",
      "kind": "EVIDENCE",
      "severity": "BLOCKING",
      "assignedPersonId": "p_5a1c…",
      "assignedPersonLabel": "María R.",
      "title": "Proof of your U.S. citizenship or permanent resident status",
      "whyRequired": "Form I-130 instructions require this from the petitioner.",
      "citation": { "sourceUrl": "https://…", "sectionRef": "What Evidence Must You Submit",
                    "revisionDate": "2025-11-04" },
      "resolutionPaths": [
        { "type": "SCAN", "label": "Take a photo of your green card or certificate" },
        { "type": "IMPORT", "label": "Choose a file you already have" }
      ],
      "batchId": "mi_batch_017",
      "ageDays": 4
    }
  ],
  "batches": [
    { "batchId": "mi_batch_017", "itemCount": 5, "estimatedMinutes": 6,
      "supportedModalities": ["CHAT", "VOICE", "FORM"] }
  ]
}
```

---

## 7.10 Document APIs

Uploads never traverse the API. The API mints a scoped SAS; the client writes directly to blob
storage; the client then notifies completion.

```http
POST   /v1/documents/upload-sessions
PUT    <sasUrl>                                     # direct to Blob, not our API
POST   /v1/documents/upload-sessions/{sessionId}/complete
GET    /v1/documents/{documentId}
PATCH  /v1/documents/{documentId}                   # reclassify (human override)
DELETE /v1/documents/{documentId}
GET    /v1/documents/{documentId}/preview           # server-rasterized
GET    /v1/documents/{documentId}/download-url      # short-lived read SAS
GET    /v1/documents/{documentId}/extractions
POST   /v1/documents/{documentId}/reprocess
GET    /v1/folders/{folderId}/documents
```

**`POST /v1/documents/upload-sessions`**
```json
{
  "folderId": "f_3f2b…",
  "subjectPersonId": "p_7d4e…",
  "isPrivateAnnex": false,
  "originalName": "passport.heic",
  "declaredMimeType": "image/heic",
  "sizeBytes": 3841204,
  "sha256": "b7e1…",
  "sourceChannel": "CAMERA",
  "captureQuality": { "blurScore": 0.08, "glareScore": 0.03, "estimatedDpi": 412,
                      "edgesComplete": true, "textDetected": true, "userOverrode": false },
  "chunkSizeBytes": 1048576
}
```
```json
201 Created
{
  "sessionId": "us_01JQ8K…",
  "documentId": "d_8e2b…",
  "uploadUrl": "https://stapquarantine.blob.core.windows.net/…?sv=…&sp=cw&se=…",
  "uploadMethod": "PUT",
  "expiresAtUtc": "2026-08-01T09:29:00Z",
  "chunkSizeBytes": 1048576,
  "notice": "We check the file type ourselves; the type you declared is recorded but not trusted."
}
```
The SAS is **write-only (`sp=cw`), single-blob, 15 minutes**. `declaredMimeType` is stored for
forensics and ignored for processing ([06 §6.6](06-security-architecture.md#66-secure-document-processing-pipeline)).

**`POST /v1/documents/upload-sessions/{sessionId}/complete`**
```json
202 Accepted
Location: /v1/operations/op_01JQ8K…
{
  "documentId": "d_8e2b…",
  "processingState": "SCANNING",
  "estimatedSeconds": 14,
  "pipeline": ["SCANNING","SANITIZED","CLASSIFYING","EXTRACTING","EXTRACTED"]
}
```

**`GET /v1/documents/{documentId}` — a sealed medical document**
```json
{
  "documentId": "d_1c4f…",
  "originalName": "I-693 sealed envelope.jpg",
  "documentClass": "SEALED_MEDICAL",
  "classConfidence": 0.9931,
  "processingState": "OPAQUE_STORED",
  "isOpaque": true,
  "previewAvailable": false,
  "extractionsAvailable": false,
  "handlingNotice": "This looks like a sealed medical exam. We store it but we never open, read, or analyse it. Do not open the envelope — the agency requires it to arrive sealed.",
  "checklistEffect": "POSSESSION_ATTESTED"
}
```

**`GET /v1/documents/{documentId}/extractions`**
```json
{
  "documentId": "d_8e2b…",
  "documentClass": "IDENTITY",
  "documentSubtype": "PASSPORT",
  "engine": "azure-document-intelligence",
  "engineVersion": "prebuilt-idDocument@2024-11-30",
  "injectionFlagged": false,
  "data": [
    { "canonicalPath": "person.name.family", "rawText": "RAMÍREZ", "normalizedValue": "Ramírez",
      "pageNumber": 2, "boundingPolygon": [[0.11,0.22],[0.39,0.22],[0.39,0.26],[0.11,0.26]],
      "rawConfidence": 0.9812, "confidenceBand": "EXTRACTED", "isModelGenerated": false },
    { "canonicalPath": "person.document.passportNumber", "rawText": "AB1234567",
      "normalizedValue": "AB1234567", "pageNumber": 2, "boundingPolygon": [ … ],
      "rawConfidence": 0.9903, "checksumValid": true, "confidenceBand": "VERIFIED",
      "isModelGenerated": false }
  ]
}
```

---

## 7.11 Question and interview APIs

```http
GET  /v1/cases/{caseId}/question-sets
GET  /v1/cases/{caseId}/question-sets/{setId}
POST /v1/cases/{caseId}/answers
POST /v1/interviews                                 # start a session
GET  /v1/interviews/{sessionId}
POST /v1/interviews/{sessionId}/turns               # chat turn (SSE stream)
POST /v1/interviews/{sessionId}/end
GET  /v1/interviews/{sessionId}/transcript
POST /v1/interviews/voice/ephemeral-key             # broker for WebRTC
```

**`POST /v1/interviews`**
```json
{
  "caseId": "c_9b2f…",
  "personId": "p_7d4e…",
  "batchId": "mi_batch_017",
  "modality": "VOICE",
  "locale": "es-MX",
  "consent": {
    "purpose": "VOICE_RECORDING",
    "noticeVersion": "2026.03",
    "noticeSha256": "4a9f…",
    "modality": "BOTH",
    "retainAudioClips": false
  }
}
```
```json
201 Created
{
  "sessionId": "is_01JQ8K…",
  "personId": "p_7d4e…",
  "scopeNotice": "This session can only see Carlos's answers. It cannot see anyone else's.",
  "budget": { "voiceSecondsRemaining": 1800, "targetSeconds": 420 },
  "consentRecordId": "cr_01JQ…",
  "disclosureSpoken": true
}
```

**`POST /v1/interviews/voice/ephemeral-key`**
```json
{ "sessionId": "is_01JQ8K…" }
```
```json
200 OK
{
  "ephemeralKey": "ek_…",
  "expiresInSeconds": 60,
  "singleUse": true,
  "endpoint": "wss://…/realtime",
  "model": "gpt-realtime-1.5-2026-02-23",
  "notice": "Audio goes straight from your device to the speech service. Our servers never receive it."
}
```

**`POST /v1/interviews/{sessionId}/turns`** — SSE stream
```
event: guardrail
data: {"agent":"16","verdict":"ALLOW"}

event: message
data: {"seq":7,"role":"assistant","text":"¿En qué ciudad nació Carlos?","englishLabel":"City/Town/Village of Birth","boundFieldPath":"person.birth.city","formRef":"I-130 Part 2, Item 9"}

event: input-affordance
data: {"type":"TEXT","maxLength":40,"alternatives":[{"type":"DOCUMENT","label":"I have a document with this"}]}

event: done
data: {"turnCost":0.0031,"tokensIn":2140,"tokensOut":48}
```

Each assistant turn declares the **single field it is asking about** and the authoritative English
label ([US-08.02](02-product-requirements.md#e-07--e-08--e-09--questionnaire-and-interviews)).

**A UPL deflection**
```json
POST /v1/interviews/{sessionId}/turns
{ "text": "¿Cree que me van a aprobar?" }
```
```
event: guardrail
data: {"agent":"16","verdict":"BLOCK","categories":["OUTCOME_PREDICTION"]}

event: message
data: {"seq":8,"role":"assistant","deterministic":true,"text":"No puedo decirle qué decidirá el gobierno — nadie aquí puede, y sería incorrecto adivinar. Lo que sí puedo hacer es ayudarle a que su solicitud esté completa y correcta. Si necesita consejo legal, aquí tiene organizaciones sin fines de lucro que ofrecen ayuda.","resources":{"directoryUrl":"/v1/resources/legal-providers"}}

event: done
data: {"deflectionLogged":"UPL_DEFLECTION"}
```
Note `"deterministic": true` — the refusal text is not generated, so it cannot itself drift into
advice.

---

## 7.12 Review, approval and package APIs

```http
GET  /v1/review/queue
GET  /v1/review/tasks/{taskId}
POST /v1/review/tasks/{taskId}/decision
GET  /v1/cases/{caseId}/review-context
POST /v1/cases/{caseId}/approvals               # step-up required; HUMAN ONLY
GET  /v1/cases/{caseId}/approvals
POST /v1/cases/{caseId}/packages                # 202
GET  /v1/packages/{packageId}
GET  /v1/packages/{packageId}/outputs
GET  /v1/packages/{packageId}/outputs/{outputId}/download-url
POST /v1/packages/{packageId}/exports
DELETE /v1/exports/{exportId}                   # revoke a delivery link
```

**`POST /v1/cases/{caseId}/approvals`**
```json
{
  "stepUpToken": "eyJhbGciOi…",
  "attestation": {
    "version": "2026.03",
    "text": "I have reviewed the information in this package. I confirm the values are as the applicant provided them. I understand Aperture has not given legal advice and this package has not been filed.",
    "accepted": true
  },
  "valueSetSha256": "c81f…",
  "reviewedDiscrepancyIds": ["disc_1f9c…", "disc_44a2…"]
}
```
```json
201 Created
{
  "approvalId": "ap_01JQ8K…",
  "approvedByUserId": "u_01JQ…",
  "approverRole": "ATTORNEY",
  "approvedAtUtc": "2026-08-01T15:41:07Z",
  "valueSetSha256": "c81f…",
  "formEditionSet": [
    { "formNumber": "I-130", "editionDate": "2025-11-04", "sourceSha256": "9f2c…" },
    { "formNumber": "I-130A", "editionDate": "2025-11-04", "sourceSha256": "1d7b…" }
  ],
  "invalidatesOnValueChange": true
}
```

**Failure — a non-human principal attempts approval**
```json
403 Forbidden
{
  "type": "https://api.aperture.app/problems/human-approval-required",
  "title": "Only a person can approve a package",
  "status": 403,
  "detail": "This action requires an authenticated human principal. Automated principals are not permitted to approve packages under any configuration.",
  "correlationId": "7f3e…"
}
```
This response also raises a **Sev-1 security event**, because reaching it means something upstream
is wrong ([06 §6.9 E-2](06-security-architecture.md#69-stride-analysis)).

**`POST /v1/cases/{caseId}/packages`**
```json
{ "approvalId": "ap_01JQ8K…" }
```
```json
202 Accepted
Location: /v1/operations/op_01JQ8K…
```
```json
GET /v1/packages/pk_01JQ8K…
{
  "packageId": "pk_01JQ8K…",
  "caseId": "c_9b2f…",
  "approvalId": "ap_01JQ8K…",
  "generatedAtUtc": "2026-08-01T15:43:19Z",
  "verification": {
    "passed": true,
    "method": "ROUND_TRIP_REPARSE",
    "fieldsVerified": 218,
    "mismatches": 0
  },
  "preparer": { "orgName": "Casa Legal Community Services",
                "verificationStatus": "VERIFIED", "verificationType": "EOIR_RECOGNIZED" },
  "outputs": [
    { "outputId": "po_1", "type": "COVER_INDEX", "pageCount": 2, "sortOrder": 1 },
    { "outputId": "po_2", "type": "FILLED_FORM", "formNumber": "I-130",
      "editionDate": "2025-11-04", "fillMode": "ACROFORM_FILLED", "pageCount": 14, "sortOrder": 2 },
    { "outputId": "po_3", "type": "ADDENDUM", "formNumber": "I-130",
      "reason": "Part 2 Item 12 exceeded field capacity", "pageCount": 1, "sortOrder": 3 },
    { "outputId": "po_9", "type": "CHECKLIST", "pageCount": 2, "sortOrder": 9 }
  ],
  "filingChecklist": {
    "feeUsdCents": 67500,
    "filingAddress": "…",
    "wetInkSignaturePoints": [ { "formNumber": "I-130", "partLabel": "Part 6, Item 7.a" } ],
    "citation": { "sourceUrl": "https://…", "revisionDate": "2025-11-04" }
  },
  "disclaimer": "This package has NOT been filed. You must file it yourself. LaPluma is not a law firm and has not given you legal advice."
}
```

**Generation failure on round-trip verification**
```json
409 Conflict
{
  "type": "https://api.aperture.app/problems/generation-verification-failed",
  "title": "We could not verify the generated forms",
  "status": 409,
  "detail": "Two fields did not read back correctly from the generated PDF. We did not produce a package. This is our defect, not yours, and the team has been alerted.",
  "errors": [
    { "formNumber": "I-130", "pdfFieldName": "Pt2Line9_CityTown[0]",
      "expected": "Quetzaltenango", "readBack": "Quetzaltenang" }
  ]
}
```
A truncation defect surfaces as a **hard failure**, not a warning
([FR-FORM-005](02-product-requirements.md#28-functional-requirements)).

**`POST /v1/packages/{packageId}/exports`** — secure delivery
```json
{
  "channel": "SECURE_LINK",
  "recipientEmail": "attorney@example.org",
  "secondFactor": { "type": "OTP_TO_PHONE", "phoneLast4Confirmation": "4417" },
  "expiresInHours": 72,
  "maxDownloads": 3,
  "stepUpToken": "eyJhbGciOi…"
}
```
```json
201 Created
{
  "exportId": "ex_01JQ8K…",
  "channel": "SECURE_LINK",
  "expiresAtUtc": "2026-08-04T15:50:00Z",
  "maxDownloads": 3,
  "downloadCount": 0,
  "revocable": true,
  "notice": "We sent a link, not the documents. The recipient needs a one-time code to open it."
}
```

---

## 7.13 Notification APIs

```http
GET    /v1/notifications
POST   /v1/notifications/{id}/read
POST   /v1/notifications/read-all
GET    /v1/notifications/preferences
PATCH  /v1/notifications/preferences
POST   /v1/notifications/device-tokens
DELETE /v1/notifications/device-tokens/{tokenId}
```

**`GET /v1/notifications`** — in-app inbox (the only place content appears)
```json
{
  "data": [
    { "notificationId": "n_01JQ…", "category": "ACTION_REQUIRED",
      "title": "2 documents still needed", "body": "Proof of status and a birth certificate.",
      "deepLink": "aperture://cases/c_9b2f…/missing-items", "createdAtUtc": "…", "readAtUtc": null }
  ]
}
```

**The corresponding APNs payload** — deliberately empty of meaning
```json
{
  "aps": { "alert": { "loc-key": "NOTIF_GENERIC_UPDATE" }, "sound": "default",
           "mutable-content": 1, "thread-id": "aperture" },
  "notificationId": "n_01JQ…"
}
```
`NOTIF_GENERIC_UPDATE` localizes to "You have an update in Aperture." **No case content, no form
number, no person name** ever reaches a lock screen
([NT-002](02-product-requirements.md#213-notification-requirements)). A contract test asserts that
every generated APNs payload matches this shape.

---

## 7.14 Administration APIs

```http
GET    /v1/admin/tenants/{tenantId}
PATCH  /v1/admin/tenants/{tenantId}
GET    /v1/admin/tenants/{tenantId}/users
POST   /v1/admin/tenants/{tenantId}/users
PATCH  /v1/admin/tenants/{tenantId}/users/{userId}/roles     # step-up
DELETE /v1/admin/tenants/{tenantId}/users/{userId}
GET    /v1/admin/tenants/{tenantId}/kyb
POST   /v1/admin/tenants/{tenantId}/kyb/verification
GET    /v1/admin/tenants/{tenantId}/usage
GET    /v1/admin/tenants/{tenantId}/budgets
PATCH  /v1/admin/tenants/{tenantId}/budgets
POST   /v1/admin/break-glass/requests                         # dual approval
POST   /v1/admin/break-glass/requests/{id}/approve
GET    /v1/admin/catalog/field-maps/pending
POST   /v1/admin/catalog/field-maps/{id}/approve              # two-person
GET    /v1/admin/reports/{reportCode}
```

**`GET /v1/admin/tenants/{tenantId}/kyb`**
```json
{
  "tenantId": "t_4a1e…",
  "legalName": "Casa Legal Community Services, Inc.",
  "providerClaim": "EOIR_RECOGNIZED",
  "verificationStatus": "VERIFIED",
  "verifiedAtUtc": "2026-02-11T00:00:00Z",
  "verificationExpiryUtc": "2027-02-11T00:00:00Z",
  "evidence": [ { "type": "EOIR_RECOGNITION", "reference": "…", "verifiedBy": "u_…" } ],
  "capabilities": {
    "canBrandApplicantExperience": true,
    "canSuppressNotALawFirmDisclosure": false,
    "packageFooterText": "Prepared using Aperture by Casa Legal Community Services (EOIR-recognized)"
  }
}
```
`canSuppressNotALawFirmDisclosure` is `false` for **every** tenant type. It appears in the response
so the constraint is visible and auditable, not because it is configurable
([C-10](00-design-authority-record.md#c-10--the-platform-will-attract-bad-faith-administrator-tenants)).

**`POST /v1/admin/break-glass/requests`**
```json
{ "targetTenantId": "t_4a1e…", "targetCaseId": "c_9b2f…",
  "reason": "SUPPORT_TICKET_4471: user reports package generation failure",
  "requestedDurationMinutes": 60 }
```
```json
201 Created
{
  "requestId": "bg_01JQ…",
  "status": "AWAITING_SECOND_APPROVAL",
  "approvalsRequired": 2,
  "approvalsReceived": 1,
  "requesterCannotSelfApprove": true,
  "userNotificationWillBeSent": true,
  "maxDurationMinutes": 240,
  "postHocReviewDueUtc": "2026-08-08T00:00:00Z"
}
```

---

## 7.15 Audit APIs

```http
GET /v1/me/audit                                # own trail, plain language
GET /v1/cases/{caseId}/audit                    # case trail, entitlement-scoped
GET /v1/admin/audit                             # tenant trail; ReadOnlyAuditor
GET /v1/admin/audit/integrity                   # hash-chain verification
POST /v1/admin/audit/export                     # 202; compliance export
```

**`GET /v1/me/audit`**
```json
{
  "data": [
    { "occurredAtUtc": "2026-08-01T15:41:07Z",
      "plainLanguage": "Danielle at Casa Legal approved your I-130 package.",
      "action": "PACKAGE_APPROVED", "actorRole": "ATTORNEY", "outcome": "SUCCESS" },
    { "occurredAtUtc": "2026-07-30T09:12:44Z",
      "plainLanguage": "You gave Jorge permission to help with your documents.",
      "action": "MEMBERSHIP_GRANTED", "actorRole": "FOLDER_OWNER", "outcome": "SUCCESS" },
    { "occurredAtUtc": "2026-07-28T22:03:10Z",
      "plainLanguage": "Aperture support looked at your case to investigate a problem you reported. Two managers approved this and it lasted 40 minutes.",
      "action": "BREAK_GLASS_ACCESS", "actorRole": "SUPPORT", "outcome": "SUCCESS" }
  ]
}
```
The break-glass entry is deliberately visible and deliberately in plain language. A user is told
when someone looked at their file.

**`GET /v1/admin/audit/integrity`**
```json
{
  "tenantId": "t_4a1e…",
  "rangeStartUtc": "2026-07-01T00:00:00Z",
  "rangeEndUtc": "2026-08-01T00:00:00Z",
  "eventCount": 184203,
  "chainValid": true,
  "lastEventHash": "e91b…",
  "anchors": [ { "anchoredAtUtc": "2026-07-15T00:00:00Z", "hash": "3c8a…" } ]
}
```

---

## 7.16 Operations (long-running work)

```http
GET /v1/operations/{operationId}
```
```json
{
  "operationId": "op_01JQ8K…",
  "type": "PACKAGE_GENERATION",
  "status": "RUNNING",
  "progress": { "current": 4, "total": 9, "stage": "FILLING_FORMS" },
  "startedAtUtc": "2026-08-01T15:42:55Z",
  "estimatedCompletionUtc": "2026-08-01T15:44:10Z",
  "resultLocation": null,
  "retryAfterSeconds": 3
}
```

Terminal states are `SUCCEEDED`, `FAILED` (with a Problem Details `error` object), and `CANCELLED`.
Operations are retained 7 days. Clients poll with the returned `retryAfterSeconds`, or receive an
APNs nudge on completion.

---

## 7.17 Rate limits and budgets

| Bucket | Limit | Applies to |
|---|---|---|
| Per user, general | 300 req/min | All |
| Per user, mutations | 60 req/min | POST/PATCH/PUT/DELETE |
| Per user, AI-invoking | 20 req/min | Interview turns, reprocess |
| Per user, uploads | 100/hour, 500/day | Upload sessions |
| Per tenant | Contracted, default 10,000 req/min | All |
| Per IP, unauthenticated | 30 req/min | Auth endpoints |
| Voice minutes | Per case and per tenant budget | Interview sessions |
| AI cost | Per case and per tenant budget | All AI-invoking |

**`429` with budget context**
```json
429 Too Many Requests
Retry-After: 42
{
  "type": "https://api.aperture.app/problems/budget-exhausted",
  "title": "You've used the voice time included with this case",
  "status": 429,
  "detail": "Voice interviews are paused for this case. Everything you've already told us is saved. You can keep going by chat or by typing, and those have no limit.",
  "budget": { "kind": "VOICE_MINUTES", "used": 30, "limit": 30, "resetsAtUtc": null,
              "alternatives": ["CHAT", "FORM"], "topUpAvailable": true }
}
```
The message is honest, preserves the user's work, and points at a free alternative — the
requirement from [C-11](00-design-authority-record.md#c-11--cost-model-for-real-time-voice-is-not-viable-as-specified).

---

## 7.18 Contract testing and governance

| Control | Implementation |
|---|---|
| Source of truth | OpenAPI 3.1 in the repository; server stubs and the Swift client generated in CI |
| Breaking-change detection | `oasdiff` on every PR; a breaking change without a version bump fails the build |
| Consumer-driven contracts | The iOS and macOS clients publish contract expectations; provider verification runs in CI |
| Schema enforcement at runtime | APIM validates requests and responses against the same OpenAPI document that generated the client |
| Invariant tests | Automated assertions that: no response contains a completion-percentage key; no notification payload contains case content; the approval endpoint rejects non-human principals; the catalog endpoint's response is independent of case data; a cross-tenant request returns 404 |
| Security review | Every new endpoint declares scope, role, step-up level, and data classification in the contract; unreviewed endpoints cannot deploy |
| Documentation | Generated from OpenAPI; examples are executed as tests so they cannot rot |
