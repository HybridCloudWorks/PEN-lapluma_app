# REVIEW — items blocked on user action or decisions

Companion to [`CODE_REVIEW.md`](CODE_REVIEW.md) (findings) and [`TODO.md`](TODO.md) (task tracking). Each item below cannot be completed by an engineer alone: it needs a decision, a credential, or environment access. Another engineer should be able to pick any item up from this page without additional context.

---

## R-1 · Decide the fate of the Alpha internal TestFlight workflow (blocks TODO T-09)

- **Blocker:** `.github/workflows/ios-alpha-internal-testflight.yml` is pinned to the Alpha 0.1 release line (`ALPHA_MARKETING_VERSION: 0.1.0`, confirmation phrase `UPLOAD ALPHA 0.1 INTERNAL`, Alpha-0.1 artifact/manifest labels) while the project is at `MARKETING_VERSION = 0.2.0` and the store-asset validator requires `releaseLabel == "Alpha 0.2"`. Preflight fails on every dispatch.
- **Why it exists:** The 0.2 catalog work updated the project version and submission manifest but not the release workflow; whether Alpha 0.2 ships through the same internal-TestFlight procedure is a release-management decision, not a code fix.
- **Impact if unresolved:** No signed build can be produced or uploaded; the only release path in the repository is dead.
- **Steps required from you:**
  1. Decide: (a) rev the workflow to the 0.2 line, or (b) retire it until the 0.2 release process is defined. → *Outcome:* engineering can apply a coordinated update (version constant, phrase, labels, manifest fields) in one PR, or remove the dead workflow.
  2. If (a): confirm the `internal-testflight` GitHub environment exists and is protected, and that `vars.APPLE_DEVELOPMENT_TEAM` plus the App Store Connect API-key secrets listed in `MOBILE_IMPLEMENTATION_LEDGER.md` are populated. → *Outcome:* a dispatch run passes preflight and uploads an internal build.
- **Recommended next action:** Option (a) — the workflow's hygiene is excellent and worth keeping current.
- **References:** CODE_REVIEW H-8; `apps/ios/RELEASE.md`; `MOBILE_IMPLEMENTATION_LEDGER.md`; `MOBILE_NEXT_TASKS.md` § Release and public store.

## R-2 · Apple / App Store Connect credentials and store-record setup

- **Blocker:** Signing team, ASC API key, app record, tester group, privacy/support URLs, and the store-listing approvals (age rating, content rights, App Privacy, export compliance, territories, pricing, review access) are all external values that only the account owner can supply or approve.
- **Why it exists:** Deliberate repository policy — no credentials or production endpoints are committed (`MOBILE_ALPHA_0.2_SPRINT_2.md` § Completion criteria); the ledger records each missing value with owner and format.
- **Impact if unresolved:** TestFlight distribution (R-1 step 2), store submission, and the production-configuration replacement of `internal-demo` are all blocked; unrelated mobile work is not.
- **Steps required from you:** Work through the open rows of `MOBILE_IMPLEMENTATION_LEDGER.md` and the unchecked items in `MOBILE_NEXT_TASKS.md` § Release and public store. → *Outcome:* each ledger row flips to supplied; release automation becomes runnable end-to-end.
- **Recommended next action:** Populate the `internal-testflight` environment first — it unblocks the only automated pipeline.

## R-3 · Brand-rename scope and professional Spanish review (blocks parts of TODO T-07, T-19)

- **Blocker:** The Aperture→LaPluma rename is incomplete in user-visible surfaces, and the broken string is the legal acknowledgment ("…is not a law firm…"). Re-wording legal/compliance copy — especially the Spanish translations — requires the professional Mexican-Spanish and legal-copy review the repo already gates on (`MOBILE_NEXT_TASKS.md` § Voice and accessibility; `apps/ios/ApertureApp/README.md` known gaps).
- **Why it exists:** ADR-015 allows internal Aperture module names but requires user-visible surfaces to say LaPluma; engineering can mechanically rename keys, but sign-off on legal wording is not an engineering call.
- **Impact if unresolved:** Spanish users see the raw English acknowledgment key at registration (CODE_REVIEW H-6); mixed Aperture/LaPluma branding ships to users; App Review metadata (`apps/ios/AppStore/metadata/*`) may diverge from in-app naming.
- **Steps required from you:**
  1. Confirm engineering may proceed with a mechanical key rename now, with existing translations carried over verbatim. → *Outcome:* H-6 is fixed immediately; Spanish acknowledgment renders again.
  2. Commission the professional review of the renamed legal/long-tail copy. → *Outcome:* T-07/T-19 close fully.
- **Recommended next action:** Approve step 1 now; it restores a broken compliance disclosure without changing any wording.

## R-4 · App Privacy declarations once a real endpoint exists (blocks TODO T-17)

- **Blocker:** `PrivacyInfo.xcprivacy` declares zero collected data types, while registration collects email+name and the capture pipeline contains a live upload path used the moment a non-stub URL is configured. What must be declared depends on the production data-handling decisions (server retention, linkage, tracking answers) recorded in `apps/ios/AppStore/review/app-privacy-answers.md` and ADR-014's pending retention approval.
- **Why it exists:** Accurate declarations require Data/Privacy/Legal decisions (delivery-anchored retention, ADR-014 explicitly "cannot become a user promise until Data, Privacy, and Legal approve").
- **Impact if unresolved:** App Review rejection risk and a public privacy-label mismatch as soon as real networking ships; today's stub-only build is technically accurate but already contradicts the app's own microphone purpose string.
- **Steps required from you:** Obtain the ADR-014 approvals and confirm the collected-data-type list against `app-privacy-answers.md`. → *Outcome:* engineering updates the manifest and reconciles the Info.plist/InfoPlist.strings purpose-string divergence (CODE_REVIEW L-8) in both languages.
- **Recommended next action:** Bundle this with the R-3 professional copy review — same reviewers, same surfaces.

## R-5 · macOS verification environment for this review's test claims

- **Blocker:** This review ran in a Linux container without Swift or Xcode; `swift test` (48 `@Test` cases) and the XCUITest suite were not executed here. The finding that three UI tests cannot pass (CODE_REVIEW H-7) is from reading the assertions against the rendered strings, and README verification claims should only be re-dated after a real run.
- **Impact if unresolved:** README continues to claim "39 tests pass" / "XCUITest-verified" — both stale.
- **Steps required from you:** On a macOS machine with Xcode 26, run the three commands in `apps/ios/ApertureApp/README.md` § Build and verify (after landing T-08's assertion fixes). → *Outcome:* confirmed counts; README verification block updated per CODE_REVIEW README recommendations 2–3.
- **Recommended next action:** Run it once now to baseline which tests are red before any fixes land.
