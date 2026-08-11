import SwiftUI
import ApertureDomain

/// Requirements are quoted from the agency, never paraphrased into our own voice.
/// An item that cannot be sourced to a citation is dropped rather than shown (AP-5).
public struct CitationView: View {
    private let citation: Citation

    public init(_ citation: Citation) {
        self.citation = citation
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Aperture.Spacing.s) {
            if let quoted = citation.quotedText {
                Text("“\(quoted)”")
                    .font(Aperture.Typography.body.italic())
            }
            VStack(alignment: .leading, spacing: Aperture.Spacing.xs) {
                Text(citation.documentTitle)
                    .font(Aperture.Typography.caption.weight(.medium))
                if let section = citation.sectionRef {
                    Text(section).font(Aperture.Typography.caption)
                }
                if let revision = citation.revisionDate {
                    Text(revision.formatted(
                        Date.FormatStyle(date: .abbreviated, time: .omitted)
                            .locale(AperturePreferredLocale())
                    ))
                        .font(Aperture.Typography.caption)
                }
                Link(citation.sourceURL.absoluteString, destination: citation.sourceURL)
                    .font(Aperture.Typography.caption)
            }
            .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
        }
        .padding(Aperture.Spacing.m)
    }
}
