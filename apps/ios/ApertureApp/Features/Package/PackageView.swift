import SwiftUI
import ApertureUI
import ApertureAPI
import ApertureDomain

/// S-14/S-15. Preview the actual filled government form, then get it out safely.
struct PackageView: View {
    let caseID: CaseID
    @Environment(AppSession.self) private var session
    @State private var generated: GeneratedPackage?
    @State private var loaded = false

    var body: some View {
        List {
            if let generated {
                Section("Verification") {
                    // A package cannot exist unverified: round-trip verification
                    // re-parses the output and asserts equality with the source record.
                    // A mismatch fails generation — it does not warn (ADR-003).
                    LabeledContent("Fields checked", value: "\(generated.verification.fieldsVerified)")
                    LabeledContent("Mismatches", value: "\(generated.verification.mismatches)")
                }

                Section("Documents") {
                    ForEach(generated.outputs.sorted { $0.sortOrder < $1.sortOrder }) { output in
                        OutputRow(output: output)
                    }
                }

                Section("Filing checklist") {
                    if let fee = generated.filingChecklist.feeUSDCents {
                        LabeledContent("Fee", value: Decimal(fee) / 100, format: .currency(code: "USD"))
                    }
                    if let address = generated.filingChecklist.filingAddress {
                        LabeledContent("Where to file", value: address)
                    }
                    ForEach(generated.filingChecklist.wetInkSignaturePoints) { point in
                        Label("Sign by hand: \(point.formNumber) \(point.partLabel)",
                              systemImage: "signature")
                            .font(Aperture.Typography.caption)
                    }
                }

                Section("Export") {
                    ForEach(ExportChannel.allCases, id: \.self) { channel in
                        Button(ApertureString(String.LocalizationValue(channel.localizationKey))) {}
                    }
                    Text(aperture: "export.linkNotAttachment")
                        .font(Aperture.Typography.caption)
                        .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                }

                Section {
                    Text(aperture: "disclosure.notFiled")
                        .font(Aperture.Typography.body.weight(.semibold))
                    DisclosureFooter(emphasis: .prominent)
                }
            } else if loaded {
                ApertureMessageView(.empty(messageKey: "progress.itemsNeedAttention"))
            } else {
                ApertureLoadingView()
            }
        }
        .navigationTitle("Forms")
        .task {
            generated = try? await session.api.generatedPackage(caseID: caseID)
            loaded = true
        }
    }
}

struct OutputRow: View {
    let output: PDFOutput

    var body: some View {
        VStack(alignment: .leading, spacing: Aperture.Spacing.xs) {
            Text(output.formNumber ?? output.kind.rawValue)
                .font(Aperture.Typography.value)
            Text("\(output.pageCount) pages")
                .font(Aperture.Typography.caption)
                .foregroundStyle(Aperture.Palette.onSurfaceSecondary)

            // XFA and flat forms cannot be filled. Say so prominently rather than
            // shipping something that looks like a filled form and is not.
            if output.fillMode == .assistedOnly {
                Label(ApertureString("catalog.assistedFillOnly"), systemImage: "exclamationmark.triangle")
                    .font(Aperture.Typography.caption)
                    .foregroundStyle(Aperture.Palette.warning)
            }

            // Overflow generates a conforming addendum. Truncating a name or an address
            // is a defect that reaches an adjudicator.
            if let reason = output.reason {
                Text(reason)
                    .font(Aperture.Typography.caption)
                    .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
