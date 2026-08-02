import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Semantic design tokens. **No colour conveys meaning on its own** — every state has an
/// icon and a label as well, because a meaningful fraction of this user base cannot
/// distinguish them (NFR-A11Y-004).
public enum Aperture {

    public enum Palette {
        #if canImport(UIKit)
        public static let surface = Color(uiColor: .systemBackground)
        public static let surfaceSecondary = Color(uiColor: .secondarySystemBackground)
        public static let onSurface = Color(uiColor: .label)
        /// A quiet foreground that still clears WCAG AA for body and caption text.
        /// `secondaryLabel` can fall just below the threshold on grouped surfaces.
        public static let onSurfaceSecondary = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.76, alpha: 1)
                : UIColor(white: 0.30, alpha: 1)
        })
        /// System orange/red do not meet the 4.5:1 text contrast threshold on a
        /// light system background. These dynamic variants preserve the familiar
        /// hues while remaining readable when used as foreground text.
        public static let warning = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? .systemOrange
                : UIColor(red: 0.49, green: 0.25, blue: 0, alpha: 1)
        })
        public static let critical = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? .systemRed
                : UIColor(red: 0.72, green: 0, blue: 0.02, alpha: 1)
        })
        public static let readyNeutral = onSurfaceSecondary
        public static let separator = Color(uiColor: .separator)
        #elseif canImport(AppKit)
        public static let surface = Color(nsColor: .windowBackgroundColor)
        public static let surfaceSecondary = Color(nsColor: .controlBackgroundColor)
        public static let onSurface = Color(nsColor: .labelColor)
        public static let onSurfaceSecondary = Color(nsColor: .secondaryLabelColor)
        public static let warning = Color(nsColor: .systemOrange)
        public static let critical = Color(nsColor: .systemRed)
        public static let readyNeutral = Color(nsColor: .secondaryLabelColor)
        public static let separator = Color(nsColor: .separatorColor)
        #endif
        public static let accent = Color.accentColor
        /// `Ready to file` is deliberately neutral, not celebratory green.
        /// A green badge reads as endorsement, and we endorse nothing (UX-2).
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

private struct ApertureAccessibilityProfileKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// The user-selected profile complements system accessibility settings. It never
    /// replaces Dynamic Type, VoiceOver, Reduce Motion, or other OS preferences.
    var apertureAccessibilityProfileEnabled: Bool {
        get { self[ApertureAccessibilityProfileKey.self] }
        set { self[ApertureAccessibilityProfileKey.self] = newValue }
    }
}

public struct ApertureMinimumTouchTarget: ViewModifier {
    @Environment(\.apertureAccessibilityProfileEnabled) private var profileEnabled
    let expandHorizontally: Bool

    public func body(content: Content) -> some View {
        content.frame(
            maxWidth: expandHorizontally ? .infinity : nil,
            minHeight: profileEnabled ? Aperture.Spacing.accessibleTarget : Aperture.Spacing.minimumTarget
        )
    }
}

/// Honors Reduce Motion. No motion in this product carries information, so removing it
/// removes nothing.
public struct RespectfulAnimation<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animationValue: Value

    public func body(content: Content) -> some View {
        content.animation(
            reduceMotion ? nil : .easeInOut(duration: 0.2),
            value: animationValue
        )
    }
}

public extension View {
    /// Applies the documented 44-point baseline or 48-point profile minimum while
    /// preserving the control's visible and spoken label.
    func apertureMinimumTouchTarget(expandHorizontally: Bool = false) -> some View {
        modifier(ApertureMinimumTouchTarget(expandHorizontally: expandHorizontally))
    }

    /// The only supported entry point for app-authored motion. The system's Reduce
    /// Motion preference removes the animation without removing state information.
    func respectfulAnimation<Value: Equatable>(value: Value) -> some View {
        modifier(RespectfulAnimation(animationValue: value))
    }

    func apertureCard() -> some View {
        self
            .padding(Aperture.Spacing.m)
            .background(Aperture.Palette.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Aperture.Radius.card, style: .continuous))
    }
}
