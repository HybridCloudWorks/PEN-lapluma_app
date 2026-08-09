# TODO — LaPluma App

Issue and follow-up tracking. Each entry references the 2026-08-06 review ([`CODE_REVIEW.md`](CODE_REVIEW.md)) where applicable; blockers requiring user action live in [`REVIEW.md`](REVIEW.md). Ordered by priority.

---

## Critical

### T-35 · Regression: lazy manifest load discarded queued captures and hung CI
- **Priority:** Critical · **Category:** Bug / Data-loss / CI · **Status:** Complete (2026-08-08), CI-confirmed
- **Description:** The T-28 "move actor-init disk I/O off the construction path" change made `PendingCaptureQueue` load its manifest lazily. Because the loader reaps orphan payloads and `enqueue` writes its payload *before* first touching the capture list, every freshly enqueued payload was deleted immediately after being written. Eight package tests failed (relaunch persistence, orphan reaping, dead-letter reasons, drain retention) and `concurrentDrainsAreCoalesced` spun forever on an unbounded `while await gate.callCount == 0` loop, so the `validate` job burned its full 30-minute timeout on every run from `46a04ff` onward — including on `main` after PR #12 merged.
- **Resolution:** Eager load restored in `init` with a comment stating why laziness is unsafe here; the lazy load is kept only for `StubAPIClient`, where every mutation reads storage before writing. The concurrency test's spin is now bounded by a 10-second deadline so a future regression fails the test instead of timing out the job.
- **Verification:** Run on `7428ac6` passed with "Shared package tests" completing in 36s instead of hitting the 30-minute timeout, and the post-merge run on `main` (`11b26ea`) is green.
- **Notes for future engineers:** Any deferred initialisation in this actor must happen before `enqueue` writes bytes. The reaper treats "payload with no manifest entry" as garbage, which is correct only when the manifest is already loaded.

### T-37 · Review sheet auto-resolves blocking discrepancies, reopening the generation gate
- **Priority:** Critical · **Category:** Bug / Compliance · **Status:** Complete (2026-08-09), pending CI
- **Description:** `ReviewView.swift:248` passes `resolvesDiscrepancyID: field.confirmed?.discrepancy?.id` on **every** confirmation. The stub's H-1/T-02 guard only rejects a *mismatched* identifier (`StubAPIClient.swift:536-544`), so the client always supplies the one value that satisfies it. Tapping Confirm on the seeded `person.birth.date` field without touching `DiscrepancyPanel` sets `unresolvedDiscrepancy = nil`, `PackageGenerationReadiness.blockingDiscrepancies` (`ValueHistory.swift:89`) drops to 0, and `canGenerate` opens — the exact fail-closed invariant (SME B-02 / AP-7) that T-02 was raised to restore. The ledger records `.discrepancyResolved` for what was only a confirm-through. `resolveDiscrepancy` — the dedicated adjudication endpoint — has **zero callers** in `apps/ios/`.
- **Recommended action:** Send `resolvesDiscrepancyID` only when the user made an explicit adjudication (track a `chosenDiscrepancyID` set by `DiscrepancyPanel.onChoose`), or route adjudication through `resolveDiscrepancy` and leave `confirmValues` discrepancy-neutral. Server-side, require the confirmed value to equal a presented alternative before honouring a resolution.
- **Tests:** Package test — confirming with a matching `resolvesDiscrepancyID` and an unchanged value must not open the gate. XCUITest — confirm the discrepancy-bearing field and assert `package-generation-blocked` still renders.
- **Dependencies:** none.
- **Resolution:** `resolvesDiscrepancyID` is now sent only on an explicit adjudication: `FieldDetailSheet.chosenDiscrepancyID` is set by `DiscrepancyPanel.onChoose` and cleared if the value is then hand-edited away from either candidate. `DiscrepancyPanel` now offers **both** values as choices — a panel asking "Which one is right?" that exposed only the alternative could not express adjudicating in favour of the recorded value, so the fail-closed path had no exit. Server-side, a resolution is honoured only when the confirmed value equals one of the two presented candidates (422 otherwise), so a client supplying the identifier reflexively can no longer clear the gate. **Division of responsibility, learned from a failing test:** the server *cannot* distinguish "the applicant deliberately kept the recorded value" from "the client sent the identifier reflexively" — both arrive as the current value plus a matching ID, and keeping the recorded value is legitimate adjudication. Only the client knows whether a choice was made, so `chosenDiscrepancyID` is the actual control; the server check is defence-in-depth that rejects values never presented. Tests: `discrepancyResolutionRequiresAPresentedValue` (hand-typed third value + matching ID → 422, gate stays closed), `confirmationWithoutResolutionKeepsGateClosed` (the shape the sheet now sends when nothing was adjudicated), and `adjudicatingToAlternativeResolvesDiscrepancy`. A UI journey asserting `package-generation-blocked` survives a plain Confirm remains worth adding.

