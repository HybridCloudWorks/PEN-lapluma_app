# ADR-019 — Lean GCP and reusable Document Library

**Status:** Accepted target; implementation planned. **Date:** 2026-09-13. **Decider:** Product owner.

## Context

The owner approved a lean managed GCP architecture and institution-specific document offerings.
The [canonical platform decision](https://github.com/HybridCloudWorks/PEN-lapluma_infra/blob/main/wiki/GCP-Document-Library-Decision.md)
records the complete service, trust, data, publication and transfer boundaries. This ADR records
the app implications; it does not claim the current client or backend has migrated.

## Decision

Use Cloud Run for existing .NET/Python services, Cloud SQL PostgreSQL only (including JSONB),
private Cloud Storage, usage-based Pub/Sub, API Gateway, Cloud Scheduler and Terraform with
GitHub workload identity federation. Google-managed encryption at rest plus TLS replaces the
mandatory HSM/CMEK baseline. Existing session, tenant/person authorization and approval contracts
remain enforced by services.

Customer-facing terms are Document Library, Document Blueprints and Document Collections.
The app discovers only assigned Collections and authorized Blueprints, explains preparation
capabilities, and uses pinned immutable revisions for entry, evidence, approval and export.
Fillable PDFs, static documents with assisted preparation and reference links to external
workflows are distinct supported modes. Official forms remain unchanged; institution branding
and instructions stay in presentation or institution-owned documents.

Versioned library/Collection APIs are added alongside the existing catalog contract. Preserve
existing package IDs and older clients during transition. A supported definition or Collection
must be onboardable through LaPluma's CLI/CI publication pipeline without changing app code or
deploying a new service. No customer self-service publishing or executable extensions in release one.

100 MB uploads bypass Gateway's 32 MB request limit via short-lived narrowly scoped grants to
private Storage objects through Google's internet endpoint. The service validates actual size,
checksum, ownership and processing results before accepting evidence. Outstanding grants are
not instantly revocable. Tenant switches must isolate caches, offline state, downloads and exports.

## Supersession and retained requirements

This supersedes the Azure placement in ADR-005 and the SQL/Cosmos split in ADR-006. It also
supersedes conflicting Azure integrations, premium messaging, mandatory HSM/CMEK and
private-network-only document transfer assumptions elsewhere. ADR-009's durable, server-controlled
workflow semantics remain; Pub/Sub alone is not a workflow state engine. ADR-004's language/runtime
separation remains; supported runtime versions follow the actual backend repository.

Keep official PDF fidelity, per-person trust, passkey/session requirements, no automatic filing,
no authoritative AI writes, approval invalidation and explicit production readiness gates.
Default platform encryption does not establish tenant-key cryptographic erasure; physical deletion,
backup aging and hold behavior must follow the implemented retention contract.

## Delivery and verification

Architecture and Blueprint/Collection foundations are both P0. The
[app board](https://github.com/orgs/HybridCloudWorks/projects/3) and
[integration board](https://github.com/orgs/HybridCloudWorks/projects/4) retain card IDs and history.
Full USCIS coverage remains planned as the first major library expansion. Prove one existing USCIS
workflow and two synthetic institutions via the same template, including shared reuse and private
Blueprint isolation through search, caches, downloads and exports. Verify immutable revisions,
independent publication review, case pinning, edition drift, withdrawal, rollback and failure paths.

Preserve the DESIGN.md reference principles with white and pastel red, yellow, green and blue app
surfaces. Any infra frontend remains gray/black/white. Styling is required after the P0 foundations.
The original attachment is not republished; the labeled DESIGN-REF summary is preserved in the
[verified planning snapshot](https://github.com/HybridCloudWorks/PEN-lapluma_infra/blob/main/wiki/planning/gcp-board-verification.json).

See the [pilot/growth cost model](https://github.com/HybridCloudWorks/PEN-lapluma_infra/blob/main/wiki/GCP-Cost-Model.md)
for explicit workload assumptions, nonproduction environments, document processing and unit costs.
Revisit placement or tenancy only when measured cost, required capabilities or policy justify it.
