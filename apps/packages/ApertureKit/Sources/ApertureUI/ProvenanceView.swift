import SwiftUI
import ApertureDomain

/// Every value is one tap from the pixels it came from (UX-3).
///
/// This is what makes human confirmation a genuine check rather than a rubber stamp:
/// the reviewer sees the source region, not just a value someone claims was extracted.
public struct ProvenanceView: View {
    private let provenance: Provenance
    private let formReference: String

    public init(provenance: Provenance, formReference: String) {
        self.provenance = provenance
        self.formReference = formReference
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Aperture.Spacing.m) {
            Text(ApertureString("provenance.title"))
                .font(Aperture.Typography.sectionTitle)

            switch provenance {
            case .document(let anchor):
                documentProvenance(anchor)
            case .manualEntry(_, let date):
                Text(ApertureFormat(
                    "provenance.youTyped",
                    date.formatted(date: .abbreviated, time: .omitted)
                ))
            case .interview(_, _, _, let date):
                Text(ApertureFormat(
                    "provenance.fromInterview",
                    date.formatted(date: .abbreviated, time: .omitted)
                ))
            }

            Divider()
            Text(ApertureFormat("provenance.goesTo", formReference))
                .font(Aperture.Typography.caption)
                .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
        }
        .padding(Aperture.Spacing.m)
    }

    @ViewBuilder
    private func documentProvenance(_ anchor: DocumentAnchor) -> some View {
        VStack(alignment: .leading, spacing: Aperture.Spacing.s) {
            Text(ApertureFormat(
                "provenance.fromDocument",
                anchor.documentName,
                anchor.pageNumber
            ))
                .font(Aperture.Typography.body)

            // The highlighted source region. In the real client this overlays the page
            // image; the geometry is already carried on the anchor.
            SourceRegionPlaceholder(anchor: anchor)

            Text(ApertureFormat("provenance.engine", anchor.engine, anchor.engineVersion))
                .font(Aperture.Typography.caption)
                .foregroundStyle(Aperture.Palette.onSurfaceSecondary)

            if let note = anchor.normalizationNote {
                Text(note)
                    .font(Aperture.Typography.caption)
                    .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
            }
        }
    }
}

/// Draws the extraction region over the page. The real implementation composites this
/// on the rasterised page image served by the backend — the client never parses an
/// unsanitised original (C-15).
struct SourceRegionPlaceholder: View {
    let anchor: DocumentAnchor

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Aperture.Radius.chip)
                    .fill(Aperture.Palette.surfaceSecondary)
                if !anchor.isDegenerate {
                    let minX = anchor.boundingPolygon.map(\.x).min() ?? 0
                    let minY = anchor.boundingPolygon.map(\.y).min() ?? 0
                    let maxX = anchor.boundingPolygon.map(\.x).max() ?? 0
                    let maxY = anchor.boundingPolygon.map(\.y).max() ?? 0
                    Rectangle()
                        .strokeBorder(Aperture.Palette.accent, lineWidth: 2)
                        .frame(width: (maxX - minX) * geometry.size.width,
                               height: max((maxY - minY) * geometry.size.height, 8))
                        .offset(x: minX * geometry.size.width, y: minY * geometry.size.height)
                }
            }
        }
        .frame(height: 160)
        .accessibilityHidden(true)
    }
}
