# ADR-018: Public evidence relay as an upload-only capability

**Status:** Accepted for contract-ready local implementation  
**Date:** 2026-08-20  
**Deciders:** Product, Architecture, Security  
**Consulted:** Privacy, Mobile, API, Document Processing

## Context

An applicant or assigned preparer sometimes needs one document held by another person. Giving that
person a case account exposes too much; sending the document through ordinary email or messaging
loses the platform's validation, sanitization, retention, and audit boundaries. A public link is
also a bearer credential and cannot identify the case, people, form package, progress, or other
documents before a second factor succeeds.

The mobile MVP needs a production-shaped local flow without claiming that a public recipient site,
message sender, or live storage service exists.

## Options considered

1. Invite every sender into the case. Rejected because a one-document sender does not need case read
   access and person-scope mistakes would have a high impact.
2. Accept documents through email or a general-purpose shared folder. Rejected because those paths
   bypass the ordinary capture validation and create uncontrolled copies and retention.
3. Mint a short-lived upload-only capability after link-plus-code verification. Chosen because its
   authority can be mechanically limited to one requested label and one validated upload.

## Decision

Private Relay uses two separately shared factors: a 256-bit opaque link token and a six-digit code.
The locked recipient response is generic. Five incorrect codes lock the request. A successful code
exchange mints a short-lived grant that can create one write-only upload session; it cannot call any
case, person, proof, catalog, counter, search, or download API. Requests expire after 72 hours and
may be revoked.

The upload uses the same byte-size, page-count, type, digest, sanitization, malware, classification,
and integrity boundaries as ordinary capture. Completion records `RECEIVED`, never accepted
evidence. Only an authorized applicant or assigned preparer can review the processed document and
link it to the cited requirement. Reviewers and approvers may read Proof Map but cannot manage
relays; tenant administrators receive no case access.

Only relay metadata and credential hashes are durable. Plaintext tokens, codes, grants, upload URLs,
and upload-session credentials are not logged or persisted. Rejected staged bytes, revoked/expired
credentials, and account erasure are deleted; an accepted document follows normal document
retention. Missing and unauthorized relay resources both return 404.

## Consequences

- Positive: the sender gets a narrow path with no case visibility, while the uploaded document
  enters the same safety pipeline as applicant capture.
- Positive: a received file cannot silently satisfy a filing requirement.
- Negative: link and code must be communicated separately; the product does not provide email or SMS
  sending in this repository.
- Negative: production needs a public edge, abuse controls, write-only object storage, lifecycle
  cleanup, non-sensitive telemetry, and recipient accessibility/localization outside the signed-in app.
- Neutral: the Debug recipient harness is simulator-only and is compiled out of Release; it is not a
  hosted recipient website.

## Compliance and enforcement

The OpenAPI contract separates `tenantSession` from `relayGrant`; only challenge and unlock declare
`security: []`. Contract and invariant tests cover generic locked state, attempt bounds, expiry,
revocation, one upload, idempotency, digest/file limits, person scope, opaque documents, no automatic
acceptance, cleanup, and absence of plaintext credentials in persisted JSON. Logs use bounded event
codes and correlation IDs, never tokens, codes, document labels, names, or case identifiers.

## Revisit triggers

Revisit before adding recipient accounts, multi-file requests, sender identity verification,
email/SMS delivery, forwarding, document download, or any recipient-visible case context.
