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
        NavigationSplitView {
            List(selection: $selectedClient) {
                Section("Clients") {
                    ForEach(clients) { client in
                        VStack(alignment: .leading) {
                            Text(client.displayLabel)
                            if let activeCase = client.primaryCase {
                                Text(activeCase.packageTitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }.tag(client)
                    }
                }
                Section("Assigned review queue") {
                    ForEach(queue) { item in
                        Text(item.clientLabel).tag(clients.first(where: { $0.id == item.caseSummary.folderID }))
                    }
                }
            }
            .searchable(text: $search)
            .navigationTitle("LaPluma")
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
                            Button(summary.packageTitle) { Task { selectedCase = try? await api.caseWorkspace(caseID: summary.id) } }
                            Text(ApertureString(String.LocalizationValue(summary.state.localizationKey))).foregroundStyle(.secondary)
                        }
                    }
                }.navigationTitle("Client Workspace")
            } else { ContentUnavailableView("Select a client", systemImage: "person.2") }
        } detail: {
            if let workspace = selectedCase {
                List {
                    Section("Case workbench") {
                        LabeledContent("Stage", value: ApertureString(String.LocalizationValue(workspace.summary.state.localizationKey)))
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
                }.navigationTitle(workspace.summary.packageTitle)
            } else { ContentUnavailableView("Select a case", systemImage: "folder") }
        }
        .task { await loadDirectory(); queue = (try? await api.reviewQueue()) ?? [] }
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
