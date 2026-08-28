import SwiftUI
import ApertureAPI
import ApertureDomain
import ApertureUI

/// The authenticated workspace entry point. A "client" is currently backed by the
/// existing `Folder` aggregate so selecting a row enters the established people,
/// documents, cases, and access-control screens without duplicating case data.
struct ClientDashboardView: View {
    @Environment(AppSession.self) private var session
    @State private var model = ClientDashboardModel()
    @State private var query = ""
    @State private var sort = ClientSort.attention
    @State private var filter = ClientFilter.all
    @State private var showsCreateFolder = false
    @State private var showsPlainCreateFolder = false

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .loading:
                    ApertureLoadingView()
                case .failed:
                    ApertureMessageView(
                        .offline,
                        action: (LaPlumaString("Try again"), { Task { await load() } })
                    )
                case .loaded:
                    content
                }
            }
            .navigationTitle("Clients")
            .searchable(text: $query, prompt: "Search clients, people, or forms")
            .toolbar { dashboardToolbar }
            .task(id: session.dataRevision) { await load() }
            .refreshable { await load() }
            .sheet(isPresented: $showsCreateFolder) {
                ClientWizardView {
                    session.dataDidChange()
                    showsCreateFolder = false
                }
            }
            .sheet(isPresented: $showsPlainCreateFolder) {
                CreateFolderView {
                    session.dataDidChange()
                    showsPlainCreateFolder = false
                }
            }
        }
    }

    private var content: some View {
        ApertureCanvas {
            List {
                Section {
                    workspaceSummary
                        .listRowBackground(Color.clear)
                }

                Section("Client actions") {
                    NavigationLink { CatalogView(folderID: model.folders.first?.id) } label: {
                        Label("Start a new application", systemImage: "plus.circle.fill")
                            .font(Aperture.Typography.value)
                            .apertureMinimumTouchTarget(expandHorizontally: true)
                    }

                    Button { showsCreateFolder = true } label: {
                        Label("New client", systemImage: "folder.badge.plus")
                            .font(Aperture.Typography.value)
                            .apertureMinimumTouchTarget(expandHorizontally: true)
                    }

                    // The plain folder flow stays available beside the client wizard:
                    // this dashboard fronts the same Folder aggregate the applicant
                    // Home uses, and a folder made here must behave identically.
                    Button { showsPlainCreateFolder = true } label: {
                        Label("Create another folder", systemImage: "folder.badge.plus")
                            .font(Aperture.Typography.value)
                            .apertureMinimumTouchTarget(expandHorizontally: true)
                    }
                }

                if visibleFolders.isEmpty {
                    ContentUnavailableView(
                        query.isEmpty ? "No clients match this filter" : "No clients found",
                        systemImage: "person.crop.circle.badge.questionmark",
                        description: Text(query.isEmpty
                            ? "Change the stage or attention filter to see other records."
                            : "Try a name, person label, or form title.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    Section("Current clients") {
                        ForEach(visibleFolders) { folder in
                            NavigationLink { FolderView(folderID: folder.id) } label: {
                                ClientRecordRow(folder: folder)
                            }
                        }
                    }
                }

                Section {
                    ReadinessCaveat()
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var workspaceSummary: some View {
        HStack(spacing: Aperture.Spacing.m) {
            Image(systemName: "building.2.crop.circle")
                .font(.title2)
                .foregroundStyle(Aperture.Palette.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Aperture.Spacing.xs) {
                Text("Workspace")
                    .font(Aperture.Typography.caption)
                    .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                Text(session.currentWorkspaceCode ?? LaPlumaString("Workspace unavailable"))
                    .font(Aperture.Typography.value)
            }
            Spacer()
            Text(LaPlumaFormat("clients.visibleCount", visibleFolders.count, model.folders.count))
                .font(Aperture.Typography.caption)
                .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
        }
        .apertureGlassCard()
        .accessibilityElement(children: .combine)
    }

    @ToolbarContentBuilder
    private var dashboardToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { showsCreateFolder = true } label: { Image(systemName: "plus") }
                .accessibilityLabel("New client")
            Menu {
                Picker("Filter", selection: $filter) {
                    Text("All clients").tag(ClientFilter.all)
                    Text("Needs attention").tag(ClientFilter.needsAttention)
                    Text("Ready to file").tag(ClientFilter.readyToFile)
                    Divider()
                    ForEach(CaseState.allCases, id: \.self) { state in
                        Text(ApertureString(String.LocalizationValue(state.localizationKey)))
                            .tag(ClientFilter.stage(state))
                    }
                }
            } label: {
                Image(systemName: filter == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
            }
            .accessibilityLabel("Filter clients")

            Menu {
                Picker("Sort", selection: $sort) {
                    ForEach(ClientSort.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .accessibilityLabel("Sort clients")
        }
    }

    private var visibleFolders: [Folder] {
        model.folders
            .filter(matchesQuery)
            .filter(filter.includes)
            .sorted(by: sort.areInIncreasingOrder)
    }

    private func matchesQuery(_ folder: Folder) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let searchable = [folder.name]
            + folder.persons.map(\.displayLabel)
            + folder.cases.flatMap { [$0.packageCode, $0.packageTitle] }
        return searchable.contains { $0.localizedCaseInsensitiveContains(trimmed) }
    }

    @MainActor
    private func load() async {
        await model.load(api: session.api)
    }
}

private struct ClientRecordRow: View {
    let folder: Folder

    private var primaryCase: CaseSummary? { folder.cases.first }

    var body: some View {
        VStack(alignment: .leading, spacing: Aperture.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(folder.name)
                    .font(Aperture.Typography.value)
                Spacer(minLength: Aperture.Spacing.s)
                stage
            }

            Text(LaPlumaFormat("clients.folderSummary", folder.persons.count, folder.documentCount))
                .font(Aperture.Typography.caption)
                .foregroundStyle(Aperture.Palette.onSurfaceSecondary)

            if let summary = primaryCase {
                Text(summary.packageTitle)
                    .font(Aperture.Typography.caption)
                    .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                    .lineLimit(2)
                ProgressCountersView(summary.counters, showsCaveat: false)
            } else {
                Label("Intake not started", systemImage: "tray")
                    .font(Aperture.Typography.caption)
                    .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
            }
        }
        .padding(.vertical, Aperture.Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var stage: some View {
        if let state = primaryCase?.state {
            Text(ApertureString(String.LocalizationValue(state.localizationKey)))
                .font(Aperture.Typography.caption.weight(.semibold))
                .foregroundStyle(state.isBlockedPendingHuman ? Aperture.Palette.warning : Aperture.Palette.accent)
                .padding(.horizontal, Aperture.Spacing.s)
                .padding(.vertical, Aperture.Spacing.xs)
                .background(Aperture.Palette.surfaceSecondary, in: Capsule())
        } else {
            Text("Intake")
                .font(Aperture.Typography.caption.weight(.semibold))
                .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
        }
    }
}

private enum ClientFilter: Hashable {
    case all
    case needsAttention
    case readyToFile
    case stage(CaseState)

    func includes(_ folder: Folder) -> Bool {
        switch self {
        case .all:
            true
        case .needsAttention:
            folder.cases.contains { $0.counters.blockingItems > 0 || $0.state.isBlockedPendingHuman }
        case .readyToFile:
            folder.cases.contains { $0.counters.isReadyToFile }
        case .stage(let state):
            folder.cases.contains { $0.state == state }
        }
    }
}

private enum ClientSort: String, CaseIterable, Identifiable {
    case attention
    case name
    case stage
    case workRemaining

    var id: String { rawValue }

    var title: String {
        switch self {
        case .attention: LaPlumaString("Needs attention first")
        case .name: LaPlumaString("Client name")
        case .stage: LaPlumaString("Case stage")
        case .workRemaining: LaPlumaString("Least work remaining")
        }
    }

    func areInIncreasingOrder(_ lhs: Folder, _ rhs: Folder) -> Bool {
        switch self {
        case .attention:
            let left = lhs.cases.reduce(0) { $0 + $1.counters.blockingItems }
            let right = rhs.cases.reduce(0) { $0 + $1.counters.blockingItems }
            return left == right ? lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending : left > right
        case .name:
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        case .stage:
            let left = lhs.cases.first?.state.rawValue ?? ""
            let right = rhs.cases.first?.state.rawValue ?? ""
            return left == right ? lhs.name < rhs.name : left < right
        case .workRemaining:
            let left = remainingUnits(in: lhs)
            let right = remainingUnits(in: rhs)
            return left == right ? lhs.name < rhs.name : left < right
        }
    }

    private func remainingUnits(in folder: Folder) -> Int {
        folder.cases.reduce(0) { result, summary in
            result
                + max(0, summary.counters.fieldsRequired - summary.counters.fieldsFilled)
                + max(0, summary.counters.documentsRequired - summary.counters.documentsCollected)
                + summary.counters.blockingItems
        }
    }
}

