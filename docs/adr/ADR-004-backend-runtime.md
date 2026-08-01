# ADR-004 — .NET 9 for the core, Python for the AI and processing planes

**Status:** Accepted · **Date:** 2026-08-01
**Deciders:** CTO, Lead Backend Architect, Principal Cloud Architect
**Consulted:** Lead DevSecOps Architect, AI Architect

## Context

The platform has two workloads with genuinely different characteristics. The transactional core is
relational, correctness-critical, and Azure-native: a wrong value here ends up on a government form.
The AI and document-processing planes need the Python ecosystem, where document understanding,
model SDKs, and evaluation tooling actually live.

A single-runtime decision would compromise one of the two.

## Options considered

| Option | Verdict |
|---|---|
| .NET everywhere | Rejected — fights the AI/document ecosystem for no gain |
| Python everywhere | Rejected — weaker typing and weaker Azure SQL tooling in the part of the system where a type error becomes a wrong date on a form |
| Node.js everywhere | Rejected — good elsewhere, weaker for this domain's correctness needs and for EF-Core-class data access |
| Java everywhere | Technically equivalent to .NET; rejected on Azure-first ergonomics and heavier operational footprint |
| Go everywhere | Excellent runtime; thinnest ecosystem for both PDF/AcroForm work and Azure data access |
| **.NET core + Python AI/processing** | **Selected** |

## Decision

**.NET 9 / ASP.NET Core** for all twelve Core-zone services. C#'s nullable reference types, strong
typing, EF Core with Always Encrypted and Row-Level Security support, and first-class Entra
integration directly reduce the bug class that matters most here.

**Python 3.12** for the AI zone (agent runtime, guardrails, PII proxy) and the processing zone
(sanitizer, OCR workers, rasterizer, PDF toolchain).

The polyglot seam costs less than it appears to, because the zone boundary between them already
exists for security reasons ([06 §6.2](../06-security-architecture.md#62-zero-trust-architecture)).
The two runtimes communicate only through queues and schema-validated messages — the same contract
they would need even if they shared a language.

## Consequences

**Positive.** Each plane uses the right tool. The security boundary and the technology boundary
coincide, which is a rare and useful alignment. Hiring pools for both are deep.

**Negative.** Two toolchains, two dependency-management stories, two sets of CI configuration, two
base-image pipelines. Shared domain concepts must be expressed twice — mitigated by generating both
sides from the JSON Schema contracts in `contracts/`.

**Neutral.** Requires engineers comfortable in both, or a clear team split. At Phase 1 headcount the
split is natural.

## Revisit triggers

If the Python planes shrink to thin integration wrappers, consolidating to .NET becomes worth
reconsidering. If the .NET core grows a substantial ML component, the reverse.
