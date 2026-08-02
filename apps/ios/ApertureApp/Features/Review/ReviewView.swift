import SwiftUI
import ApertureUI
import ApertureAPI
import ApertureDomain

/// S-13 Form Review — the human-in-the-loop screen.
///
/// Every proposed value is confirmed here, or nowhere. The package API refuses to
/// generate while any required value is still a proposal, and the database refuses to
/// store a `FieldValue` without a human confirmer, so this screen is not a formality —
/// it is the control that the whole compliance position rests on.
///
/// Bulk accept is deliberately **absent on iPhone**. Friction belongs exactly where
/// automation bias is most likely.
struct ReviewView: View {
    let caseID: CaseID
    @Environment(AppSession.self) private var session
    @State private var model = ReviewModel()
    @State private var selectedField: ReviewableField?

    var body: some View {
        List {
            if model.fields.isEmpty {
                ApertureLoadingView()
            }

            ForEach(model.groupedByPerson, id: \.person) { group in
                Section(group.person) {
                    ForEach(group.fields) { field in
                        Button {
                            selectedField = field
                        } label: {
                            FieldRow(field: field)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section {
                DisclosureFooter()
                    .listRowBackground(Color.clear)
            }
        }
        .apertureReadableContentWidth()
        .navigationTitle("Review information")
        .task { await model.load(api: session.api, caseID: caseID) }
        .sheet(item: $selectedField) { field in
            FieldDetailSheet(caseID: caseID, field: field) {
                Task { await model.load(api: session.api, caseID: caseID) }
            }
        }
    }
}

@Observable
@MainActor
final class ReviewModel {
    var fields: [ReviewableField] = []
    var personLabels: [PersonID: String] = [:]

    struct PersonGroup { let person: String; let fields: [ReviewableField] }

    var groupedByPerson: [PersonGroup] {
        Dictionary(grouping: fields, by: \.subjectPersonID)
            .map {
                PersonGroup(
                    person: personLabels[$0.key] ?? "Person",
                    fields: $0.value
                )
            }
            .sorted { $0.person < $1.person }
    }

    func load(api: any ApertureAPIClient, caseID: CaseID) async {
        async let fieldsRequest = api.reviewableFields(caseID: caseID)
        async let foldersRequest = api.folders()
        fields = (try? await fieldsRequest) ?? []
        let people = ((try? await foldersRequest) ?? []).flatMap(\.persons)
        personLabels = people.reduce(into: [:]) { labels, person in
            labels[person.id] = person.displayLabel
        }
    }
}

struct FieldRow: View {
    let field: ReviewableField

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Aperture.Spacing.xs) {
                BilingualLabel(
                    primary: field.localizedLabel,
                    english: field.englishFormLabel,
                    formReference: field.formReference
                )
                Text(field.displayValue ?? "—")
                    .font(Aperture.Typography.value)
                if field.isBlocked {
                    Label(ApertureString("discrepancy.title"), systemImage: "exclamationmark.triangle")
                        .font(Aperture.Typography.caption)
                        .foregroundStyle(Aperture.Palette.critical)
                }
            }
            Spacer()
            ConfidenceChip(field.band)
        }
        .padding(.vertical, Aperture.Spacing.xs)
        .contentShape(Rectangle())
    }
}

/// Shows the value beside the source region it was read from. This is what makes
/// confirmation a genuine check: the human sees the pixels, not just an assertion.
struct FieldDetailSheet: View {
    let caseID: CaseID
    let field: ReviewableField
    let onConfirmed: () -> Void

    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var editedValue: String
    @State private var history: [ValueHistoryEntry] = []

    init(caseID: CaseID, field: ReviewableField, onConfirmed: @escaping () -> Void) {
        self.caseID = caseID
        self.field = field
        self.onConfirmed = onConfirmed
        _editedValue = State(initialValue: field.displayValue ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Aperture.Spacing.l) {
                    BilingualLabel(primary: field.localizedLabel,
                                   english: field.englishFormLabel,
                                   formReference: field.formReference)

                    TextField("Value", text: $editedValue)
                        .textFieldStyle(.roundedBorder)
                        .font(Aperture.Typography.value)

                    ConfidenceChip(field.band)

                    if !field.extractionReviewReasons.isEmpty {
                        ExtractionSafetyPanel(reasons: field.extractionReviewReasons)
                    }

                    if let extractedName = field.extractedName {
                        ExtractedNamePanel(name: extractedName)
                    }

                    if let discrepancy = field.confirmed?.discrepancy {
                        DiscrepancyPanel(discrepancy: discrepancy) { chosen in
                            editedValue = chosen
                        }
                    }

                    if let provenance = field.provenance {
                        ProvenanceView(provenance: provenance, formReference: field.formReference)
                            .apertureCard()
                    }

                    if !history.isEmpty {
                        ValueHistoryPanel(entries: history)
                    }
                }
                .padding(Aperture.Spacing.l)
            }
            .navigationTitle("Check this")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                history = (try? await session.api.valueHistory(
                    caseID: caseID,
                    personID: field.subjectPersonID,
                    canonicalPath: field.canonicalPath
                )) ?? []
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ApertureString("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(ApertureString("provenance.confirm")) {
                        Task {
                            _ = try? await session.api.confirmValues(
                                caseID: caseID,
                                confirmations: [ValueConfirmation(
                                    personID: field.subjectPersonID,
                                    canonicalPath: field.canonicalPath,
                                    value: editedValue,
                                    resolvesDiscrepancyID: field.confirmed?.discrepancy?.id
                                )],
                                idempotencyKey: IdempotencyKey.make()
                            )
                            session.dataDidChange()
                            onConfirmed()
                            dismiss()
                        }
                    }
                    .disabled(editedValue.isEmpty)
                }
            }
        }
    }
}

