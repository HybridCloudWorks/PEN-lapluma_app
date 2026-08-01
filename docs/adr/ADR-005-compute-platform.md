# ADR-005 — Azure Container Apps, not AKS

**Status:** Accepted · **Date:** 2026-08-01
**Deciders:** Principal Cloud Architect, CTO, Lead DevSecOps Architect
**Consulted:** Principal Security Architect

## Context

The workload needs container orchestration with: independent per-service scaling, scale-to-zero for
bursty document extraction, revision-based deployment with traffic splitting, and — critically —
**hard isolation between three security zones** ([06 §6.2](../06-security-architecture.md#62-zero-trust-architecture)).

The team at Phase 1 is 17 people. A platform team is not among them.

## Options considered

| Option | Verdict |
|---|---|
| **Azure Container Apps** | **Selected.** Kubernetes semantics (Dapr, KEDA, Envoy, revisions, traffic splitting, scale-to-zero) without cluster operations. Decisively: a Container Apps **environment is a security boundary**, so the three-zone isolation is achieved by using three environments rather than by trusting network policy inside one cluster |
| App Service | Good for a web app; weaker for event-driven workers and multi-zone isolation. Retained for the marketing site only |
| Azure Functions | Selected in a supporting role: event glue, scheduled jobs, Durable Task host. Not the primary platform — the programming model fights a rich domain model |
| AKS | Rejected for Phase 1–2. Buys Kubernetes API access, custom admission control, and service-mesh configuration we do not yet need, at the cost of a platform team we would rather spend on the product |
| Container Instances | Too low-level — no scaling, ingress, or lifecycle management |

## Decision

**Three Container Apps environments** — `core`, `ai`, `proc` — each with its own subnet, managed
identity, and network policy. The `proc` environment has no outbound internet and no data-plane role
assignments, which is verified by a policy check rather than asserted.

Azure Functions hosts the Durable Task orchestrator and event-glue handlers.

## Consequences

**Positive.** No cluster upgrades, no node pools, no CNI decisions. Scale-to-zero materially reduces
the cost of the bursty extraction workload. The security boundary is a platform primitive rather
than a configuration we must get right.

**Negative.** No direct Kubernetes API access, so anything requiring a custom operator, an admission
webhook, or a specific service-mesh configuration is unavailable. Some Kubernetes-native tooling
does not apply. Migration to AKS later is real work, though the container images and Dapr usage
transfer.

**Neutral.** Container Apps is built on Kubernetes, so the concepts transfer if we do migrate.

## Revisit triggers

Move to AKS when **any** of these becomes true:
1. We need more than three hard security boundaries, or boundaries with finer granularity than an
   environment provides.
2. We need custom admission control or a specific service-mesh configuration Container Apps cannot
   express.
3. Cost analysis shows dedicated node pools are materially cheaper at our sustained scale.
4. We need workload types Container Apps does not support (GPU-heavy on-cluster inference, for
   example).
5. We have a platform team that can operate a cluster to the standard this data requires.

Until at least three of those are true, the migration is not worth it.
