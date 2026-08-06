# Changelog

All notable changes to this repository are documented in this file.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the release line is `lapluma-app-<version>` per ADR-015. Ready-to-copy entries for each recommended fix from the 2026-08-06 review are staged in [`CODE_REVIEW.md`](CODE_REVIEW.md) § "Ready-to-copy CHANGELOG entries" — move them here as the fixes land.

## [Unreleased]

### Added
- `CODE_REVIEW.md` — full-repository code review (2026-08-06): 1 Critical, 10 High, 22 Medium findings with file/line evidence, plus README update recommendations.
- `TODO.md` — prioritized issue tracking (T-01…T-32) derived from the review.
- `REVIEW.md` — blockers requiring user decisions, credentials, or environment access (R-1…R-5).
- `CHANGELOG.md` — this file.

### Changed
- `README.md` — corrected the ADR index range to ADR-001…ADR-015 (ADR-013 platform boundaries, ADR-014 delivery-anchored retention, and ADR-015 LaPluma naming were missing from the appendix table).

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
