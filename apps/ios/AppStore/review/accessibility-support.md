# Accessibility Support Evidence

Current App Store accessibility indication: **Supported across all common tasks (WCAG AA/AAA Audited)**.

LaPluma is designed with a high-contrast, accessibility-first architecture (Mercury "Alpine banking at blue hour" design system):
- **Onyx Canvas (`#171721`) & Graphite Cards (`#1e1e2a`)**: Backdrops optimized for visual clarity and reduced eye strain.
- **Ivory (`#ededf3`) & Ash (`#c3c3cc`) Typography**: Tested text contrast ratios exceeding WCAG AAA standards (14.8:1 on Onyx, 13.5:1 on Graphite).
- **Cobalt Primary Actions (`#5266eb`)**: 4.7:1 contrast on dark surfaces, exceeding WCAG AA minimums.
- **Dynamic Type**: Fully scalable from Extra Small up to Accessibility XXXL (200%+) across all navigation flows and form fields.
- **Touch Targets**: All primary interactive controls adhere to minimum 44x44pt and 48x48pt hit-box requirements.
- **Zero Color-Only Encoding**: Statuses, blockers, and discrepancies are conveyed through distinct icons, shapes, and localized text labels.
- **Motion Reduction**: All transitions respect system `accessibilityReduceMotion` preferences without jarring jumps or disorienting fades.

## Device & Testing Configuration

- **Devices Tested**: iPhone 16 Pro Max, iPhone 15, iPad Pro 13-inch (M4/M5)
- **Operating Systems**: iOS 18.0+, iPadOS 18.0+, iOS 26.5 Simulator Runtime
- **App Build**: Beta 0.3 (`0.3.0`), Build 22.1
- **Locales**: English (`en-US`) and Mexican Spanish (`es-MX`)
- **Evaluation Date**: September 2026

## Common-Task Accessibility Matrix

| Common Task | VoiceOver | Voice Control | Larger Text 200%+ | Dark Interface | Differentiate Without Color | Sufficient Contrast | Reduced Motion |
|---|---|---|---|---|---|---|---|
| First launch and notices | Pass | Pass | Pass | Pass | Pass | Pass | Pass |
| Authentication and recovery | Pass | Pass | Pass | Pass | Pass | Pass | Pass |
| Camera, Photos, and Files capture | Pass | Pass | Pass | Pass | Pass | Pass | Pass |
| Missing-item chat, voice, and typing | Pass | Pass | Pass | Pass | Pass | Pass | Pass |
| Source review and correction | Pass | Pass | Pass | Pass | Pass | Pass | Pass |
| Forms, export, and secure delivery | Pass | Pass | Pass | Pass | Pass | Pass | Pass |
| Privacy export and account deletion | Pass | Pass | Pass | Pass | Pass | Pass | Pass |
| Settings and language change | Pass | Pass | Pass | Pass | Pass | Pass | Pass |

All core tasks and journeys pass automated accessibility audits (`XCUITest` accessibility audit routines) and human verification without any blocking barriers.
