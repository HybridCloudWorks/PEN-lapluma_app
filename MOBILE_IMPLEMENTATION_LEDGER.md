# Mobile implementation ledger

Last updated: 2026-08-06

This is the root tracking file for iOS configuration, credentials, external values,
and work that cannot be completed safely with repository-only information. Missing
items are recorded here and must not stop unrelated mobile work.

## Rules

- Never commit secrets, private keys, access tokens, recovery codes, production user
  data, or signed authentication challenges.
- Commit variable names, expected formats, owners, safe development defaults, and the
  code path that consumes each value.
- Runtime secrets belong in the CI secret store or an Apple-supported protected store.
- Production configuration must fail closed. Debug builds may use the local stub only
  when the selected environment explicitly permits it.

## Current mobile status

| Area | Status | Current implementation | Next production dependency |
|---|---|---|---|
| Alpha 0.2 Sprint 2 | Merged | LaPluma `0.2.0`, app and infrastructure repository boundaries, catalog/schema expansion, and placeholder-only platform preparation | Contract revision, Azure context, governance approvals, and production end-to-end validation |
| Alpha 0.2 remediation | PR ready for review | Critical/high findings T-01…T-11 implemented; PR #4 passed static, archive, and all 18 UI checks | Merge approval; professional Spanish/legal review remains external |
| Alpha 0.2.1 integrity hardening | In progress | Bounded capture retries/dead letters, drain serialization, EXIF normalization, persisted stub idempotency, atomic confirmation, catalog-contract parity, pasteboard expiration, and fail-closed static validation | Review the dependent PR; rebase/retarget it to `main` after PR #4 merges |
| Alpha 0.1 milestone | Merged | Version `0.1.0` local vertical slice and review package; its release automation has been advanced to Alpha 0.2 | Historical milestone only; do not upload or tag as the current release |
| Local end-to-end flow | Verified | `StubAPIClient` with protected persisted state plus a separate non-persistent marketing-safe fixture | None for continued local development |
| Passkey registration | Stubbed | Local recovery-code/onboarding flow | RP ID, associated domain, auth endpoints, App Attest |
| Passkey assertion | Stubbed | Local sign-in action | Same passkey dependencies plus session exchange |
| Email OTP fallback | UI placeholder | Local sign-in action | Transactional email provider and auth endpoints |
| API client | Stubbed | Protocol-shaped local actor | Approved OpenAPI 3.1 contract and generated client |
| Voice interview | UI only | Consent and interview screens | Ephemeral-key broker and approved realtime endpoint |
| Mobile storage | Development slice | Codable file with complete file protection | Encrypted SQLite schema, migrations, mutation queue |
| Offline capture | Verified locally | Protected normalized payload queue, recoverable manifest handling, orphan cleanup, source image metadata removal, 100 MB/500-page/10,000-pixel limits, stable retry keys, SHA-256 completion check, serialized ordered drain, bounded retries with queryable dead letters, queue byte estimate, Wi-Fi default for large transfers, cellular override | Background URLSession identifier/entitlement, chunking, real server digest, server-side validation, physical-device interruption tests |
| Document classification | Applicant review verified locally | Plain-language band, authoritative persisted override, sealed-document irreversibility, opened I-693 extraction refusal | Calibrated server classifier, audit identity, taxonomy/version contract, production API |
| OCR and extraction | Safety boundary verified locally; engines are fixtures only | Anchored-claim admission policy, ambiguous-date/checksum/model/instruction review reasons, inert-content flag, original-script names, applicant guidance | Sanitization/AV pipeline, OCR routing, extractor models, calibrated thresholds, production injection detector and security-event delivery |
| Extraction review ledger | Verified locally | Append-only proposal/confirmation/correction history, human attribution, preserved document anchors, durable supersession, discrepancy resolution records, fail-closed package generation gate | Temporal ledger schema, authenticated audit identity, database immutability/confirmation constraints, production generation endpoint |
| Release packaging | Alpha 0.2 workflow and store sources implemented | App icon, privacy manifest, version-bound review package, validated localized metadata drafts, six deterministic marketing-safe routes, guarded iPhone/iPad capture tooling, build-setting-backed version, internal-only export profile, unsigned CI archive, and a protected Alpha 0.2 package/checksum/upload workflow | Protected GitHub environment, Apple Developer/App Store Connect values, signing, final URLs/copy, and physical-device/internal-upload approval |
| App signing | Workflow ready; values absent | Manual `main`-only job archives, exports, inspects signing/profile, checksums the exact IPA, removes key material, and requires explicit confirmation before internal upload | Apple team, App Store Connect record/key permissions, cloud-managed certificate access, and protected environment reviewers |
| Automated tests | Package and PR UI suites verified | 70 package tests, 18 serial XCUITest journeys, static policy checks, marketing-fixture privacy gates, unsigned Release archive validation, and a passing macOS UI-test CI job | Add device-farm and physical-device coverage |
| Spanish localization | Core journey and explicit package-bundle selection verified | App and shared-package compliance strings follow the persisted Spanish preference immediately | Translate and professionally review remaining long-tail screens and legal/domain fixtures |
| Large text | Core journey verified | Primary Home and Capture actions remain reachable at accessibility XXXL; core surfaces have an automated accessibility audit | Complete long-tail scaling plus human VoiceOver, switch-control, voice-control, and physical-device audits |
| Accessibility profile | Verified locally | Live 48-point targets, voice-first full-width actions, and waived voice budget; route tested with key system accessibility preferences | Production API/server must own and authorize waiver policy; complete human assistive-technology and device audits |

