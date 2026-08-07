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
                Label(itemsNeedAttentionText, systemImage: "exclamationmark.circle.fill")
                    .font(Aperture.Typography.caption)
                    .foregroundStyle(Aperture.Palette.warning)
            } else if counters.isReadyToFile {
                // Neutral, not celebratory. We are not endorsing anything.
                Label(
                    ApertureString("progress.readyToFile"),
                    systemImage: "doc.badge.checkmark"
                )
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
        String.localizedStringWithFormat(
            ApertureString("progress.fields"),
            counters.fieldsFilled,
            counters.fieldsRequired
        )
    }

    private var documentsText: String {
        String.localizedStringWithFormat(
            ApertureString("progress.documents"),
            counters.documentsCollected,
            counters.documentsRequired
        )
    }

    private var itemsNeedAttentionText: String {
        String.localizedStringWithFormat(
            ApertureString("progress.itemsNeedAttention"),
            counters.blockingItems
        )
    }
}
