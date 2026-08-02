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
                Section {
                    ForEach(model.required) { item in
                        MissingItemRow(item: item, caseID: caseID)
                    }
                } header: {
                    sectionHeader(
                        ApertureString("missing.required"),
                        systemImage: "exclamationmark.circle.fill",
                        tone: .critical
                    )
                }
            }

            if !model.advisory.isEmpty {
                Section {
                    ForEach(model.advisory) { item in
                        MissingItemRow(item: item, caseID: caseID)
                    }
                } header: {
                    sectionHeader(
                        ApertureString("missing.alsoWorthHaving"),
                        systemImage: "info.circle.fill",
                        tone: .information
                    )
                }
            }

            if model.required.isEmpty && model.advisory.isEmpty && model.hasLoaded {
                // Never "You're done!" — no celebration, because completion of paperwork
                // is not an achievement we are in a position to congratulate.
                Label {
                    Text(aperture: "progress.nothingNeedsYou")
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .apertureStatusSurface(.positive)
            }

            Section {
                DisclosureFooter().listRowBackground(Color.clear)
            }
        }
        .apertureReadableContentWidth()
        .navigationTitle("What's missing")
        .scrollContentBackground(.hidden)
        .background {
            ApertureCanvas { Color.clear }
        }
        .task { await model.load(api: session.api, caseID: caseID) }
        .refreshable { await model.load(api: session.api, caseID: caseID) }
    }

    private func sectionHeader(
        _ title: String,
        systemImage: String,
        tone: Aperture.StatusTone
    ) -> some View {
        Label(title, systemImage: systemImage)
            .font(Aperture.Typography.sectionTitle)
            .foregroundStyle(tone.foreground)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
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
    @Environment(AppSession.self) private var appSession
    @Environment(\.apertureAccessibilityProfileEnabled) private var profileEnabled
    @State private var selectedModality: InterviewModality?

    var body: some View {
        VStack(alignment: .leading, spacing: Aperture.Spacing.m) {
            Text("\(batch.itemCount) quick questions — about \(batch.estimatedMinutes) minutes")
                .font(Aperture.Typography.value)

            Label {
                Text(aperture: "interview.chooseHow")
            } icon: {
                Image(systemName: "questionmark.bubble.fill")
            }
            .font(Aperture.Typography.caption.weight(.semibold))
            .apertureStatusSurface(.information)

            if !appSession.connectivity.isOnline {
                Label("AI needs a connection. You can still use Type it in and save your answers.",
                      systemImage: "wifi.slash")
                    .font(Aperture.Typography.caption)
                    .apertureStatusSurface(.attention)
                    .accessibilityIdentifier("offline-interview-status")
            }

            if profileEnabled {
                VStack(spacing: Aperture.Spacing.s) {
                    ForEach(presentedModalities, id: \.self) { modality in
                        modalityButton(modality, tile: false)
                    }
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: Aperture.Spacing.s) {
                        ForEach(presentedModalities, id: \.self) { modality in
                            modalityButton(modality, tile: true)
                        }
                    }
                    VStack(spacing: Aperture.Spacing.s) {
                        ForEach(presentedModalities, id: \.self) { modality in
                            modalityButton(modality, tile: false)
                        }
                    }
                }
            }
        }
        .padding(.vertical, Aperture.Spacing.xs)
        .apertureGlassCard()
        .navigationDestination(item: $selectedModality) { modality in
            destination(for: modality)
        }
    }

    private var presentedModalities: [InterviewModality] {
        guard profileEnabled, batch.supportedModalities.contains(.voice) else {
            return batch.supportedModalities
        }
        return [.voice] + batch.supportedModalities.filter { $0 != .voice }
    }

    private func modalityButton(
        _ modality: InterviewModality,
        tile: Bool
    ) -> some View {
        Button {
            selectedModality = modality
        } label: {
            if tile {
                VStack(spacing: Aperture.Spacing.s) {
                    Image(systemName: icon(for: modality))
                        .font(.title2)
                    Text(title(for: modality))
                        .font(Aperture.Typography.caption.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 76, alignment: .center)
                .contentShape(Rectangle())
            } else {
                Label(title(for: modality), systemImage: icon(for: modality))
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
        }
        .apertureGlassButton(prominent: isPreferred(modality))
        .controlSize(profileEnabled ? .large : .regular)
        .apertureMinimumTouchTarget(expandHorizontally: true)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("interview-modality-\(modality.rawValue.lowercased())")
        .disabled(!appSession.connectivity.isOnline && modality != .form)
    }

    @ViewBuilder
    private func destination(for modality: InterviewModality) -> some View {
        switch modality {
        case .chat: ChatInterviewView(caseID: caseID, batchID: batch.id)
        case .voice: VoiceConsentView(caseID: caseID, batchID: batch.id)
        case .form: StructuredQuestionsView(caseID: caseID, batchID: batch.id)
        }
    }

    private func title(for modality: InterviewModality) -> LocalizedStringKey {
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

    private func isPreferred(_ modality: InterviewModality) -> Bool {
        modality == (profileEnabled ? .voice : .chat)
    }
}

struct MissingItemRow: View {
    let item: MissingItem
    let caseID: CaseID
    @Environment(\.apertureAccessibilityProfileEnabled) private var profileEnabled
    @State private var showsWhy = false

    var body: some View {
        VStack(alignment: .leading, spacing: Aperture.Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: Aperture.Spacing.s) {
                Image(systemName: item.severity == .blocking
                      ? "exclamationmark.circle.fill"
                      : "info.circle.fill")
                    .foregroundStyle(item.severity == .blocking
                                     ? Aperture.Palette.critical
                                     : Aperture.Palette.information)
                    .accessibilityHidden(true)
                Text(item.title).font(Aperture.Typography.value)
            }

            Label(item.assignedPersonLabel, systemImage: "person.crop.circle")
                .font(Aperture.Typography.caption)
                .foregroundStyle(Aperture.Palette.onSurfaceSecondary)

            Text(item.whyRequired).font(Aperture.Typography.caption)

            if let citation = item.citation {
                Button {
                    showsWhy.toggle()
                } label: {
                    HStack {
                        Text(ApertureString("missing.why"))
                        Spacer()
                        Image(systemName: showsWhy ? "chevron.up" : "chevron.down")
                            .accessibilityHidden(true)
                    }
                    .frame(
                        minHeight: profileEnabled
                            ? Aperture.Spacing.accessibleTarget
                            : Aperture.Spacing.minimumTarget
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(showsWhy ? Text("Expanded") : Text("Collapsed"))
                .font(Aperture.Typography.caption)
                .apertureMinimumTouchTarget(expandHorizontally: true)

                if showsWhy {
                    CitationView(citation)
                }
            }

            VStack(alignment: .leading, spacing: Aperture.Spacing.s) {
                ForEach(item.resolutionPaths) { path in
                    NavigationLink {
                        destination(for: path)
                    } label: {
                        HStack {
                            Label(path.label, systemImage: icon(for: path.kind))
                            Spacer()
                        }
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )
                            .frame(
                                minWidth: Aperture.Spacing.minimumTarget,
                                minHeight: Aperture.Spacing.accessibleTarget
                            )
                            .contentShape(Rectangle())
                            .accessibilityElement(children: .combine)
                    }
                    .buttonStyle(.bordered)
                    .font(Aperture.Typography.caption)
                    .apertureMinimumTouchTarget(expandHorizontally: true)
                }
            }
        }
        .padding(.vertical, Aperture.Spacing.xs)
    }

    private func icon(for kind: ResolutionPath.Kind) -> String {
        switch kind {
        case .scan: "doc.viewfinder"
        case .importFile: "folder"
        case .answer: "bubble.left.and.bubble.right"
        case .type: "keyboard"
        case .cannotObtain: "questionmark.circle"
        }
    }

    @ViewBuilder private func destination(for path: ResolutionPath) -> some View {
        switch path.kind {
        case .scan, .importFile:
            CaptureEntryView()
        case .answer, .type:
            StructuredQuestionsView(
                caseID: caseID,
                batchID: item.batchID ?? BatchID("single_\(item.id.rawValue)")
            )
        case .cannotObtain:
            CannotObtainView(item: item)
        }
    }
}

struct CannotObtainView: View {
    let item: MissingItem

    var body: some View {
        List {
            Section {
                Text("A reviewer can help record why this item is unavailable and what the agency instructions permit next. Aperture will not invent a substitute or decide whether one is sufficient.")
            }
            if let citation = item.citation {
                Section("Agency source") { CitationView(citation) }
            }
            Section {
                NavigationLink {
                    LegalHelpDirectoryView()
                } label: {
                    Label(ApertureString("catalog.findLegalHelp"), systemImage: "person.2")
                }
            }
            Section { DisclosureFooter() }
        }
        .navigationTitle("I can't get this")
    }
}