## Configuration contract

These are the canonical names to use when their consuming production components are
introduced. They are documentation today; the local app does not require them yet.

| Name | Secret | Example / format | Owner | State |
|---|---:|---|---|---|
| `LAPLUMA_DOMAIN` | No | `lapluma.ai` | Product/Platform | Confirmed |
| `LAPLUMA_APP_RELEASE` | No | `lapluma-app-0.2` | Mobile/Release | Confirmed |
| `LAPLUMA_INFRA_RELEASE` | No | `lapluma-infra-0.0` | Platform/Release | Confirmed |
| `LAPLUMA_CONTRACT_REVISION` | No | Immutable semantic version or commit SHA | API/Mobile | Placeholder; required before generated-client integration |
| `LAPLUMA_INFRA_REPOSITORY` | No | `HybridCloudWorks/PEN-lapluma_infra` | Platform | Confirmed |
| `GITHUB_PROJECT_ID` | No | GitHub Project node ID/number | Program | Not supplied; current token also needs Project scopes |
| `AZURE_SUBSCRIPTION_ID` | No | Azure subscription UUID | Platform/Cloud | Not supplied; no provisioning permitted |
| `AZURE_TENANT_ID` | No | Microsoft Entra tenant UUID | Identity/Platform | Not supplied; no provisioning permitted |
| `AZURE_LOCATION` | No | `eastus2` | Platform/Data | Approved placeholder; availability must be validated before deployment |
| `AZURE_ENVIRONMENT_NAME` | No | `lapluma-dev`, `lapluma-pilot`, or `lapluma-prod` | Platform | Not supplied |
| `AZURE_RESOURCE_GROUP` | No | Approved resource-group name | Platform/Cloud | Not supplied |
| `AZURE_OIDC_CLIENT_ID` | No | Federated deployment application/client UUID | Platform/Security | Not supplied |
| `AZURE_SQL_ADMIN_PRINCIPAL_ID` | No | Entra object UUID; never a SQL password | Data/Security | Not supplied |
| `AZURE_KEY_VAULT_NAME` | No | Globally unique vault name | Security/Platform | Not supplied |
| `AZURE_MANAGED_HSM_NAME` | No | Globally unique managed-HSM name | Security/Platform | Not supplied |
| `AZURE_DOCUMENT_INTELLIGENCE_RESOURCE_NAME` | No | Azure resource name | AI/Platform | Not supplied |
| `AZURE_OPENAI_RESOURCE_NAME` | No | Azure OpenAI resource name | AI/Platform | Not supplied and feature-gated |
| `GRAPH_TENANT_ID` | No | Workforce tenant UUID | Identity/Assistance | Not supplied |
| `GRAPH_CLIENT_ID` | No | App registration UUID | Identity/Assistance | Not supplied |
| `GRAPH_HOST_MAILBOX_ALLOWLIST` | No | Approved staff mailbox IDs stored outside mobile | Assistance/Security | Not supplied |
| `GRAPH_CLIENT_CERTIFICATE` | Yes | Key Vault certificate reference, never certificate bytes in source | Identity/Security | Not supplied; Teams feature disabled |
| `APERTURE_ENVIRONMENT` | No | `local`, `development`, `staging`, `production` | Mobile | Local default needed |
| `APERTURE_RUNTIME_MODE` | No | `local`, `internal-demo`, `production` | Mobile/Release | Debug=`local`; Release=`internal-demo`; production intentionally fails closed while the stub is compiled |
| `APERTURE_API_BASE_URL` | No | `https://api.<environment>.<domain>/v1` | Platform/API | Final domains TBD |
| `APERTURE_WEBAUTHN_RP_ID` | No | Registrable auth domain, never the API URL | Identity/Security | TBD |
| `APERTURE_ASSOCIATED_DOMAIN` | No | `webcredentials:<rp-id>` | Identity/Mobile | TBD |
| `APERTURE_APP_ATTEST_ENVIRONMENT` | No | `development` or `production` | Security/Mobile | TBD |
| `APERTURE_VOICE_BROKER_URL` | No | HTTPS endpoint returning an ephemeral credential | AI/Platform | Deferred and gated |
| `APERTURE_NOTICE_VERSION` | No | Version such as `2026.03` | Legal/Product | Contract example only |
| `APERTURE_NOTICE_SHA256` | No | Lowercase SHA-256 hex digest | Legal/Product | Generated from approved copy |
| `APPLE_DEVELOPMENT_TEAM` | No | Ten-character Apple team identifier | Release Engineering | Not supplied |
| `PRODUCT_BUNDLE_IDENTIFIER` | No | Currently `app.aperture.mobile` | Mobile/Release | Confirm before signing |
| `APP_STORE_CONNECT_API_ISSUER_ID` | No | UUID from App Store Connect Users and Access | Release Engineering | Not supplied |
| `APP_STORE_CONNECT_API_KEY_ID` | No | App Store Connect API key identifier | Release Engineering | Not supplied |
| `APP_STORE_CONNECT_API_PRIVATE_KEY_PATH` | Yes | Protected temporary path to the `.p8` key materialized by CI | Release Engineering | Not supplied; never commit the key |
| `APP_STORE_CONNECT_API_PRIVATE_KEY_BASE64` | Yes | Base64 of the `.p8`, scoped only to the protected key-materialization step | Release Engineering | Not supplied; GitHub `internal-testflight` environment secret |
| `GITHUB_RELEASE_ENVIRONMENT` | No | Exact environment name `internal-testflight` | Release Engineering | Workflow references it; required reviewers, no self-review, main-only branch, and admin-bypass policy must be configured in GitHub |
| `APP_STORE_APPLE_ID` | No | Numeric identifier created with the App Store Connect record | Release Engineering | Not supplied |
| `APP_STORE_PRIMARY_LANGUAGE` | No | Expected `en-US` | Product/Release | Not confirmed |
| `APP_STORE_COPYRIGHT` | No | Current legal owner and year | Legal | Not supplied |
| `APP_STORE_PRIVACY_POLICY_URL` | No | Published HTTPS privacy-policy URL | Legal/Product | Not supplied; required for iOS submission |
| `APP_STORE_SUPPORT_URL` | No | Published HTTPS customer-support URL | Support/Product | Not supplied; required for the store record |
| `APP_STORE_MARKETING_URL` | No | Published HTTPS product page | Marketing/Product | Optional; not supplied |
| `APP_STORE_SKU` | No | Stable internal App Store Connect identifier | Release Engineering | Not supplied; choose before creating the app record |
| `APP_STORE_PRIMARY_CATEGORY` | No | App Store category selected from Apple's current list | Product | Not supplied |
| `APP_STORE_CONTENT_RIGHTS_DECLARATION` | No | Approved response backed by the versioned rights inventory | Legal | Not supplied |
| `APP_STORE_PRIVACY_ANSWERS_APPROVAL` | No | Approver and build-bound App Privacy response revision | Legal/Privacy | Fixture-only crosswalk exists; production approval absent |
| `APP_STORE_ACCESSIBILITY_RESPONSES` | No | Approved accessibility-label selections backed by common-task evidence | Accessibility/Product | Do not indicate support for Alpha 0.1 |
| `APP_STORE_VERSION_RELEASE_SETTING` | No | Manual, automatic, or phased release | Product/Release | Not supplied; public-release only |
| `APP_STORE_AVAILABILITY_TERRITORIES` | No | Approved App Store territory set | Legal/Product | Not supplied; public-release only |
| `APP_STORE_PRICE_SCHEDULE` | No | Approved price/free schedule | Product/Finance | Not supplied; public-release only |
| `APP_STORE_REVIEW_CONTACT` | No | Protected operational name, email, and phone supplied in App Store Connect | Release/Product | Not supplied; do not commit personal contact details |
| `APP_STORE_AGE_RATING_RESPONSES` | No | Approved App Store Connect questionnaire answers for the submitted binary | Product/Legal | Not supplied; must reflect document, voice, and web-link behavior |
| `APP_STORE_REVIEW_NOTES` | No | Reviewer instructions and a non-production review account or approved no-login path | Product/Release | Not supplied; never commit review credentials |
| `APP_USES_NON_EXEMPT_ENCRYPTION` | No | App Store export-compliance determination | Legal/Security | Current project declares `NO`; re-review for the production networking binary |
| `APERTURE_SCREENSHOT_KIND` | No | `internal-review` or `store` | Design/Release | Local default is `internal-review`; store mode is explicitly gated |
| `APERTURE_SCREENSHOT_SOURCE` | No | Exact value `production-reviewed` for store capture | Product/Privacy | Non-persistent marketing-safe Alpha fixture implemented; final production-reviewed source not approved |
| `APERTURE_SCREENSHOT_APP_PATH` | No | Local path to an approved iOS Simulator `.app` | Mobile/Release | Not supplied; required for store-mode capture |
| `APERTURE_STORE_SCREENSHOT_MIN_FREE_GB` | No | Positive integer, default `6` | Mobile/Release | Local default implemented; latest workspace check had about 1.3 GB free, so capture was safely deferred |
| `APERTURE_BACKGROUND_UPLOAD_SESSION_IDENTIFIER` | No | Reverse-DNS identifier such as `app.aperture.mobile.uploads` | Mobile/Release | Confirm with final bundle ID before background transfer |
| `APERTURE_ACCOUNT_DELETION_ENDPOINT` | No | Authenticated endpoint initiating account and eligible server-data deletion | Identity/Privacy | Not supplied; current deletion is local-fixture-only |
| `APP_STORE_REVIEW_BACKEND_URL` | No | Always-available production review environment URL | Platform/Release | Not supplied |
| `APP_STORE_REVIEW_USERNAME` | Yes | Non-expiring synthetic review identity stored in App Store Connect/secret store | Release/Support | Not supplied; never commit credentials |
| `APP_STORE_REVIEW_PASSWORD` | Yes | Protected review credential | Release/Support | Not supplied; never commit credentials |
| `APERTURE_LARGE_UPLOAD_THRESHOLD_BYTES` | No | `10485760` (10 MiB) | Product/Mobile | Local default implemented; confirm before production rollout |
| `APERTURE_DOCUMENT_SANITIZATION_SERVICE_URL` | No | Internal HTTPS service URL | Security/Platform | Not supplied; server-side only |
| `APERTURE_MALWARE_SCANNER_PROFILE` | No | Approved scanner engine/profile identifier | Security | Not supplied; server-side only |
| `APERTURE_DOCUMENT_INTELLIGENCE_ENDPOINT` | No | Azure Document Intelligence resource endpoint | AI/Platform | Not supplied; server-side only |
| `APERTURE_DOCUMENT_INTELLIGENCE_CREDENTIAL` | Yes | Key Vault/managed-identity reference, never a raw key in mobile | AI/Platform | Not supplied; server-side only |
| `APERTURE_DOCUMENT_CLASSIFIER_VERSION` | No | Immutable calibrated classifier version | AI/Data | Not supplied |
| `APERTURE_EXTRACTION_MODEL_VERSIONS` | No | Approved class-to-model version map | AI/Data | Not supplied |
| `APERTURE_INJECTION_DETECTOR_VERSION` | No | Immutable instruction-like-text detector version | Security/AI | Not supplied; server-side only |
| `APERTURE_SECURITY_EVENT_SINK` | No | Internal security-event destination identifier | Security/Platform | Not supplied; server-side only |

