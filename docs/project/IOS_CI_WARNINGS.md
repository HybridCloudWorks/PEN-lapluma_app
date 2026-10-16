# iOS CI warning register

Last verified: 2026-08-07 with GitHub `macos-26`, Xcode 26.6, and the iOS 26.5
simulator runtime.

This register separates application defects from Apple build/test-runner diagnostics.
Do not hide the remaining messages with broad log filters: a wording, owner, or severity
change should remain visible in review.

| Log signal | Owner / classification | Repository action |
|---|---|---|
| `Extracted no relevant App Intents symbols` for ApertureDomain/UI/API | Xcode informational output. These modules intentionally contain no App Intents. | None. Adding an unused framework or an unsupported extraction flag would misrepresent the product. |
| `Metadata extraction skipped. No AppIntents.framework dependency found` for the app/UI tests | Xcode 26.6 warning from its automatic extraction phase. LaPluma currently exposes no App Intents. | Retain visibly. Re-evaluate only when App Intents become an approved feature. |
| `Ignoring --strip-bitcode because --sign was not passed` | Xcode Swift-library tool output caused by the intentionally unsigned simulator build. | Retain. CI must not introduce signing merely to silence it. |
| `not stripping binary because it is signed` for injected XCTest frameworks | Debug UI-test build setting, repository-fixable. The frameworks are Apple test-runner dependencies, not shipped app content. | Resolved by disabling copy-phase stripping for the UI-test Debug target only. |
| Duplicate `UIAccessibilityLoaderWebShared` in WebCore/WebKit accessibility bundles | Apple iOS 26.5 simulator-runtime defect; both binaries are under the simulator runtime, not the app. Potential source of simulator-only accessibility flakiness. | Track the selected Xcode/runtime. Investigate again if a failing test or crash stack points to these bundles; never modify runtime files. |
| `t = nans Interface orientation changed to Portrait` | XCTest activity-log timestamp formatting before the first UI event. | Track with the runtime; no app clock or orientation code is involved. |
| `DebuggerVersionStore.StoreError` / `no debugger version` | Headless Xcode launch-snapshot tooling. UI tests do not attach LLDB. | Preserve the `.xcresult` artifact on failure so diagnostics remain available without an attached debugger. |
| Confirm-screen diagnostic snapshot in `testHumanSelectedApplicationPersists` | Test logic used a negative navigation-bar timeout, which caused XCTest failure-triage collection even when the assertion passed. | Resolved by waiting for the actual attestation control to appear and disappear. |
| Delete-key control characters printed while clearing the Value field | XCUITest logged raw delete-key characters; this was not source-file mojibake. | Resolved with select-all replacement plus an exact value assertion before submission. |

## Escalation rule

Treat an Apple-owned signal as actionable if it changes wording/severity, begins failing
the build, correlates with a reproducible crash, or appears in a signed device/archive
path rather than the simulator UI-test runner. Record the Xcode build, runtime build,
job URL, and `.xcresult` before changing application code.