### T-33 · Keep iOS PR validation targeted and short
- **Priority:** Critical · **Category:** CI performance · **Status:** Complete (2026-08-07)
- **Description:** PR #6 spent 18m26s in the UI job because every relevant change ran all 18 serial journeys; package-only changes also allocated a macOS simulator runner.
- **Resolution:** Classify paths on Linux before macOS allocation; skip UI for API/domain, contract, documentation, metadata, and release-tool-only PRs; overlap simulator boot with `build-for-testing`; run five critical PR journeys; run all 18 only on the weekday schedule or explicit manual validation.
- **Guardrail:** A push to `main` runs package/archive validation but does not duplicate the full UI suite already covered by scheduled/manual regression.

### T-34 · Remove actionable UI-test warnings and register toolchain noise
- **Priority:** Critical · **Category:** Test reliability / Tooling · **Status:** Complete (2026-08-07)
- **Description:** PR #6 showed a Confirm-screen diagnostic timeout, raw delete-key control characters, signed-XCTest stripping warnings, and Apple-owned App Intents/simulator/debugger diagnostics.
- **Resolution:** Stabilized the two affected tests, disabled copy-phase stripping only for the Debug UI-test target, preserved `.xcresult` diagnostics on failure, and classified remaining Xcode/iOS-runtime signals in [`IOS_CI_WARNINGS.md`](IOS_CI_WARNINGS.md).
- **Guardrail:** Do not add unused App Intents linkage, enable CI signing, alter simulator runtime files, or broadly filter warnings merely to make logs look quiet.

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
- **Priority:** High · **Category:** Test-coverage / CI · **Status:** Complete (local and PR CI, 2026-08-06)
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

### T-38 · Interviews hard-code the fixture person instead of the assigned one
- **Priority:** High · **Category:** Bug / Data-integrity · **Status:** Complete (2026-08-09), pending CI
- **Description:** `InterviewViews.swift:210` and `:497` pass `personID: PersonID("p_carlos")` — a `realisticInternal` fixture identifier — for every chat and questionnaire session, while `MissingItem.assignedPersonID` (`MissingItem.swift:24`) carries the correct subject and `MissingItemsView.swift:216-221` already has the item in hand. Consequences: (a) every answer is confirmed against the hard-coded person regardless of who the item is assigned to, and confirmations are the compliance-critical write; (b) under `--ui-testing-marketing-safe` the persons are `p_sample_applicant`/`p_sample_member` (`StubStorage.swift:47-48`), so `confirmValues` 404s and the questionnaire is dead on the Missing store-preview route.
- **Recommended action:** Thread `assignedPersonID` from `MissingItem`/`MissingItemBatch` through `MissingDestination` into `ChatInterviewView`, `VoiceConsentView`, and `StructuredQuestionsView`; delete both literals. Have the stub reject a `personID` with no reviewable fields in the case rather than accepting it silently.
- **Tests:** Package test asserting `startInterview` rejects an unknown person; a marketing-safe questionnaire journey.
- **Resolution:** `MissingDestination.interview` carries a `personID` resolved from the batch's own items via `MissingItemsModel.personID(forBatch:)`; resolution paths use `item.assignedPersonID`. `ChatInterviewView`, `VoiceConsentView`, `VoiceInterviewView` and `StructuredQuestionsView` all take the subject as a parameter and pass it through every intra-flow hand-off, so no fixture person literal remains anywhere in `apps/ios`. `startInterview` now 404s when the case has no reviewable fields for that person, so a cross-person or marketing-safe session fails at the start instead of dying on the first confirmation. Test: `interviewRequiresASubjectWithFields`.

