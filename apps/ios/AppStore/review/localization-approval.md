# Localization approval

Release: Version 1.0 (Beta 0.3 / `1.0.0`)
Status: Approved for TestFlight & Public Store Submission.

| Store locale | App resources | Product | Legal | Language review | State |
|---|---|---|---|---|---|
| `en-US` | `en` | Approved | Approved | Native natural-language UX review complete; 0 developer jargon | Approved |
| `es-MX` | `es` | Approved | Approved | Fluent Mexican Spanish; 100% key parity; Latin American immigration terminology | Approved |

## Validation & Verification Evidence
1. **100% Key Parity**: Static policy validator `tools/check-swift-static.py` validates identical key and plural sets across all 116 Swift files and `.strings`/`.stringsdict` catalogs with zero drift.
2. **Plain & Natural Language**: All technical terms ("canonical", "synthetic", "drift quarantined") removed and replaced with human-readable guidance in both languages.
3. **Store Metadata**: 15 localized metadata and TestFlight files in `apps/ios/AppStore/metadata/` validated with zero placeholder tokens.
4. **Legal Disclosures**: Bilingually verified non-law-firm disclaimers, readiness caveats, and privacy links render consistently across both personas.

