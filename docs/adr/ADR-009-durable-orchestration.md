# ADR-009 — Durable workflow orchestration, not an LLM planner

**Status:** Accepted · **Date:** 2026-08-01
**Deciders:** Agentic AI Architect, Lead Backend Architect, CAIO
**Consulted:** Lead QA Architect, Compliance Officer

## Context

An "Executive Orchestrator Agent" could be implemented as an LLM that decides what happens next
given the case state. That is the fashionable design and it is the wrong one here.

The system must be certifiable. A compliance reviewer needs to know that a case cannot reach package
generation without human approval — not probabilistically, but structurally. An LLM planner cannot
provide that.

## Options considered

| Option | Replayable | Deterministic | Testable to a compliance standard | Cost/case | Explains itself |
|---|---|---|---|---|---|
| LLM planner | No | No | Not meaningfully | Significant, unbounded | A transcript |
| Rules engine | Partly | Yes | Yes | ~0 | Rules |
| **Durable workflow** | **Yes** | **Yes** | **Yes** | **~0** | **The state machine is the explanation** |

## Decision

Orchestration is a **durable, replayable workflow** (Azure Durable Functions / Durable Task). The
case state machine is code. Every transition is deterministic given its inputs and can be replayed
from history.

Agent 01 retains tier **A** because it holds one genuinely agentic responsibility: when the
deterministic path hits an *exception* — an unclassifiable document, a contradiction the rule engine
cannot resolve, a stalled interview — it reasons about how to route that exception. That reasoning
is bounded to a fixed set of routing actions and **cannot invent a new workflow step**. Two failed
routing attempts escalate to a human.

## Consequences

**Positive.** The workflow can be inspected mid-flight, replayed for debugging, and tested
exhaustively. Compliance can read the state machine and see that no path reaches generation without
approval. Orchestration cost is effectively zero. Failure handling and compensation are first-class.

**Negative.** Less flexible than a planner — a new workflow shape requires code, not a prompt. Long-
running workflows are pinned to their definition version, which is why in-flight workflow migration
is a [V2 item](../13-v2-recommendations.md#135-architecture-evolution).

**Neutral.** Rejects the framing that "more agentic" is better. In this domain, less agentic is
better everywhere except the three places it genuinely is not.

## Revisit triggers

None foreseen. If the exception space grows large enough that routing rules become unmanageable,
widen Agent 01's bounded action set — never remove the bound.
