# TODO — LaPluma App

Issue and follow-up tracking. Each entry references the 2026-08-06 review ([`CODE_REVIEW.md`](CODE_REVIEW.md)) where applicable; blockers requiring user action live in [`REVIEW.md`](REVIEW.md). Ordered by priority.

---

## Critical

### T-01 · Surface confirmation failures in the Review sheet
- **Priority:** Critical · **Category:** Bug / Compliance · **Status:** Complete (2026-08-06)
- **Description:** `ReviewView.swift:187` swallows `confirmValues` errors with `try?` and unconditionally dismisses, so a failed confirmation looks successful. This is the human-confirmation control the compliance position rests on. (CODE_REVIEW C-1)
- **Recommended action:** Replace `try?` with do/catch; on error keep the sheet open, show a localized retry message, and do not call `dataDidChange()`/`onConfirmed()`.
- **Dependencies:** none. **Notes:** Add a UI test that stubs a failing confirm.

## High

### T-02 · Preserve blocking discrepancies through `confirmValues` in the stub
- **Priority:** High · **Category:** Bug / Compliance · **Status:** Complete (2026-08-06)
- **Description:** `StubAPIClient.swift:415-427` rebuilds `FieldValue` without the prior `discrepancy` and accepts any `resolvesDiscrepancyID` unchecked; confirming the seeded `person.birth.date` opens the generation gate without resolution. (H-1)
- **Recommended action:** Carry the discrepancy forward unless a matching, validated `resolvesDiscrepancyID` is supplied; reject unknown IDs with 422. Extend `confirmationIsAttributed` to assert discrepancy survival and gate closure.

### T-03 · Make `completeUpload` honor `sessionID` and expiry
- **Priority:** High · **Category:** Bug · **Status:** Complete (2026-08-06)
- **Description:** `StubAPIClient.swift:272-278` pops an arbitrary pending upload; concurrent sessions can complete under the wrong person/digest. (H-2)
- **Recommended action:** Look up by `sessionID`, 404 on miss, 410 on expired. Add a two-concurrent-sessions test.

### T-04 · Harden the offline capture-queue manifest against decode failure
- **Priority:** High · **Category:** Error-handling / Data-loss · **Status:** Complete (2026-08-06)
- **Description:** `PendingCaptureQueue.swift:155-159` returns `[]` on any decode failure, silently dropping the queue while payload bytes remain on disk. (H-3; related M-1 orphan reaping)
- **Recommended action:** Decode per-element leniently; on total failure preserve the manifest aside and surface a recoverable error. Reap payload files with no manifest entry; make `erase()` disk-first.

### T-05 · Upload all scanned pages
- **Priority:** High · **Category:** Bug / Data-loss · **Status:** Complete (2026-08-06)
- **Description:** `CaptureView.swift:312-316` uploads only `pages.first` behind a "Use N scanned pages" label. (H-4)
- **Recommended action:** Enqueue every page (or assemble a multi-page payload consistent with the 500-page limit policy); add a multi-page capture test.

### T-06 · Make the in-app language override reach package-bundle strings
- **Priority:** High · **Category:** Localization / Compliance · **Status:** Complete (2026-08-06)
- **Description:** `.environment(\.locale)` does not affect `String(localized:bundle:.module)`; legal disclosures, attestation, consent, and error copy ignore the Settings language picker. (H-5)
- **Recommended action:** Resolve `ApertureString` against an explicit locale-selected bundle (e.g. `Bundle.module.path(forResource:ofType:)` lookup driven by `session.preferredLocale`), or set per-app language via `UserDefaults` `AppleLanguages` with restart semantics — decide and apply consistently to the main-bundle `String(localized:)` call sites too.

### T-07 · Finish the user-visible LaPluma rename
- **Priority:** High · **Category:** Localization / Compliance · **Status:** Engineering complete; professional review remains in REVIEW R-3 (2026-08-06)
- **Description:** Key mismatch breaks the localized legal acknowledgment (`RegistrationView.swift:53` vs `Localizable.strings:25`); "Aperture" still user-visible in `SettingsView.swift:128`, `FolderView.swift:300`, `Localizable.strings:106`. (H-6)
- **Recommended action:** Rename the `.strings` keys and values in both languages, sweep for user-visible "Aperture", keep internal module names per ADR-015. Professional Spanish review of changed legal copy (see REVIEW.md R-3).

