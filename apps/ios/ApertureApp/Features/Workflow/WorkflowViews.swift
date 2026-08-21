import SwiftUI
import ApertureAPI
import ApertureDomain
import ApertureUI

struct CaseWorkspaceView: View {
    let caseID: CaseID
    @Environment(AppSession.self) private var session
    @State private var workspace: CaseWorkspace?
    @State private var failed = false
    @State private var capabilities: Set<WorkflowCapability> = []

    var body: some View {
        List {
            if let workspace {
                Section {
                    VStack(alignment: .leading, spacing: Aperture.Spacing.s) {
                        Text(workspace.client.displayLabel).font(Aperture.Typography.caption)
                        Text(ApertureString(String.LocalizationValue(workspace.summary.state.localizationKey)))
                            .font(Aperture.Typography.value)
                        ProgressCountersView(workspace.summary.counters, showsCaveat: false)
                    }
                } header: { Text("Current client") }

                Section("Case workspace") {
                    NavigationLink("Overview") { CaseOverviewView(summary: workspace.summary) }
                    if capabilities.contains(.runGuidedFinish) {
                        NavigationLink("Guided Finish") { GuidedFinishSetupView(caseID: caseID) }
                    }
                    if capabilities.contains(.viewProofMap) {
                        NavigationLink("Proof Map") { ProofMapView(caseID: caseID) }
                    }
                    NavigationLink("Evidence") { EvidenceInboxView(workspace: workspace) }
                    NavigationLink("Data Entry") { FormSectionListView(caseID: caseID, sections: workspace.sections) }
                    NavigationLink("Review") { WorkforceReviewView(workspace: workspace) }
                    NavigationLink("Form Preview") { DraftPreviewView(caseID: caseID) }
                    NavigationLink("History") { CaseHistoryView(caseID: caseID) }
                    NavigationLink("Package") { PackageView(caseID: caseID) }
                }

                Section("Assignments") {
                    AssignmentRow(role: "Preparer", memberID: workspace.assignments.preparerID)
                    AssignmentRow(role: "Reviewer", memberID: workspace.assignments.reviewerID)
                    AssignmentRow(role: "Approver", memberID: workspace.assignments.approverID)
                }
            } else if failed {
                ApertureMessageView(.failed(messageKey: "error.generic"), action: (ApertureString("common.retry"), { Task { await load() } }))
            } else { ApertureLoadingView() }
        }
        .navigationTitle(workspace?.summary.packageTitle ?? LaPlumaString("Case workspace"))
        .task(id: session.dataRevision) { await load() }
    }

    private func load() async {
        do {
            async let workspaceRequest = session.api.caseWorkspace(caseID: caseID)
            async let contextRequest = session.api.authenticatedContext()
            let (loadedWorkspace, context) = try await (workspaceRequest, contextRequest)
            workspace = loadedWorkspace
            capabilities = context.capabilities
            failed = false
        }
        catch is CancellationError {} catch { failed = true }
    }
}

private struct AssignmentRow: View {
    let role: String
    let memberID: UserID?
    var body: some View { LabeledContent(role, value: memberID?.rawValue ?? LaPlumaString("Unassigned")) }
}

struct EvidenceInboxView: View {
    let workspace: CaseWorkspace
    @Environment(AppSession.self) private var session
    @State private var documents: [CaseDocument] = []
    @State private var evidence: [EvidenceRequirementItem]

    init(workspace: CaseWorkspace) {
        self.workspace = workspace
        _evidence = State(initialValue: workspace.evidence)
    }

    var body: some View {
        List(evidence) { requirement in
            Section {
                Text(requirement.title)
                LabeledContent("Person role", value: requirement.personRole)
                if requirement.linkedDocumentIDs.isEmpty { Text("No document linked").foregroundStyle(.secondary) }
                ForEach(requirement.linkedDocumentIDs, id: \.self) { id in
                    Label(documents.first(where: { $0.id == id })?.originalName ?? id.rawValue, systemImage: "link")
                }
                Menu("Link existing document") {
                    ForEach(documents) { document in
                        Button(document.originalName) { Task { await link(document, to: requirement) } }
                    }
                }
            } header: { Text(requirement.code) }
        }
        .navigationTitle("Evidence")
        .task { documents = (try? await session.api.documents(folderID: workspace.summary.folderID)) ?? [] }
    }

    private func link(_ document: CaseDocument, to requirement: EvidenceRequirementItem) async {
        guard let updated = try? await session.api.linkEvidence(caseID: workspace.summary.id, requirementCode: requirement.code, documentID: document.id, idempotencyKey: IdempotencyKey.make()), let index = evidence.firstIndex(where: { $0.code == updated.code }) else { return }
        evidence[index] = updated; session.dataDidChange()
    }
}

