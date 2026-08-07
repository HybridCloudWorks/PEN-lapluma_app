# Changelog

All notable changes to this repository are documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the release line is `lapluma-app-<version>` per ADR-015. Ready-to-copy entries for each recommended fix from the 2026-08-06 review are staged in [`CODE_REVIEW.md`](CODE_REVIEW.md) § "Ready-to-copy CHANGELOG entries" — move them here as the fixes land.

## [Unreleased]

### Added
- `CODE_REVIEW.md` — full-repository code review (2026-08-06): 1 Critical, 10 High, 22 Medium findings with file/line evidence, plus README update recommendations.
- `TODO.md` — prioritized issue tracking (T-01…T-32) derived from the review.
- `REVIEW.md` — blockers requiring user decisions, credentials, or environment access (R-1…R-5).
- `CHANGELOG.md` — this file.
- Serial XCUITest validation in the iOS pull-request workflow, including current LaPluma assertions and 18 applicant journeys.
- Explicit English/Spanish bundle selection shared across the app and ApertureKit, with runtime localization tests.
- Recoverable offline-capture manifest handling and focused tests for corrupt manifests, upload-session correlation, and discrepancy resolution.
- Persisted, endpoint-scoped stub idempotency replay with conflict and atomic batch-confirmation coverage.
- Catalog-package compatibility parity tests covering all six supported form packages.
- Queryable capture dead letters with bounded retry and concurrent-drain tests.
- A versioned iOS CI warning register and failure-only `.xcresult` retention.
- Complete English/Spanish service-label coverage and plural-aware app resources for counts, summaries, and exported package manifests.
- A shared typed load-state model with localized empty and retryable failure surfaces.

### Changed
- `README.md` — corrected the ADR index range to ADR-001…ADR-015 (ADR-013 platform boundaries, ADR-014 delivery-anchored retention, and ADR-015 LaPluma naming were missing from the appendix table).
- Advanced the guarded internal-TestFlight workflow and release documentation to the Alpha 0.2 line; no deployment was run.
- Completed the user-visible LaPluma rename while preserving internal Aperture module identifiers under ADR-015.
- Expanded pull-request path coverage so contract, static-checker, and workflow changes run their owning validations.
- Replaced the all-journey PR UI gate with Linux path classification, five critical UI journeys for UI-relevant changes, and weekday/manual full regression.
- Routed app-authored dynamic status, error, accessibility, date, byte-count, and export copy through the explicitly selected app locale.

### Fixed
- Confirmation failures now remain visible and retryable instead of dismissing as success.
- Confirmation and interview retries preserve their idempotency identity until success or an applicant changes the submitted value.
- Multi-page scans are encoded and queued as one orientation-preserving PDF rather than dropping every page after the first.
- Stub upload completion now validates the requested session, expiry, and document correlation.
- Blocking discrepancies survive confirmation unless the matching discrepancy is explicitly resolved.
- Chat interview start/send/budget failures retain applicant input and provide retry or questionnaire fallback paths.
- The Missing tab now renders loading, empty, ready, and failed states and refreshes after application creation.
- Local-data deletion resets both persisted and in-memory language/accessibility preferences to avoid mixed UI state.
- Concurrent capture drains no longer duplicate uploads, and permanently invalid captures no longer block later queued work.
- Invalid EXIF orientation values normalize safely; empty decoded form packages fail closed.
- Copied recovery codes remain local to the device and expire from the pasteboard after 60 seconds.
- Static validation now fails when no Swift sources or expected localization resources are found.
- UI tests no longer trigger false Confirm-screen failure triage or print raw delete-key control characters; Debug UI-test builds no longer attempt to strip signed XCTest frameworks.
- Release archives no longer compile unreachable marketing-fixture branches.
- Localization validation now rejects missing applicant-facing keys, locale drift, malformed plural rules, hand-written English plurals, interpolated-copy bypasses, and format keys rendered without arguments.
- Service-backed case, modality, notification, consent, and document states no longer expose raw localization keys; the package fallback no longer renders a raw `%lld` token.
- Review, form requirements, and folder loading no longer turn API failures into endless spinners or misleading empty content; each surface now preserves saved data, explains the failure, and offers Retry.
- Missing-item actions now route through one screen-level destination, preventing sibling row links from activating together; Capture content reuses the existing navigation stack instead of nesting another stack.
- VoiceOver now hears the blocking-items warning, readiness state, and caveat in the progress counters, the official form reference in bilingual field labels, and an immediate announcement when a capture-quality hint appears.
- Consent toggles no longer show a state the backend does not hold: a failed save rolls the switch back with a localized retry message, and stored consent records refresh after each change.

## [lapluma-app-0.2] — 2026-08-05

Pre-existing work, recorded retroactively for reference (see `MOBILE_ALPHA_0.2_SPRINT_2.md` and merge `6251d9a`).

### Added
- Expanded form catalog: categories, subcategories, artifact kinds, activation states, immutable edition metadata, extracted-schema manifests (ADR-013).
- Category-to-form selection UI without recommendations or ranking.
- Cross-repository catalog/package compatibility contract (`contracts/catalog-package-compatibility.json`).
- Delivery-anchored retention proposal (ADR-014) and LaPluma naming/repository boundary (ADR-015).

## [lapluma-app-0.1] — 2026-08-02

### Added
- Mobile Alpha 0.1 end-to-end local vertical slice: ApertureKit (domain/API/UI) with invariant tests; iOS applicant app screens S-01…S-15; offline capture queue with complete file protection; extraction-safety client mirror; en/es core-journey localization; XCUITest journey suite; App Store metadata, release validation, and internal-TestFlight workflow.
