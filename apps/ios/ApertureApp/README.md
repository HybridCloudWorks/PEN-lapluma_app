# LaPluma — iOS applicant app

> ## Verified mobile vertical slice
>
> **Gated by CI on every pull request** (macOS 26 / Xcode 26.6): the shared package's
> 87 tests run in full, the app builds for iPhone 17, and five critical XCUITest
> journeys run; the full 25-journey suite runs on the weekday schedule and on manual
> dispatch. The last full local verification was August 6, 2026 with Xcode 26.6 and
> the iOS 26.5 Simulator. The journeys cover onboarding,
> authenticated tabs, folder and case creation, human confirmation, secure export,
> Spanish core navigation, primary-action reachability at accessibility XXXL text, and
> the accessibility profile's voice-first, enlarged-target, waived-budget flow. They also
> audit visible controls on the core surfaces and exercise key system accessibility settings.
> Offline mode keeps capture and structured manual entry reachable, while AI modalities
> clearly disclose that they need a connection; a capture queued offline survives a
> relaunch and drains itself once the network returns.
>
> This is an end-to-end **local mobile vertical slice**, not a production release. The
> production passkey, networking, voice session, and hardened database work listed
> below remain deliberately unclaimed.

## What is here

| Path | Contents |
|---|---|
| `packages/ApertureKit/Sources/ApertureDomain` | Value types, state machines, invariants. No UI, no networking, no presentation strings |
| `packages/ApertureKit/Sources/ApertureAPI` | Client protocol + `StubAPIClient` with realistic fixture data |
| `packages/ApertureKit/Sources/ApertureUI` | Design tokens and the components that carry compliance meaning |
| `packages/ApertureKit/Tests` | Invariant tests — the ones that matter, not smoke tests |
| `ios/ApertureApp` | The applicant app: screens S-01…S-15 |

