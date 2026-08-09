# REVIEW — items blocked on user action or decisions

Companion to [`CODE_REVIEW.md`](CODE_REVIEW.md) (findings) and [`TODO.md`](TODO.md) (task tracking). Each item below cannot be completed by an engineer alone: it needs a decision, a credential, or environment access. Another engineer should be able to pick any item up from this page without additional context.

---

## R-1 · Configure the Alpha 0.2 internal TestFlight environment (remaining part of TODO T-09)

- **Resolved engineering decision:** Option (a) was approved on 2026-08-06. The workflow now uses version `0.2.0`, confirmation phrase `UPLOAD ALPHA 0.2 INTERNAL`, and coordinated Alpha 0.2 artifact/manifest labels. No workflow was dispatched and no deployment occurred.
- **Remaining blocker:** The protected `internal-testflight` GitHub environment and its Apple/App Store Connect variables and secrets require repository-owner access.
- **Impact if unresolved:** Local and PR validation remain available, but no signed build can be produced or uploaded.
- **Steps required from you:**
  1. Confirm the `internal-testflight` GitHub environment exists and is protected.
  2. Populate `vars.APPLE_DEVELOPMENT_TEAM` and the App Store Connect values listed in `MOBILE_IMPLEMENTATION_LEDGER.md`.
- **Recommended next action:** Configure the protected environment, then run packaging with upload disabled before considering an internal upload.
- **References:** CODE_REVIEW H-8; `apps/ios/RELEASE.md`; `MOBILE_IMPLEMENTATION_LEDGER.md`; `MOBILE_NEXT_TASKS.md` § Release and public store.

## R-2 · Apple / App Store Connect credentials and store-record setup

- **Blocker:** Signing team, ASC API key, app record, tester group, privacy/support URLs, and the store-listing approvals (age rating, content rights, App Privacy, export compliance, territories, pricing, review access) are all external values that only the account owner can supply or approve.
- **Why it exists:** Deliberate repository policy — no credentials or production endpoints are committed (`MOBILE_ALPHA_0.2_SPRINT_2.md` § Completion criteria); the ledger records each missing value with owner and format.
- **Impact if unresolved:** TestFlight distribution (R-1 step 2), store submission, and the production-configuration replacement of `internal-demo` are all blocked; unrelated mobile work is not.
- **Steps required from you:** Work through the open rows of `MOBILE_IMPLEMENTATION_LEDGER.md` and the unchecked items in `MOBILE_NEXT_TASKS.md` § Release and public store. → *Outcome:* each ledger row flips to supplied; release automation becomes runnable end-to-end.
- **Recommended next action:** Populate the `internal-testflight` environment first — it unblocks the only automated pipeline.

## R-3 · Brand-rename scope and professional Spanish review (blocks parts of TODO T-07, T-19)

- **Engineering status:** The user-visible Aperture→LaPluma rename, broken legal-acknowledgment key, long-tail app copy, plural rules, accessibility hints, export manifests, and service-backed label families are localized mechanically. Static checks enforce en/es parity and prevent known runtime-string bypasses. Internal Aperture identifiers remain under ADR-015.
- **Blocker:** Re-wording or approving legal/compliance copy—especially the Spanish translations—still requires professional Mexican-Spanish and legal-copy review (`MOBILE_NEXT_TASKS.md` § Voice and accessibility; `apps/ios/ApertureApp/README.md` known gaps).
- **Why it exists:** ADR-015 allows internal Aperture module names but requires user-visible surfaces to say LaPluma; engineering can mechanically rename keys, but sign-off on legal wording is not an engineering call.
- **Impact if unresolved:** The corrected strings remain engineering translations without professional sign-off; future wording changes and App Review metadata could diverge.
- **Steps required from you:**
  1. Commission the professional review of the renamed legal/long-tail copy. → *Outcome:* T-07/T-19 close fully.
- **Recommended next action:** Review the current English and Mexican-Spanish copy together so both remain semantically aligned.

## R-4 · App Privacy declarations once a real endpoint exists (blocks TODO T-17)

- **Blocker:** `PrivacyInfo.xcprivacy` declares zero collected data types, while registration collects email+name and the capture pipeline contains a live upload path used the moment a non-stub URL is configured. What must be declared depends on the production data-handling decisions (server retention, linkage, tracking answers) recorded in `apps/ios/AppStore/review/app-privacy-answers.md` and ADR-014's pending retention approval.
- **Why it exists:** Accurate declarations require Data/Privacy/Legal decisions (delivery-anchored retention, ADR-014 explicitly "cannot become a user promise until Data, Privacy, and Legal approve").
- **Impact if unresolved:** App Review rejection risk and a public privacy-label mismatch as soon as real networking ships; today's stub-only build is technically accurate but already contradicts the app's own microphone purpose string.
- **Steps required from you:** Obtain the ADR-014 approvals and confirm the collected-data-type list against `app-privacy-answers.md`. → *Outcome:* engineering updates the manifest and reconciles the Info.plist/InfoPlist.strings purpose-string divergence (CODE_REVIEW L-8) in both languages.
- **Recommended next action:** Bundle this with the R-3 professional copy review — same reviewers, same surfaces.
