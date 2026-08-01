import SwiftUI

/// Semantic design tokens. **No colour conveys meaning on its own** — every state has an
/// icon and a label as well, because a meaningful fraction of this user base cannot
/// distinguish them (NFR-A11Y-004).
public enum Aperture {

    public enum Palette {
        public static let surface = Color(.systemBackground)
        public static let surfaceSecondary = Color(.secondarySystemBackground)
        public static let onSurface = Color(.label)
        public static let onSurfaceSecondary = Color(.secondaryLabel)
        public static let accent = Color.accentColor
        public static let warning = Color(.systemOrange)
        public static let critical = Color(.systemRed)
        /// `Ready to file` is deliberately neutral, not celebratory green.
        /// A green badge reads as endorsement, and we endorse nothing (UX-2).
        public static let readyNeutral = Color(.secondaryLabel)
        public static let separator = Color(.separator)
    }

    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 8
        public static let m: CGFloat = 16
        public static let l: CGFloat = 24
        public static let xl: CGFloat = 32
        /// Minimum touch target. 48 in the accessibility profile.
        public static let minimumTarget: CGFloat = 44
        public static let accessibleTarget: CGFloat = 48
    }

    public enum Radius {
        public static let card: CGFloat = 12
        public static let chip: CGFloat = 8
    }

    /// Everything scales with Dynamic Type. Snapshot tests run at XXXL and a
    /// truncation or overlap fails the accessibility gate.
    public enum Typography {
        public static let screenTitle = Font.largeTitle.weight(.bold)
        public static let sectionTitle = Font.title3.weight(.semibold)
        public static let body = Font.body
        public static let value = Font.body.weight(.medium)
        public static let caption = Font.footnote
        /// The secondary language in a bilingual pair. Never below 13pt effective size.
        public static let secondaryLanguage = Font.subheadline
    }
}

/// Honors Reduce Motion. No motion in this product carries information, so removing it
/// removes nothing.
public struct RespectfulAnimation: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: UUID())
    }
}

public extension View {
    func apertureCard() -> some View {
        self
            .padding(Aperture.Spacing.m)
            .background(Aperture.Palette.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Aperture.Radius.card, style: .continuous))
    }
}
