# Mobile implementation ledger

Last updated: 2026-08-09

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
| Alpha 0.2 remediation | Merged | Critical/high findings T-01…T-11 implemented with static, archive, and UI validation | Professional Spanish/legal review remains external |
| Alpha 0.2.1 integrity hardening | Merged | Bounded capture retries/dead letters, drain serialization, EXIF normalization, persisted stub idempotency, atomic confirmation, catalog-contract parity, pasteboard expiration, and fail-closed static validation | Continue production integration behind approved contracts and placeholders |
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
| Load-state resilience | Verified locally | Shared typed loading lifecycle; localized empty/failure states and accessible retry actions in Review, form requirements, Folder, and Missing | Production API error taxonomy and observability correlation once the generated client is approved |
| Navigation resilience | Verified locally | One screen-level Missing destination for interview and resolution actions; Capture content embeds in the owning stack; focused push/back UI coverage | Continue monitoring navigation behavior across supported iPhone/iPad sizes and assistive technologies |
| Release packaging | Alpha 0.2 workflow and store sources implemented | App icon, privacy manifest, version-bound review package, validated localized metadata drafts, six deterministic marketing-safe routes, guarded iPhone/iPad capture tooling, build-setting-backed version, internal-only export profile, unsigned CI archive, and a protected Alpha 0.2 package/checksum/upload workflow | Protected GitHub environment, Apple Developer/App Store Connect values, signing, final URLs/copy, and physical-device/internal-upload approval |
| App signing | Workflow ready; values absent | Manual `main`-only job archives, exports, inspects signing/profile, checksums the exact IPA, removes key material, and requires explicit confirmation before internal upload | Apple team, App Store Connect record/key permissions, cloud-managed certificate access, and protected environment reviewers |
| Automated tests | Package and UI suites verified | The package's full Swift Testing suite on every pull request; five critical PR UI journeys only for UI-relevant changes; the whole journey suite on weekday/manual regression; static policy checks; marketing-fixture privacy gates; unsigned Release archive validation; failure-only `.xcresult` retention. What runs is defined by [`ios-release-validation.yml`](.github/workflows/ios-release-validation.yml) — see [`README.md`](README.md) | Add device-farm and physical-device coverage; monitor Apple iOS 26.5 simulator warnings in `IOS_CI_WARNINGS.md` |
| Spanish localization | Engineering sweep verified; professional review pending | Parity-matched app keys per locale and plural-aware formats, both enforced on every pull request by `tools/check-swift-static.py` rather than counted here; complete shared service-label families, explicit bundle selection, static bypass/key enforcement, and a Spanish UI journey covering visible plural rendering | Professional Mexican-Spanish and legal/compliance review of the engineering translations in REVIEW R-3 |
| Large text | Core journey verified | Primary Home and Capture actions remain reachable at accessibility XXXL; core surfaces have an automated accessibility audit | Complete long-tail scaling plus human VoiceOver, switch-control, voice-control, and physical-device audits |
| Accessibility profile | Verified locally | Live 48-point targets, voice-first full-width actions, and waived voice budget; route tested with key system accessibility preferences | Production API/server must own and authorize waiver policy; complete human assistive-technology and device audits |

## Configuration contract

These are the canonical names to use when their consuming production components are
introduced. They are documentation today; the local app does not require them yet.

Read the columns as four different questions, which is why none of them substitutes
for another:

- **Purpose** — what the value is *for*, in terms of product behaviour rather than a
  restatement of the name.
- **Consumer** — the code path that reads it, which the Rules above require. Derived
  from the repository, not asserted: 12 of the 73 names are read by the
  internal-TestFlight workflow, the Xcode project, or the screenshot tool; the rest
  are `— none yet` and exist only as agreed spelling for work not yet built.
- **Required for** — the milestone that is blocked until the value exists. A name
  marked `Optional` blocks nothing.
