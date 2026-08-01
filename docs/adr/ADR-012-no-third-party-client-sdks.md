# ADR-012 — No third-party SDKs in the client

**Status:** Accepted · **Date:** 2026-08-01
**Deciders:** Privacy Officer, CISO, Lead Mobile Architect
**Consulted:** SPM, CPO
**Related:** [C-19](../00-design-authority-record.md#c-19--analytics-on-this-data-is-a-liability-not-an-asset)

## Context

Standard mobile products ship analytics, attribution, and crash-reporting SDKs as a matter of course.
Each is a third party receiving an event stream from the device.

An event named `form_selected: I-589` transmitted to a US analytics vendor is a disclosure that a
specific device is preparing an asylum application. That disclosure is made to a company with its
own data-retention practices, its own subpoena exposure, and its own sub-processors — none of which
we control and none of which our users consented to.

The SPM's position was that funnel analytics are necessary to improve the product, and that
crash reporting is necessary to keep it working.

## Decision

**The iOS and macOS clients ship no third-party analytics, advertising, attribution, or crash
SDK.** No exceptions.

Replacements:
- **Telemetry** is first-party, to our own endpoint, over the same authenticated channel, carrying no
  case content, no form identifier, and no free text ([02 §2.11](../02-product-requirements.md#211-analytics-requirements)).
- **Crash reporting** uses Apple's own MetricKit and the App Store's crash reports, which stay
  within the platform relationship the user already has.
- Analytics consent is separate from service consent and **defaults to off**; the product is fully
  functional without it.

Enforced by an **SBOM policy gate** that fails the build on any new client runtime dependency
without Security approval, and by a **network egress test** that fails CI if the app contacts any
host outside the allowlist.

## Consequences

**Positive.** Closes an entire attack path (AP-5, supply-chain compromise of the client). Makes the
privacy notice's claims literally true rather than approximately true. The near-zero dependency
footprint also means a materially smaller binary and fewer upgrade treadmills.

**Negative.** We build our own telemetry pipeline and our own dashboards. Crash diagnostics are less
rich than a dedicated vendor's. Some standard product-analytics workflows are unavailable, and the
product team must work with coarser data.

**Neutral.** Forces discipline about what we actually need to measure. In practice the events that
matter — funnel stage transitions, capture retry rate, extraction accept rate, review throughput —
are all first-party anyway.

## Revisit triggers

None foreseen. A vendor offering genuinely on-device, zero-egress analytics with a verifiable claim
could be reassessed, but the bar is verification, not assurance.