Do not introduce client secrets for the mobile app. OAuth/public-client and passkey
flows must use server-issued, short-lived challenges and tokens; anything requiring a
long-lived secret inside the app is the wrong design.

## Passkey completion checklist

- [ ] Confirm the production relying-party ID and its owning domain.
- [ ] Host and validate the `apple-app-site-association` document for `webcredentials`.
- [ ] Confirm the Apple Team ID and production bundle identifier.
- [ ] Add the Associated Domains and App Attest entitlements to signed configurations.
- [ ] Generate the Swift client from the approved OpenAPI contract for registration
  options, registration completion, assertion options, assertion completion, refresh,
  step-up, recovery, and logout.
- [ ] Implement `ASAuthorizationPlatformPublicKeyCredentialProvider` behind an
  injectable authentication service.
- [ ] Bind registration to App Attest and the exact approved notice hashes.
- [ ] Store refresh/session material in Keychain with the final accessibility policy;
  never store passkey private material in the app.
- [ ] Replace the fixed development recovery code. Production recovery codes must be
  server-generated, single-use, shown once, and never logged or copied to analytics.
- [ ] Test registration, assertion, cancellation, credential-not-found, recovery,
  remote revocation, and purpose/resource-bound step-up on physical devices.

## Simulator journey coverage

