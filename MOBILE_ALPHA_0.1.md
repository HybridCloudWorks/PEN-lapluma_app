# Aperture mobile — Alpha 0.1

Version: `0.1.0`

Distribution: internal TestFlight only

Runtime: `internal-demo`

Alpha 0.1 is the end of the repository-only mobile foundation. It is a reviewable,
accessible documentation-app vertical slice, not a public App Store release and not a
production data service.

## Included

- End-to-end local onboarding, folders, application selection, document organization,
  capture entry, missing-item interviews, source review, correction history, package
  safety gates, privacy settings, offline behavior, and secure-delivery UI.
- Document-first Liquid Glass visual system with semantic information, warning,
  critical, positive, and neutral states that never rely on color alone.
- English and Mexican Spanish core journeys, Dynamic Type, semantic labels, large
  targets, accessibility profile, and automated accessibility checks.
- Protected capture queue and fixture persistence with fail-closed document and package
  invariants.
- App icon, privacy manifest, internal-only export profile, unsigned release validation,
  and repository-managed App Store/TestFlight drafts.
- A non-persistent marketing-safe fixture, six deterministic showcase routes, and
  readable iPad composition.
- A protected, manual Alpha packaging workflow that retains checksummed signed artifacts
  and uploads the exact IPA only after explicit confirmation.

## Deliberately excluded

- Real user data or production credentials.
- Production API, passkeys, OTP, server sessions, App Attest, voice service, OCR,
  extraction models, document storage, background upload, or server account deletion.
- Public App Store distribution, external TestFlight, accessibility nutrition-label
  claims, approved age rating, or final marketing screenshots.

## Release rule

The merge commit may be tagged `ios-alpha-0.1` only after the draft PR is reviewed and
merged. Do not tag this feature branch, and do not upload until the protected
`internal-testflight` GitHub environment and Apple values are configured. An internal
upload does not make this binary eligible for external testing or public submission.

The next body of work starts in `MOBILE_NEXT_TASKS.md`. Configuration and credential
contracts remain in `MOBILE_IMPLEMENTATION_LEDGER.md`.
