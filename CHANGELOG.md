# Changelog

All notable changes to this repository are documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the release line is `lapluma-app-<version>` per ADR-015. Ready-to-copy entries for each recommended fix from the 2026-08-06 review are staged in [`CODE_REVIEW.md`](CODE_REVIEW.md) § "Ready-to-copy CHANGELOG entries" — move them here as the fixes land.

## [Unreleased]

### Added
- Finish Together MVP: deterministic 5/10/20-minute Guided Finish sessions, a person-scoped Proof Map with source-region previews and multi-form destinations, and 72-hour Private Relay requests protected by a separately shared six-digit code.
- Production-shaped authenticated and recipient relay client contracts, an OpenAPI 3.1 route set, persistent fixture migrations, ADR-018, English/Spanish copy, and a Debug-only recipient harness for end-to-end simulator testing.
- Form I-131 is restored to the Phase 2 roadmap and appears in the versioned catalog as an honest preview pinned to the official 01/20/25 XFA edition; case creation remains closed until its field map, variable-fee rules, requirements, and round-trip verification exist.
- `CODE_REVIEW.md` — full-repository code review (2026-08-06): 1 Critical, 10 High, 22 Medium findings with file/line evidence, plus README update recommendations.
- `TODO.md` — prioritized issue tracking (T-01…T-32) derived from the review.
- `REVIEW.md` — blockers requiring user decisions, credentials, or environment access (R-1…R-4; R-5 was resolved and moved to `TODO.md` T-36).
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
- Package-level unit coverage for the Home, Catalog, Review, Package, and Missing-items screen models: severity splits, batch-to-person resolution, stale-versus-failed catalog refreshes, and the package-generation gate including transport-failure retention of the readiness verdict.

### Changed
- The Home, Catalog, Review, Package, and Missing-items screen models moved from the app target into `ApertureUI`, so `swift test` exercises their state transitions on every pull request instead of only scheduled simulator journeys; view behavior is unchanged.
- Guided Finish is always regenerated from current missing items; accepted evidence and confirmed fields reconcile immediately, while active relays remain waiting work and never inflate readiness counters.
- `README.md` — corrected the ADR index range to ADR-001…ADR-018.
- Advanced the guarded internal-TestFlight workflow and release documentation to the Alpha 0.2 line; no deployment was run.
- Completed the user-visible LaPluma rename while preserving internal Aperture module identifiers under ADR-015.
- Expanded pull-request path coverage so contract, static-checker, and workflow changes run their owning validations.
- Replaced the all-journey PR UI gate with Linux path classification, five critical UI journeys for UI-relevant changes, and weekday/manual full regression.
- Routed app-authored dynamic status, error, accessibility, date, byte-count, and export copy through the explicitly selected app locale.

### Fixed
- An applicant tapping their own case gets the applicant case screen again (review, forms and export) instead of the workforce case workspace: case rows now route by the authenticated principal's capabilities, so only workforce-only principals see assignments, data entry, and history (T-73).
- The Clients dashboard is now the workforce persona's home tab on iPhone (the applicant persona keeps the personal Home), matching the sign-in and accessibility journeys that expected it, and it offers the plain "Create another folder" flow beside the client wizard (T-73).
- Private Relay persistence stores credential hashes rather than plaintext link tokens, access codes, grants, or upload-session secrets; rejected, revoked, expired, and deleted fixture data is cleaned up at the owning lifecycle boundary.
- Case creation now rejects catalog-preview and unavailable form editions at the API boundary instead of relying on the UI to hide navigation.
- Fully reviewed local cases can now generate and persist a retry-safe demo package; missing review data fails closed and every generated page is marked **NOT FOR FILING**.
- Save to Files and Print now receive a verified, byte-identical PDF artifact instead of a text inventory, while secure delivery retains its separate link contract and scratch filenames cannot escape the protected export directory.
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
- The structured questionnaire actually works: its single question previously targeted a field the case did not contain, so every save failed. It now walks three scripted questions bound to required fields, saves each answer as a real confirmation, explains guardrail-blocked turns, and ends with a completion state matching the advertised count.
- Extraction anchors with repeated points are treated as degenerate; PDF uploads shed their identity-bearing Info dictionary on device (with an honest flag when a rebuild is unsafe); stub mutations fail loudly when local durability fails; deletion failures surface with retry instead of silently resurrecting data on relaunch.
- Launching in airplane mode can no longer start a capture drain in the pre-first-path window; voice minutes round up instead of showing "0 minutes" mid-session; a failed photo pick can be retried by re-picking the same photo.
- Release tooling: screenshot capture waits for an app-written readiness marker instead of a fixed sleep; the release validator checks the compiled app icon it always claimed to; the wiki build fails on missing mapped sources; ruby is checked before first use; the stale `Aperture.app` product reference is renamed; `.gitignore` blocks Apple key material.
- Previously untested stub endpoints (PDF preparation, verified-extraction branch, guardrail block, interview scripting, export, consent, document-counter math) are covered by `StubEndpointTests`; UI-test toggles flip through identifier-first helpers and the accessibility-audit filter no longer silently ignores everything when the tab bar is absent.
- The offline capture promise is now tested end to end: a journey queues a capture with no connection, relaunches online, and asserts the durable queue drains itself. Marketing-fixture checks are one test per route, so an early route's failure no longer hides the rest.
- **Fixed a regression in the previous release entry:** deferring the capture queue's manifest load deleted every freshly queued payload, because the loader reaps payloads no manifest entry claims and `enqueue` writes its payload before touching the capture list. The manifest is loaded eagerly again; the queue's no-data-loss guarantee is restored. The concurrency test that spun forever on the resulting empty queue — burning a 30-minute CI timeout per run — now fails fast on a bounded deadline.
- Repository verification claims are anchored to what CI actually runs (87 package tests every pull request; five critical journeys per PR with the full 25-journey suite on schedule and manual dispatch) instead of a point-in-time count that drifts with every added test.

