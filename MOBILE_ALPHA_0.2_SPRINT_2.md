# LaPluma App — Alpha 0.2 Sprint 2

Release label: `lapluma-app-0.2`

This file converts the Alpha 0.2 master prompt into an implementation steering
record. The prompt guides the work; accepted ADRs, verified platform behavior, and
tests remain authoritative when recommendations conflict.

## Repository boundary

- `PEN-lapluma_app` owns the native iOS app, shared Swift packages, mobile tests,
  mobile metadata, and app-facing architecture records.
- `PEN-lapluma_infra` owns OpenAPI/event contracts, backend services, Azure Functions,
  infrastructure as code, policy, and deployment automation.
- This sprint creates code and deployable-shaped configuration, but performs no live
  Azure provisioning or production deployment.

## Sprint 2 implementation order

1. Expand the form catalog into category, subcategory, artifact kind, activation
   state, immutable edition metadata, and extracted-schema manifests.
2. Present category-to-form selection in iOS without recommendations or case-aware
   ranking.
3. Establish the cross-repository contract and Azure preparation plan using only
   documented placeholders.
4. Scaffold acquisition, extraction, human review, deterministic generation,
   delivery, and retention boundaries behind fail-closed feature flags.
5. Keep appointment/Teams automation, electronic signatures, final legal copy, and
   live deployment gated until their prerequisites are approved.

## Conflict outcomes

- Azure SQL is authoritative; Cosmos contains disposable derived payloads only.
- Container Apps host core/processing services; Durable Functions and Service Bus
  coordinate workflows.
- Official-form acquisition has controlled outbound access and is isolated from the
  no-egress processing zone.
- Document Intelligence proposes extracted values; it does not fill official forms.
- Official AcroForms are filled deterministically and round-trip verified. Other
  artifact kinds use explicit assisted or external workflows.
- No digital signature capture is enabled until form-specific counsel approval.
- Delivery-anchored 90-day retention is proposed in ADR-014 and cannot become a user
  promise until Data, Privacy, and Legal approve the complete deletion semantics.

## Completion criteria

- App and infrastructure work remain in separate repositories and PRs.
- Every configuration input appears in a root implementation ledger with owner,
  format, secret classification, and status.
- No credentials or production endpoints are committed.
- Package tests, iOS build-for-testing, schema/contract validation, static checks, and
  repository secret scans pass before either PR is marked ready.

