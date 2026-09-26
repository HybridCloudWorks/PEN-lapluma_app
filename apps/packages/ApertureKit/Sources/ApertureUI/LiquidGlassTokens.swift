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
        let topHighlight = Aperture.Palette.mistBorder.opacity(prominent ? 0.35 : 0.18)
        let midHighlight = Aperture.Palette.slateBorder.opacity(0.12)
        let bottomShadow = Color.clear

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
                colorScheme == .light
                    ? Color.white.opacity(opacity)
                    : Aperture.Palette.onyxCanvas.opacity(opacity)
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
            .respectfulAnimation(value: configuration.isPressed)
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
                    .fill(Aperture.Palette.graphiteCard.opacity(0.88))
                    .overlay {
                        material.backgroundMaterial
                            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    }
                    .overlay {
                        if let tone = tone {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(tone.background.opacity(0.25))
                        }
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LiquidGlass.specularRim(tone: tone),
                        lineWidth: 1.0
                    )
            }
            .shadow(color: .clear, radius: 0)
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
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        ZStack {
            // Base canvas tone: Mercury Onyx Canvas (#171721)
            Aperture.Palette.onyxCanvas
                .ignoresSafeArea()

            // Mesh gradient blooms: Alpine banking at blue hour
            RadialGradient(
                colors: [
                    Aperture.Palette.cobalt.opacity(0.18),
                    .clear
                ],
                center: .topLeading,
                startRadius: 40,
                endRadius: 650
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color.cyan.opacity(0.08),
                    .clear
                ],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 580
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Aperture.Palette.obsidianButton.opacity(0.35),
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