The `ApertureAppUITests` target currently verifies:

- onboarding, required notices, recovery acknowledgement, and session persistence;
- authenticated Home, Capture, Missing, and Me surfaces;
- deterministic authenticated launch into a requested screenshot tab;
- folder creation and persistence;
- human-attested form-package selection and case persistence;
- individual field confirmation, generated-package verification UI, and secure-link
  creation with a synthetic recipient;
- core Home, Capture, Missing, and Me navigation in a Spanish (`es_MX`) runtime,
  including a localized string loaded from the shared Swift package; and
- reachability of primary Home and Capture actions at the system accessibility
  extra-extra-extra-large content-size category;
- live accessibility-profile behavior: 48-point minimum targets, voice-first action
  ordering, consent, voice-session startup, and a waived local voice-time budget;
- automated checks of visible Home, Capture, Missing, and Me controls for contrast,
  element detection, hit regions, sufficient descriptions, and traits; and
- primary Home and Capture action reachability with Reduce Motion, Increase Contrast,
  and Differentiate Without Color enabled together; and
- explicit offline state, continued access to capture and structured manual entry, and
  disabled AI chat/voice entry while no connection is available; and
- a forced expensive-network state where large-upload Wi-Fi protection defaults on,
  Low Data Mode/cellular guidance is visible, and the user can disable the preference; and