private struct ValueHistoryPanel: View {
    let entries: [ValueHistoryEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: Aperture.Spacing.m) {
            Text(aperture: "valueHistory.title")
                .font(Aperture.Typography.sectionTitle)

            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: Aperture.Spacing.xs) {
                    Text(ApertureString(String.LocalizationValue(actionKey(entry.action))))
                        .font(Aperture.Typography.body.weight(.semibold))
                    if let value = entry.value {
                        Text(value).font(Aperture.Typography.value)
                    }
                    if let previous = entry.previousValue {
                        Text(ApertureFormat("valueHistory.previous", previous))
                            .font(Aperture.Typography.caption)
                            .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                    }
                    Text(entry.recordedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(Aperture.Typography.caption)
                        .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("value-history-\(entry.action.rawValue)")

                if entry.id != entries.last?.id { Divider() }
            }
        }
        .apertureCard()
        .accessibilityIdentifier("value-history-ledger")
    }

    private func actionKey(_ action: ValueHistoryEntry.Action) -> String {
        switch action {
        case .proposalRecorded: "valueHistory.proposalRecorded"
        case .proposalSuperseded: "valueHistory.proposalSuperseded"
        case .humanConfirmed: "valueHistory.humanConfirmed"
        case .humanCorrected: "valueHistory.humanCorrected"
        case .discrepancyResolved: "valueHistory.discrepancyResolved"
        }
    }
}

private struct ExtractionSafetyPanel: View {
    let reasons: [ExtractionReviewReason]

    var body: some View {
        VStack(alignment: .leading, spacing: Aperture.Spacing.s) {
            Label("Please check carefully", systemImage: "exclamationmark.triangle")
                .font(Aperture.Typography.sectionTitle)
                .foregroundStyle(Aperture.Palette.critical)
            ForEach(reasons, id: \.self) { reason in
                Text(ApertureString(String.LocalizationValue(reason.localizationKey)))
                    .font(Aperture.Typography.body)
                    .accessibilityIdentifier("extraction-review-\(reason.rawValue)")
            }
        }
        .apertureCard()
    }
}

private struct ExtractedNamePanel: View {
    let name: ExtractedName

    var body: some View {
        VStack(alignment: .leading, spacing: Aperture.Spacing.s) {
            Text("Name as written")
                .font(Aperture.Typography.sectionTitle)
            Text(name.original)
                .font(Aperture.Typography.value)
            LabeledContent("Script", value: name.script)
            if let transliteration = name.transliteration {
                LabeledContent("Transliteration", value: transliteration)
            }
            Text("We keep the original writing and do not split or reorder this name automatically.")
                .font(Aperture.Typography.caption)
                .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
        }
        .apertureCard()
        .accessibilityIdentifier("extracted-name-original-script")
    }
}

/// Presents both values with their sources and stops. The system never arbitrates —
/// picking a winner silently is how a wrong date reaches an adjudicator (AP-7).
struct DiscrepancyPanel: View {
    let discrepancy: Discrepancy
    let onChoose: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Aperture.Spacing.m) {
            Label(ApertureString("discrepancy.title"), systemImage: "exclamationmark.triangle")
                .font(Aperture.Typography.sectionTitle)
                .foregroundStyle(Aperture.Palette.critical)

            Text(discrepancy.description).font(Aperture.Typography.body)
            Text(aperture: "discrepancy.chooseCorrect").font(Aperture.Typography.caption)

            if let alternative = discrepancy.alternativeValue,
               let anchor = discrepancy.alternativeAnchor {
                Button {
                    onChoose(alternative)
                } label: {
                    VStack(alignment: .leading, spacing: Aperture.Spacing.xs) {
                        Text(alternative).font(Aperture.Typography.value)
                        Text(anchor.documentName)
                            .font(Aperture.Typography.caption)
                            .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }
        }
        .apertureCard()
    }
}
