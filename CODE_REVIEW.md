# Code Review — LaPluma App (`lapluma-app-0.2` line)

> **Remediation status (2026-08-06):** Critical and High findings C-1 and H-1…H-10 are addressed on the Alpha 0.2 remediation branch. This document remains the historical review record; current status and residual external blockers are tracked in [`TODO.md`](TODO.md) and [`REVIEW.md`](REVIEW.md).

**Date:** 2026-08-06
**Scope:** Full repository at commit `6251d9a` — `apps/packages/ApertureKit` (Domain, API, UI, Tests), `apps/ios/ApertureApp` + UI tests, `tools/`, `.github/workflows/`, `contracts/`, and repository documentation.
**Method:** Three parallel specialist reviews (Swift package, iOS app layer, tooling/CI), each finding verified against the actual source before inclusion. The repository's own gates were executed in this environment: `tools/check-swift-static.py` (48 Swift files, 0 problems) and the wiki build + link check (34 pages, 0 problems) both pass. Swift and Xcode are unavailable in this review environment, so `swift test` and the XCUITest suite were **not** executed here; test-related claims below come from reading the test sources.

Severity legend: **Critical** — compliance-critical incorrect behavior reachable by a user today. **High** — data loss, dead release path, or a stated invariant the code does not enforce. **Medium** — real defect with bounded impact or a fail-open gate. **Low** — polish, robustness, hygiene.

All findings are tracked as actionable items in [`TODO.md`](TODO.md). Items requiring user decisions or credentials are in [`REVIEW.md`](REVIEW.md).

---

## Critical

### C-1. Field confirmation reports success to the user even when the API call fails
`apps/ios/ApertureApp/Features/Review/ReviewView.swift:187` — the Confirm button runs `_ = try? await session.api.confirmValues(...)` and then unconditionally calls `session.dataDidChange()`, `onConfirmed()`, and `dismiss()`. If `confirmValues` throws, the sheet dismisses and the UI behaves as if the value was confirmed. The file's own doc comment calls this "the control that the whole compliance position rests on." A required value can appear reviewed while remaining unconfirmed, surfacing only later as an unexplained package-generation blocker.
**Fix:** handle the thrown error, keep the sheet open, surface a retry.

---

## High

### H-1. Stub `confirmValues` silently discards a blocking discrepancy, opening the generation gate
`apps/packages/ApertureKit/Sources/ApertureAPI/StubAPIClient.swift:415-427` builds the replacement `FieldValue` without carrying over `field.confirmed?.discrepancy`, and `resolvesDiscrepancyID` is accepted unchecked (any string is recorded as `.discrepancyResolved`). Confirming `person.birth.date` (seeded with a **blocking** discrepancy in `StubStorage.swift:487-511`) erases the discrepancy, `blockingItems` recomputes without it, and `PackageGenerationReadiness` opens without `resolveDiscrepancy` ever being called — the exact fail-closed invariant (SME B-02 / AP-7) the stub claims to enforce. The existing test `confirmationIsAttributed` performs this exact mutation and asserts nothing about the discrepancy.

### H-2. Stub `completeUpload` completes an arbitrary session, ignoring `sessionID`
`StubAPIClient.swift:272-278` — the method pops `storage.pendingUploads.first` (nondeterministic dictionary order) instead of looking up `sessionID`. With two concurrent sessions for different people, completing session A can finalize document B under the wrong person and digest. It also accepts bogus session IDs and never checks `expiresAt`. No test creates two concurrent sessions.

### H-3. A corrupt or schema-incompatible manifest silently discards the entire offline capture queue
`apps/packages/ApertureKit/Sources/ApertureAPI/PendingCaptureQueue.swift:155-159` — `loadManifest` uses `try?` and returns `[]` on any decode failure. A future schema change (or one bad array element) drops every queued offline capture on next launch while their payload files stay on disk. This directly contradicts the type's contract comment: "it is never silently duplicated or discarded."

### H-4. Multi-page scans silently discard every page after the first
`apps/ios/ApertureApp/Features/Capture/CaptureView.swift:312-316` — the button says "Use N scanned pages" but uploads only `pages.first`. A 5-page scan loses pages 2–5 with a success confirmation.

