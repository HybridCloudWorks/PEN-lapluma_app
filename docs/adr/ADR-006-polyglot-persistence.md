# ADR-006 — Azure SQL as the only system of record; Cosmos for derived data

**Status:** Accepted · **Date:** 2026-08-01
**Deciders:** Chief Data Officer (arbitrating), Principal Data Architect, Lead Backend Architect
**Related:** [C-18](../00-design-authority-record.md#c-18--cosmos-db-and-azure-sql-both-in-mvp-is-premature-complexity)

## Context

The Principal Data Architect proposed Azure SQL plus Cosmos DB. The Lead Backend Architect objected
that two datastores in an MVP means two consistency models, two backup regimes, two access-control
models, two sets of operational muscle, and a distributed-transaction problem at the seam.

Both were right about something. The workloads genuinely differ: case, person, and form data is
relational and needs referential integrity, row-level security, and point-in-time restore. Agent
traces, extraction payloads, and interview transcripts are schemaless, high-write, TTL-expiring, and
would rot a relational schema.

## Options considered

1. **SQL only.** Traces and transcripts as JSON columns or blobs.
   *Rejected — high-write append traffic against the transactional database, and JSON columns become
   an unqueryable swamp at volume.*
2. **Cosmos only.** *Rejected — no referential integrity for a domain that is fundamentally
   relational, and RLS-equivalent tenant isolation would move into application code, violating
   [AP-8](../03-solution-architecture.md#31-architectural-principles).*
3. **Both, with a hard invariant.** *Selected.*

## Decision

**Azure SQL Hyperscale is the system of record.** Everything a government form depends on lives
there, and there is exactly one authoritative home for any value that can reach a PDF.

**Cosmos DB holds only derived, append-only, expiring data**: agent traces, raw extraction payloads,
interview transcripts, materialized questionnaire graphs.

The invariant that makes this safe:

> **No foreign key crosses the boundary in the write direction.** Cosmos documents reference SQL
> identifiers; SQL never references Cosmos. Nothing in Cosmos is authoritative. Total loss of Cosmos
> must not affect the correctness of any package.

Proven, not assumed: a **quarterly drill drops the Cosmos store in staging and regenerates every
package from SQL alone.** A failure of that drill is a design defect, not an operational one.

## Consequences

**Positive.** Each store does what it is good at. The invariant makes the DR story simple — Cosmos
has an RPO of "don't care." High-write trace traffic never touches the transactional database.

**Negative.** Two backup regimes, two access-control models, two sets of operational knowledge.
Engineers must internalize which store is authoritative, and the answer must be obvious in code —
enforced by putting all Cosmos access behind a `DerivedStore` interface that has no write path into
domain aggregates.

**Neutral.** Cosmos configuration is deliberately modest: session consistency, autoscale, no
analytical store. We are not using its distributed-database capabilities, only its shape.

## Revisit triggers

If trace and transcript volume proves small enough for SQL, or if the operational cost of two stores
exceeds the benefit, collapse to SQL only. Measure at the end of Phase 1.
