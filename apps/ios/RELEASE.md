# Aperture iOS release runbook

The repository can produce and validate an unsigned Release archive without Apple
credentials. Uploading to TestFlight remains intentionally blocked until the values in
`MOBILE_IMPLEMENTATION_LEDGER.md` are supplied.

## Repository validation

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  tools/validate-ios-release.sh /tmp/Aperture-Unsigned.xcarchive
```

This validates the Release build, app icon, resolved version/build number, bundle
identifier, and bundled privacy manifest. GitHub Actions runs the same check on a
`macos-26` runner. The resulting archive is unsigned and cannot be distributed.
CI supplies its run number as `CURRENT_PROJECT_VERSION`, while local validation uses
the project build number unless `APERTURE_BUILD_NUMBER_OVERRIDE` is set.

## Store metadata and visual assets

Localized App Store copy and internal TestFlight instructions live under
`apps/ios/AppStore/`. Validate character limits and any generated images with:

```bash
tools/validate-ios-store-assets.sh
```

The capture harness produces deterministic English and Spanish entry-state images for
the current 6.9-inch iPhone and 13-inch iPad screenshot classes. It requires at least
6 GB of free disk space, creates temporary simulators, and deletes them after capture.

```bash
tools/capture-ios-store-screenshots.sh
```

That default produces internal-review images only. It uses the realistic fixture and
must not be uploaded. Store capture requires an independently approved simulator app
and an explicit gate:

```bash
APERTURE_SCREENSHOT_KIND=store \
APERTURE_SCREENSHOT_SOURCE=production-reviewed \
APERTURE_SCREENSHOT_APP_PATH=/path/to/Approved.app \
tools/capture-ios-store-screenshots.sh
```

Current accepted portrait dimensions encoded by the validator are 1260×2736,
1290×2796, or 1320×2868 for the 6.9-inch iPhone class and 2048×2732 or 2064×2752 for
the 13-inch iPad class. Each localized family accepts 1–10 images with no alpha
channel. Human review remains required for alignment, occlusion, privacy, accurate
claims, and iPad composition.

## Internal TestFlight archive

Do not place credentials in this repository. On a protected release machine or CI job,
provide the Apple team and App Store Connect API values through its secret store.

```bash
xcodebuild \
  -project apps/ios/ApertureApp.xcodeproj \
  -scheme ApertureApp \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/Aperture.xcarchive \
  DEVELOPMENT_TEAM="$APPLE_DEVELOPMENT_TEAM" \
  PRODUCT_BUNDLE_IDENTIFIER="$PRODUCT_BUNDLE_IDENTIFIER" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$APP_STORE_CONNECT_API_PRIVATE_KEY_PATH" \
  -authenticationKeyID "$APP_STORE_CONNECT_API_KEY_ID" \
  -authenticationKeyIssuerID "$APP_STORE_CONNECT_API_ISSUER_ID" \
  archive

xcodebuild \
  -exportArchive \
  -archivePath build/Aperture.xcarchive \
  -exportOptionsPlist apps/ios/ExportOptions-InternalTestFlight.plist \
  -exportPath build/TestFlight \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$APP_STORE_CONNECT_API_PRIVATE_KEY_PATH" \
  -authenticationKeyID "$APP_STORE_CONNECT_API_KEY_ID" \
  -authenticationKeyIssuerID "$APP_STORE_CONNECT_API_ISSUER_ID"
```

The export options permanently mark this artifact as internal-TestFlight-only. This is
appropriate while authentication, API calls, voice, and extraction are still local
fixtures. Create a separate reviewed export profile before external testing or App Store
submission; do not silently remove that restriction.

## App Store Connect checklist

- Confirm the final bundle identifier and Apple Developer team.
- Create the App Store Connect app record and internal tester group.
- Supply privacy-policy, support, and marketing URLs.
- Complete App Privacy answers for the behavior of the submitted binary. The current
  privacy manifest declares no tracking and no off-device collection because the current
  mobile slice uses local fixtures; update it when production networking is introduced.
- Confirm export-compliance answers. The current binary declares no non-exempt encryption.
- Provide localized description, keywords, release notes, review notes, age rating, and
  contact details. English and Mexican Spanish copy is drafted in the repository, but
  still needs Product/Legal approval and professional Spanish review.
- Capture current-device screenshots for every supported family. The target currently
  supports iPhone and iPad, so both require QA and store assets unless iPad is removed by
  an explicit product decision.
- Run physical-device onboarding, capture/import, offline recovery, accessibility, and
  deletion tests before inviting testers.
- Increment `CURRENT_PROJECT_VERSION` for every upload; never reuse a build number.

## Production-only capabilities

Associated Domains and App Attest entitlements are not added with fake values. Add them
only after the relying-party domain, Apple team, production bundle identifier, and hosted
`apple-app-site-association` file are confirmed. Background upload capability should be
added with the production `URLSession` implementation; `UIBackgroundModes=processing`
was removed because the current app does not register a `BGProcessingTask`.