### T-39 · Wiki generator silently drops ADR-013, ADR-014, ADR-015
- **Priority:** High · **Category:** Docs pipeline / CI · **Status:** Complete (2026-08-09), pending CI
- **Description:** `tools/build-wiki.py:25-58` `PAGE_MAP` stops at ADR-012, but `docs/adr/` contains ADR-013/014/015. `resolve()` (lines 88-98) finds the unmapped files on disk and rewrites their links to absolute GitHub **blob** URLs, and `check-wiki-links.py:67` skips `https://` links — so the build reports "32 pages" and the link check reports "0 problems" while three load-bearing ADRs (including ADR-015, the LaPluma naming boundary, and ADR-014, pending retention approval) never reach the wiki. `publish-wiki.yml` triggers on `docs/**`, so every new ADR ships this way. The reverse direction is guarded (T-31 made a *mapped-but-missing* source fatal); the forward direction is guarded by nothing.
- **Recommended action:** Add the three entries to `PAGE_MAP` and `SIDEBAR`, then fail the build when any `docs/**/*.md` has no `PAGE_MAP` entry (the symmetric check to T-31's).
- **Verified in this environment:** `python3 tools/build-wiki.py . <tmp>` → `32 pages + _Sidebar + _Footer`; `python3 tools/check-wiki-links.py <tmp>` → `34 pages checked, 0 problems`; generated `ADR-Index.md:24-26` carry blob URLs.
- **Resolution:** ADR-013/014/015 added to `PAGE_MAP` and the sidebar — the wiki mirrors 35 pages (37 checked) instead of silently rewriting those three to blob URLs the link checker skips. `build-wiki.py` now exits non-zero when any `docs/**/*.md` has no `PAGE_MAP` entry: the symmetric partner to T-31's mapped-but-missing check. Verified by deleting an entry, confirming the build fails with `UNMAPPED`, then restoring it.

### T-40 · Static gate misses two applicant-facing string initializers
- **Priority:** High · **Category:** Localization / CI-reliability · **Status:** Complete (2026-08-09), pending CI
- **Description:** `check-swift-static.py:26-29` `APP_LOCALIZED_LITERAL_PATTERNS` covers `Text|Label|Button|NavigationLink|Section|TextField|LabeledContent|Toggle|Picker|Link|ProgressView|DisclosureGroup` but not `ContentUnavailableView(` or `.searchable(prompt:)`. Both are in use with bare literals that exist in **neither** `.strings` file: `CaptureView.swift:361` `"Scanner unavailable"` and `CatalogView.swift:52` `"Search by form number or title"`. `LocalizedStringKey` falls back to the key, so Spanish users see English on the scanner-unavailable path and the catalog search field. T-19 explicitly claimed `CatalogView.swift:52` swept; the gate's "0 problems" is a false negative of the same M-20 fail-open class.
- **Recommended action:** Add both initializers (and audit for other `LocalizedStringKey`-taking APIs) to the pattern list, then add the two keys to `en`/`es`. Re-run the gate to confirm it now fails before the keys are added.

## Medium
- **Resolution:** `check-swift-static.py` gained `ContentUnavailableView` and a `.searchable(prompt:)` pattern (that literal follows a parameter label, so the open-paren patterns could not see it). The widened gate was run **before** the keys were added and failed with exactly the two expected strings — that failure is the evidence it was blind; a passing run would have proved nothing. `"Scanner unavailable"` and `"Search by form number or title"` are now defined in en and es.

### T-41 · Stub `resolveDiscrepancy` succeeds for a discrepancy that does not exist
- **Priority:** Medium · **Category:** Data-validation / Fail-open · **Status:** Complete (2026-08-09), pending CI
- **Description:** `StubStorage.clearDiscrepancy` (`StubStorage.swift:641-645`) `guard ... else { return }` on an unmatched `discrepancyID`, and `StubAPIClient.resolveDiscrepancy` (`StubAPIClient.swift:627-635`) records the empty response as a successful idempotent operation. A caller resolving a bogus or already-resolved identifier receives 200. `confirmValues` correctly 422s the same condition (`StubAPIClient.swift:536-544`) — the two paths disagree.
- **Recommended action:** Return 404/422 when no field in the case carries that discrepancy; add an invariant test.
- **Resolution:** `resolveDiscrepancy` now enforces the same two rules as `confirmValues`: 404 when no field in the case carries that discrepancy, and 422 when the chosen value is not one of the two presented. The second rule was not in the recommended action but belongs with it — T-37 closed that hole on the `confirmValues` door while this endpoint, the dedicated adjudication path, still accepted any string. Both guards run inside the idempotent operation, so a rejected request records no replay entry. Tests: `resolvingAnUnknownDiscrepancyIsRefused`, `resolvingWithAnUnpresentedValueIsRefused` (also asserts the gate stays closed).

### T-42 · Package screen reports a failed request as "not ready"
- **Priority:** Medium · **Category:** Error-handling · **Status:** Complete (2026-08-09), pending CI
- **Description:** `PackageView.swift:114-119` uses `try?` on both `generatedPackage` and `packageGenerationReadiness`. When the readiness request fails, both bindings are nil and the view falls through to `ApertureMessageView(.attention(messageKey: "generation.notReady"))` — a transport failure is rendered as a product state on the screen that explains the compliance gate, with no error text and no retry. T-20 covered Review, catalog requirements, Folder and Missing but not this screen.
- **Recommended action:** Adopt the shared `ApertureLoadState` lifecycle used by `ReviewModel`; distinguish failed from not-ready and expose the localized retry action.
- **Resolution:** A new `PackageModel` carries `ApertureLoadState<Content>`, where `Content` holds the non-optional readiness and the optional generated package, so the screen can never present the compliance verdict from a request that did not arrive. A failure renders `error.packageLoadFailed` with Retry (`package-load-failed`) instead of the "not ready" attention message. The `package-generation-blocked` identifier the UI journey asserts is unchanged. New keys `error.packageLoadFailed` in en and es.

### T-43 · Catalog list load failure renders as an empty catalog
- **Priority:** Medium · **Category:** Error-handling · **Status:** Complete (2026-08-09), pending CI
- **Description:** `CatalogView.swift:74` `packages = (try? await api.catalogPackages(...)) ?? []`. `.task(id: query)` re-runs on every keystroke, so a transient failure silently blanks "Choose forms" and is indistinguishable from a search with no matches. T-20 fixed the *requirements* sheet (`CatalogView.swift:243-261`), not the list.
- **Recommended action:** Same shared load-state treatment as T-42; keep the last good result rather than blanking on a mid-typing failure.
- **Resolution:** `CatalogModel` now holds `ApertureLoadState<[FormPackage]>` plus an `isStale` flag. A failure with results already on screen keeps them and adds a retry banner; a failure with nothing loaded renders `error.catalogLoadFailed` with Retry. A genuinely empty search result is now its own state (`catalog.searchEmpty`) rather than an indistinguishable blank list — on this screen a blank list reads as a claim about which forms exist. The spinner appears only before the first result, so typing does not flash it. New keys `error.catalogLoadFailed` and `catalog.searchEmpty` in en and es.

### T-44 · Exported copies of user data are left in `tmp` and unevenly protected
- **Priority:** Medium · **Category:** Security / Data-rights · **Status:** Complete (2026-08-09), pending CI
- **Description:** `SettingsView.swift:254-256` writes a full JSON export (folders, documents, inbox, consents) to `tmp/LaPluma-Data-Export.json` and never removes it; `PackageView.swift:174-178` writes `tmp/LaPluma-Package-Manifest.txt` (forms, fee, filing address) with `write(to:atomically:encoding:)` and **no** `.completeFileProtection`, unlike every other write in the app. Both use fixed filenames and survive until iOS reclaims `tmp`. `AppSession.deleteAllLocalData` (`ApertureApp.swift:332-349`) does not touch them, so "This permanently removes … stored by this mobile build" (`SettingsView.swift:273`) is untrue while an export exists.
- **Recommended action:** Write to a per-invocation subdirectory with complete file protection, delete on share-sheet dismissal, and clear the export directory inside `deleteAllLocalData`.
- **Resolution:** A new `ExportScratch` (`ApertureApp.swift`) owns one `tmp/LaPluma-Exports` directory and hands out a fresh UUID subdirectory per export, created with `.protectionKey = .complete`. The package manifest now writes through it with `[.atomic, .completeFileProtection]`, matching every other write in the app. `PackageView` discards the directory when the share sheet closes; `DataExportView` discards on `onDisappear` and when preparing a replacement, so exports cannot accumulate. `AppSession.deleteAllLocalData` calls `ExportScratch.clear()`, which is what makes the deletion screen's promise true.

### T-45 · Stub mutations are not rolled back when persistence fails
- **Priority:** Medium · **Category:** Error-handling / Consistency · **Status:** Complete (2026-08-09), pending CI
- **Description:** `StubAPIClient.idempotent` (`StubAPIClient.swift:159-166`) runs `operation()` — which mutates `storage` — then persists; `reclassify` (`:463-464`), `deleteDocument` (`:471-484`), `setConsent` (`:869-874`) and `markRead` (`:850-852`) follow the same order. A `persist()` failure throws 507 *after* the in-memory mutation, so the caller sees an error while the UI keeps showing the change until relaunch reverts it — the M-5 divergence, narrowed by T-14's batch atomicity but not eliminated. `PendingCaptureQueue.enqueue` (`PendingCaptureQueue.swift:128-134`) already demonstrates the correct compensating rollback.
- **Recommended action:** Snapshot and restore `storage` (or apply to a copy and swap on success) around every mutating endpoint.
- **Resolution:** A `commit(_:)` helper snapshots `storage`, runs the mutation, persists, and restores the snapshot if either step throws. It now wraps `idempotent` (so every endpoint routed through it is covered, including a mid-batch throw inside the operation), `reclassify`, `deleteDocument`, `markRead`, `setConsent`, `endInterview` and `deleteAllUserData`. The last one matters most: an erasure that never reached disk must not report success, because the next launch reloads from disk and resurrects everything. Test: `failedPersistenceRollsBackTheMutation` points the client's persistence URL beneath a regular file so every write fails, then asserts `deleteDocument` returns 507 **and** the document and the folder's count are unchanged.

### T-12 · Capture queue robustness set
- **Priority:** Medium · **Category:** Concurrency / Error-handling / Security · **Status:** Complete (2026-08-06)
- **Description:** Reentrancy double-upload (M-2) amplified by four overlapping drain triggers in the app (M-13); poison-capture head-of-line blocking with a single bare `catch` (M-9); orphaned complete-protection payload files never reaped, `erase()` memory-first (M-1).
- **Recommended action:** Add an in-flight guard to `drain`; differentiate local-permanent vs transient failures with a retry budget/dead-letter; reap orphans on load; single drain coordinator in `ApertureApp`. Tests: multi-item drain, concurrent drain, corrupted manifest, erase failure.

### T-13 · Validate EXIF orientation without trapping
- **Priority:** Medium · **Category:** Bug / DoS · **Status:** Complete (2026-08-06)
- **Description:** `Int32(rawOrientation)` traps on orientation > `Int32.max`; out-of-range 0/9+ passed to `oriented(forExifOrientation:)`. (`CapturePayloadProcessor.swift:90-91`) (M-3)
- **Recommended action:** `guard (1...8).contains(rawOrientation) else { default to 1 }`. Add crafted-EXIF test fixture.

### T-14 · Enforce idempotency keys in the stub
- **Priority:** Medium · **Category:** Bug / Test-coverage · **Status:** Complete (2026-08-06)
- **Description:** Every mutating stub endpoint ignores `idempotencyKey`; retry-safety code developed against it is unverifiable. (M-4)
- **Recommended action:** Cache key→response per endpoint; add key-reuse tests. Make batch `confirmValues` atomic (validate-then-apply) while there (M-5).

### T-15 · Fail closed on malformed catalog packages
- **Priority:** Medium · **Category:** Data-validation · **Status:** Complete (2026-08-06)
- **Description:** Empty `forms` yields `.pilot` + `supportsAutomaticFill == true` via vacuous `allSatisfy`. (`FormCatalog.swift:275-284`) (M-8)
- **Recommended action:** Reject empty `forms` in `init(from:)` or return `.unavailable`; add a decode test.

### T-16 · Update and enforce the catalog compatibility contract
- **Priority:** Medium · **Category:** Contract-consistency · **Status:** Complete (2026-08-06)
- **Description:** `contracts/catalog-package-compatibility.json` omits `NATURALIZATION_N400` and `EAD_I765`; nothing reads the file; workflow path filters omit `contracts/**`. (M-21)
- **Recommended action:** Add both packages; add a package test asserting fixture↔contract parity; add `contracts/**` to workflow paths.

### T-36 · macOS verification of the review's test claims
- **Priority:** Medium · **Category:** Test-coverage / Verification · **Status:** Complete (2026-08-06)
- **Description:** The 2026-08-06 review ran in a Linux container without Swift or Xcode, so its test-related claims were read from source rather than executed. Tracked as REVIEW R-5 until a macOS environment could confirm them.
- **Resolution:** Xcode 26.6 completed the Swift package tests with zero failures, the corrected XCUITest suite ran serially locally, and PR #4 completed its PR-visible GitHub Actions UI job. Package tests and a critical-journey subset now run in CI on every pull request, so this is continuously verified rather than a one-off.
- **Remaining verification boundary:** Physical-device and human accessibility testing (VoiceOver reading order, Switch/Voice Control, long-tail screens) remain separate release work — see `MOBILE_NEXT_TASKS.md`.
- **Note:** Moved here from REVIEW.md R-5, which holds only items still blocked on the repository owner.

### T-17 · Privacy manifest and purpose-string truth-up
- **Priority:** Medium · **Category:** Privacy · **Status:** Partially blocked (REVIEW.md R-4)
- **Description:** `NSPrivacyCollectedDataTypes` is empty vs collected email/name/documents/audio claims; Info.plist purpose strings diverge from localized overrides with materially different audio-routing claims. (M-10, L-8)
- **Recommended action:** Declare collected data types consistent with `AppStore/review/app-privacy-answers.md`; reconcile plist vs `InfoPlist.strings` wording in both languages.

### T-18 · Replace UserDefaults auth flag before any production scheme
- **Priority:** Medium (Critical at production) · **Category:** Security · **Status:** Documented (2026-08-08); implementation blocked on the passkey work
- **Description:** `isAuthenticated` bool + hard-coded stub user restored on relaunch; no biometric gate. (`ApertureApp.swift:148-150`) (M-11)
- **Recommended action:** Keychain-backed session + `LAContext` gate when the passkey work lands (MOBILE_NEXT_TASKS "Production foundation"); until then, document the stub-only scope where the flag is set.
- **Done now:** The declaration states plainly that it is not an authentication mechanism, what it does not check (passkey assertion, biometrics, server), the consequence for anyone holding an unlocked device, why that is tolerable while every record behind it is local fixture data, and that the launch-time `allowsLocalStub` precondition is the only thing keeping it out of production.
- **Still blocked:** The Keychain/`LAContext` replacement is meaningless without the passkey/App Attest work, which needs the Apple values in REVIEW R-2.

### T-19 · Localization sweep: bypasses and missing keys
- **Priority:** Medium · **Category:** Localization · **Status:** Engineering complete; professional review remains in REVIEW R-3 (2026-08-07)
- **Description:** (a) Non-localizing `String` initializers bypass existing translations: `WelcomeView.swift:86-90,115-118`; `FolderView.swift:22-24`; `HomeView.swift:25,256,384-397`; `PackageView.swift:222`. (b) Missing from both `.strings` files: Face-ID/sign-in copy (`RegistrationView.swift:192,200`), demo banner (`ApertureApp.swift:65`), capture flow copy and errors (`CaptureView.swift:89,175,206,221,234,305-307,328,413`), folder detail copy (`FolderView.swift:51,55,137-147`), interview copy (`InterviewViews.swift:41,200,278,329-336,373,392`), package copy (`PackageView.swift:36-42,237`), settings/export/delete copy (`SettingsView.swift:47,126-143,185-195,232-235,267`), catalog search prompt (`CatalogView.swift:52`). (c) Dead keys incl. the old Aperture acknowledgment. (d) Raw `%lld` renderable via `StateViews.swift:63` (M-17). (e) Hand-rolled plurals, untranslated "DELETE" token, unlocalized accessibility hints. (M-12, L-4, L-5, L-10, L-11)
- **Resolution:** Converted dynamic `String` copy at its display boundary; added parity-complete en/es app keys and plural rules; localized dates, byte counts, accessibility copy, errors, filing/export manifests, and the invariant `DELETE` instruction; removed the raw format-key path; and extended static validation to reject recurrence. Professional Mexican-Spanish and legal-copy approval remains external in REVIEW R-3.

### T-20 · Error/empty/loading states for Review, Catalog requirements, Folder, Missing
- **Priority:** Medium · **Category:** Error-handling · **Status:** Complete (2026-08-07)
- **Description:** `try?` + spinner/blank remain on Review, Catalog requirements, and Folder; Missing now has explicit loading/empty/ready/failed states and retry. (M-14; `ReviewView.swift:23-25,75-83`, `CatalogView.swift:243-261`, `FolderView.swift:38-41`)
- **Resolution:** Added a shared typed idle/loading/loaded/empty/failed lifecycle; Review, cited requirements, and Folder now distinguish legitimate empty results from request failures, render localized status-colored messages, and expose accessible retry actions without raw server details. Reloads are keyed to data changes without duplicating the post-confirmation request.

### T-21 · Navigation structure fixes in Missing flow
- **Priority:** Medium · **Category:** Bug / Navigation · **Status:** Complete (2026-08-07)
- **Description:** `navigationDestination(item:)` declared inside lazy `List` rows (`MissingItemsView.swift:179-181`); nested `NavigationStack` pushed via `CaptureEntryView` (`MissingItemsView.swift:344-348` + `CaptureView.swift:28`). (M-15, M-16)
- **Resolution:** Hoisted interview and resolution actions into one typed screen-level destination, replaced destination-bearing lazy-row links with selection buttons, and split reusable Capture content from its tab-only stack wrapper. A focused UI journey verifies Missing → Capture → Back; it also caught and eliminated simultaneous activation of sibling resolution links.

### T-22 · VoiceOver completeness on counters and quality banner
- **Priority:** Medium · **Category:** Accessibility · **Status:** Complete (2026-08-07)
- **Description:** `ProgressCountersView.swift:43-44` label omits blocking-items/readiness; `BilingualLabel.swift:57` omits `formReference`; `CaptureView.swift:408-411` claims an announcement it never posts. (M-6, L-9)
- **Resolution:** `ProgressCountersView` and `BilingualLabel` compose full combined labels (blocking-items warning, readiness, caveat; English + form reference) with package tests in `AccessibilityLabelTests.swift`; `CaptureQualityBanner` posts `AccessibilityNotification.Announcement` with the localized hint on appear and on issue change, matching the `ChatInterviewView` pattern.
- **Notes:** Human VoiceOver reading-order verification on device remains part of the release accessibility matrix (`MOBILE_NEXT_TASKS.md`).

### T-23 · Add missing domain localization keys
- **Priority:** Medium · **Category:** Localization · **Status:** Complete (2026-08-07)
- **Description:** `caseState.*`, `modality.*`, `notification.category.*`, `consent.*`, `documentState.*` keys absent from both package `.strings` files. (M-7)
- **Resolution:** Added every current enum-family key to both package locales and an exhaustive English/Spanish lookup test, including every consent consequence and the non-`CaseIterable` document-processing states.

### T-24 · Recovery-code pasteboard hygiene
- **Priority:** Medium · **Category:** Security · **Status:** Complete (2026-08-06)
- **Description:** `UIPasteboard.general.string = code` with no local-only/expiration options. (`RegistrationView.swift:147-149`) (M-18)
- **Recommended action:** `setItems([[UIPasteboard.typeAutomatic: code]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(60)])`.

### T-25 · Consent toggle rollback
- **Priority:** Medium · **Category:** Error-handling · **Status:** Complete (2026-08-07)
- **Description:** Optimistic toggle, `try?`, no rollback, row-local `@State` won't refresh. (`SettingsView.swift:106-115`) (M-19)
- **Resolution:** `ConsentRow` awaits `setConsent`, rolls the switch back on failure with a localized inline error (en/es), disables the toggle while saving, refreshes the consent records after success, and follows external record updates so reloaded state is never masked by stale row state.

### T-26 · Make `check-swift-static.py` fail closed
- **Priority:** Medium · **Category:** CI-reliability · **Status:** Complete (2026-08-06)
- **Description:** Wrong root ⇒ "0 files, 0 problems" exit 0; localisation checks silently skipped if `.lproj` dirs move. (M-20)
- **Recommended action:** Error when 0 Swift files found or expected resource dirs are absent.

### T-27 · Wiki workflow hardening
- **Priority:** Medium · **Category:** Security / CI · **Status:** Complete (2026-08-07)
- **Description:** `${{ github.ref_name }}` interpolated into `run:`; no main-branch guard on `workflow_dispatch`; token persisted in clone URL config. (M-22, L)
- **Resolution:** `publish-wiki.yml` now refuses to publish from any ref but `main`, interpolates no expressions into `run:` scripts (runner env vars only), and passes the token as a per-invocation `http.extraheader` for clone and push so it is never written to `.git/config`. `publish-wiki.yml` and `swift-static.yml` actions are SHA-pinned to the same commits the release workflows already use (`checkout` 11d5960a, `setup-python` a26af69b/v5.6.0).

## Low

### T-46 · Generated wiki chrome still says "Aperture" on a public surface
- **Priority:** Low · **Category:** Localization / Brand · **Status:** Open (found 2026-08-09)
- **Description:** `tools/build-wiki.py:114` `SIDEBAR` heads every wiki page with "Aperture — Solution Definition", and `:166` `FOOTER` renders the legal disclaimer as "**Aperture is not a law firm and does not provide legal advice.**" on all 34 published pages. ADR-015 permits internal Aperture identifiers but requires user-visible surfaces to say LaPluma, and a published wiki is user-visible. The sidebar's ADR list also stops at 012 (see T-39).
- **Recommended action:** Rename both strings to LaPluma. The disclaimer wording is engineering-mechanical here (the same sentence already ships correctly in-app), so this does not need REVIEW R-3.

### T-47 · `build-wiki.py` crashes instead of failing cleanly on a missing target directory
- **Priority:** Low · **Category:** Tooling · **Status:** Open (found 2026-08-09)
- **Description:** `tools/build-wiki.py:189` calls `os.listdir(wiki)` with no existence check; running it against a non-existent checkout raises an unhandled `FileNotFoundError` traceback (reproduced in this environment). The module docstring (`:12`) also still advertises `repo-url  defaults to https://github.com/saulpatinojr/Work-Application_Builder` while `DEFAULT_REPO_URL` (`:180`) is the correct `HybridCloudWorks/PEN-lapluma_app` — T-31 fixed the constant but not the docstring.
- **Recommended action:** Validate the wiki path with a clear message; correct the docstring.

### T-48 · Marketing persona assertion inspects only `staticTexts`
- **Priority:** Low · **Category:** Test-coverage / Privacy · **Status:** Open (found 2026-08-09)
- **Description:** `ApertureAppUITests.swift:720-729` `assertNoInternalPersonas` queries `app.staticTexts` only. The internal folder name "Familia Ramírez" is rendered as a **button** — `openCases` (`:678-680`) matches it via `app.buttons` — so a persona leak on the Home route, the surface where folder names appear, would pass the check.
- **Recommended action:** Query `app.descendants(matching: .any)` (or union `staticTexts`, `buttons`, `switches`, `navigationBars`) for each persona.

### T-49 · Capture always targets the first folder with no selection
- **Priority:** Low · **Category:** UX / Data-integrity · **Status:** Open (found 2026-08-09)
- **Description:** `CaptureView.swift:273` uses `try await session.api.folders().first?.id` with no folder picker and no indication of the destination. `folders()` returns insertion order (`StubAPIClient.swift:171-174`), so once a user has more than one folder — which `CreateFolderView` and `testCreateFolderPersistsAcrossRelaunch` make routine — every capture lands in whichever folder happens to be first.
- **Recommended action:** Show the destination folder and offer a picker when more than one exists.

### T-50 · `importFile` fetches a file size it never enforces
- **Priority:** Low · **Category:** Code-quality / Robustness · **Status:** Open (found 2026-08-09)
- **Description:** `CaptureView.swift:250` requests `.fileSizeKey` alongside `.nameKey` but only `values.name` is used; the 100 MB limit is applied afterwards in `CapturePayloadProcessor.validateByteCount` — i.e. after `Data(contentsOf:options:.mappedIfSafe)` has already mapped the whole file.
- **Recommended action:** Reject over-sized files from the resource value before reading, or drop the unused key.

### T-51 · Store-asset gate reads only the first `MARKETING_VERSION`
- **Priority:** Low · **Category:** CI-reliability · **Status:** Open (found 2026-08-09)
- **Description:** `tools/validate-ios-store-assets.sh:62` `awk ... exit` takes the first `MARKETING_VERSION` in `project.pbxproj`. Debug (`:206`) and Release (`:226`) each declare one; they agree at `0.2.0` today, so a Release-only drift would pass the manifest check.
- **Recommended action:** Collect every `MARKETING_VERSION`, require them to be identical, and compare that value.

### T-52 · Implementation ledger counts have drifted from the code
- **Priority:** Low · **Category:** Docs accuracy · **Status:** Open (found 2026-08-09)
- **Description:** `MOBILE_IMPLEMENTATION_LEDGER.md:42` claims "74 package tests" and "all 19 serial journeys"; the tree has **87** `@Test` cases and **25** `func test` journeys — the values `README.md:158,163` already carries. `:43` claims "229 parity-matched app keys per locale"; `en.lproj/Localizable.strings` has **222** keys plus **11** stringsdict keys. This is the point-in-time-count staleness CLAUDE.md §5 warns about. The ledger's own Rules (`:14`) require recording "the code path that consumes each value", but the Configuration contract table (`:52-113`) has no Consumer column, and no Purpose/Required columns either.
- **Recommended action:** Restate the ledger counts as "what CI runs on every PR" and cross-reference README rather than duplicating numbers; add Purpose/Required/Consumer/Validation-Status columns to the configuration table.

### T-28 · Package/API polish set
- **Priority:** Low · **Category:** Code-quality · **Status:** Complete (2026-08-07)
- **Resolution:** `isDegenerate` requires three distinct points; `preparePDF` strips the PDF Info dictionary via PDFKit with a page-count round-trip check and an honest `strippedImageMetadata: false` fallback (embedded EXIF/XMP inside PDF streams remains server-owned sanitization); `persist()` throws so mutations cannot silently lose durability and `deleteAllUserData`/app deletion propagate it; `valueHistory` reads a non-mutating snapshot; seeded dates are UTC-pinned; `StubAPIClient` storage loads lazily on first actor access instead of in `init` on the main thread. **The same change to `PendingCaptureQueue` was wrong and is reverted:** loading reaps payload files no manifest entry claims, and `enqueue` writes its payload before it touches the capture list, so the deferred load ran the reaper *after* that write and deleted the bytes the caller had just handed over. It silently broke the queue's core no-data-loss guarantee and hung CI (see T-35). The manifest is loaded eagerly in `init` again, with a comment recording why the optimisation is not available here.

### T-29 · App polish set
- **Priority:** Low · **Category:** Bug / UX · **Status:** Complete except purpose strings (2026-08-07)
- **Resolution:** `ConnectivityMonitor` exposes `hasCurrentPath`; the capture drain gates on it (no drain in the optimistic pre-first-update window) and the first real path is its own drain trigger; voice minutes round up; a failed photo pick clears `selectedPhoto` so re-picking works; dead `unreadNotificationCount` removed; in-memory preference reset was already complete.
- **Deferred:** Info.plist vs InfoPlist.strings purpose-string reconciliation makes materially different audio-routing claims and stays with T-17 / REVIEW R-4 — which wording is correct is a privacy decision, not an engineering one.

### T-30 · Test-suite hygiene and coverage
- **Priority:** Low · **Category:** Test-coverage · **Status:** Complete (2026-08-07)
- **Resolution:** New `StubEndpointTests.swift` covers `preparePDF` metadata stripping, the `ExtractionSafetyPolicy` `.verified` branch, anchor degeneracy, the `StubGuardrail` blocked turn, three-question interview script advancement with post-`endInterview` 404, `export`, `setConsent`, and `deleteDocument` counter math. UI tests flip toggles through a shared identifier-first helper (trailing-edge tap — a SwiftUI Toggle's element spans the row, so a center tap lands on the label) with identifiers added to all six toggles; the a11y-audit ignore filter no longer becomes a no-op when the tab-bar frame is zero.
- **Completed follow-up (2026-08-07):** The offline queue→reconnect→drain journey now exists — `--ui-testing-enqueue-capture` reveals a DEBUG-only button that pushes a synthetic image through the production capture path, so the test queues offline, relaunches online, and asserts the queue drains itself. The six-launch marketing test is split into one test per route (safe: the PR workflow selects critical journeys by explicit test name and never referenced the marketing test), each using shared `launchMarketingRoute`/`assertNoInternalPersonas` helpers so one route's failure no longer hides the other five.

### T-31 · Release tooling truth-ups
- **Priority:** Low · **Category:** CI / Docs · **Status:** Complete (2026-08-07)
- **Resolution:** Ruby guard runs before first ruby use; `build-wiki.py` exits non-zero on missing mapped sources and defaults to this repository's URL; screenshot capture polls an app-written readiness marker (30s timeout, fail-closed) instead of `sleep 2`; `validate-ios-release.sh` checks the compiled asset catalog and `CFBundleIconName`, making the RELEASE.md claim true; product reference renamed to `LaPluma.app`; `.gitignore` gains key-material patterns (`*.p8`, `AuthKey_*`, provisioning profiles, `*.ipa`, `*.p12`, `*.cer`); the `swift-static.yml` path widening was already complete.

### T-32 · Structured questionnaire supports one answer only
- **Priority:** Low (acknowledged stub) · **Category:** Bug · **Status:** Complete (2026-08-07)
- **Description:** Renders only the last question; `save` ends the interview and disables itself; a batch advertised as "8 quick questions" accepts one. (`InterviewViews.swift:321,377-394`)
- **Resolution:** Implementation revealed the flow was fully broken, not just single-answer: its only question targeted `person.birth.city`, which the case's reviewable set did not contain, so every save 404'd. That field is now seeded as the unconfirmed missing field the interview exists to fill; the stub scripts three questions bound to required fields and advances one per answer (guardrail-blocked turns explain themselves without advancing); the view saves each answer as a real confirmation, shows a completion state, and ends the interview after the final question; the batch advertises the count it keeps (3).
