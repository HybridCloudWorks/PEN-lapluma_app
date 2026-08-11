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
            switch model.state {
            case .idle, .loading:
                ApertureLoadingView()
            case .empty:
                ApertureMessageView(.empty(messageKey: "review.empty"))
                    .accessibilityIdentifier("review-empty")
            case .failed:
                ApertureMessageView(
                    .failed(messageKey: "error.reviewLoadFailed"),
                    action: (ApertureString("common.retry"), {
                        Task { await model.load(api: session.api, caseID: caseID) }
                    })
                )
                .accessibilityIdentifier("review-load-failed")
            case .loaded:
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
            }

            Section {
                DisclosureFooter()
                    .listRowBackground(Color.clear)
            }
        }
        .apertureReadableContentWidth()
        .navigationTitle("Review information")
        .task(id: session.dataRevision) { await model.load(api: session.api, caseID: caseID) }
        .sheet(item: $selectedField) { field in
            FieldDetailSheet(caseID: caseID, field: field)
        }
    }
}

@Observable
@MainActor
final class ReviewModel {
    var state: ApertureLoadState<[ReviewableField]> = .idle
    var personLabels: [PersonID: String] = [:]

    private var fields: [ReviewableField] { state.value ?? [] }

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
        state = .loading
        do {
            async let fieldsRequest = api.reviewableFields(caseID: caseID)
            async let foldersRequest = api.folders()
            let (fields, folders) = try await (fieldsRequest, foldersRequest)
            let people = folders.flatMap(\.persons)
            personLabels = people.reduce(into: [:]) { labels, person in
                labels[person.id] = person.displayLabel
            }
            state = fields.isEmpty ? .empty : .loaded(fields)
        } catch is CancellationError {
            return
        } catch {
            personLabels = [:]
            state = .failed
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
            if let displayBand = field.displayBand { ConfidenceChip(displayBand) }
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

    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var editedValue: String
    @State private var history: [ValueHistoryEntry] = []
    @State private var isConfirming = false
    @State private var confirmationError: String?
    @State private var confirmationIdempotencyKey = IdempotencyKey.make()
    /// Set only when the applicant explicitly picks a side in `DiscrepancyPanel`.
    /// Confirming without adjudicating must leave the disagreement standing, so
    /// this is never derived from the field — deriving it is what let an ordinary
    /// Confirm tap clear a blocking discrepancy and open the generation gate.
    @State private var chosenDiscrepancyID: DiscrepancyID?

    init(caseID: CaseID, field: ReviewableField) {
        self.caseID = caseID
        self.field = field
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

                    if let displayBand = field.displayBand { ConfidenceChip(displayBand) }

                    if !field.extractionReviewReasons.isEmpty {
                        ExtractionSafetyPanel(reasons: field.extractionReviewReasons)
                    }

                    if let extractedName = field.extractedName {
                        ExtractedNamePanel(name: extractedName)
                    }

                    if let discrepancy = field.confirmed?.discrepancy {
                        DiscrepancyPanel(
                            discrepancy: discrepancy,
                            currentValue: field.confirmed?.value,
                            currentSourceName: field.confirmed?.provenance.documentName
                        ) { chosen in
                            editedValue = chosen
                            chosenDiscrepancyID = discrepancy.id
                        }
                    }

                    if let provenance = field.provenance {
                        ProvenanceView(provenance: provenance, formReference: field.formReference)
                            .apertureCard()
                    }

                    if !history.isEmpty {
                        ValueHistoryPanel(entries: history)
                    }

                    if let confirmationError {
                        Label(confirmationError, systemImage: "exclamationmark.octagon.fill")
                            .font(Aperture.Typography.caption)
                            .apertureStatusSurface(.critical)
                            .accessibilityIdentifier("confirmation-error")

                        Button(ApertureString("common.retry")) {
                            Task { await confirm() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isConfirming)
                        .accessibilityIdentifier("confirmation-retry")
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
            .onChange(of: editedValue) {
                confirmationIdempotencyKey = IdempotencyKey.make()
                confirmationError = nil
                // Hand-editing the field abandons the adjudication: the typed text
                // is no longer the side that was chosen, so the disagreement stands.
                if let discrepancy = field.confirmed?.discrepancy,
                   editedValue != field.confirmed?.value,
                   editedValue != discrepancy.alternativeValue {
                    chosenDiscrepancyID = nil
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ApertureString("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(ApertureString("provenance.confirm")) {
                        Task { await confirm() }
                    }
                    .disabled(editedValue.isEmpty || isConfirming)
                }
            }
        }
    }

    @MainActor
    private func confirm() async {
        guard !isConfirming else { return }
        isConfirming = true
        confirmationError = nil
        defer { isConfirming = false }

        do {
            _ = try await session.api.confirmValues(
                caseID: caseID,
                confirmations: [ValueConfirmation(
                    personID: field.subjectPersonID,
                    canonicalPath: field.canonicalPath,
                    value: editedValue,
                    resolvesDiscrepancyID: chosenDiscrepancyID
                )],
                idempotencyKey: confirmationIdempotencyKey
            )
            session.dataDidChange()
            dismiss()
        } catch {
            confirmationError = LaPlumaString("review.confirmationFailed")
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
                    Text(entry.recordedAt.formatted(
                        Date.FormatStyle(date: .abbreviated, time: .shortened)
                            .locale(AperturePreferredLocale())
                    ))
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
/// Adjudicating a disagreement is an explicit act, not a side effect of confirming.
///
/// Both candidates are offered as choices — the value already recorded and the one
/// the other document carries — because "Which one is right?" cannot be answered by
/// a panel that only lets the applicant pick one side. Until a choice is made the
/// discrepancy stays unresolved and package generation stays closed (SME B-02 /
/// AP-7); see `FieldDetailSheet.chosenDiscrepancyID`.
struct DiscrepancyPanel: View {
    let discrepancy: Discrepancy
    let currentValue: String?
    let currentSourceName: String?
    let onChoose: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Aperture.Spacing.m) {
            Label(ApertureString("discrepancy.title"), systemImage: "exclamationmark.triangle")
                .font(Aperture.Typography.sectionTitle)
                .foregroundStyle(Aperture.Palette.critical)

            Text(discrepancy.description).font(Aperture.Typography.body)
            Text(aperture: "discrepancy.chooseCorrect").font(Aperture.Typography.caption)

            if let currentValue {
                candidate(value: currentValue, sourceName: currentSourceName)
                    .accessibilityIdentifier("discrepancy-choice-current")
            }

            if let alternative = discrepancy.alternativeValue {
                candidate(value: alternative, sourceName: discrepancy.alternativeAnchor?.documentName)
                    .accessibilityIdentifier("discrepancy-choice-alternative")
            }
        }
        .apertureCard()
    }

    private func candidate(value: String, sourceName: String?) -> some View {
        Button {
            onChoose(value)
        } label: {
            VStack(alignment: .leading, spacing: Aperture.Spacing.xs) {
                Text(value).font(Aperture.Typography.value)
                if let sourceName {
                    Text(sourceName)
                        .font(Aperture.Typography.caption)
                        .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .apertureMinimumTouchTarget()
    }
}