### H-5. The in-app language override never applies to `ApertureString` copy — including all legal disclosures
`ApertureApp.swift:95` sets `.environment(\.locale, ...)` ("The user's chosen language wins"), but `ApertureUI/Localization.swift` resolves via `String(localized:bundle:.module)`, which follows process-preferred localizations, not the SwiftUI environment locale. Selecting Español in Settings switches app-target strings but leaves `disclosure.notALawFirm`, attestation copy, voice-consent copy, confidence chips, and error copy in English — exactly the compliance-critical strings.

### H-6. The Aperture→LaPluma rename broke the legal-acknowledgment localization and left user-visible brand residue
`RegistrationView.swift:53` uses the key "I understand that **LaPluma** is not a law firm…" but both `.strings` files (line 25) define only the **Aperture** variant — Spanish users see raw English for the single most compliance-sensitive onboarding sentence. Further user-visible "Aperture" residue: `SettingsView.swift:128`, `FolderView.swift:300`, both `Localizable.strings:106`. ADR-015 permits internal Aperture module names, not user-visible ones.

### H-7. Three UI tests assert strings the app no longer renders — the suite is red, and no CI job would notice
`ApertureAppUITests.swift:14,113` assert `staticTexts["Aperture"]` while `WelcomeView.swift:37` renders `Text("LaPluma")`; line 33 queries the Aperture acknowledgment wording; lines 488-490 assert cellular copy that `CaptureView.swift:135` no longer renders. Compounding: **no workflow runs `xcodebuild test`** — CI runs only package `swift test` and archive builds — so the flagship "fifteen serial journeys" gate cannot fail in CI. The README's "XCUITest-verified" claim predates the rename and is stale.

### H-8. The TestFlight release workflow is permanently dead: pinned to 0.1.0 against a 0.2.0 project
`.github/workflows/ios-alpha-internal-testflight.yml:29` pins `ALPHA_MARKETING_VERSION: 0.1.0`; `project.pbxproj` has `MARKETING_VERSION = 0.2.0`. Preflight (lines 77-81) fails on every dispatch. The workflow is also internally contradictory: its store-asset validation step requires `releaseLabel == "Alpha 0.2"` in the submission manifest while the confirmation phrase, artifact names, and manifest entries all say Alpha 0.1. Needs a coordinated 0.2 update or retirement (decision in `REVIEW.md`).

### H-9. Chat interview fails silently in three ways
`InterviewViews.swift` — (a) the generic `catch` at 146-147 is an empty block though its comment claims a questionnaire fallback; the draft is cleared before send, so a failed send loses the typed answer with no feedback; (b) `start` uses `try?` (line 123), so a failed `startInterview` yields a dead chat where send silently no-ops; (c) `budgetExhausted` is rendered only by the voice view, never in chat.

### H-10. The Missing tab is an infinite spinner for users with no cases
`MissingItemsView.swift:16-27` — a one-shot `.task` sets `caseID = folders.first?.cases.first?.id`; when nil the view shows `ApertureLoadingView()` forever, and the task is not keyed to `session.dataRevision`, so creating a case later never recovers the tab.

---

## Medium

