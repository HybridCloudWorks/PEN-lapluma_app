# App Review Access Contract

App Review and external TestFlight testers sign in the way a clinic user does: enterprise SAML
single sign-on through Microsoft Entra ID, against the live staging backend. There is no test
token, bypass, or reviewer-only code path in the submitted binary (INT-22).

## 1. Review Credentials & Authentication

- **Review account**: `reviewer@hybridcloudworks.com`, a dedicated user in the hybridcloudworks.com
  Microsoft Entra ID tenant, assigned only to the **LaPluma Staging** enterprise application.
- **Password**: stored in App Store Connect only (App Review Information > Sign-In Information,
  and TestFlight > Test Information > Beta App Review Information). Never kept in this repository.
- **Sign-in path**: **Sign in** > **Organization** (when the screen asks for an account type) >
  enter the review account as **Work email** > **Sign in with
  Microsoft Entra ID** > confirm the system prompt > enter the password at Microsoft's sign-in
  page. The app receives a one-time code and exchanges it for a one-hour session; when that
  expires the app signs in again through the same Microsoft session, with no password, after the
  system prompt.
- **No MFA prompt (required before submitting)**: the account must be excluded from multifactor
  authentication for LaPluma Staging, so a reviewer never needs the owner's phone. This needs
  Conditional Access; security defaults cannot exclude a user.
- **Instant local workspace (alternative)**: **Create account** with any email and name still
  opens a local, synthetic workspace on the device without contacting the backend.

The owner creates, assigns, and rotates the account by following PEN-lapluma_infra
`docs/runbooks/session-tokens-and-saml-identity-providers.md`, section 6 ("App Review and
TestFlight reviewer account"), which also says where each value goes in App Store Connect.

## 2. Review Environment & Live Ingress

- **Ingress Gateway**: Google Cloud API Gateway staging deployment
  (`https://lp-gateway-staging-am9yq93d.uc.gateway.dev`).
- **Sign-in endpoints**: `GET /auth/saml/login` (PKCE, S256), `POST /auth/saml/acs/{tenantId}`,
  and `POST /auth/token`. The session token never appears in a URL.
- **Availability**: staging must be deployed with the INT-22 backend (PEN-lapluma_infra) before a
  build that signs in this way is submitted.

## 3. Synthetic Test Data & Reset Capability

- **Demo Workspace Isolation**: All casework, folders, and documents rendered during review are synthetically generated and isolated from real applicant data.
- **Data Reset**: Reviewers can reset all state at any time via `Settings` -> `Reset demo data` or delete the local store via `Delete all local data`.

## 4. Support Contact During Review

- **Primary Contact**: Saul Patino (`spatino@hybridcloudworks.com`)
- **Developer Support**: `https://lapluma.ai`