### T-08 · Repair the UI test suite and run it in CI
- **Priority:** High · **Category:** Test-coverage / CI · **Status:** Complete locally; first PR CI run pending (2026-08-06)
- **Description:** Three tests assert pre-rename strings and cannot pass (`ApertureAppUITests.swift:14,33,113,488-490`); no workflow runs `xcodebuild test`, so the suite being red is invisible. (H-7)
- **Recommended action:** Fix the assertions; add an XCUITest job (macOS runner) to `ios-release-validation.yml` or a dedicated workflow; then refresh the README verification claims (CODE_REVIEW README rec. 2-3).

### T-09 · Update or retire the Alpha internal TestFlight workflow for 0.2
- **Priority:** High · **Category:** CI-reliability · **Status:** Engineering complete; environment and Apple values remain in REVIEW R-1/R-2 (2026-08-06)
- **Description:** `ALPHA_MARKETING_VERSION: 0.1.0` vs `MARKETING_VERSION = 0.2.0`; confirmation phrase, artifact names, and manifest entries still say Alpha 0.1 while the asset validator requires "Alpha 0.2". (H-8)
- **Recommended action:** Coordinated update of version constant, confirmation phrase, artifact labels, and manifest fields to the 0.2 release line — or retire the workflow until the 0.2 release process is defined.

### T-10 · Give the chat interview real failure paths
- **Priority:** High · **Category:** Error-handling · **Status:** Complete (2026-08-06)
- **Description:** Empty `catch` on send (draft already cleared → answer lost), `try?` on start (dead chat), `budgetExhausted` never rendered in chat. (`InterviewViews.swift:44-47,123-148,262-264`) (H-9)
- **Recommended action:** Restore the draft on failure, surface start/send errors with retry, render budget exhaustion in chat, and implement (or remove the comment about) the questionnaire fallback.

### T-11 · Fix the Missing tab empty-state spinner
- **Priority:** High · **Category:** Bug / Empty-state · **Status:** Complete (2026-08-06)
- **Description:** One-shot `.task` leaves a permanent spinner when no case exists and never re-checks after case creation. (`MissingItemsView.swift:16-27`) (H-10)
- **Recommended action:** Key the task to `session.dataRevision`; render a real empty state with a "create an application" path.

## Medium

### T-12 · Capture queue robustness set
- **Priority:** Medium · **Category:** Concurrency / Error-handling / Security · **Status:** Open
- **Description:** Reentrancy double-upload (M-2) amplified by four overlapping drain triggers in the app (M-13); poison-capture head-of-line blocking with a single bare `catch` (M-9); orphaned complete-protection payload files never reaped, `erase()` memory-first (M-1).
- **Recommended action:** Add an in-flight guard to `drain`; differentiate local-permanent vs transient failures with a retry budget/dead-letter; reap orphans on load; single drain coordinator in `ApertureApp`. Tests: multi-item drain, concurrent drain, corrupted manifest, erase failure.

### T-13 · Validate EXIF orientation without trapping
- **Priority:** Medium · **Category:** Bug / DoS · **Status:** Open
- **Description:** `Int32(rawOrientation)` traps on orientation > `Int32.max`; out-of-range 0/9+ passed to `oriented(forExifOrientation:)`. (`CapturePayloadProcessor.swift:90-91`) (M-3)
- **Recommended action:** `guard (1...8).contains(rawOrientation) else { default to 1 }`. Add crafted-EXIF test fixture.

### T-14 · Enforce idempotency keys in the stub
- **Priority:** Medium · **Category:** Bug / Test-coverage · **Status:** Open
- **Description:** Every mutating stub endpoint ignores `idempotencyKey`; retry-safety code developed against it is unverifiable. (M-4)
- **Recommended action:** Cache key→response per endpoint; add key-reuse tests. Make batch `confirmValues` atomic (validate-then-apply) while there (M-5).

### T-15 · Fail closed on malformed catalog packages
- **Priority:** Medium · **Category:** Data-validation · **Status:** Open
- **Description:** Empty `forms` yields `.pilot` + `supportsAutomaticFill == true` via vacuous `allSatisfy`. (`FormCatalog.swift:275-284`) (M-8)
- **Recommended action:** Reject empty `forms` in `init(from:)` or return `.unavailable`; add a decode test.

### T-16 · Update and enforce the catalog compatibility contract
- **Priority:** Medium · **Category:** Contract-consistency · **Status:** Open
- **Description:** `contracts/catalog-package-compatibility.json` omits `NATURALIZATION_N400` and `EAD_I765`; nothing reads the file; workflow path filters omit `contracts/**`. (M-21)
- **Recommended action:** Add both packages; add a package test asserting fixture↔contract parity; add `contracts/**` to workflow paths.

