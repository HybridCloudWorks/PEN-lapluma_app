import SwiftUI
import ApertureUI
import ApertureAPI
import ApertureDomain

/// S-11. The applicant's to-do list, and the screen most responsible for completion.
///
/// Required and "also worth having" are separated because only agency-required items
/// may be marked blocking. Nothing here characterises evidence as sufficient,
/// persuasive or likely to succeed — items are *required by the instructions* or
/// *listed in the instructions*, never *strong* or *weak* (prohibited speech act #7).
struct MissingItemsEntryView: View {
    @Environment(AppSession.self) private var session
    @State private var caseID: CaseID?

    var body: some View {
        NavigationStack {
            if let caseID {
                MissingItemsView(caseID: caseID)
            } else {
                ApertureLoadingView()
                    .task {
                        caseID = (try? await session.api.folders())?.first?.cases.first?.id
                    }
            }
        }
    }
}

struct MissingItemsView: View {
    let caseID: CaseID
    @Environment(AppSession.self) private var session
    @State private var model = MissingItemsModel()

    var body: some View {
        List {
            ForEach(model.batches) { batch in
                Section {
                    BatchCard(batch: batch, caseID: caseID)
                }
            }

            if !model.required.isEmpty {
                Section(ApertureString("missing.required")) {
                    ForEach(model.required) { item in
                        MissingItemRow(item: item)
                    }
                }
            }

            if !model.advisory.isEmpty {
                Section(ApertureString("missing.alsoWorthHaving")) {
                    ForEach(model.advisory) { item in
                        MissingItemRow(item: item)
                    }
                }
            }

            if model.required.isEmpty && model.advisory.isEmpty && model.hasLoaded {
                // Never "You're done!" — no celebration, because completion of paperwork
                // is not an achievement we are in a position to congratulate.
                Text(aperture: "progress.nothingNeedsYou")
                    .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
            }

            Section {
                DisclosureFooter().listRowBackground(Color.clear)
            }
        }
        .navigationTitle("What's missing")
        .task { await model.load(api: session.api, caseID: caseID) }
        .refreshable { await model.load(api: session.api, caseID: caseID) }
    }
}

@Observable
@MainActor
final class MissingItemsModel {
    var required: [MissingItem] = []
    var advisory: [MissingItem] = []
    var batches: [MissingItemBatch] = []
    var hasLoaded = false

    func load(api: any ApertureAPIClient, caseID: CaseID) async {
        guard let result = try? await api.missingItems(caseID: caseID) else { return }
        required = result.items.filter { $0.severity == .blocking }
        advisory = result.items.filter { $0.severity == .advisory }
        batches = result.batches
        hasLoaded = true
    }
}

/// Batches are sized for a single sitting: roughly eight chat questions, or five
/// minutes of voice. An open-ended interview is how the voice budget evaporates.
struct BatchCard: View {
    let batch: MissingItemBatch
    let caseID: CaseID

    var body: some View {
        VStack(alignment: .leading, spacing: Aperture.Spacing.m) {
            Text("\(batch.itemCount) quick questions — about \(batch.estimatedMinutes) minutes")
                .font(Aperture.Typography.value)

            Text(aperture: "interview.chooseHow")
                .font(Aperture.Typography.caption)
                .foregroundStyle(Aperture.Palette.onSurfaceSecondary)

            HStack(spacing: Aperture.Spacing.s) {
                ForEach(batch.supportedModalities, id: \.self) { modality in
                    NavigationLink {
                        destination(for: modality)
                    } label: {
                        Label(title(for: modality), systemImage: icon(for: modality))
                            .frame(minHeight: Aperture.Spacing.minimumTarget)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.vertical, Aperture.Spacing.xs)
    }

    @ViewBuilder
    private func destination(for modality: InterviewModality) -> some View {
        switch modality {
        case .chat: ChatInterviewView(caseID: caseID, batchID: batch.id)
        case .voice: VoiceConsentView(caseID: caseID, batchID: batch.id)
        case .form: StructuredQuestionsView(caseID: caseID, batchID: batch.id)
        }
    }

    private func title(for modality: InterviewModality) -> String {
        switch modality {
        case .chat: "Chat"
        case .voice: "Speak"
        case .form: "Type it in"
        }
    }

    private func icon(for modality: InterviewModality) -> String {
        switch modality {
        case .chat: "bubble.left.and.bubble.right"
        case .voice: "waveform"
        case .form: "keyboard"
        }
    }
}

struct MissingItemRow: View {
    let item: MissingItem
    @State private var showsWhy = false

    var body: some View {
        VStack(alignment: .leading, spacing: Aperture.Spacing.s) {
            Text(item.title).font(Aperture.Typography.value)

            Text(item.assignedPersonLabel)
                .font(Aperture.Typography.caption)
                .foregroundStyle(Aperture.Palette.onSurfaceSecondary)

            Text(item.whyRequired).font(Aperture.Typography.caption)

            if let citation = item.citation {
                DisclosureGroup(ApertureString("missing.why"), isExpanded: $showsWhy) {
                    CitationView(citation)
                }
                .font(Aperture.Typography.caption)
            }

            HStack {
                ForEach(item.resolutionPaths) { path in
                    Button(path.label) {}
                        .buttonStyle(.bordered)
                        .font(Aperture.Typography.caption)
                }
            }
        }
        .padding(.vertical, Aperture.Spacing.xs)
    }
}
