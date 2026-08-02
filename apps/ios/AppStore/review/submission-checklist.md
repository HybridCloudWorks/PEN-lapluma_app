# Alpha 0.1 submission checklist

## Internal TestFlight gate

- [ ] PR merged to `main` and commit identified.
- [ ] Protected `internal-testflight` environment configured with required reviewer.
- [ ] Apple team, bundle ID, API key metadata, protected private key, and cloud signing confirmed.
- [ ] App Store Connect app record and internal tester group exist.
- [ ] Static checks, package tests, metadata validation, signed archive, IPA inspection, and checksums pass.
- [ ] Internal-only export flag and `internal-demo` banner verified.
- [ ] Physical-device smoke test completed without real personal information.
- [ ] Upload confirmation phrase entered intentionally.

## Public submission gate — deliberately incomplete

- [ ] Production API, authentication, deletion, document, voice, and delivery behavior complete.
- [ ] Metadata claims approved against the submitted binary.
- [ ] Privacy and support pages published, linked in-app, and approved.
- [ ] App Privacy answers and production privacy manifest approved.
- [ ] Age-rating and content-rights responses approved.
- [ ] Review account/backend and reviewer notes verified.
- [ ] Accessibility common-task matrix completed on iPhone and iPad.
- [ ] English and Mexican Spanish copy professionally reviewed.
- [ ] Final iPhone/iPad screenshots visually and privately approved.
- [ ] Export compliance, territories, pricing, release setting, and regional obligations approved.

Alpha 0.1 cannot satisfy the public gate by changing a manifest flag; it requires a
production-capable binary and owner approvals.