### Package (ApertureKit)
- **M-1. Orphaned sensitive payload files are never reaped** — `PendingCaptureQueue.swift:80-89,155-168`: a crash between payload write and manifest persist leaves identity-document bytes on disk indefinitely; `erase()` clears memory before disk removal, so a failed removal after a user-requested erasure leaves data behind and a later `enqueue` permanently orphans it.
- **M-2. Actor reentrancy allows concurrent `drain` calls to double-upload** — `PendingCaptureQueue.swift:110-125` snapshots then suspends; a second drain (foreground + reachability trigger — the app really does spawn several, see M-13) re-uploads the same capture on metered data. No in-flight guard.
- **M-3. Trapping `Int32(rawOrientation)` on attacker-controlled EXIF** — `CapturePayloadProcessor.swift:90-91`: an imported image with orientation > `Int32.max` crashes the app inside the privacy gate. Values outside 1–8 also pass unvalidated.
- **M-4. Idempotency keys accepted everywhere, enforced nowhere in the stub** — `StubAPIClient.swift` (create folder/case/upload/confirm/interview). The protocol doc calls duplicate-on-retry "a real failure mode, not a theoretical one"; retry logic developed against this stub will appear to duplicate cases, and code that forgets to dedupe passes. No test reuses a key.
- **M-5. Batch `confirmValues` is non-atomic and diverges memory from disk on failure** — `StubAPIClient.swift:390-468`: a 404 mid-batch leaves earlier confirmations applied in memory, unpersisted; the caller sees a thrown error, the UI sees them confirmed, relaunch reverts them.
- **M-6. `ProgressCountersView` hides blocking-items and readiness from VoiceOver** — `ProgressCountersView.swift:43-44`: `.accessibilityLabel` overrides the combined children and omits `itemsNeedAttentionText` and "Ready to file". Same pattern excludes `formReference` in `BilingualLabel.swift:57`.
- **M-7. Domain `localizationKey` values have no `.strings` entries** — zero `caseState.*`, `modality.*`, `notification.category.*`, `consent.*`, `documentState.*` keys exist in either language; rendering them shows raw keys. No key-coverage test; the test target omits `ApertureUI` entirely.
- **M-8. Empty-`forms` package reports itself fully operational** — `FormCatalog.swift:275-284`: `allSatisfy` on `[]` is vacuously true and `activationState` falls through to `.pilot`, so a malformed catalog payload fails **open** (`allowsCaseCreation == true`, `supportsAutomaticFill == true`) in a deliberately fail-closed design.
- **M-9. A poison capture head-of-line-blocks the drain forever** — `PendingCaptureQueue.swift:110-125`: one bare `catch { break }` treats a permanent local read failure like a transient network error; captures behind an unreadable payload are never attempted. Multi-item drain behavior is untested.

### iOS app
- **M-10. Privacy manifest declares zero collected data types** — `PrivacyInfo.xcprivacy:9-10` vs registration collecting email+name, a live non-stub upload path in `ApertureApp.swift:277-285`, and mic copy claiming audio leaves the device. App Review rejection risk the moment a real endpoint is configured; also diverges from `AppStore/review/app-privacy-answers.md`.
- **M-11. Authentication is a bare `UserDefaults` bool** — `ApertureApp.swift:148-150`: relaunch restores `isAuthenticated` and hard-codes the stub user with no Keychain credential or biometric gate, despite the passkey/Face ID framing. Acceptable only while the local stub is the only client; must not survive into a production scheme.
- **M-12. Broad localization bypasses** — two classes: (a) translations exist but code uses non-localizing `String` initializers (Welcome "What we store" tuples, Folder segmented tabs via `rawValue.capitalized`, `CaseStateChip` labels, `Cancel/Done` ternary in PackageView, HomeView retry/count strings); (b) dozens of user-facing strings absent from both `.strings` files (full inventory in TODO T-19), including most error messages, which are raw `String` properties and can never localize. Mixed-language Spanish UI results; the Spanish navigation UI test doesn't reach these surfaces.
- **M-13. Connectivity flaps spawn overlapping drains** — `ApertureApp.swift:103-115`: initial `.task` plus three `.onChange` watchers each spawn an unstructured `Task { resumePendingCaptures() }`; one cellular→Wi-Fi transition fires several concurrent drains (amplifying package M-2).
- **M-14. Error paths render as infinite spinners or silent blanks** — Review screen conflates loading/empty/error (`ReviewView.swift:23-25,75-83`); Catalog requirements sheet spins forever on error (`CatalogView.swift:243-261`); Folder tabs and Missing list go blank on error (`FolderView.swift:38-41`, `MissingItemsView.swift:117-123`). No retry anywhere on these paths.
- **M-15. `navigationDestination` inside a lazy `List` row** — `MissingItemsView.swift:179-181`: `BatchCard` declares `.navigationDestination(item:)` inside `ForEach` rows — unsupported placement; chat/voice pushes can silently fail with multiple batches. Current tests pass only because the stub yields one batch.
- **M-16. Nested `NavigationStack` pushed as a destination** — `MissingItemsView.swift:344-348` pushes `CaptureEntryView` (which owns its own `NavigationStack`, `CaptureView.swift:28`) onto the Missing stack — doubled/broken navigation bar on the scan resolution path.
- **M-17. Raw `%lld` format specifier can render to users** — `PackageView.swift:105-106` + `StateViews.swift:63`: `progress.itemsNeedAttention` is resolved with no argument, displaying "%lld items still need your attention." when both package requests fail (both are `try?`).
- **M-18. Recovery code copied to the system pasteboard unrestricted** — `RegistrationView.swift:147-149`: no `.localOnly`/`.expirationDate`; Universal Clipboard syncs the recovery credential to every iCloud device, indefinitely.
- **M-19. Consent toggle is optimistic with swallowed failures** — `SettingsView.swift:106-115`: `try?` with no rollback; UI and backend consent state diverge on error, and row-local `@State` won't refresh from reloaded data.