- **Validation** — whether anything actually checks the value today, and what.
  `Asserted in CI` means a gate runs on every pull request; `Checked by … when run`
  means a tool validates it but only when invoked; `Format agreed only` means nothing
  verifies it and the spelling is the whole of the agreement. Two names — the bundle
  identifier and the runtime mode — are the only ones asserted on every pull request.
- **State** — supply and approval status: whether a real value exists and who still
  has to approve it.

The distinction that matters: **Validation is not State.** A value can be supplied and
still unverified, and `Format agreed only` against a `Confirmed` state means the
agreement is about spelling, not about anything having been proven to work.

| Name | Purpose | Secret | Example / format | Owner | Consumer | Required for | Validation | State |
|---|---|---:|---|---|---|---|---|---|
| `LAPLUMA_DOMAIN` | Root domain every product URL is derived from | No | `lapluma.ai` | Product/Platform | — none yet | Production API and passkey domains | Format agreed only | Confirmed |
| `LAPLUMA_APP_RELEASE` | Release line label for this repository | No | `lapluma-app-0.2` | Mobile/Release | — none yet | Release tagging | Format agreed only | Confirmed |
| `LAPLUMA_INFRA_RELEASE` | Release line label for the infrastructure repository | No | `lapluma-infra-0.0` | Platform/Release | — none yet | Cross-repository release pairing | Format agreed only | Confirmed |
| `LAPLUMA_CONTRACT_REVISION` | Pins the app to one immutable API contract revision | No | Immutable semantic version or commit SHA | API/Mobile | — none yet | Generated-client integration | Format agreed only | Placeholder; required before generated-client integration |
| `LAPLUMA_INFRA_REPOSITORY` | Names the repository that owns provisioning | No | `HybridCloudWorks/PEN-lapluma_infra` | Platform | — none yet | Cross-repository coordination | Format agreed only | Confirmed |
| `GITHUB_PROJECT_ID` | Target board for programme tracking automation | No | GitHub Project node ID/number | Program | — none yet | Programme tracking | Format agreed only | Not supplied; current token also needs Project scopes |
| `AZURE_SUBSCRIPTION_ID` | Billing and deployment scope for every Azure resource | No | Azure subscription UUID | Platform/Cloud | — none yet | Azure provisioning | Format agreed only | Not supplied; no provisioning permitted |
| `AZURE_TENANT_ID` | Entra tenant that authenticates deployments | No | Microsoft Entra tenant UUID | Identity/Platform | — none yet | Azure provisioning | Format agreed only | Not supplied; no provisioning permitted |
| `AZURE_LOCATION` | Region that fixes data residency for stored records | No | `eastus2` | Platform/Data | — none yet | Azure provisioning | Placeholder; availability unverified | Approved placeholder; availability must be validated before deployment |
| `AZURE_ENVIRONMENT_NAME` | Separates dev, pilot and production estates | No | `lapluma-dev`, `lapluma-pilot`, or `lapluma-prod` | Platform | — none yet | Azure provisioning | Format agreed only | Not supplied |
| `AZURE_RESOURCE_GROUP` | Lifecycle boundary for the deployed resources | No | Approved resource-group name | Platform/Cloud | — none yet | Azure provisioning | Format agreed only | Not supplied |
| `AZURE_OIDC_CLIENT_ID` | Federated identity CI deploys as, instead of a stored secret | No | Federated deployment application/client UUID | Platform/Security | — none yet | Azure provisioning | Format agreed only | Not supplied |
| `AZURE_SQL_ADMIN_PRINCIPAL_ID` | Entra principal that administers the database, so no SQL password exists | No | Entra object UUID; never a SQL password | Data/Security | — none yet | Azure provisioning | Format agreed only | Not supplied |
| `AZURE_KEY_VAULT_NAME` | Vault holding runtime secrets outside the repository | No | Globally unique vault name | Security/Platform | — none yet | Azure provisioning | Format agreed only | Not supplied |
| `AZURE_MANAGED_HSM_NAME` | Hardware-backed keys for applicant data at rest | No | Globally unique managed-HSM name | Security/Platform | — none yet | Azure provisioning | Format agreed only | Not supplied |
| `AZURE_DOCUMENT_INTELLIGENCE_RESOURCE_NAME` | Extraction service the OCR pipeline calls | No | Azure resource name | AI/Platform | — none yet | Server-side extraction | Format agreed only | Not supplied |
| `AZURE_OPENAI_RESOURCE_NAME` | Model resource behind the interview assistant | No | Azure OpenAI resource name | AI/Platform | — none yet | Server-side interview (feature-gated) | Format agreed only | Not supplied and feature-gated |
| `GRAPH_TENANT_ID` | Workforce tenant for staff-assisted sessions | No | Workforce tenant UUID | Identity/Assistance | — none yet | Teams assistance (disabled) | Format agreed only | Not supplied |
| `GRAPH_CLIENT_ID` | App registration used for staff assistance | No | App registration UUID | Identity/Assistance | — none yet | Teams assistance (disabled) | Format agreed only | Not supplied |
| `GRAPH_HOST_MAILBOX_ALLOWLIST` | Bounds which staff mailboxes may host a session | No | Approved staff mailbox IDs stored outside mobile | Assistance/Security | — none yet | Teams assistance (disabled) | Format agreed only | Not supplied |
| `GRAPH_CLIENT_CERTIFICATE` | Certificate credential for Graph, held by reference only | Yes | Key Vault certificate reference, never certificate bytes in source | Identity/Security | — none yet | Teams assistance (disabled) | Format agreed only | Not supplied; Teams feature disabled |
| `APERTURE_ENVIRONMENT` | Selects which deployment the app talks to | No | `local`, `development`, `staging`, `production` | Mobile | — none yet | Local development and every deployed build | Format agreed only | Local default needed |
| `APERTURE_RUNTIME_MODE` | Decides whether the compiled stub may serve data; production fails closed | No | `local`, `internal-demo`, `production` | Mobile/Release | `Info.plist` via `project.pbxproj`; `ios-alpha-internal-testflight.yml` | Every build | Asserted in CI by `validate-ios-release.sh` | Debug=`local`; Release=`internal-demo`; production intentionally fails closed while the stub is compiled |
| `APERTURE_API_BASE_URL` | Base URL the generated client issues requests against | No | `https://api.<environment>.<domain>/v1` | Platform/API | — none yet | Production API | Format agreed only | Final domains TBD |
| `APERTURE_WEBAUTHN_RP_ID` | Relying-party domain that scopes every passkey | No | Registrable auth domain, never the API URL | Identity/Security | — none yet | Passkey registration and sign-in | Format agreed only | TBD |
| `APERTURE_ASSOCIATED_DOMAIN` | Entitlement binding the app to the passkey domain | No | `webcredentials:<rp-id>` | Identity/Mobile | — none yet | Passkey registration and sign-in | Format agreed only | TBD |
| `APERTURE_APP_ATTEST_ENVIRONMENT` | Selects Apple's attestation environment for client integrity | No | `development` or `production` | Security/Mobile | — none yet | Production client attestation | Format agreed only | TBD |
| `APERTURE_VOICE_BROKER_URL` | Issues short-lived voice credentials so no long-lived key reaches the device | No | HTTPS endpoint returning an ephemeral credential | AI/Platform | — none yet | Voice interview | Format agreed only | Deferred and gated |
| `APERTURE_NOTICE_VERSION` | Version of the consent notice recorded with each grant | No | Version such as `2026.03` | Legal/Product | — none yet | Consent record integrity | Fixture value only | Contract example only |
| `APERTURE_NOTICE_SHA256` | Digest binding a consent record to the exact copy shown | No | Lowercase SHA-256 hex digest | Legal/Product | — none yet | Consent record integrity | Fixture value only | Generated from approved copy |
| `APPLE_DEVELOPMENT_TEAM` | Apple team that owns signing identity | No | Ten-character Apple team identifier | Release Engineering | `ios-alpha-internal-testflight.yml` | Internal TestFlight upload | Consumed by the release workflow; unverifiable until supplied | Not supplied |
| `PRODUCT_BUNDLE_IDENTIFIER` | Identity of the shipped app across signing, store and entitlements | No | Currently `app.aperture.mobile` | Mobile/Release | `project.pbxproj`, `Info.plist`, `ios-alpha-internal-testflight.yml` | Every build; signing | Asserted in CI by `validate-ios-release.sh` | Confirm before signing |
| `APP_STORE_CONNECT_API_ISSUER_ID` | Identifies the App Store Connect API tenant | No | UUID from App Store Connect Users and Access | Release Engineering | `ios-alpha-internal-testflight.yml` | Internal TestFlight upload | Consumed by the release workflow; unverifiable until supplied | Not supplied |
| `APP_STORE_CONNECT_API_KEY_ID` | Names which API key is authenticating | No | App Store Connect API key identifier | Release Engineering | `ios-alpha-internal-testflight.yml` | Internal TestFlight upload | Consumed by the release workflow; unverifiable until supplied | Not supplied |
| `APP_STORE_CONNECT_API_PRIVATE_KEY_PATH` | Where CI materialises the key for the upload step only | Yes | Protected temporary path to the `.p8` key materialized by CI | Release Engineering | `ios-alpha-internal-testflight.yml` | Internal TestFlight upload | Consumed by the release workflow; unverifiable until supplied | Not supplied; never commit the key |
| `APP_STORE_CONNECT_API_PRIVATE_KEY_BASE64` | Transport form of the key, scoped to one protected step | Yes | Base64 of the `.p8`, scoped only to the protected key-materialization step | Release Engineering | `ios-alpha-internal-testflight.yml` | Internal TestFlight upload | Consumed by the release workflow; unverifiable until supplied | Not supplied; GitHub `internal-testflight` environment secret |
| `GITHUB_RELEASE_ENVIRONMENT` | Protected environment enforcing reviewers before any upload | No | Exact environment name `internal-testflight` | Release Engineering | `ios-alpha-internal-testflight.yml` (`environment:` name, not a variable) | Internal TestFlight upload | Referenced by the workflow; environment policy unconfigured | Workflow references it; required reviewers, no self-review, main-only branch, and admin-bypass policy must be configured in GitHub |
| `APP_STORE_APPLE_ID` | Numeric identity of the App Store Connect record | No | Numeric identifier created with the App Store Connect record | Release Engineering | — none yet | App Store record | Format agreed only | Not supplied |
| `APP_STORE_PRIMARY_LANGUAGE` | Default language of the store listing | No | Expected `en-US` | Product/Release | — none yet | App Store record | Format agreed only | Not confirmed |
| `APP_STORE_COPYRIGHT` | Legal owner asserted on the listing | No | Current legal owner and year | Legal | — none yet | App Store record | Format agreed only | Not supplied |
| `APP_STORE_PRIVACY_POLICY_URL` | Published policy Apple requires before review | No | Published HTTPS privacy-policy URL | Legal/Product | — none yet | App Store submission | Format agreed only | Not supplied; required for iOS submission |
| `APP_STORE_SUPPORT_URL` | Published support route Apple requires | No | Published HTTPS customer-support URL | Support/Product | — none yet | App Store record | Format agreed only | Not supplied; required for the store record |
| `APP_STORE_MARKETING_URL` | Optional product page on the listing | No | Published HTTPS product page | Marketing/Product | — none yet | Optional | Format agreed only | Optional; not supplied |
| `APP_STORE_SKU` | Stable internal identifier for the app record | No | Stable internal App Store Connect identifier | Release Engineering | — none yet | App Store record | Format agreed only | Not supplied; choose before creating the app record |
| `APP_STORE_PRIMARY_CATEGORY` | Category the listing is filed under | No | App Store category selected from Apple's current list | Product | — none yet | App Store record | Format agreed only | Not supplied |
| `APP_STORE_CONTENT_RIGHTS_DECLARATION` | Declares rights over third-party content in the app | No | Approved response backed by the versioned rights inventory | Legal | — none yet | App Store submission | Backed by the versioned rights inventory; unapproved | Not supplied |
| `APP_STORE_PRIVACY_ANSWERS_APPROVAL` | Approved App Privacy answers bound to a build | No | Approver and build-bound App Privacy response revision | Legal/Privacy | — none yet | App Store submission (REVIEW R-4) | Fixture crosswalk only; production approval absent | Fixture-only crosswalk exists; production approval absent |
| `APP_STORE_ACCESSIBILITY_RESPONSES` | Accessibility support claimed on the listing | No | Approved accessibility-label selections backed by common-task evidence | Accessibility/Product | — none yet | App Store submission | Evidence incomplete; must not claim support yet | Do not indicate support for Alpha 0.1 |
| `APP_STORE_VERSION_RELEASE_SETTING` | Whether an approved build releases manually, automatically or in phases | No | Manual, automatic, or phased release | Product/Release | — none yet | Public release | Format agreed only | Not supplied; public-release only |
| `APP_STORE_AVAILABILITY_TERRITORIES` | Territories the app may be downloaded in | No | Approved App Store territory set | Legal/Product | — none yet | Public release | Format agreed only | Not supplied; public-release only |
| `APP_STORE_PRICE_SCHEDULE` | Price or free schedule for the listing | No | Approved price/free schedule | Product/Finance | — none yet | Public release | Format agreed only | Not supplied; public-release only |
| `APP_STORE_REVIEW_CONTACT` | Operational contact Apple uses during review | No | Protected operational name, email, and phone supplied in App Store Connect | Release/Product | — none yet | App Store submission | Format agreed only | Not supplied; do not commit personal contact details |
| `APP_STORE_AGE_RATING_RESPONSES` | Questionnaire answers producing the age rating | No | Approved App Store Connect questionnaire answers for the submitted binary | Product/Legal | — none yet | App Store submission | Format agreed only | Not supplied; must reflect document, voice, and web-link behavior |
| `APP_STORE_REVIEW_NOTES` | Instructions and access path for Apple's reviewer | No | Reviewer instructions and a non-production review account or approved no-login path | Product/Release | — none yet | App Store submission | Format agreed only | Not supplied; never commit review credentials |
| `APP_USES_NON_EXEMPT_ENCRYPTION` | Export-compliance determination for the binary | No | App Store export-compliance determination | Legal/Security | — none yet | Every submitted build | Project declares `NO`; re-review needed for production networking | Current project declares `NO`; re-review for the production networking binary |
| `APERTURE_SCREENSHOT_KIND` | Separates internal-review capture from store capture | No | `internal-review` or `store` | Design/Release | `tools/capture-ios-store-screenshots.sh` | Store screenshot capture | Checked by `capture-ios-store-screenshots.sh` when run | Local default is `internal-review`; store mode is explicitly gated |
| `APERTURE_SCREENSHOT_SOURCE` | Requires an approved data source before store capture | No | Exact value `production-reviewed` for store capture | Product/Privacy | `tools/capture-ios-store-screenshots.sh` | Store screenshot capture | Checked by `capture-ios-store-screenshots.sh` when run | Non-persistent marketing-safe Alpha fixture implemented; final production-reviewed source not approved |
| `APERTURE_SCREENSHOT_APP_PATH` | Points at the approved simulator build to capture | No | Local path to an approved iOS Simulator `.app` | Mobile/Release | `tools/capture-ios-store-screenshots.sh` | Store screenshot capture | Checked by `capture-ios-store-screenshots.sh` when run | Not supplied; required for store-mode capture |
| `APERTURE_STORE_SCREENSHOT_MIN_FREE_GB` | Refuses capture without enough disk to finish it | No | Positive integer, default `6` | Mobile/Release | `tools/capture-ios-store-screenshots.sh` | Store screenshot capture | Checked by `capture-ios-store-screenshots.sh` when run | Local default implemented; latest workspace check had about 1.3 GB free, so capture was safely deferred |
| `APERTURE_BACKGROUND_UPLOAD_SESSION_IDENTIFIER` | Names the background session resumed across launches | No | Reverse-DNS identifier such as `app.aperture.mobile.uploads` | Mobile/Release | — none yet | Background upload | Format agreed only | Confirm with final bundle ID before background transfer |
| `APERTURE_ACCOUNT_DELETION_ENDPOINT` | Server route that makes deletion real beyond this device | No | Authenticated endpoint initiating account and eligible server-data deletion | Identity/Privacy | — none yet | Production data-rights compliance | Format agreed only | Not supplied; current deletion is local-fixture-only |
| `APP_STORE_REVIEW_BACKEND_URL` | Environment Apple's reviewer exercises | No | Always-available production review environment URL | Platform/Release | — none yet | App Store submission | Format agreed only | Not supplied |
| `APP_STORE_REVIEW_USERNAME` | Non-production reviewer account identity | Yes | Non-expiring synthetic review identity stored in App Store Connect/secret store | Release/Support | — none yet | App Store submission | Format agreed only | Not supplied; never commit credentials |
| `APP_STORE_REVIEW_PASSWORD` | Credential for the reviewer account | Yes | Protected review credential | Release/Support | — none yet | App Store submission | Format agreed only | Not supplied; never commit credentials |
| `APERTURE_LARGE_UPLOAD_THRESHOLD_BYTES` | Size above which a transfer waits for Wi-Fi | No | `10485760` (10 MiB) | Product/Mobile | — none yet | Production transfer policy | Local default implemented; unconfirmed for production | Local default implemented; confirm before production rollout |
| `APERTURE_DOCUMENT_SANITIZATION_SERVICE_URL` | Service that neutralises uploaded documents before processing | No | Internal HTTPS service URL | Security/Platform | — none yet | Server-side ingestion | Format agreed only | Not supplied; server-side only |
| `APERTURE_MALWARE_SCANNER_PROFILE` | Scanning profile applied to every upload | No | Approved scanner engine/profile identifier | Security | — none yet | Server-side ingestion | Format agreed only | Not supplied; server-side only |
| `APERTURE_DOCUMENT_INTELLIGENCE_ENDPOINT` | Endpoint the extraction pipeline calls | No | Azure Document Intelligence resource endpoint | AI/Platform | — none yet | Server-side extraction | Format agreed only | Not supplied; server-side only |
| `APERTURE_DOCUMENT_INTELLIGENCE_CREDENTIAL` | Credential reference for that endpoint | Yes | Key Vault/managed-identity reference, never a raw key in mobile | AI/Platform | — none yet | Server-side extraction | Format agreed only | Not supplied; server-side only |
| `APERTURE_DOCUMENT_CLASSIFIER_VERSION` | Pins the classifier version a decision is attributable to | No | Immutable calibrated classifier version | AI/Data | — none yet | Server-side classification | Format agreed only | Not supplied |
| `APERTURE_EXTRACTION_MODEL_VERSIONS` | Pins extractor versions recorded in the provenance ledger | No | Approved class-to-model version map | AI/Data | — none yet | Server-side extraction | Format agreed only | Not supplied |
| `APERTURE_INJECTION_DETECTOR_VERSION` | Pins the detector version for instruction-like document text | No | Immutable instruction-like-text detector version | Security/AI | — none yet | Server-side extraction safety | Format agreed only | Not supplied; server-side only |
| `APERTURE_SECURITY_EVENT_SINK` | Destination for security events the client cannot deliver itself | No | Internal security-event destination identifier | Security/Platform | — none yet | Server-side observability | Format agreed only | Not supplied; server-side only |

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
The Spanish journey now covers the mechanically inventoried app and shared-package copy,
including visible plural rendering. Server/fixture-authored content remains verbatim, and
all engineering translations—especially legal, privacy, security, and retention claims—
still require the professional review in REVIEW R-3. Apple's Dynamic Type and text-clipping audit categories are excluded
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
