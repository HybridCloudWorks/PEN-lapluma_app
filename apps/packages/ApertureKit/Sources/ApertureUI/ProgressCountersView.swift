import SwiftUI
import ApertureDomain

/// Two explicit mechanical counters. **There is no percentage and no ring.**
///
/// "Your application is 94% complete" is heard by an anxious applicant as "you are 94%
/// of the way to being approved" (C-20). The denominators are always shown, and the
/// caveat travels with the numbers rather than living in a settings screen nobody reads.
public struct ProgressCountersView: View {
    private let counters: ProgressCounters
    private let showsCaveat: Bool

    public init(_ counters: ProgressCounters, showsCaveat: Bool = true) {
        self.counters = counters
        self.showsCaveat = showsCaveat
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Aperture.Spacing.s) {
            Text(fieldsText)
                .font(Aperture.Typography.body)
            Text(documentsText)
                .font(Aperture.Typography.body)

            if counters.blockingItems > 0 {
                Text(String(localized: "progress.itemsNeedAttention \(counters.blockingItems)",
                            bundle: .module))
                    .font(Aperture.Typography.caption)
                    .foregroundStyle(Aperture.Palette.critical)
            } else if counters.isReadyToFile {
                // Neutral, not celebratory. We are not endorsing anything.
                Text(String(localized: "progress.readyToFile", bundle: .module))
                    .font(Aperture.Typography.caption.weight(.semibold))
                    .foregroundStyle(Aperture.Palette.readyNeutral)
            }

            if showsCaveat {
                ReadinessCaveat()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(fieldsText). \(documentsText)")
    }

    private var fieldsText: String {
        String(localized: "progress.fields \(counters.fieldsFilled) \(counters.fieldsRequired)",
               bundle: .module)
    }

    private var documentsText: String {
        String(localized: "progress.documents \(counters.documentsCollected) \(counters.documentsRequired)",
               bundle: .module)
    }
}