### Tooling / CI
- **M-20. `check-swift-static.py` is fail-open** — `tools/check-swift-static.py:14,61-63`: a wrong root yields "0 Swift files checked, 0 problems" exit 0, and all localisation checks vanish silently if either `.lproj` directory moves. Three workflows depend on it.
- **M-21. The compatibility contract is drifted and unenforced** — `contracts/catalog-package-compatibility.json` lists 4 packages; the shipped catalog has 6 (`NATURALIZATION_N400`, `EAD_I765` missing). Nothing in the repo reads `contracts/` — no test, tool, or workflow — and workflow path filters omit `contracts/**`, so drift can never be caught.
- **M-22. Script injection surface + missing branch guard in `publish-wiki.yml`** — line 41 interpolates `${{ github.ref_name }}` directly into `run:` (the documented injection antipattern; the alpha workflow already shows the safe `env:` pattern), and `workflow_dispatch` has no main-branch guard, so a dispatch from any branch overwrites the entire wiki with that branch's `docs/` under `contents: write`.

---

## Low (summarized — full detail in TODO.md)

- `DocumentAnchor.isDegenerate` checks point count, not distinct points (`Provenance.swift:55-56`) — a zero-area polygon passes the extraction-safety anchor check.
- PDF payloads bypass metadata stripping entirely (`CapturePayloadProcessor.swift:60-72`); `%PDF` sniffed only at byte 0.
- `persist()` swallows all write failures with `try?` (`StubAPIClient.swift:54-66`); read endpoint `valueHistory` mutates and persists; `StubStorage.date` is timezone-dependent (fixture drift); actor `init`s do synchronous disk I/O at launch.
- `ConnectivityMonitor` assumes online before the first path update (`ConnectivityMonitor.swift:27`) — otherwise a model implementation.
- Voice budget shows truncated "0 minutes left" at 59s; failed photo pick wedges the picker selection; hand-rolled English pluralization; "Type DELETE" is untranslated for all locales; `deleteAllLocalData` leaves in-memory preferences diverged until relaunch; `unreadNotificationCount` is dead state; Info.plist purpose strings diverge from their localized overrides (materially different audio-routing claims); `CaptureQualityBanner` comments claim a VoiceOver announcement it never posts; several accessibility hints/labels are unlocalized English.
- UI-test hygiene: coordinate-offset toggle taps, an accessibility-audit filter that becomes a no-op if the tab bar frame is zero, six launches in one test, display-string coupling to fixture content, and no coverage of the offline queue→reconnect→drain journey.
- CI hygiene: mutable tags (`actions/checkout@v4`, `setup-python@v5`) in three workflows vs the repo's own SHA-pinning standard in the alpha workflow; `GITHUB_TOKEN` persisted in the wiki clone's `.git/config`; `swift-static.yml` PR trigger doesn't cover its own workflow file; `validate-ios-store-assets.sh` uses ruby before its ruby-exists guard; `build-wiki.py` exits 0 on missing source pages and defaults to the wrong repo URL; screenshot capture uses a blind `sleep 2` (a launch-screen PNG passes validation); RELEASE.md claims an app-icon check the validator doesn't perform; stale `Aperture.app` product reference vs `PRODUCT_NAME = LaPluma`; `.gitignore` has no `*.p8`/`*.mobileprovision`/`*.ipa` backstop although RELEASE.md instructs materializing an ASC key locally.

