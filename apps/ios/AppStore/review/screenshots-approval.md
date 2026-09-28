# App Store Screenshots Approval & Asset Manifest

Approval Status: **Approved for Beta 0.3 Staging & Production Review** (`staging-reviewed`).

## 1. Specifications & Dimensions

Screenshots are generated and validated according to Apple App Store specifications via `tools/capture-ios-store-screenshots.sh` and `tools/validate-ios-store-assets.sh`:

- **iPhone 6.9" Display**:
  - Target Resolution: `1290 x 2796` (iPhone 16 Pro Max / 15 Pro Max)
  - Color Profile: sRGB, 72 dpi, 24-bit RGB (No alpha channel)
  - Required Orientations: Portrait
- **iPad 13" Display**:
  - Target Resolution: `2048 x 2732` (iPad Pro 13-inch M4/M5)
  - Color Profile: sRGB, 72 dpi, 24-bit RGB (No alpha channel)
  - Required Orientations: Portrait

## 2. Supported Locales & Captures

All screenshots are captured across both supported App Store locales:
1. `en-US` (English - United States)
2. `es-MX` (Spanish - Mexico / Latin America)

### Capture Sequence & Routes

| Index | Asset Identifier | Route | Content Demonstrated |
| :--- | :--- | :--- | :--- |
| 1 | `01-welcome` | `welcome` | Clean onboarding interface; non-law-firm advisory notice; passwordless passkey creation |
| 2 | `02-home` | `home` | Client dashboard; active case organization; status indicators; quick action pills |
| 3 | `03-capture` | `capture` | Smart document scanner; on-device VisionKit camera integration; multi-format import options |
| 4 | `04-missing` | `missing` | Interactive question resolution; conversational chat and voice interview modes |
| 5 | `05-review` | `review` | Source-grounded value verification; side-by-side discrepancy panel; human confirmation ledger |
| 6 | `06-package` | `package` | Assembled official USCIS form packages (I-130, N-400, I-765, I-131); completion readiness check |

## 3. Human Visual & Privacy Audit

- **Privacy & PII**: Verified that zero real applicant PII or live identities appear in any capture; all client names, alien registration numbers, addresses, and dates of birth are synthetically generated demo fixtures.
- **Visual Design**: Verified compliance with Mercury "Alpine banking at blue hour" aesthetic, WCAG AA/AAA typography contrast, and Dynamic Type legibility.
- **Localization**: Verified 100% native Spanish copy with zero English leakage or truncated labels on `es-MX` captures.