### T-17 · Privacy manifest and purpose-string truth-up
- **Priority:** Medium · **Category:** Privacy · **Status:** Partially blocked (REVIEW.md R-4)
- **Description:** `NSPrivacyCollectedDataTypes` is empty vs collected email/name/documents/audio claims; Info.plist purpose strings diverge from localized overrides with materially different audio-routing claims. (M-10, L-8)
- **Recommended action:** Declare collected data types consistent with `AppStore/review/app-privacy-answers.md`; reconcile plist vs `InfoPlist.strings` wording in both languages.

### T-18 · Replace UserDefaults auth flag before any production scheme
- **Priority:** Medium (Critical at production) · **Category:** Security · **Status:** Open
- **Description:** `isAuthenticated` bool + hard-coded stub user restored on relaunch; no biometric gate. (`ApertureApp.swift:148-150`) (M-11)
- **Recommended action:** Keychain-backed session + `LAContext` gate when the passkey work lands (MOBILE_NEXT_TASKS "Production foundation"); until then, document the stub-only scope where the flag is set.

### T-19 · Localization sweep: bypasses and missing keys
- **Priority:** Medium · **Category:** Localization · **Status:** Open
- **Description:** (a) Non-localizing `String` initializers bypass existing translations: `WelcomeView.swift:86-90,115-118`; `FolderView.swift:22-24`; `HomeView.swift:25,256,384-397`; `PackageView.swift:222`. (b) Missing from both `.strings` files: Face-ID/sign-in copy (`RegistrationView.swift:192,200`), demo banner (`ApertureApp.swift:65`), capture flow copy and errors (`CaptureView.swift:89,175,206,221,234,305-307,328,413`), folder detail copy (`FolderView.swift:51,55,137-147`), interview copy (`InterviewViews.swift:41,200,278,329-336,373,392`), package copy (`PackageView.swift:36-42,237`), settings/export/delete copy (`SettingsView.swift:47,126-143,185-195,232-235,267`), catalog search prompt (`CatalogView.swift:52`). (c) Dead keys incl. the old Aperture acknowledgment. (d) Raw `%lld` renderable via `StateViews.swift:63` (M-17). (e) Hand-rolled plurals, untranslated "DELETE" token, unlocalized accessibility hints. (M-12, L-4, L-5, L-10, L-11)
- **Recommended action:** Convert to `LocalizedStringKey`/`String(localized:)` throughout; add missing keys in en+es; delete dead keys; use plural format keys (stringsdict); extend `check-swift-static.py` used-key check to catch bypasses it currently misses.

### T-20 · Error/empty/loading states for Review, Catalog requirements, Folder, Missing
- **Priority:** Medium · **Category:** Error-handling · **Status:** Open
- **Description:** `try?` + spinner/blank on four screens; no retry. (M-14; `ReviewView.swift:23-25,75-83`, `CatalogView.swift:243-261`, `FolderView.swift:38-41`, `MissingItemsView.swift:117-123`)
- **Recommended action:** Introduce a shared loadable-state enum (idle/loading/loaded/empty/failed) and `ApertureMessageView` retry rendering.

### T-21 · Navigation structure fixes in Missing flow
- **Priority:** Medium · **Category:** Bug / Navigation · **Status:** Open
- **Description:** `navigationDestination(item:)` declared inside lazy `List` rows (`MissingItemsView.swift:179-181`); nested `NavigationStack` pushed via `CaptureEntryView` (`MissingItemsView.swift:344-348` + `CaptureView.swift:28`). (M-15, M-16)
- **Recommended action:** Hoist the destination to the stack level keyed on a selection model; split `CaptureView` content from its stack wrapper so pushed contexts embed content only.

### T-22 · VoiceOver completeness on counters and quality banner
- **Priority:** Medium · **Category:** Accessibility · **Status:** Open
- **Description:** `ProgressCountersView.swift:43-44` label omits blocking-items/readiness; `BilingualLabel.swift:57` omits `formReference`; `CaptureView.swift:408-411` claims an announcement it never posts. (M-6, L-9)
- **Recommended action:** Compose full accessibility labels; post `AccessibilityNotification.Announcement` on quality-hint changes (pattern exists in `ChatInterviewView`).

