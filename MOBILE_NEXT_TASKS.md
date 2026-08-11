# LaPluma mobile — task list after Alpha 0.2 remediation

This is the task list for major changes planned after the Alpha 0.2 remediation. Add each
requested change with its user outcome, acceptance criteria, affected journeys, data
contract, migration impact, and release risk before implementation.

## Major-change intake

- [x] Add I-131 to the versioned catalog and restore it to the Phase 2 roadmap.
- [ ] Operationalize I-131 with a reviewed field map, category-aware fees, requirements,
  fixtures, round-trip verification, and generation tests before enabling case creation.
- [ ] Record the first additional major change and define the applicant-visible outcome.
- [ ] Record the second major change and identify any navigation or information-model change.
- [ ] Record the third major change and identify API, storage, privacy, and migration effects.
- [ ] Re-prioritize this list after the major changes are known; do not preserve Alpha
  structure merely for compatibility if the new product direction supersedes it.

## Alpha 0.2 remediation

- [x] Correct confirmation, discrepancy, upload-session, and offline-manifest integrity defects.
- [x] Preserve every scanned page in an orientation-aware PDF payload.
- [x] Complete the user-visible LaPluma rename and explicit in-app language selection.
- [x] Add interview and Missing-state failure, retry, and empty-state paths.
- [x] Add explicit loading, empty, failed, and retry states to Review, form requirements, and Folder.
- [x] Stabilize Missing navigation and reuse Capture content without nested navigation stacks.
- [x] Restore and extend the 18-journey UI suite and add serial pull-request CI coverage.
- [x] Advance guarded release tooling to Alpha 0.2 without deploying.

## Alpha 0.2.1 mobile integrity hardening

- [x] Serialize capture draining and retain bounded-retry dead letters for diagnosis.
- [x] Normalize invalid EXIF orientation values without integer traps.
- [x] Persist endpoint-scoped stub idempotency and make batch confirmation atomic.
- [x] Reject empty form packages and enforce catalog-to-contract compatibility.
- [x] Expire copied recovery codes and make static validation fail closed.
- [ ] Merge PR #4, then rebase/retarget the dependent integrity PR to `main`.

## Production foundation

- [ ] Approve the OpenAPI 3.1 contract and generate the production Swift client.
- [ ] Implement passkey registration/assertion, server sessions, recovery, and OTP fallback.
- [ ] Add App Attest, associated domains, Keychain policy, and purpose-bound step-up.
- [ ] Replace local fixture persistence with encrypted SQLite, migrations, and a durable mutation queue.
- [ ] Implement production account export and deletion, including server-held data and retention exceptions.

## Document services

- [ ] Implement background `URLSession` uploads, chunking, digest verification, and interruption recovery.
- [ ] Connect sanitization, malware scanning, classification, OCR, extraction, and security-event delivery.
- [ ] Calibrate confidence bands and preserve human overrides and the append-only value ledger server-side.
- [ ] Complete production package generation, verification, secure delivery, and revocation.

## Voice and accessibility

- [ ] Connect the ephemeral-key voice broker and approved realtime endpoint.
- [ ] Implement production consent, retention, transcript, budget, and accessibility-waiver policies.
- [ ] Complete the common-task accessibility matrix on physical iPhone and iPad devices.
- [ ] Finish professional Mexican Spanish and long-tail/legal-copy review.

## Release and public store

- [ ] Configure and protect the `internal-testflight` GitHub environment.
- [ ] Supply Apple signing/App Store Connect values and create the app record and tester group.
- [ ] Publish privacy/support pages and expose the privacy policy inside the app.
- [ ] Approve age rating, content rights, App Privacy, export compliance, territories, pricing, and review access.
- [ ] Produce and approve final production-build iPhone/iPad screenshots.
- [ ] Replace `internal-demo` with a reviewed production configuration before external TestFlight or App Store submission.

Exact missing values, owners, formats, and secret-handling rules live in
`MOBILE_IMPLEMENTATION_LEDGER.md`; this list should link to that contract instead of
copying credentials or placeholders.
