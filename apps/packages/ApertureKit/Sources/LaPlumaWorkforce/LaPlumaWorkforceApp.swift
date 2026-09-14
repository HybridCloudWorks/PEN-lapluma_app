import SwiftUI
import ApertureAPI
import ApertureDomain
import ApertureUI

@main
struct LaPlumaWorkforceApp: App {
    private let api = StubAPIClient()
    var body: some Scene {
        WindowGroup { WorkforceWorkbench(api: api) }
            .defaultSize(width: 1280, height: 800)
    }
}

private struct WorkforceWorkbench: View {
    let api: any ApertureAPIClient
    @State private var clients: [ClientDirectoryEntry] = []
    @State private var queue: [ReviewQueueItem] = []
    @State private var selectedClient: ClientDirectoryEntry?
    @State private var selectedCase: CaseWorkspace?
    @State private var search = ""

    var body: some View {
        ApertureCanvas {
            NavigationSplitView {
                List(selection: $selectedClient) {
                    Section("Clients") {
                        ForEach(clients) { client in
                            VStack(alignment: .leading, spacing: Aperture.Spacing.xs) {
                                Text(client.displayLabel)
                                    .font(Aperture.Typography.value)
                                if let activeCase = client.primaryCase {
                                    HStack(spacing: Aperture.Spacing.s) {
                                        Text(activeCase.packageTitle)
                                            .font(Aperture.Typography.caption)
                                            .foregroundStyle(Aperture.Palette.inkSecondary)
                                        Spacer()
                                        stagePill(state: activeCase.state)
                                    }
                                }
                            }
                            .padding(.vertical, Aperture.Spacing.xs)
                            .tag(client)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    Section("Assigned review queue") {
                        ForEach(queue) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: Aperture.Spacing.xs) {
                                    Text(item.clientLabel)
                                        .font(Aperture.Typography.value)
                                    Text(item.caseSummary.packageTitle)
                                        .font(Aperture.Typography.caption)
                                        .foregroundStyle(Aperture.Palette.inkSecondary)
                                }
                                Spacer()
                                stagePill(state: item.caseSummary.state)
                            }
                            .padding(.vertical, Aperture.Spacing.xs)
                            .tag(clients.first(where: { $0.id == item.caseSummary.folderID }))
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .searchable(text: $search)
                .navigationTitle("LaPluma Workforce")
                .onChange(of: selectedClient) { _, client in Task { await loadCase(client) } }
                .onSubmit(of: .search) { Task { await loadDirectory() } }
            } content: {
                if let client = selectedClient {
                    List {
                        Section("Current client") {
                            LabeledContent("Client", value: client.displayLabel)
                            LabeledContent("People", value: "\(client.personCount)")
                            LabeledContent("Documents", value: "\(client.documentCount)")
                        }
                        if let summary = client.primaryCase {
                            Section("Cases") {
                                Button {
                                    Task { selectedCase = try? await api.caseWorkspace(caseID: summary.id) }
                                } label: {
                                    HStack {
                                        Text(summary.packageTitle)
                                            .font(Aperture.Typography.value)
                                        Spacer()
                                        stagePill(state: summary.state)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .navigationTitle("Client Workspace")
                } else {
                    ContentUnavailableView("Select a client", systemImage: "person.2")
                }
            } detail: {
                if let workspace = selectedCase {
                    List {
                        Section("Case workbench") {
                            HStack {
                                Text("Stage")
                                    .font(Aperture.Typography.body)
                                Spacer()
                                stagePill(state: workspace.summary.state)
                            }
                            LabeledContent("Form package", value: workspace.summary.packageTitle)
                        }
                        Section("Work areas") {
                            Label("Overview", systemImage: "rectangle.grid.1x2")
                            Label("Evidence", systemImage: "doc.text.magnifyingglass")
                            Label("Data Entry", systemImage: "square.and.pencil")
                            Label("Review", systemImage: "checklist")
                            Label("Form Preview", systemImage: "doc.richtext")
                            Label("History", systemImage: "clock.arrow.circlepath")
                            Label("Package", systemImage: "shippingbox")
                        }
                        Section("Separation of duties") {
                            LabeledContent("Preparer", value: workspace.assignments.preparerID?.rawValue ?? "Unassigned")
                            LabeledContent("Reviewer", value: workspace.assignments.reviewerID?.rawValue ?? "Unassigned")
                            LabeledContent("Approver", value: workspace.assignments.approverID?.rawValue ?? "Unassigned")
                        }
                    }
                    .navigationTitle(workspace.summary.packageTitle)
                } else {
                    ContentUnavailableView("Select a case", systemImage: "folder")
                }
            }
        }
        .task { await loadDirectory(); queue = (try? await api.reviewQueue()) ?? [] }
    }

    private func stagePill(state: CaseState) -> some View {
        HStack(spacing: Aperture.Spacing.xs) {
            Image(systemName: iconName(for: state))
                .imageScale(.small)
            Text(ApertureString(String.LocalizationValue(state.localizationKey)))
                .font(Aperture.Typography.caption.weight(.medium))
        }
        .aperturePastelPill(tone: tone(for: state), horizontalPadding: Aperture.Spacing.s, verticalPadding: Aperture.Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(ApertureString(String.LocalizationValue(state.localizationKey)))
    }

    private func iconName(for state: CaseState) -> String {
        switch state {
        case .approved, .generated: "doc.badge.checkmark"
        case .delivered: "paperplane.fill"
        case .closed: "archivebox.fill"
        case .validating: "checklist"
        case .inReview: "person.crop.circle.badge.clock"
        case .readyForApproval: "signature"
        case .draft, .collecting: "tray.full"
        case .interviewing: "bubble.left.and.bubble.right.fill"
        case .changesRequested: "exclamationmark.triangle.fill"
        case .quarantinedFormDrift: "arrow.triangle.2.circlepath.circle.fill"
        case .onHold: "pause.circle.fill"
        case .abandoned: "stop.circle.fill"
        }
    }

    private func tone(for state: CaseState) -> Aperture.StatusTone {
        switch state {
        case .approved, .generated, .delivered, .closed: .positive
        case .validating, .inReview, .readyForApproval: .attention
        case .draft, .collecting, .interviewing: .information
        case .changesRequested, .quarantinedFormDrift, .onHold, .abandoned: .critical
        }
    }

    private func loadDirectory() async {
        clients = (try? await api.clientDirectory(query: search.isEmpty ? nil : search, cursor: nil).items) ?? []
        if selectedClient == nil { selectedClient = clients.first }
    }

    private func loadCase(_ client: ClientDirectoryEntry?) async {
        guard let caseID = client?.primaryCase?.id else { selectedCase = nil; return }
        selectedCase = try? await api.caseWorkspace(caseID: caseID)
    }
}