### T-23 · Add missing domain localization keys
- **Priority:** Medium · **Category:** Localization · **Status:** Open
- **Description:** `caseState.*`, `modality.*`, `notification.category.*`, `consent.*`, `documentState.*` keys absent from both package `.strings` files. (M-7)
- **Recommended action:** Add en+es entries; add a key-coverage test; add `ApertureUI` to the test target (`Package.swift:25`).

### T-24 · Recovery-code pasteboard hygiene
- **Priority:** Medium · **Category:** Security · **Status:** Open
- **Description:** `UIPasteboard.general.string = code` with no local-only/expiration options. (`RegistrationView.swift:147-149`) (M-18)
- **Recommended action:** `setItems([[UIPasteboard.typeAutomatic: code]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(60)])`.

### T-25 · Consent toggle rollback
- **Priority:** Medium · **Category:** Error-handling · **Status:** Open
- **Description:** Optimistic toggle, `try?`, no rollback, row-local `@State` won't refresh. (`SettingsView.swift:106-115`) (M-19)
- **Recommended action:** Await the call, revert on failure with a message; derive toggle state from the session model.

### T-26 · Make `check-swift-static.py` fail closed
- **Priority:** Medium · **Category:** CI-reliability · **Status:** Open
- **Description:** Wrong root ⇒ "0 files, 0 problems" exit 0; localisation checks silently skipped if `.lproj` dirs move. (M-20)
- **Recommended action:** Error when 0 Swift files found or expected resource dirs are absent.

### T-27 · Wiki workflow hardening
- **Priority:** Medium · **Category:** Security / CI · **Status:** Open
- **Description:** `${{ github.ref_name }}` interpolated into `run:`; no main-branch guard on `workflow_dispatch`; token persisted in clone URL config. (M-22, L)
- **Recommended action:** Pass ref via `env:`; add `test "$GITHUB_REF" = refs/heads/main`; use header-based auth for the wiki clone. Port SHA-pinning to the three tag-pinned workflows.

## Low

### T-28 · Package/API polish set
- **Priority:** Low · **Category:** Code-quality · **Status:** Open
- **Description & actions:** Distinct-point check in `DocumentAnchor.isDegenerate` (`Provenance.swift:55-56`); PDF metadata stripping or explicit downstream gate on `strippedImageMetadata == false` (`CapturePayloadProcessor.swift:60-72`); replace `try?` in `persist()` with surfaced errors; make `valueHistory` read-only; UTC-pin `StubStorage.date`; move actor-init disk I/O off the construction path.

### T-29 · App polish set
- **Priority:** Low · **Category:** Bug / UX · **Status:** Open
- **Description & actions:** `ConnectivityMonitor` initial `isOnline` should be unknown/false until first path update; ceil voice-budget minutes display; clear `selectedPhoto` on failed load (`CaptureView.swift:85-95`); reset in-memory preferences in `deleteAllLocalData`; remove dead `unreadNotificationCount`; reconcile Info.plist purpose strings with localized overrides.

### T-30 · Test-suite hygiene and coverage
- **Priority:** Low · **Category:** Test-coverage · **Status:** Open
- **Description & actions:** Replace coordinate-offset toggle taps with accessibility identifiers; fix the a11y-audit filter zero-frame no-op; split the six-launch marketing test; add package tests for `preparePDF`, EXIF orientation, `ExtractionSafetyPolicy` `.verified` branch, `StubGuardrail` blocked-turn, `endInterview`, `export`, `setConsent`, `deleteDocument` counters; add an offline queue→reconnect→drain UI journey.

### T-31 · Release tooling truth-ups
- **Priority:** Low · **Category:** CI / Docs · **Status:** Open
- **Description & actions:** Move the ruby-exists guard to the top of `validate-ios-store-assets.sh`; make `build-wiki.py` fail on missing sources and fix `DEFAULT_REPO_URL`; replace screenshot `sleep 2` with a readiness poll; align RELEASE.md's icon-check claim with `validate-ios-release.sh` (or add the check); fix stale `Aperture.app` product reference; add `*.p8`/`AuthKey_*`/`*.mobileprovision`/`*.ipa` to `.gitignore`; widen `swift-static.yml` PR paths to cover the workflow file and checker script.

### T-32 · Structured questionnaire supports one answer only
- **Priority:** Low (acknowledged stub) · **Category:** Bug · **Status:** Open
- **Description:** Renders only the last question; `save` ends the interview and disables itself; a batch advertised as "8 quick questions" accepts one. (`InterviewViews.swift:321,377-394`)
- **Recommended action:** Iterate questions or scope the advertised count; track under the interview production work.
