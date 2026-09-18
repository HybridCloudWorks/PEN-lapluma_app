import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import ApertureDomain

/// iOS / iPadOS 27 Liquid Glass design tokens and spatial styling system.
///
/// Implements translucent materials, specular rim luminescence, multi-layer elevation,
/// physics-based spring interactions, and Adaptive Contrast Scrims to strictly preserve
/// WCAG AA (>= 4.5:1) text contrast over dynamic backdrops.
public enum LiquidGlass {

    public enum MaterialStyle: Sendable {
        case ultraThin
        case regular
        case prominent
        case chromatic(tint: Color)

        @ViewBuilder
        public var backgroundMaterial: some View {
            switch self {
            case .ultraThin:
                #if canImport(UIKit)
                Rectangle().fill(.ultraThinMaterial)
                #else
                Rectangle().fill(Color.primary.opacity(0.05))
                #endif
            case .regular:
                #if canImport(UIKit)
                Rectangle().fill(.regularMaterial)
                #else
                Rectangle().fill(Color.primary.opacity(0.10))
                #endif
            case .prominent:
                #if canImport(UIKit)
                Rectangle().fill(.thickMaterial)
                #else
                Rectangle().fill(Color.primary.opacity(0.18))
                #endif
            case .chromatic(let tint):
                ZStack {
                    #if canImport(UIKit)
                    Rectangle().fill(.regularMaterial)
                    #else
                    Rectangle().fill(Color.primary.opacity(0.10))
                    #endif
                    tint.opacity(0.12)
                }
            }
        }
    }

    public enum Elevation: Sendable {
        case flat
        case raised
        case floating
        case modal

        public var primaryShadowRadius: CGFloat {
            switch self {
            case .flat: return 0
            case .raised: return 12
            case .floating: return 24
            case .modal: return 36
            }
        }

        public var primaryShadowY: CGFloat {
            switch self {
            case .flat: return 0
            case .raised: return 4
            case .floating: return 10
            case .modal: return 16
            }
        }

        public var ambientShadowRadius: CGFloat {
            switch self {
            case .flat: return 0
            case .raised: return 2
            case .floating: return 4
            case .modal: return 8
            }
        }
    }

    /// Specular rim gradient mimicking refractive glass edges under directional lighting.
    public static func specularRim(
        tone: Aperture.StatusTone? = nil,
        prominent: Bool = false
    ) -> LinearGradient {
        let topHighlight = Color.white.opacity(prominent ? 0.65 : 0.40)
        let midHighlight: Color
        if let tone = tone {
            midHighlight = tone.foreground.opacity(0.30)
        } else {
            midHighlight = Aperture.Palette.accent.opacity(0.20)
        }
        let bottomShadow = Color.black.opacity(0.08)

        return LinearGradient(
            colors: [topHighlight, midHighlight, bottomShadow],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// Adaptive Contrast Scrim ensuring underlying dynamic gradients or mesh canvases
/// never degrade legibility below WCAG AA thresholds (NFR-A11Y-004).
public struct AdaptiveContrastScrim: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let opacity: Double

    public init(opacity: Double = 0.88) {
        self.opacity = opacity
    }

    public func body(content: Content) -> some View {
        content
            .background(
                colorScheme == .dark
                    ? Color(red: 18 / 255.0, green: 20 / 255.0, blue: 24 / 255.0).opacity(opacity)
                    : Color.white.opacity(opacity)
            )
    }
}

/// Interactive button style with physics spring scale and haptic feedback.
public struct ApertureInteractiveSpringButtonStyle: ButtonStyle {
    let prominent: Bool
    let tint: Color?

    public init(prominent: Bool = false, tint: Color? = nil) {
        self.prominent = prominent
        self.tint = tint
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1.0)
            .animation(.spring(response: 0.32, dampingFraction: 0.68), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    ApertureHaptics.sensoryTick()
                }
            }
    }
}

/// Liquid Glass Card ViewModifier with specular rim, translucent material, and spatial elevation.
public struct LiquidGlassCardModifier: ViewModifier {
    let tone: Aperture.StatusTone?
    let material: LiquidGlass.MaterialStyle
    let elevation: LiquidGlass.Elevation
    let cornerRadius: CGFloat