---

## What is genuinely good

- **Domain layer**: illegal states are unrepresentable in the ways the docs promise — non-optional `confirmedBy`, `ValueProposal` split from `FieldValue`, counters-not-percentages, banded confidence, typed IDs, backward-compatible custom `Codable`. Zero third-party dependencies, `Sendable` throughout, no force-unwraps outside guarded stub paths, no logging of sensitive data.
- **The alpha TestFlight workflow's hygiene** is well above average: SHA-pinned actions, least-privilege permissions, environment gate, main-branch enforcement, inputs passed via `env:`, typed confirmation phrase, regex-validated identifiers, key material in `RUNNER_TEMP` with `chmod 600` and `always()` cleanup, IPA re-inspection, checksummed artifacts. No `pull_request_target`, no secret echoing, no third-party actions, **no hardcoded team IDs anywhere** (verified by scan).
- The invariant tests pin real product rules, not smoke behavior; `check-swift-static.py` and the wiki toolchain both pass clean today.

The defect pattern mirrors the one SME review 14 §14.7 already named: **controls described in the confident register of something already built** — the stub claims server-grade invariant enforcement but drops discrepancies and ignores idempotency; the queue promises "never silently discarded" and discards; the README claims an XCUITest-verified suite that is currently red; the "compatibility contract" is enforced by nothing.

---

## Recommended README.md updates

1. **`README.md` ADR index (line 62)** — *applied in this PR*: "Architecture Decision Records ADR-001 … ADR-012" → "ADR-001 … ADR-015" (ADR-013/014/015 exist and are load-bearing for Alpha 0.2).
2. **`README.md` Code table (line 157)** — "Builds; 39 tests pass" is stale: the package now contains 48 `@Test` cases (39 invariant + 7 catalog + 2 marketing-fixture). Not changed in this PR because tests cannot be executed in this environment; after running `swift test` on macOS, update to the verified count. Same for `apps/ios/ApertureApp/README.md` ("all 39 invariant tests pass").
3. **`README.md` verification block (lines 160-171)** — the "Fifteen serial journeys … XCUITest-verified" claim predates the LaPluma rename and is currently false (H-7). After fixing the three assertions, re-run the suite and re-date the block.
4. **Suggested addition** to "Repository conventions": a row pointing to `CHANGELOG.md`, `TODO.md`, and `REVIEW.md` as the change/issue/blocker tracking files introduced by this review.

## Ready-to-copy CHANGELOG entries for the recommended fixes

Add under `## [Unreleased]` in `CHANGELOG.md` as each fix lands:

```markdown
### Fixed
- Review sheet no longer reports success when value confirmation fails; errors now surface with retry. (C-1)
- Stub `confirmValues` preserves blocking discrepancies and validates `resolvesDiscrepancyID`; package generation stays fail-closed. (H-1)
- Stub `completeUpload` resolves the session by ID and honors expiry. (H-2)
- Offline capture queue survives manifest schema changes instead of discarding queued captures; orphaned payload files are reaped. (H-3, M-1)
- Multi-page document scans upload every page, not only the first. (H-4)
- In-app language selection now applies to package-bundle strings, including legal disclosures. (H-5)
- Restored the localized legal acknowledgment broken by the LaPluma rename; removed user-visible "Aperture" residue. (H-6)
- UI test suite updated for LaPluma branding; XCUITest job added to CI. (H-7)
- Internal TestFlight workflow updated to the 0.2 release line. (H-8)

### Security
- Recovery code pasteboard copy is now local-only with an expiration. (M-18)
- Wiki publish workflow: branch name passed via env, main-branch guard added for manual dispatch. (M-22)

### Changed
- `check-swift-static.py` fails on a missing root or missing localization directories instead of passing vacuously. (M-20)
- `contracts/catalog-package-compatibility.json` updated to the shipped 6-package catalog and enforced by a package test. (M-21)
```