struct FormSectionListView: View {
    let caseID: CaseID
    let sections: [FormSection]
    var body: some View {
        List(sections) { section in
            NavigationLink { FormSectionEditor(caseID: caseID, section: section) } label: {
                VStack(alignment: .leading) {
                    Text(section.title).font(Aperture.Typography.value)
                    Text(LaPlumaFormat("workflow.sectionSummary", section.formNumber, section.fields.count)).font(Aperture.Typography.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Data Entry")
    }
}

struct FormSectionEditor: View {
    let caseID: CaseID
    let section: FormSection
    @Environment(AppSession.self) private var session
    @State private var values: [String: String]
    @State private var message: String?

    init(caseID: CaseID, section: FormSection) {
        self.caseID = caseID; self.section = section
        _values = State(initialValue: Dictionary(uniqueKeysWithValues: section.fields.map { ($0.path.rawValue, $0.value) }))
    }

    var body: some View {
        Form {
            Section("Local draft") {
                ForEach(section.fields) { field in
                    VStack(alignment: .leading, spacing: Aperture.Spacing.xs) {
                        TextField(field.label, text: Binding(get: { values[field.path.rawValue] ?? "" }, set: { values[field.path.rawValue] = $0 }))
                        ForEach(field.references, id: \.self) { reference in
                            Text(LaPlumaFormat("workflow.formReference", reference.formNumber, reference.page, reference.fieldName)).font(Aperture.Typography.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                Button("Commit confirmed values") { Task { await commit() } }.buttonStyle(.borderedProminent)
                if let message { Text(message).font(Aperture.Typography.caption) }
            } footer: { Text("Saving commits canonical case data. Every pinned form binding that uses a changed field receives the same authoritative value.") }
        }
        .navigationTitle(section.title)
    }

    private func commit() async {
        do {
            let result = try await session.api.commitSection(caseID: caseID, sectionID: section.id, baseRevision: section.revision, values: values, idempotencyKey: IdempotencyKey.make())
            message = result.invalidatedApproval ? LaPlumaString("Approval invalidated; review reopened") : result.reopenedReview ? LaPlumaString("Review reopened") : LaPlumaString("Values committed")
            session.dataDidChange()
        } catch { message = LaPlumaString("The section changed elsewhere. Reload before committing.") }
    }
}

struct ReviewerQueueView: View {
    @Environment(AppSession.self) private var session
    @State private var items: [ReviewQueueItem] = []
    var body: some View {
        NavigationStack {
            List(items) { item in
                NavigationLink { CaseWorkspaceView(caseID: item.id) } label: {
                    VStack(alignment: .leading, spacing: Aperture.Spacing.xs) {
                        Text(item.clientLabel).font(Aperture.Typography.value)
                        Text(item.caseSummary.packageTitle)
                        Text(LaPlumaFormat("workflow.queueSummary", item.ageDays, item.blockerCount)).font(Aperture.Typography.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .overlay { if items.isEmpty { ContentUnavailableView("No assigned reviews", systemImage: "checkmark.circle") } }
            .navigationTitle("Review Queue")
            .task(id: session.dataRevision) { items = (try? await session.api.reviewQueue()) ?? [] }
        }
    }
}

struct WorkforceReviewView: View {
    let workspace: CaseWorkspace
    @Environment(AppSession.self) private var session
    @State private var note = ""
    @State private var message: String?
    var body: some View {
        Form {
            Section("Source and value comparison") {
                NavigationLink("Review canonical values and sources") { ReviewView(caseID: workspace.summary.id) }
                TextField("Decision note", text: $note, axis: .vertical)
            }
            Section("Review decision") {
                if workspace.summary.state == .collecting {
                    Button("Finish collection and validate") { Task { await transition(.validating, message: "Case moved to validation") } }
                } else if workspace.summary.state == .validating {
                    Button("Submit for review") { Task { await transitionToReview() } }
                } else if workspace.summary.state == .inReview {
                    Button("Request changes") { Task { await decide(.changesRequested) } }
                    Button("Ready for approval") { Task { await decide(.readyForApproval) } }.buttonStyle(.borderedProminent)
                } else { Text(ApertureString(String.LocalizationValue(workspace.summary.state.localizationKey))) }
                if let message { Text(message) }
            }
        }
        .navigationTitle("Review")
    }
    private func transition(_ state: CaseState, message successMessage: String.LocalizationValue) async { if (try? await session.api.transition(caseID: workspace.summary.id, to: state, idempotencyKey: IdempotencyKey.make())) != nil { message = LaPlumaString(successMessage); session.dataDidChange() } }
    private func transitionToReview() async { if (try? await session.api.transition(caseID: workspace.summary.id, to: .inReview, idempotencyKey: IdempotencyKey.make())) != nil { message = LaPlumaString("Submitted for review"); session.dataDidChange() } }
    private func decide(_ outcome: ReviewOutcome) async { if (try? await session.api.recordReviewDecision(caseID: workspace.summary.id, outcome: outcome, note: note.isEmpty ? nil : note, idempotencyKey: IdempotencyKey.make())) != nil { message = LaPlumaString("Review decision recorded"); session.dataDidChange() } }
}

struct DraftPreviewView: View {
    let caseID: CaseID
    @Environment(AppSession.self) private var session
    @State private var preview: DraftFormPreview?
    @State private var attested = false
    @State private var message: String?
    var body: some View {
        List {
            if let preview {
                Section {
                    Text(preview.watermark).font(.title2.bold()).foregroundStyle(.red)
                    LabeledContent("Pages", value: "\(preview.pageCount)")
                    LabeledContent("Value set", value: preview.valueSetHash)
                    LabeledContent("Edition set", value: preview.editionSetHash)
                    Text("Read-only server preview. Export is disabled before approval.").font(Aperture.Typography.caption)
                }
                Section("Approval") {
                    Toggle("I reviewed the immutable value and edition sets", isOn: $attested)
                    Button("Step up and approve") { Task { await approve(preview) } }.disabled(!attested).buttonStyle(.borderedProminent)
                    if let message { Text(message) }
                }
            } else { ContentUnavailableView("Preview unavailable", systemImage: "doc.text.magnifyingglass", description: Text("Submit review before requesting the official-form draft preview.")) }
        }
        .navigationTitle("Form Preview")
        .task { preview = try? await session.api.draftPreview(caseID: caseID) }
    }
    private func approve(_ preview: DraftFormPreview) async { if (try? await session.api.approve(caseID: caseID, preview: preview, stepUpChallenge: UUID().uuidString, attested: attested, idempotencyKey: IdempotencyKey.make())) != nil { message = LaPlumaString("Approval recorded. Package generation is now eligible."); session.dataDidChange() } }
}

struct CaseHistoryView: View {
    let caseID: CaseID
    @Environment(AppSession.self) private var session
    @State private var events: [CaseHistoryEvent] = []
    var body: some View {
        List(events) { event in
            VStack(alignment: .leading) { Text(event.summary); Text("\(event.kind) · \(event.occurredAt.formatted())").font(Aperture.Typography.caption).foregroundStyle(.secondary) }
        }.overlay { if events.isEmpty { ContentUnavailableView("No case history yet", systemImage: "clock.arrow.circlepath") } }.navigationTitle("History").task { events = (try? await session.api.caseHistory(caseID: caseID)) ?? [] }
    }
}

struct AdministrationView: View {
    @Environment(AppSession.self) private var session
    @State private var members: [AdminMember] = []
    @State private var sessions: [ActiveWorkspaceSession] = []
    @State private var audit: AuditSummary?
    var body: some View {
        NavigationStack {
            List {
                Section("Workspace profile") { LabeledContent("Workspace", value: session.currentWorkspaceCode ?? "—") }
                Section("Members and roles") { ForEach(members) { member in LabeledContent(member.displayLabel, value: member.roles.map(\.rawValue).sorted().joined(separator: ", ")) } }
                Section("Active devices and sessions") { ForEach(sessions) { item in LabeledContent(item.deviceLabel, value: item.lastSeenAt.formatted()) } }
                if let audit { Section("Audit summary") { LabeledContent("Events", value: "\(audit.eventCount)"); LabeledContent("Security events", value: "\(audit.securityEventCount)") } }
                Section("Demo workspace") {
                    if session.isDemoWorkspace {
                        Button("Reset synthetic data", role: .destructive) { Task { try? await session.resetDemoWorkspace() } }
                        Button("Exit demo workspace") { session.exitDemoWorkspace() }
                    } else { Button("Enable isolated demo") { session.enterDemoWorkspace() } }
                    Text("Demo uses a separate synthetic tenant. Invitations and secure delivery are disabled.").font(Aperture.Typography.caption)
                }
            }
            .navigationTitle("Administration")
            .task(id: session.dataRevision) { async let m = session.api.adminMembers(); async let s = session.api.activeWorkspaceSessions(); async let a = session.api.auditSummary(); members = (try? await m) ?? []; sessions = (try? await s) ?? []; audit = try? await a }
        }
    }
}

struct ClientWizardView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var label = ""
    @State private var primaryPerson = ""
    @State private var inviteApplicant = false
    @State private var firstCase = false
    let onCreated: () -> Void
    var body: some View {
        NavigationStack {
            Form {
                if step == 0 { Section("Client") { TextField("Minimal client label", text: $label) } }
                else if step == 1 { Section("People and relationships") { TextField("Primary person label", text: $primaryPerson); Text("Relationships and person scopes are confirmed before access is granted.") } }
                else if step == 2 { Section("Scoped access and assignment") { LabeledContent("Preparer", value: "Demo Preparer"); Toggle("Send secure applicant invitation", isOn: $inviteApplicant).disabled(session.isDemoWorkspace) } }
                else { Section("First case") { Toggle("Create a first case after client setup", isOn: $firstCase); Text("The form package is selected by a human from the versioned Form Catalog after client creation.") } }
            }
            .navigationTitle("New Client")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(step == 3 ? "Create" : "Next") { if step < 3 { step += 1 } else { Task { await create() } } }.disabled(step == 0 && label.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
        }
    }
    private func create() async { if (try? await session.api.createClient(label: label, idempotencyKey: IdempotencyKey.make())) != nil { session.dataDidChange(); onCreated(); dismiss() } }
}
