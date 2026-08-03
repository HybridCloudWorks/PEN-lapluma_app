# ADR-015 — LaPluma identity and two-repository boundary

**Status:** Accepted · **Date:** 2026-08-02 · **Decider:** Product owner

## Decision

- The user-facing product name is **LaPluma** and its domain is `lapluma.ai`.
- The application release line uses `lapluma-app-<version>`; Alpha 0.2 is
  `lapluma-app-0.2` with marketing version `0.2.0`.
- `PEN-lapluma_app` owns iOS and shared mobile code.
- `PEN-lapluma_infra` owns API/event contracts, backend services, infrastructure as
  code, policy, and deployment automation. Its initial release line is
  `lapluma-infra-0.0`.
- Cross-repository compatibility is pinned through a versioned contract revision and
  exact commit/deployment identifiers in release manifests.

Internal Swift module and target names may retain the Aperture codename until a
separate low-risk refactor; user-visible surfaces must say LaPluma.

## Consequences

The two repositories require coordinated PRs and release evidence. Neither repository
may silently duplicate the other's source of truth. Secrets and concrete environment
values remain external and are represented only by documented variable contracts.