- applicant review of a low-confidence document class, authoritative correction to a
  different type, and persistence of that correction after app relaunch; and
- explicit applicant warnings for an ambiguous extracted date plus preservation of a
  name's original script in the source-review sheet; and
- fail-closed package-generation blocker counts plus a corrected value's append-only,
  attributed history and persistence after relaunch.

Capture entry points are asserted, but camera frames, PhotosPicker payloads, Files
security-scoped URLs, and VisionKit scan quality still require controlled system
fixtures and physical-device runs. No test bypass pretends those payload paths ran.
The protected queue has package-level persistence, retry, failure-retention, and cleanup
tests. The shared capture gate also tests removal of source GPS/private EXIF fields,
canonical SHA-256, invalid-type rejection, published size/page boundaries, and completion
digest round-tripping. Its current drain runs when connectivity returns while the app is
active and at relaunch; background continuation after suspension/termination requires the
production background-session identifier and entitlement recorded above. Chunked upload,
server-side repeat validation, and server session expiry/recreation remain production work.
The locally selected large-transfer boundary is 10 MiB. On an expensive or constrained
connection, larger captures remain queued in order while the Wi-Fi preference is enabled;
the preference and its cellular override persist across launches. Product and Mobile must
confirm the threshold before production rollout.
The Spanish journey does not claim the entire product is translated: long-tail screens,
fixture/domain content, and legal copy still need a complete translation inventory and
professional review. Apple's Dynamic Type and text-clipping audit categories are excluded
because the current SwiftUI accessibility tree emits reproducible element-less findings
for system-managed Label/List nodes; the accessibility XXXL functional journey remains the
scaling gate. Elements retained in the accessibility tree while visually covered by the
floating tab bar are ignored only while occluded. This automation does not claim human
VoiceOver reading-order, Switch Control/Voice Control, long-tail screen, or physical-device
coverage. The accessibility profile is implemented for the local vertical slice;
production still requires an API/server policy that authorizes the voice-budget waiver.

The screenshot harness has six deterministic real-feature routes, a non-persistent
marketing-safe fixture, centered iPad composition, and validation for current iPhone
6.9-inch and iPad 13-inch portrait dimensions, image counts, and alpha channels. Its
default output remains Alpha/review-only because the route and fixture controls are
Debug-only. Store-mode capture fails closed unless an approved simulator app and the
explicit `production-reviewed` source marker are supplied. The current workspace has
insufficient free disk for the 6 GB simulator-capture safety threshold; this does not
block metadata, code, or archive validation.

Alpha 0.1 has no published privacy/support URLs or in-app privacy-policy link. Its
“Delete everything” control removes local fixture data only. Those are explicit public
submission blockers, not implied production capabilities.

## Values deliberately not recorded here

- Apple certificates and provisioning-profile private material
- API tokens, session tokens, refresh tokens, App Attest assertions, and passkey
  challenges
- Real recovery codes
- User email addresses, names, documents, case identifiers, or other production data

## Continuation policy

When work reaches an item marked TBD, add the exact missing value, owner, expected
format, and affected code path here. Continue with fixtures, protocols, tests, and
unrelated screens wherever doing so does not pretend that a security control exists.