### Fixed
- Confirming a value no longer clears a blocking document disagreement by itself. The disagreement panel now offers both values as explicit choices, the resolution identifier is sent only when one is chosen, and the stub honours a resolution only for a value that was actually presented — so package generation stays closed until a human adjudicates.
- Interview answers are attributed to the person the missing item is assigned to instead of a hard-coded fixture person, and an interview cannot start for someone the case has no fields for.
- The wiki now publishes ADR-013, ADR-014 and ADR-015, which were being rewritten to external links and silently omitted; the build fails when any documentation page is missing from the page map.
- The static gate now sees `ContentUnavailableView` and `.searchable(prompt:)` literals; the two applicant-facing strings it had been missing are localized in English and Spanish.

### Added
- An advisory Claude code review on pull requests that touch code, driven by the repository's own Code Review SOP. It cannot block a merge — an automated reviewer has already been confidently wrong here — and stays silent until an API key is supplied rather than showing a red check.
- A pull-request UI journey that confirms a value carrying a document disagreement **without** adjudicating it, then re-opens the field to prove the disagreement is still standing. The control that keeps package generation closed here lives in the client, so no package test can cover it; this journey is the only thing that would catch its removal.

### Fixed
- A voice interview no longer starts on a consent record that says the recording notice was never spoken or shown, or that names no notice version. Some states require every party to a recorded conversation to have heard the disclosure, and the check previously only asked whether a consent object existed.
- Dates shown inside Spanish sentences are now formatted in Spanish. Eight places formatted a date against the device's language while the sentence around it used the applicant's choice, so a single label could read "Edición Oct 24, 2025" or "Verificado 2 hours ago".
- A value the applicant typed or spoke no longer displays a confidence band. The band measures how far a document extraction can be trusted, and its highest level tells the applicant that two of their documents agree — which was false for a value they entered from memory, on the screen whose whole purpose is careful checking.
- The secure-delivery sheet no longer empties itself when a queued capture finishes uploading in the background, which discarded the recipient address the applicant had already typed.
- Resolving a document disagreement now refuses an identifier the case does not carry (404) and a value the applicant was never shown (422), instead of reporting success for a gate that never moved. The dedicated adjudication endpoint and the confirmation path now enforce the same two rules.
- The Forms screen no longer reports a failed request as "your forms are not ready". A transport failure now says so and offers Retry, so a compliance verdict is never rendered from a request that did not arrive.
- The form catalog keeps its results when a search request fails mid-typing and offers Retry, and a genuinely empty search now says so — a blank list on that screen reads as a claim about which forms exist.
- Stub mutations that cannot be written to disk are rolled back in memory, so a failed change is no longer left on screen until the next launch silently reverts it. This includes "delete everything": an erasure that never reached disk no longer reports success.

### Fixed
- A captured document now shows where it will be filed, and offers a picker once more than one folder exists, instead of silently landing in whichever folder the API returned first.
- An over-sized file is refused from its own metadata before it is read, and the applicant is told it is larger than 100 MB rather than that it "could not be opened".
- The published wiki says LaPluma on every page — the sidebar, the disclaimer footer, and the three source pages (including the wiki Home page) that still carried the old name in the legal disclaimer.
- The store-asset gate now requires every `MARKETING_VERSION` in the project to agree before comparing it to the release manifest; it previously read only the first, so a Release-only drift would have passed.
- The wiki builder reports a missing repository or wiki checkout instead of raising an unhandled traceback, and its usage text names the right default repository.
- The marketing-fixture privacy check inspects every element type, not only static text, so a persona rendered as a button can no longer pass it.

### Changed
- The implementation ledger's configuration table now records each value's purpose, the milestone it blocks, and whether anything actually validates it. The last of those is the point: 53 of 73 names are agreed spelling that nothing verifies, and only two are asserted on every pull request — which the supply-status column alone did not say.
- `README.md` and the implementation ledger no longer publish test and localization counts that go stale on the next commit; they describe what CI runs on every pull request and name the workflow and gate that enforce it. The ledger's configuration table gained the consuming code path its own rules require, recorded from the repository rather than asserted.

### Security
- Exported copies of applicant data are written to a per-export directory with complete file protection, removed when the sharing screen is done with them, and erased by "delete everything" — which previously left both the data export and the package manifest in `tmp` under fixed filenames, the manifest with no file protection at all.
- Wiki publishing now refuses to run from any branch but `main`, interpolates no expressions into workflow shell scripts, and passes its token as a per-invocation header instead of persisting it in the clone's git config; `publish-wiki.yml` and `swift-static.yml` actions are pinned to commit SHAs.

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
