# Aperture — iOS applicant app (scaffold)

> ## Read this before you judge the code
>
> **None of this has ever been compiled.** It was written in a Linux container with no
> Swift toolchain, no Xcode, no iOS SDK and no Simulator:
>
> ```
> OS: Linux x86_64
> swift:      not installed
> xcodebuild: not installed (macOS-only)
> ```
>
> SwiftUI, VisionKit and the iOS SDK are Apple-platform-only, so this is **source for a
> developer to open in Xcode on a Mac**, not a working app. Expect the first build to
> surface errors. The honest first milestone is *"it compiles"*, and only you can
> confirm it.
>
> This warning exists because the central finding of the [SME review](../../docs/14-sme-review-and-signoff.md#147-what-this-review-says-about-rev-a)
> was that the design repeatedly described things in the confident register of
> something already built. Handing over thousands of lines of never-compiled Swift and
> calling it "the iOS app" would be the same mistake in a new costume.

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

## Getting it to build

```bash
# 1. Create an Xcode project (App, SwiftUI, iOS 18) named ApertureApp
# 2. Add the local package:
#      File > Add Package Dependencies > Add Local… > apps/packages/ApertureKit
# 3. Link ApertureDomain, ApertureAPI and ApertureUI to the app target
# 4. Add ios/ApertureApp/*.swift and Features/ to the target
# 5. Use ios/ApertureApp/Info.plist (the camera/photo/microphone purpose strings
#    are required — the app will crash on first camera use without them)
```

The app runs entirely against `StubAPIClient`, so every screen is reachable in the
Simulator with no backend.

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

## Known gaps in this scaffold

Stated plainly rather than discovered later:

- **Nothing is compiled or tested.** See the warning above.
- **Passkey registration is stubbed.** There is no Simulator passkey flow worth faking;
  the real work is `ASAuthorizationPlatformPublicKeyCredentialProvider` plus App Attest.
- **The camera is a placeholder.** `VNDocumentCameraViewController` needs a device, and
  the on-device quality gate needs real Vision requests. The `CaptureQuality` shape and
  its hint logic are real; the frame analysis is not.
- **Voice is UI only.** The WebRTC session, ephemeral-key exchange and the
  interrupt-on-block path (SME B-01) are not implemented. That path is gated on CON-1
  and may be cut from MVP entirely if interrupt latency exceeds 600 ms.
- **No offline store.** The design calls for encrypted SQLite under
  `NSFileProtectionComplete` with a queued mutation log; this scaffold holds state in
  memory.
- **No real networking.** `StubAPIClient` only. The real client is generated from the
  OpenAPI document — hand-written clients are not permitted (API-2).
- **Localisation covers en and es**, with full key parity enforced by the generator.
  The eight Phase-2 languages are not present.

## The rule that matters most

Every screen renders `DisclosureFooter`, and there is **no parameter that removes it**.
`canSuppressNotALawFirmDisclosure` is false for every tenant type in the admin API — it
appears in the response so the constraint is auditable, not because it is configurable.

If a future change makes that footer optional, the change is wrong.
