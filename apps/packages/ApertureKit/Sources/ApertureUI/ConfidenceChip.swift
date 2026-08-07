import SwiftUI
import ApertureDomain

/// A confidence band rendered as icon + label. Never a percentage.
///
/// A fluent number beside someone's date of birth manufactures assurance exactly where
/// verification matters most, so applicants see a band and a plain sentence. The raw
/// score is retained for calibration and shown only in the reviewer workbench, where
/// the audience is trained and the number is actionable (ADR-010).
public struct ConfidenceChip: View {
    private let band: ConfidenceBand

    public init(_ band: ConfidenceBand) {
        self.band = band
    }

    public var body: some View {
        HStack(spacing: Aperture.Spacing.xs) {
            Image(systemName: band.symbolName)
                .imageScale(.small)
            Text(label)
                .font(Aperture.Typography.caption)
        }
        .padding(.horizontal, Aperture.Spacing.s)
        .padding(.vertical, Aperture.Spacing.xs)
        .background(background)
        .foregroundStyle(foreground)
        .clipShape(Capsule())
        // One element to VoiceOver, with the plain-language meaning as the hint so a
        // non-visual user gets the same information a sighted user gets on tap.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityHint(explanation)
    }

    private var label: String {
        ApertureString(String.LocalizationValue(band.chipKey))
    }

    private var explanation: String {
        ApertureString(String.LocalizationValue(band.explanationKey))
    }

    private var foreground: Color {
        switch band {
        case .verified: Aperture.Palette.onSurface
        case .extracted: Aperture.Palette.onSurfaceSecondary
        case .needsReview: Aperture.Palette.critical
        }
    }

    private var background: Color {
        switch band {
        case .verified: Aperture.Palette.surfaceSecondary
        case .extracted: Aperture.Palette.surfaceSecondary
        case .needsReview: Aperture.Palette.critical.opacity(0.12)
        }
    }
}
