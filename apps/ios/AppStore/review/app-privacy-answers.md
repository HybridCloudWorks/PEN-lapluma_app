# Build-specific App Privacy answers

Release: Version 1.0 (Beta 0.3 / `1.0.0`)
Status: Approved for TestFlight & Public Store Submission.

`PrivacyInfo.xcprivacy` declares zero tracking (`NSPrivacyTracking: false`), zero tracking domains, and only standard `UserDefaults` API access with reason `CA92.1`. The application includes zero third-party advertising or analytics SDKs (ADR-012).

## Approved Privacy Declarations

| Data type | Collected | Linked | Tracking | Purpose | Evidence & Handling |
|---|---|---|---|---|---|
| Account identifiers & Email | Yes | Yes | No | App functionality / Sign-in | Bound to user session via passkey or enterprise SAML |
| Form answers & Identity data | Yes | Yes | No | App functionality | Stored locally and encrypted in transit to authorized gateway |
| Documents, photos, and scans | Yes | Yes | No | App functionality | Processed locally on-device via Apple VisionKit; zero unauthorized sharing |
| Voice recordings & Transcripts | Yes (optional) | Yes | No | Optional interview | Ephemeral audio processing; user-controlled consent toggles in Settings |
| Diagnostic info & Security events | Yes | No | No | Security & Integrity | Security event ledger; no cross-app tracking |

## Policy Links & Data Rights
- **Published Privacy Policy URL**: `https://lapluma.ai/privacy`
- **In-App Policy Access**: Integrated directly within `SettingsView` under the `Privacy and data` section.
- **Data Subject Rights**: In-app "Export all my data" and "Delete everything" affordances allow complete user data management.