Screens **S-16, S-17 and S-18 are not here.** Those are the macOS reviewer workbench and
admin console — a separate target with a different persona, different navigation and a
throughput-oriented design ([08 §8.7](../../docs/08-ux-design.md#87-macos-reviewer-workbench)).
An "applicant app scaffold" is the wrong place for them.

## Build and verify

```bash
# Install Xcode with the iOS 18+ platform and accept its licence, then:
xcodebuild -project apps/ios/ApertureApp.xcodeproj \
  -scheme ApertureApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build

swift test --package-path apps/packages/ApertureKit

xcodebuild -project apps/ios/ApertureApp.xcodeproj \
  -scheme ApertureApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO \
  test
```

Unsigned Release archive validation and the credentialed internal TestFlight procedure
are documented in [`../RELEASE.md`](../RELEASE.md). The archive gate runs in GitHub
Actions on macOS 26; it does not sign or upload an artifact.

The UI test launches with `--ui-testing-reset`, a test-only argument that removes local
stub state and preferences before the journey. It is not exposed as an applicant-facing
reset control. Authenticated journey tests also use `--ui-testing-authenticated`; both
arguments affect only test-process startup and do not bypass production authorization.

`--ui-testing-enqueue-capture` reveals a `#if DEBUG` button on the capture screen that
pushes a synthetic image through the **production** capture path — payload validation,
the durable queue, and the drain — because the camera and photo picker need
capabilities a Simulator test cannot grant. It is compiled out of Release entirely, and
it adds no code path the applicant flow does not already take.

The project already links ApertureDomain, ApertureAPI and ApertureUI from the local
`ApertureKit` package. The app runs against a production-shaped local client, so every
screen is reachable in the Simulator with no backend. Mutations persist under
Application Support using complete file protection.

## What the stub does and does not do

It is deliberately **not** a toy: it enforces the invariants the real server enforces,
so a screen that would be rejected in production is rejected here too.

- Creating a case without a selection attestation → `422`
- Starting a voice interview without recorded consent → `422`
- The catalog returns a deterministic order and accepts no case data
- Reclassifying to `SEALED_MEDICAL` makes a document permanently opaque

`StubGuardrail` is **not a safety control** and must never be mistaken for one. The real
Legal Advice Classifier is three stages, fails closed, and is gated on a held-out corpus
engineering never sees ([09 §9.3](../../docs/09-responsible-ai.md#93-the-legal-advice-classifier)).
The stub is a keyword list good enough to exercise the blocked-turn UI path.

## Invariants the code enforces, not just documents

These are the places where the compliance position is expressed in types rather than in
prose. Breaking one should fail the build.

| Invariant | How |
|---|---|
| Nothing model-touched reaches a form unattended | `FieldValue.confirmedBy` is **non-optional** — the type cannot represent an unconfirmed authoritative value |
| A new extraction never silently overwrites a human | `ValueProposal` is a separate type from `FieldValue` (SME B-02) |
| Progress is never a percentage | `ProgressCounters` exposes numerators and denominators and nothing that divides them; a test asserts no forbidden key survives encoding |
| Confidence is never a number to an applicant | `ConfidenceBand` is a three-case enum with localisation keys, not a `Double` |
| Sealed medical documents are never opened | `allowsPreview` / `allowsExtraction` are false and the class is opaque by policy |
| A checkmark never marks a verified value | `ConfidenceBand.verified.symbolName` is asserted not to contain `checkmark` — a tick reads as endorsement (SME m-01) |
| No third-party dependencies | `Package.swift` declares `dependencies: []` |

## Known gaps

Stated plainly rather than discovered later:

- **Passkey registration is stubbed.** There is no Simulator passkey flow worth faking;
  the real work is `ASAuthorizationPlatformPublicKeyCredentialProvider` plus App Attest.
- **Capture is wired to VisionKit, PhotosPicker and Files.** The scanner requires a
  supported device. The `CaptureQuality` policy and hints are real; production-grade
  per-frame blur/glare/text analysis still needs Vision requests and device calibration.
  Every selected payload is now written to a complete-protection queue before upload,
  with stable retry keys and automatic foreground/relaunch draining. Images are oriented
  and re-encoded without source GPS/private EXIF metadata before persistence; invalid,
  over-100-MB, over-500-page, and over-10,000-pixel payloads fail with specific guidance.
  Local bytes are released only when the completion SHA-256 matches. Captures over 10 MiB
  wait for Wi-Fi by default on cellular or Low Data Mode; the capture screen reports the
  queued count and estimated bytes and offers a persistent, deliberate cellular override.
  The 10 MiB threshold is a local product assumption recorded in the root ledger.
  Production still needs
  a background `URLSession` identifier and entitlement so transfers continue after suspension
  or termination, plus the server-side repeat of all content validation.
- **Voice is UI only.** The WebRTC session, ephemeral-key exchange and the
  interrupt-on-block path (SME B-01) are not implemented. That path is gated on CON-1
  and may be cut from MVP entirely if interrupt latency exceeds 600 ms.
- **Document classification review is local; OCR is not.** Applicants see a plain-language
  confidence band, can correct every readable document's type, and their authoritative
  override persists. Selecting sealed medical is an irreversible opaque-storage decision;
  an opened I-693 remains previewable only for warning context and refuses extraction.
  Production malware scanning, active-content removal, OCR routing, calibrated classifier,
  extraction engines, and server security events require the services recorded in the root
  ledger. The fixture does not claim that those services ran.
- **Extraction safety has a client mirror, not a production detector.** The shared policy
  drops extraction-engine claims without a non-degenerate page anchor, downgrades ambiguous
  dates, failed checksums, model suggestions, and instruction-like text to human review,
  and marks instruction-like content for a security event. The review UI explains ambiguous
  dates without choosing one and keeps original-script names intact beside transliteration.
  Production detection, calibration, and event delivery remain server-owned.
- **The extraction review ledger is append-only in the local slice.** Accepting a source
  preserves its document anchor, correcting it records the prior value and human actor,
  superseded proposals remain visible, and the history survives relaunch. Package generation
  fails closed while any required value is unconfirmed, any proposal remains open, or any
  blocking discrepancy is unresolved. Production still requires the temporal ledger schema,
  authenticated audit identity, database constraints, and server generation gate.
- **The local store is for the mobile vertical slice.** It persists Codable state and
  queued capture bytes with complete file protection. Production still requires encrypted
  SQLite, schema migrations, a general queued/idempotent mutation log, and conflict UI.
- **No real networking.** `StubAPIClient` only. The real client is generated from the
  OpenAPI document — hand-written clients are not permitted (API-2).
- **The core journey is localised in en and es.** App- and package-owned Spanish strings
  are runtime tested and key parity is checked statically. Long-tail screens, fixture
  content, and legal copy still require a complete inventory and professional review;
  the eight Phase-2 languages are not present.
- **Accessibility automation covers the core surfaces, not the whole product.** Visible
  controls on Home, Capture, Missing, and Me are audited for contrast, element detection,
  hit regions, sufficient descriptions, and traits. Primary Home and Capture actions are
  also exercised at accessibility XXXL and with Reduce Motion, Increase Contrast, and
  Differentiate Without Color enabled. Apple's Dynamic Type and text-clipping audit
  categories are excluded because SwiftUI emits reproducible element-less findings for
  system-managed Label/List nodes; the functional XXXL journey remains the scaling gate.
  Elements visually occluded by the floating tab bar are ignored only while occluded.
  Human VoiceOver reading-order, Switch Control/Voice Control, long-tail screen, and
  physical-device audits are still required. The production server must also own and
  authorize the accessibility profile's voice-budget waiver policy.

Required production values and owners are maintained in the repository-root
[`MOBILE_IMPLEMENTATION_LEDGER.md`](../../../MOBILE_IMPLEMENTATION_LEDGER.md). Missing
credentials or domains are recorded there and do not block unrelated mobile work.

## The rule that matters most

Every screen renders `DisclosureFooter`, and there is **no parameter that removes it**.
`canSuppressNotALawFirmDisclosure` is false for every tenant type in the admin API — it
appears in the response so the constraint is auditable, not because it is configurable.

If a future change makes that footer optional, the change is wrong.
