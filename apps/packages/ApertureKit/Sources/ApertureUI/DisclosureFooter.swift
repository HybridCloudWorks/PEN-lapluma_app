import SwiftUI

/// The not-a-law-firm disclosure.
///
/// Rendered by the **platform layer**, not by a tenant template, and there is no
/// parameter that removes it. `canSuppressNotALawFirmDisclosure` is false for every
/// tenant type in the admin API — it appears in the response so the constraint is
/// visible and auditable, not because it is configurable (C-10).
public struct DisclosureFooter: View {
    private let emphasis: Emphasis

    public enum Emphasis {
        /// Persistent, quiet, always present.
        case standard
        /// Used at moments of consequence: package generation, export, approval.
        case prominent
    }

    public init(emphasis: Emphasis = .standard) {
        self.emphasis = emphasis
    }

    public var body: some View {
        Text(ApertureString("disclosure.notALawFirm"))
            .font(emphasis == .prominent ? Aperture.Typography.caption.weight(.semibold)
                                         : Aperture.Typography.caption)
            .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Aperture.Spacing.m)
            .padding(.vertical, Aperture.Spacing.s)
            .accessibilityAddTraits(.isStaticText)
    }
}

/// Shown wherever readiness is displayed. Readiness is a statement about paperwork,
/// never a prediction about an agency decision (C-20).
public struct ReadinessCaveat: View {
    public init() {}

    public var body: some View {
        Text(ApertureString("disclosure.readinessNotPrediction"))
            .font(Aperture.Typography.caption)
            .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
    }
}
