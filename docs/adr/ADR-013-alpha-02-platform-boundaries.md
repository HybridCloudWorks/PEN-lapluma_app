# ADR-013 — Alpha 0.2 platform and form-processing boundaries

**Status:** Accepted · **Date:** 2026-08-02 · **Deciders:** Product owner with delegated architecture-agent review

## Context

The Alpha 0.2 steering prompt recommended a Cosmos-centric, Functions-led pipeline
and a single Document Intelligence path for parsing and output. Those recommendations
conflict with accepted ADR-003 through ADR-009 and collapse official PDFs,
proprietary workflows, and authored templates into one artifact type.

## Decision

- Azure SQL remains the authoritative system of record. Cosmos stores derived,
  append-only, TTL-bound extraction payloads and traces only.
- .NET core and Python processing workloads run on Container Apps. Durable Functions
  and Service Bus coordinate deterministic workflows; Event Grid is non-authoritative
  fan-out.
- A restricted acquisition component outside the processing zone fetches allowlisted
  official sources into quarantine. The processing zone has no general internet or
  authoritative-database route.
- Document Intelligence produces anchored proposals. Only a confirmed human value can
  become authoritative or reach output.
- Approved official AcroForms are filled deterministically and round-trip verified.
  Document Intelligence is not treated as a fill-back engine.
- Catalog entries declare an artifact kind: `officialPDF`, `externalWorkflow`,
  `proprietaryForm`, or `authoredTemplate`. Capability and rights status are explicit.
- Electronic signatures remain disabled. Output identifies wet-ink checkpoints until
  form-specific legal and agency acceptance is approved.

## Consequences

The implementation is more explicit and uses more components, but it preserves
referential integrity, review authority, form fidelity, and honest capability claims.
Unsupported artifacts can remain visible without pretending they share a PDF pipeline.

## Enforcement

Contract tests reject authoritative Cosmos records, processor database writes,
unapproved form activation, and any output value lacking human confirmation.

