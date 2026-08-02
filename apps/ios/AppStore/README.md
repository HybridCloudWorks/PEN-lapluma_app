# App Store submission sources

This directory versions reviewable App Store and TestFlight copy. The text is a
product draft, not authorization to submit the current binary. Public distribution
remains blocked while the app is compiled with `StubAPIClient` and the
`internal-demo` runtime mode.

## Layout

- `metadata/<locale>/` contains App Store Connect text fields.
- `testflight/` contains internal beta instructions.
- `privacy-practices-draft.md` is the review crosswalk for App Privacy answers.
- Generated screenshots belong under `build/store-screenshots/output/` and are not
  committed by default.

Validate the versioned copy without generating images:

```bash
tools/validate-ios-store-assets.sh
```

The capture harness supports the current App Store dimensions, but it deliberately
requires an explicitly approved, marketing-safe data source. It must never capture
applicant information, recovery codes, typed email addresses, secure links, camera
frames, or the realistic internal fixture.

```bash
tools/capture-ios-store-screenshots.sh
```

The default writes Alpha/review images to a path separate from upload candidates. It
uses a non-persistent marketing-safe fixture and six real feature routes: Welcome,
Home, Capture, Missing, Review, and Forms. These images still come from a Debug fixture
build and are not public-store artwork.
For store candidates, set `APERTURE_SCREENSHOT_KIND=store`,
`APERTURE_SCREENSHOT_SOURCE=production-reviewed`, and
`APERTURE_SCREENSHOT_APP_PATH` to an approved simulator app. The script uses temporary
iPhone 17 Pro Max and iPad Pro 13-inch simulators and captures deterministic Home,
Capture, and Missing entry states in English and Spanish. Before upload, a person must
inspect every image for clipping, occlusion, privacy, accurate product behavior, and
appropriate iPad use of space.

The version-bound review package under `review/` records the Alpha distribution gate,
age-rating evidence, privacy answers, accessibility evidence, localization approval,
content rights, reviewer access, and human submission checklist. Run
`REQUIRE_STORE_REVIEW_READY=1 tools/validate-ios-store-assets.sh` only when testing a
future production manifest; it intentionally fails for Alpha 0.1.

Apple-account values, URLs, signing inputs, and unresolved decisions are tracked in
the repository-root `MOBILE_IMPLEMENTATION_LEDGER.md`. Secrets never belong here.
