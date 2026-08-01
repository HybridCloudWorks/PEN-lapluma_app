import SwiftUI
import ApertureUI
import ApertureAPI
import ApertureDomain

/// S-06 Form Selection — the most compliance-sensitive screen in the product.
///
/// What this screen does **not** do: no "recommended for you", no "popular", no ranking
/// of any kind, and no request carrying case data. The catalog API accepts none, so
/// personalisation is impossible rather than merely disallowed (ADR-001). Results are
/// ordered deterministically and are identical for every user.
struct CatalogView: View {
    @Environment(AppSession.self) private var session
    @State private var model = CatalogModel()
    @State private var query = ""

    var body: some View {
        List {
            Section {
                Text(aperture: "catalog.cannotChoose")
                    .font(Aperture.Typography.body)
                Link(ApertureString("catalog.findLegalHelp"),
                     destination: URL(string: "https://www.justice.gov/eoir/recognition-accreditation-roster-reports")!)
            }

            Section {
                ForEach(model.packages) { package in
                    NavigationLink { RequirementsView(package: package) } label: {
                        PackageRow(package: package)
                    }
                }
            } header: {
                Text("Form packages")
            } footer: {
                Text("Listed alphabetically by form number. This order is the same for everyone.")
            }
        }
        .navigationTitle("Choose forms")
        .searchable(text: $query, prompt: "Search by form number or title")
        .task(id: query) { await model.load(api: session.api, query: query) }
    }
}

@Observable
@MainActor
final class CatalogModel {
    var packages: [FormPackage] = []

    /// Note the parameters: a locale-scoped query and nothing else. No folder, no case,
    /// no person. The absence is the control.
    func load(api: any ApertureAPIClient, query: String) async {
        packages = (try? await api.catalogPackages(query: query.isEmpty ? nil : query)) ?? []
    }
}

struct PackageRow: View {
    let package: FormPackage

    var body: some View {
        VStack(alignment: .leading, spacing: Aperture.Spacing.xs) {
            Text(package.forms.map(\.formNumber).joined(separator: " + "))
                .font(Aperture.Typography.value)
            Text(package.title).font(Aperture.Typography.body)

            HStack(spacing: Aperture.Spacing.s) {
                Text(package.agency)
                if let edition = package.forms.first?.editionDate {
                    Text(ApertureString("catalog.editionDate \(edition.formatted(date: .abbreviated, time: .omitted))"))
                }
                if let fee = package.feeUSDCents {
                    Text(Decimal(fee) / 100, format: .currency(code: "USD"))
                }
            }
            .font(Aperture.Typography.caption)
            .foregroundStyle(Aperture.Palette.onSurfaceSecondary)

            // An XFA or flat form cannot be filled programmatically. Say so here rather
            // than letting the user discover it at generation time (ADR-003).
            if !package.supportsAutomaticFill {
                Label(ApertureString("catalog.assistedFillOnly"), systemImage: "exclamationmark.triangle")
                    .font(Aperture.Typography.caption)
                    .foregroundStyle(Aperture.Palette.warning)
            }

            Text(ApertureString("catalog.lastVerified \(package.lastVerified.formatted(.relative(presentation: .named)))"))
                .font(Aperture.Typography.caption)
                .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
        }
        .padding(.vertical, Aperture.Spacing.xs)
        .accessibilityElement(children: .combine)
    }
}

/// The cited requirement list. Conditional requirements show the agency's own wording
/// verbatim — we do not resolve the condition for the user and we do not paraphrase it.
struct RequirementsView: View {
    let package: FormPackage
    @Environment(AppSession.self) private var session
    @State private var requirements: RequirementSet?
    @State private var showsAttestation = false

    var body: some View {
        List {
            if let requirements {
                Section("What you'll need") {
                    Text("\(requirements.fieldCount) pieces of information and \(requirements.evidence.count) documents.")
                        .font(Aperture.Typography.body)
                }

                ForEach(requirements.evidence) { requirement in
                    Section {
                        Text(requirement.requirementDescription)
                            .font(Aperture.Typography.body)
                        if requirement.isConditional, let condition = requirement.conditionText {
                            Text("“\(condition)”")
                                .font(Aperture.Typography.caption.italic())
                                .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                        }
                        DisclosureGroup(ApertureString("missing.why")) {
                            CitationView(requirement.citation)
                        }
                    }
                }
            } else {
                ApertureLoadingView()
            }

            Section {
                Button {
                    showsAttestation = true
                } label: {
                    Text("Use these forms")
                        .frame(maxWidth: .infinity, minHeight: Aperture.Spacing.minimumTarget)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle(package.title)
        .task {
            requirements = try? await session.api.requirements(packageCode: package.packageCode)
        }
        .sheet(isPresented: $showsAttestation) {
            SelectionAttestationView(package: package)
        }
    }
}

/// A case cannot be created without this. The attestation records that a *human* chose
/// the package — it is the user-facing half of the scrivener boundary.
struct SelectionAttestationView: View {
    let package: FormPackage
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var attested = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Aperture.Spacing.l) {
                Text(aperture: "attestation.title")
                    .font(Aperture.Typography.sectionTitle)
                Text(aperture: "attestation.body")
                    .font(Aperture.Typography.body)

                Toggle(isOn: $attested) {
                    Text(aperture: "attestation.confirm")
                        .font(Aperture.Typography.body)
                }

                Spacer()

                Button {
                    Task {
                        _ = try? await session.api.createCase(
                            folderID: FolderID("f_ramirez"),
                            packageCode: package.packageCode,
                            roleAssignments: [:],
                            attestation: SelectionAttestation(
                                attested: attested,
                                attestationVersion: "2026.03",
                                text: ApertureString("attestation.confirm")
                            ),
                            idempotencyKey: IdempotencyKey.make()
                        )
                        dismiss()
                    }
                } label: {
                    Text(aperture: "common.continue")
                        .frame(maxWidth: .infinity, minHeight: Aperture.Spacing.minimumTarget)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!attested)

                DisclosureFooter()
            }
            .padding(Aperture.Spacing.l)
            .navigationTitle("Confirm")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
