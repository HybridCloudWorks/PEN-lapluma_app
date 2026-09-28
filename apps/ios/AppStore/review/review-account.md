# App Review Access Contract

Beta 0.3 / Version 1.0 provides direct, non-expiring App Review access via both instant onboarding and enterprise sign-in credentials.

## 1. Review Credentials & Authentication

- **Review Username**: `reviewer@hybridcloudworks.com`
- **Review Password / Passkey**: `ReviewPasskey2026!`
- **Workspace Code**: `NYC-01`
- **Instant Testing (Option A)**: App Reviewers can tap "Create account" with any email/name (e.g. `reviewer@apple.com`) to generate an instant local passkey and enter the workspace immediately.
- **Enterprise Testing (Option B)**: Enter the reviewer credentials above and proceed via passkey or account recovery without requiring employee OTP intervention.

## 2. Review Environment & Live Ingress

- **Ingress Gateway**: Live Google Cloud API Gateway staging deployment (`https://lp-gateway-staging-am9yq93d.uc.gateway.dev`).
- **Health Check & Availability**: Always-on HTTPS endpoints with 24/7 uptime.
- **Bypass Safeguards**: Passkey recovery flows bypass hardware device security keys without degrading production security controls.

## 3. Synthetic Test Data & Reset Capability

- **Demo Workspace Isolation**: All casework, folders, and documents rendered during review are synthetically generated and isolated from real applicant data.
- **Data Reset**: Reviewers can reset all state at any time via `Settings` -> `Reset demo data` or delete the local store via `Delete all local data`.

## 4. Support Contact During Review

- **Primary Contact**: Saul Patino (`spatino@hybridcloudworks.com`)
- **Developer Support**: `https://lapluma.ai`
