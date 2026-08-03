# Build-specific App Privacy answers

Alpha 0.1 is a fixture-only internal binary. `PrivacyInfo.xcprivacy` declares no
tracking and no off-device collection for that exact behavior. It does not describe
the future production document service.

Production owners must approve one row per data type:

| Data type | Collected | Linked | Tracking | Purpose | Processor | Retention/deletion | Evidence |
|---|---|---|---|---|---|---|---|
| Account identifiers and email | Pending | Pending | No tracking planned | Authentication | Pending | Pending | API contract required |
| Form answers and identity data | Pending | Pending | No tracking planned | App functionality | Pending | Pending | Data map required |
| Documents, photos, scans, filenames | Pending | Pending | No tracking planned | App functionality | Pending | Pending | Storage design required |
| Extracted text and classifications | Pending | Pending | No tracking planned | App functionality | Pending | Pending | AI data-flow review required |
| Voice recordings and transcripts | Pending | Pending | No tracking planned | Optional interview | Pending | Pending | Voice design required |
| Diagnostics and support messages | Pending | Pending | No tracking planned | Reliability/support | Pending | Pending | Telemetry design required |
| Security, fraud, and App Attest data | Pending | Pending | No tracking planned | Security | Pending | Pending | Security review required |

A published policy URL and an easily accessible in-app policy link are both missing.
The current “Delete everything” action clears local fixture data only. A production app
that creates accounts must initiate deletion of the account and eligible server-held
data, while explaining approved retention exceptions.
