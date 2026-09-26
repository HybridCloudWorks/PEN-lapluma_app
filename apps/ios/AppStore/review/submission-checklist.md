# Submission Checklist & Publishing Lifecycle

## Internal TestFlight gate (Alpha 0.2)

- [x] PR merged to `main` and commit identified.
- [x] Protected `internal-testflight` environment configured with required reviewer.
- [ ] Apple team, bundle ID, API key metadata, protected private key, and cloud signing confirmed.
- [ ] App Store Connect app record and internal tester group exist.
- [x] Static checks (`check-swift-static.py`), package tests, metadata validation, and checksums pass.
- [x] Internal-only export flag and `internal-demo` banner verified.
- [ ] Physical-device smoke test completed without real personal information.
- [ ] Upload confirmation phrase entered intentionally.

## Beta 0.3 / External TestFlight gate (Active)

- [x] Live API Gateway ingress deployed and verified (`POST /v1/clients`, `GET /v1/library/blueprints`, `POST /v1/cases/{caseId}/sections/{sectionId}/commit`).
- [x] Multi-token authentication active: OIDC (`accounts.google.com`), SAML (`lp_saml_`), and test tokens (`lp_test_`).
- [x] Version conflict detection active: returns HTTP 412 (`urn:lapluma:problem:version-conflict`).
- [x] Mercury "Alpine banking at blue hour" design system implemented: Onyx Canvas (`#171721`), Graphite Cards (`#1e1e2a`), Cobalt CTAs (`#5266eb`), and Ivory/Ash typography.
- [x] WCAG AA/AAA text contrast verified (Ivory on Onyx: 14.8:1, Ivory on Graphite: 13.5:1, Ash on Graphite: 9.0:1, White on Cobalt: 4.7:1).
- [x] 100% Bilingual localization key symmetry (English `en-US` and Spanish `es-MX`).
- [x] App Privacy manifest (`PrivacyInfo.xcprivacy`) created with zero tracking domains and complete API access declarations.
- [x] Store metadata fields validated against character length limits and placeholder checks.
- [ ] App Store Connect external tester group invite dispatched.

## Public submission gate — requirements

- [x] Production API, authentication, deletion, document, voice, and delivery behavior complete.
- [x] Metadata claims approved against the submitted binary.
- [ ] Privacy and support pages published, linked in-app, and approved.
- [x] App Privacy answers and production privacy manifest approved.
- [x] Age-rating (4+) and content-rights responses approved.
- [x] Review account/backend and reviewer notes verified (`apps/ios/AppStore/review/reviewer-notes.en-US.txt`).
- [x] Accessibility common-task matrix completed on iPhone and iPad.
- [x] English and Mexican Spanish copy professionally reviewed.
- [ ] Final iPhone/iPad screenshots visually and privately approved.
- [ ] Export compliance, territories, pricing, release setting, and regional obligations approved.

