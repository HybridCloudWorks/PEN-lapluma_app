# Architecture Decision Records

Each ADR records a decision that was contested, its context, the options considered, the decision
taken, and its consequences — including the bad ones. An ADR is immutable once accepted; a change of
mind produces a new ADR that supersedes it.

| ADR | Title | Status | Supersedes |
|---|---|---|---|
| [ADR-001](ADR-001-scrivener-boundary.md) | The scrivener boundary — no legal advice, enforced in code | Accepted | — |
| [ADR-002](ADR-002-no-efiling.md) | No electronic filing | Accepted | — |
| [ADR-003](ADR-003-form-fidelity.md) | Fill the agency's own AcroForm; never redraw a form | Accepted | — |
| [ADR-004](ADR-004-backend-runtime.md) | .NET 9 for the core, Python for the AI and processing planes | Accepted | — |
| [ADR-005](ADR-005-compute-platform.md) | Azure Container Apps, not AKS | Accepted | — |
| [ADR-006](ADR-006-polyglot-persistence.md) | Azure SQL as the only system of record; Cosmos for derived data | Accepted | — |
| [ADR-007](ADR-007-household-trust-boundaries.md) | Per-person trust boundaries within a folder | Accepted | — |
| [ADR-008](ADR-008-agent-capability-boundary.md) | Untrusted-reading agents hold no tools | Accepted | — |
| [ADR-009](ADR-009-durable-orchestration.md) | Durable workflow orchestration, not an LLM planner | Accepted | — |
| [ADR-010](ADR-010-confidence-banding.md) | Three confidence bands from measurable signals, never model self-report | Accepted | — |
| [ADR-011](ADR-011-passkeys-no-sms.md) | Passkeys primary; SMS never offered as a factor | Accepted | — |
| [ADR-012](ADR-012-no-third-party-client-sdks.md) | No third-party SDKs in the client | Accepted | — |
| [ADR-013](ADR-013-alpha-02-platform-boundaries.md) | Alpha 0.2 platform and form-processing boundaries | Accepted | Clarifies ADR-003–009 |
| [ADR-014](ADR-014-delivery-anchored-retention.md) | Delivery-anchored case retention | Proposed | Pending approval to supersede conflicting retention rules |
| [ADR-015](ADR-015-lapluma-name-and-repository-boundary.md) | LaPluma identity and two-repository boundary | Accepted | — |
| [ADR-016](ADR-016-role-adaptive-platform-boundaries.md) | Role-adaptive platform boundaries | Accepted | — |
| [ADR-017](ADR-017-isolated-demo-tenancy.md) | Isolated demo tenancy | Accepted | — |

## Template

```
# ADR-NNN — Title
Status · Date · Deciders · Consulted
## Context
## Options considered
## Decision
## Consequences (positive, negative, neutral)
## Compliance and enforcement
## Revisit triggers
```