    public init(
        tone: Aperture.StatusTone? = nil,
        material: LiquidGlass.MaterialStyle = .regular,
        elevation: LiquidGlass.Elevation = .raised,
        cornerRadius: CGFloat = Aperture.Radius.card
    ) {
        self.tone = tone
        self.material = material
        self.elevation = elevation
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content
            .padding(Aperture.Spacing.m)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.82))
                    .overlay {
                        material.backgroundMaterial
                            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    }
                    .overlay {
                        if let tone = tone {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(tone.background.opacity(0.35))
                        }
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LiquidGlass.specularRim(tone: tone),
                        lineWidth: 1.2
                    )
            }
            .shadow(
                color: Color.black.opacity(0.06),
                radius: elevation.primaryShadowRadius,
                x: 0,
                y: elevation.primaryShadowY
            )
            .shadow(
                color: Color.black.opacity(0.03),
                radius: elevation.ambientShadowRadius,
                x: 0,
                y: 1
            )
    }
}

/// Liquid Glass Button ViewModifier with iridescent highlight and elevation.
public struct LiquidGlassButtonModifier: ViewModifier {
    let prominent: Bool
    let tint: Color?

    public init(prominent: Bool = false, tint: Color? = nil) {
        self.prominent = prominent
        self.tint = tint
    }

    public func body(content: Content) -> some View {
        content
            .buttonStyle(ApertureInteractiveSpringButtonStyle(prominent: prominent, tint: tint))
            .apertureGlassButton(prominent: prominent)
            .overlay {
                RoundedRectangle(cornerRadius: Aperture.Radius.control, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(prominent ? 0.60 : 0.35),
                                Color.clear,
                                Color.black.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.0
                    )
            }
    }
}

/// Dynamic atmospheric mesh background creating spatial depth across iOS / iPadOS 27 surfaces
/// while preserving comfortable text contrast.
public struct AtmosphericMeshCanvas<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        ZStack {
            // Base canvas tone
            (colorScheme == .dark
                ? Color(red: 14 / 255.0, green: 16 / 255.0, blue: 22 / 255.0)
                : Color(red: 248 / 255.0, green: 249 / 255.0, blue: 252 / 255.0))
                .ignoresSafeArea()

            // Mesh gradient blooms
            RadialGradient(
                colors: [
                    Aperture.Palette.accent.opacity(colorScheme == .dark ? 0.28 : 0.14),
                    .clear
                ],
                center: .topLeading,
                startRadius: 40,
                endRadius: 650
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color.cyan.opacity(colorScheme == .dark ? 0.22 : 0.12),
                    .clear
                ],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 580
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color.indigo.opacity(colorScheme == .dark ? 0.20 : 0.08),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 60,
                endRadius: 500
            )
            .ignoresSafeArea()

            content
        }
    }
}

public extension View {
    /// Applies iOS / iPadOS 27 Liquid Glass card styling with specular rim and elevation.
    func apertureLiquidGlassCard(
        tone: Aperture.StatusTone? = nil,
        material: LiquidGlass.MaterialStyle = .regular,
        elevation: LiquidGlass.Elevation = .raised,
        cornerRadius: CGFloat = Aperture.Radius.card
    ) -> some View {
        modifier(LiquidGlassCardModifier(
            tone: tone,
            material: material,
            elevation: elevation,
            cornerRadius: cornerRadius
        ))
    }

    /// Applies iOS / iPadOS 27 Liquid Glass button styling with spring physics and tactile feedback.
    func apertureLiquidGlassButton(
        prominent: Bool = false,
        tint: Color? = nil
    ) -> some View {
        modifier(LiquidGlassButtonModifier(prominent: prominent, tint: tint))
    }

    /// Enforces an adaptive contrast scrim behind text elements over dynamic surfaces.
    func apertureAdaptiveContrastScrim(opacity: Double = 0.88) -> some View {
        modifier(AdaptiveContrastScrim(opacity: opacity))
    }
}
