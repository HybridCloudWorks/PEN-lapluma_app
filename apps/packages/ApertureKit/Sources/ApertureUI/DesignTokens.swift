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
        public static let information = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? .systemCyan
                : UIColor(red: 0, green: 0.34, blue: 0.52, alpha: 1)
        })
        public static let positive = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? .systemGreen
                : UIColor(red: 0, green: 0.38, blue: 0.18, alpha: 1)
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
        public static let information = Color(nsColor: .systemCyan)
        public static let positive = Color(nsColor: .systemGreen)
        public static let readyNeutral = Color(nsColor: .secondaryLabelColor)
        public static let separator = Color(nsColor: .separatorColor)
        #endif
        public static let accent = Color.accentColor
        /// `Ready to file` is deliberately neutral, not celebratory green.
        /// A green badge reads as endorsement, and we endorse nothing (UX-2).
    }

    public enum StatusTone {
        case information
        case attention
        case critical
        case positive
        case neutral

        public var foreground: Color {
            switch self {
            case .information: Palette.information
            case .attention: Palette.warning
            case .critical: Palette.critical
            case .positive: Palette.positive
            case .neutral: Palette.onSurface
            }
        }

        public var background: Color { foreground.opacity(0.13) }
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
        public static let card: CGFloat = 20
        public static let chip: CGFloat = 8
        public static let control: CGFloat = 14
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

/// Keeps long-form mobile content intentional on iPad while retaining full width for
/// accessibility text sizes. The outer frame preserves the shared canvas around the
/// centered reading column.
public struct ApertureReadableContentWidth: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let maximum: CGFloat

    public func body(content: Content) -> some View {
        content
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : maximum)
            .frame(maxWidth: .infinity)
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

public struct ApertureGlassCardModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let padding: CGFloat

    @ViewBuilder
    public func body(content: Content) -> some View {
        if reduceTransparency {
            fallback(content: content, material: false)
        } else if #available(iOS 26.0, macOS 26.0, *) {
            content
                .padding(padding)
                .glassEffect(
                    .regular.tint(Aperture.Palette.accent.opacity(0.06)),
                    in: RoundedRectangle(cornerRadius: Aperture.Radius.card, style: .continuous)
                )
        } else {
            fallback(content: content, material: true)
        }
    }

    @ViewBuilder
    private func fallback(content: Content, material: Bool) -> some View {
        content
            .padding(padding)
            .background(
                material ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(Aperture.Palette.surfaceSecondary),
                in: RoundedRectangle(cornerRadius: Aperture.Radius.card, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Aperture.Radius.card, style: .continuous)
                    .strokeBorder(Aperture.Palette.onSurface.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.06), radius: 18, y: 8)
    }
}

public struct ApertureGlassButtonModifier: ViewModifier {
    let prominent: Bool

    @ViewBuilder
    public func body(content: Content) -> some View {
        if prominent {
            // A solid primary action gives XCTest and assistive technologies a
            // deterministic foreground/background pair. Glass remains the surrounding
            // hierarchy and the treatment for secondary controls.
            content.buttonStyle(AperturePrimaryButtonStyle())
        } else {
            content.buttonStyle(ApertureSecondaryButtonStyle())
        }
    }
}

public struct AperturePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? Color.white : Aperture.Palette.onSurfaceSecondary)
            .padding(.horizontal, Aperture.Spacing.s)
            .padding(.vertical, Aperture.Spacing.xs)
            .background(
                isEnabled ? Aperture.Palette.accent : Aperture.Palette.surfaceSecondary,
                in: RoundedRectangle(cornerRadius: Aperture.Radius.control, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Aperture.Radius.control, style: .continuous)
                    .strokeBorder(
                        isEnabled ? Aperture.Palette.accent : Aperture.Palette.onSurface.opacity(0.18),
                        lineWidth: 1
                    )
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

public struct ApertureSecondaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Aperture.Palette.onSurface)
            .padding(.horizontal, Aperture.Spacing.s)
            .padding(.vertical, Aperture.Spacing.xs)
            .background(
                Aperture.Palette.surfaceSecondary,
                in: RoundedRectangle(cornerRadius: Aperture.Radius.control, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Aperture.Radius.control, style: .continuous)
                    .strokeBorder(Aperture.Palette.onSurface.opacity(0.18), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

public extension View {
    /// Applies the documented 44-point baseline or 48-point profile minimum while
    /// preserving the control's visible and spoken label.
    func apertureMinimumTouchTarget(expandHorizontally: Bool = false) -> some View {
        modifier(ApertureMinimumTouchTarget(expandHorizontally: expandHorizontally))
    }

    /// Centers a readable column on regular-width devices without constraining
    /// accessibility text layouts.
    func apertureReadableContentWidth(maximum: CGFloat = 840) -> some View {
        modifier(ApertureReadableContentWidth(maximum: maximum))
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

    /// A quiet, system-material surface. The tint and stroke keep cards distinct in
    /// Increase Contrast and Reduce Transparency modes without turning the interface
    /// into a stack of heavy boxes.
    func apertureGlassCard(padding: CGFloat = Aperture.Spacing.m) -> some View {
        modifier(ApertureGlassCardModifier(padding: padding))
    }

    /// Contrast-stable controls that sit cleanly on Liquid Glass surfaces. Native
    /// transparent button glass is avoided because its backdrop cannot be proven by
    /// the automated contrast audit.
    func apertureGlassButton(prominent: Bool = false) -> some View {
        modifier(ApertureGlassButtonModifier(prominent: prominent))
    }

    /// Gives a status an icon-friendly semantic color surface. Callers still provide
    /// a visible label and symbol so meaning never depends on color alone.
    func apertureStatusSurface(
        _ tone: Aperture.StatusTone,
        horizontalPadding: CGFloat = Aperture.Spacing.s,
        verticalPadding: CGFloat = Aperture.Spacing.xs
    ) -> some View {
        self
            .foregroundStyle(tone.foreground)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(tone.background, in: RoundedRectangle(cornerRadius: Aperture.Radius.chip))
            .background(
                Aperture.Palette.surfaceSecondary,
                in: RoundedRectangle(cornerRadius: Aperture.Radius.chip)
            )
    }
}

public struct ApertureGlassEffectGroup<Content: View>: View {
    private let spacing: CGFloat?
    private let content: Content

    public init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    @ViewBuilder
    public var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

/// The shared app canvas keeps the translucent hierarchy legible in both appearances.
/// System materials automatically become opaque when Reduce Transparency is enabled.
public struct ApertureCanvas<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Aperture.Palette.surface,
                    Aperture.Palette.accent.opacity(0.08),
                    Color.cyan.opacity(0.10)
                ],
                startPoint: .top,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [Aperture.Palette.accent.opacity(0.24), .clear],
                center: .topLeading,
                startRadius: 20,
                endRadius: 520
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [Color.cyan.opacity(0.22), .clear],
                center: .bottomTrailing,
                startRadius: 12,
                endRadius: 460
            )
            .ignoresSafeArea()

            content
        }
    }
}
