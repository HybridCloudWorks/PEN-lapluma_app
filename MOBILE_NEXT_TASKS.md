# Aperture mobile — task list after Alpha 0.1

This is the fresh task list for the major changes planned after Alpha 0.1. Add each
requested change with its user outcome, acceptance criteria, affected journeys, data
contract, migration impact, and release risk before implementation.

## Major-change intake

- [ ] Record the first major change and define the applicant-visible outcome.
- [ ] Record the second major change and identify any navigation or information-model change.
- [ ] Record the third major change and identify API, storage, privacy, and migration effects.
- [ ] Re-prioritize this list after the major changes are known; do not preserve Alpha
  structure merely for compatibility if the new product direction supersedes it.

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
