import Foundation
import SwiftUI
import Testing
import ApertureDomain
@testable import ApertureUI

@Suite("Pastel Visual System & Accessibility (APP-10, APP-11, APP-12)")
@MainActor
struct PastelVisualAccessibilityTests {

    @Test("Design tokens geometry satisfies specified radii and grid rhythm")
    func geometryInvariants() {
        #expect(Aperture.Radius.card == 12)
        #expect(Aperture.Radius.chip == 8)
        #expect(Aperture.Radius.control == 32)
        #expect(Aperture.Radius.pill == 40)

        #expect(Aperture.Spacing.xs == 4)
        #expect(Aperture.Spacing.s == 8)
        #expect(Aperture.Spacing.grid12 == 12)
        #expect(Aperture.Spacing.m == 16)
        #expect(Aperture.Spacing.grid20 == 20)
        #expect(Aperture.Spacing.l == 24)
        #expect(Aperture.Spacing.xl == 32)
        #expect(Aperture.Spacing.grid40 == 40)
        #expect(Aperture.Spacing.grid56 == 56)
        #expect(Aperture.Spacing.grid72 == 72)
        #expect(Aperture.Spacing.grid112 == 112)
        #expect(Aperture.Spacing.grid128 == 128)

        #expect(Aperture.Spacing.minimumTarget == 44)
        #expect(Aperture.Spacing.accessibleTarget == 48)
    }

    @Test("Status tones provide non-empty SF Symbol icons for non-color state encoding (NFR-A11Y-004)")
    func statusToneNonColorInvariants() {
        let tones: [Aperture.StatusTone] = [
            .information,
            .attention,
            .critical,
            .positive,
            .neutral
        ]

        for tone in tones {
            #expect(!tone.iconName.isEmpty)
        }

        #expect(Aperture.StatusTone.information.iconName == "info.circle.fill")
        #expect(Aperture.StatusTone.attention.iconName == "exclamationmark.circle.fill")
        #expect(Aperture.StatusTone.critical.iconName == "exclamationmark.triangle.fill")
        #expect(Aperture.StatusTone.positive.iconName == "checkmark.circle.fill")
        #expect(Aperture.StatusTone.neutral.iconName == "circle.fill")
    }

    @Test("Confidence bands map to symbols, localized chip labels, and explanations")
    func confidenceBandInvariants() {
        for band in ConfidenceBand.allCases {
            #expect(!band.symbolName.isEmpty)
            #expect(!band.chipKey.isEmpty)
            #expect(!band.explanationKey.isEmpty)

            let chipTextEn = ApertureString(String.LocalizationValue(band.chipKey), locale: Locale(identifier: "en"))
            let chipTextEs = ApertureString(String.LocalizationValue(band.chipKey), locale: Locale(identifier: "es"))
            #expect(chipTextEn != band.chipKey)
            #expect(chipTextEs != band.chipKey)

            let explanationEn = ApertureString(String.LocalizationValue(band.explanationKey), locale: Locale(identifier: "en"))
            let explanationEs = ApertureString(String.LocalizationValue(band.explanationKey), locale: Locale(identifier: "es"))
            #expect(explanationEn != band.explanationKey)
            #expect(explanationEs != band.explanationKey)
        }
    }

    @Test("Every case state has localized text and deterministic status representation")
    func caseStateLocalizationAndToneIntegrity() {
        for state in CaseState.allCases {
            let localizedEn = ApertureString(String.LocalizationValue(state.localizationKey), locale: Locale(identifier: "en"))
            let localizedEs = ApertureString(String.LocalizationValue(state.localizationKey), locale: Locale(identifier: "es"))

            #expect(!localizedEn.isEmpty)
            #expect(!localizedEs.isEmpty)
            #expect(localizedEn != state.localizationKey)
            #expect(localizedEs != state.localizationKey)
        }
    }

    @Test("Haptics trigger without error")
    func hapticsExecution() {
        ApertureHaptics.feedback(.success)
        ApertureHaptics.feedback(.warning)
        ApertureHaptics.feedback(.error)
        ApertureHaptics.impact(.light)
        ApertureHaptics.impact(.medium)
        ApertureHaptics.impact(.heavy)
        ApertureHaptics.sensoryTick()
        ApertureHaptics.magneticSnap()
    }

    @Test("Liquid Glass elevation metrics conform to spatial depth hierarchy")
    func liquidGlassElevationMetrics() {
        #expect(LiquidGlass.Elevation.flat.primaryShadowRadius == 0)
        #expect(LiquidGlass.Elevation.raised.primaryShadowRadius == 12)
        #expect(LiquidGlass.Elevation.floating.primaryShadowRadius == 24)
        #expect(LiquidGlass.Elevation.modal.primaryShadowRadius == 36)

        #expect(LiquidGlass.Elevation.flat.primaryShadowY == 0)
        #expect(LiquidGlass.Elevation.raised.primaryShadowY == 4)
        #expect(LiquidGlass.Elevation.floating.primaryShadowY == 10)
        #expect(LiquidGlass.Elevation.modal.primaryShadowY == 16)
    }

    @Test("Liquid Glass specular rim gradient generates valid color ramp")
    func liquidGlassSpecularRimIntegrity() {
        let defaultRim = LiquidGlass.specularRim()
        #expect(defaultRim != nil)

        for tone in Aperture.StatusTone.allCases {
            let toneRim = LiquidGlass.specularRim(tone: tone, prominent: true)
            #expect(toneRim != nil)
        }
    }
}
