import SwiftUI

/// The user's language is primary; the **authoritative English form label** always
/// appears alongside.
///
/// This is a correctness requirement, not a courtesy: the applicant is filling an
/// English form, and a mistranslated field label produces a wrong answer in the right
/// box. Above accessibility size XL the secondary label collapses to a disclosure
/// control, because two languages at AX5 can exceed a single screen (SME m-14).
public struct BilingualLabel: View {
    private let primary: String
    private let english: String
    private let formReference: String?

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showsEnglish = false

    public init(primary: String, english: String, formReference: String? = nil) {
        self.primary = primary
        self.english = english
        self.formReference = formReference
    }

    private var shouldCollapse: Bool { typeSize >= .accessibility3 }

    public var body: some View {
        VStack(alignment: .leading, spacing: Aperture.Spacing.xs) {
            Text(primary)
                .font(Aperture.Typography.body)
                .foregroundStyle(Aperture.Palette.onSurface)

            if shouldCollapse {
                Button {
                    showsEnglish.toggle()
                } label: {
                    Label(
                        showsEnglish ? english : ApertureString("field.showEnglishLabel"),
                        systemImage: showsEnglish ? "chevron.up" : "chevron.down"
                    )
                    .font(Aperture.Typography.secondaryLanguage)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
            } else if primary != english {
                Text(english)
                    .font(Aperture.Typography.secondaryLanguage)
                    .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
            }

            if let formReference {
                Text(formReference)
                    .font(Aperture.Typography.caption)
                    .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    /// The form reference is part of the label's meaning — it tells the applicant
    /// which official field this answer lands in — so it is spoken too, even while
    /// the English text is visually collapsed behind the disclosure control.
    /// Internal so the invariant is testable.
    var accessibilityText: String {
        var parts: [String] = []
        if !primary.isEmpty {
            parts.append(primary)
        }
        if primary != english, !english.isEmpty {
            parts.append(english)
        }
        if let formReference, !formReference.isEmpty {
            parts.append(formReference)
        }
        return parts.joined(separator: ". ")
    }
}
