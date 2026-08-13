# ADR-017: Isolated demo tenancy

**Status:** Accepted for contract-ready local implementation
**Date:** 2026-08-12

## Decision

Demo mode is a server-authorized transition into a separate synthetic tenant, not a client boolean and not an authorization bypass. Demo and live tenants use different persistence, encryption context, cache namespace, search index, queues, audit stream, object-storage namespace, and delivery policy.

The local vertical slice mirrors this with a separate persistent synthetic stub store and a persistent banner. Demo reset targets that store only. Real invitations and secure delivery are unavailable, and all generated output must be watermarked.

## Consequences

Production requires a demo-provisioning job, synthetic-data versioning, isolation monitors, explicit enter/exit session exchanges, cache erasure on exit, and tenant-scoped reset authorization. Cross-demo/live access tests are blocking.
