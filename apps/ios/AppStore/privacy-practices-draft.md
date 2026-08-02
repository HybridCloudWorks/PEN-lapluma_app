# App Privacy review crosswalk

Status: draft for Product, Legal, Security, and Backend review. Do not paste these
answers into App Store Connect until they match the exact submitted binary and its
production services.

## Current repository binary

The current local/internal binary uses persisted fixture data and does not send user
content to a production service. Its privacy manifest declares no tracking and no
off-device data collection. That statement is valid only for this fixture build.

## Production questions to resolve

For every data category below, owners must document whether it is collected, linked
to identity, used for tracking, retained, shared, or optional:

- account identifiers, email address, and authentication/security events;
- names, addresses, dates, identifiers, and other form answers;
- documents, photos, scans, filenames, and extracted text;
- voice recordings, transcripts, and derived interview answers;
- diagnostics, performance data, crash reports, and support communications;
- usage analytics, fraud prevention, App Attest signals, and coarse network data.

The review must also identify processors, retention/deletion behavior, user-request
workflows, encryption, cross-border handling, and whether sensitive or health-related
documents are accepted. Update both `PrivacyInfo.xcprivacy` and App Store Connect when
production behavior is introduced; neither artifact replaces a published privacy
policy.
