import SwiftUI
import ApertureUI
import ApertureAPI
import ApertureDomain

/// S-03. Answers "what do I need to do next" in one glance.
///
/// Folder cards carry two mechanical counters and a neutral state chip. There is no
/// ring, no percentage and no celebratory colour, because every one of those is read as
/// a statement about the outcome of the application (C-20).
struct HomeView: View {
    @Environment(AppSession.self) private var session
    @State private var model = HomeModel()
    @State private var showsCreateFolder = false

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .loading:
                    ApertureLoadingView()
                case .failed:
                    ApertureMessageView(
                        .offline,
                        action: ("Try again", { Task { await model.load(api: session.api) } })
                    )
                case .loaded:
                    content
                }
            }
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { InboxView() } label: {
                        Image(systemName: "bell")
                    }
                    .accessibilityLabel("Notifications")
                }
            }
            .task(id: session.dataRevision) { await model.load(api: session.api) }
            .refreshable { await model.load(api: session.api) }
            .sheet(isPresented: $showsCreateFolder) {
                CreateFolderView {
                    session.dataDidChange()
                    showsCreateFolder = false
                }
            }
        }
    }

    private var content: some View {
        ApertureCanvas {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Aperture.Spacing.l) {
                    sectionHeader("Needs your attention", systemImage: "sparkle.magnifyingglass")

                if model.attentionItems.isEmpty {
                    Label {
                        Text(aperture: "progress.nothingNeedsYou")
                    } icon: {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(Aperture.Palette.accent)
                    }
                    .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .apertureGlassCard()
                } else {
                    // At most three. More than that is a list, not attention.
                    ForEach(model.attentionItems.prefix(3)) { item in
                        NavigationLink {
                            MissingItemsView(caseID: item.caseID)
                        } label: {
                            HStack(spacing: Aperture.Spacing.m) {
                                Image(systemName: "exclamationmark.circle")
                                    .font(.title2)
                                    .foregroundStyle(Aperture.Palette.critical)
                                    .accessibilityHidden(true)
                                AttentionRow(item: item)
                                Spacer(minLength: Aperture.Spacing.s)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                                    .accessibilityHidden(true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .apertureGlassCard()
                        }
                        .buttonStyle(.plain)
                    }
                }

                    sectionHeader("Your folders", systemImage: "folder")

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Aperture.Spacing.s) {
                            startApplicationButton
                            createFolderButton
                        }
                        VStack(spacing: Aperture.Spacing.s) {
                            startApplicationButton
                            createFolderButton
                        }
                    }
                    .apertureGlassCard(padding: Aperture.Spacing.s)

                ForEach(model.folders) { folder in
                    NavigationLink { FolderView(folderID: folder.id) } label: {
                        FolderCard(folder: folder)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .apertureGlassCard()
                    }
                    .buttonStyle(.plain)
                }

                    DisclosureFooter()
                }
                .padding(.horizontal, Aperture.Spacing.m)
                .padding(.vertical, Aperture.Spacing.s)
            }
        }
    }

    private func sectionHeader(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(Aperture.Typography.sectionTitle)
            .foregroundStyle(Aperture.Palette.onSurface)
            .accessibilityAddTraits(.isHeader)
    }

    private var startApplicationButton: some View {
        NavigationLink { CatalogView(folderID: model.folders.first?.id) } label: {
            Label("Start a new application", systemImage: "plus.circle.fill")
                .font(Aperture.Typography.value)
                .apertureMinimumTouchTarget(expandHorizontally: true)
        }
        .apertureGlassButton(prominent: true)
        .buttonBorderShape(.roundedRectangle(radius: Aperture.Radius.control))
    }

    private var createFolderButton: some View {
        Button { showsCreateFolder = true } label: {
            Label("Create another folder", systemImage: "folder.badge.plus")
                .font(Aperture.Typography.value)
                .apertureMinimumTouchTarget(expandHorizontally: true)
        }
        .apertureGlassButton()
        .buttonBorderShape(.roundedRectangle(radius: Aperture.Radius.control))
    }
}

struct CreateFolderView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    let onCreated: () -> Void

    var body: some View {
        NavigationStack {
            ApertureCanvas {
                VStack(alignment: .leading, spacing: Aperture.Spacing.l) {
                    VStack(alignment: .leading, spacing: Aperture.Spacing.s) {
                        Image(systemName: "folder.badge.plus")
                            .font(.largeTitle)
                            .foregroundStyle(Aperture.Palette.accent)
                            .accessibilityHidden(true)
                        Text("Name it so it is easy to find.")
                            .font(Aperture.Typography.sectionTitle)
                    }

                    TextField("For example, My application", text: $name)
                        .textInputAutocapitalization(.words)
                        .padding(.horizontal, Aperture.Spacing.m)
                        .frame(minHeight: 56)
                        .apertureGlassCard(padding: 0)

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Aperture.Palette.critical)
                    }

                    Button("Create folder") {
                        Task { await create() }
                    }
                    .fontWeight(.semibold)
                    .apertureMinimumTouchTarget(expandHorizontally: true)
                    .apertureGlassButton(prominent: true)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)

                    Spacer()
                    DisclosureFooter()
                }
                .padding(Aperture.Spacing.l)
            }
            .navigationTitle("New folder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ApertureString("common.cancel")) { dismiss() }
                }
            }
        }
    }

    @MainActor private func create() async {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await session.api.createFolder(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                idempotencyKey: IdempotencyKey.make()
            )
            onCreated()
            dismiss()
        } catch {
            errorMessage = "The folder could not be created. Try again."
        }
    }
}

@Observable
@MainActor
final class HomeModel {
    enum Phase { case loading, loaded, failed }

    var phase: Phase = .loading
    var folders: [Folder] = []
    var attentionItems: [AttentionItem] = []

    struct AttentionItem: Identifiable {
        let id: String
        let caseID: CaseID
        let title: String
        let detail: String
    }

    func load(api: any ApertureAPIClient) async {
        do {
            let folders = try await api.folders()
            self.folders = folders
            self.attentionItems = folders.flatMap { folder in
                folder.cases.compactMap { summary -> AttentionItem? in
                    guard summary.counters.blockingItems > 0 else { return nil }
                    return AttentionItem(
                        id: summary.id.rawValue,
                        caseID: summary.id,
                        title: summary.packageTitle,
                        detail: "\(summary.counters.blockingItems) items need you"
                    )
                }
            }
            phase = .loaded
        } catch {
            phase = .failed
        }
    }
}

struct AttentionRow: View {
    let item: HomeModel.AttentionItem

    var body: some View {
        VStack(alignment: .leading, spacing: Aperture.Spacing.xs) {
            Text(item.title).font(Aperture.Typography.value)
            Text(item.detail)
                .font(Aperture.Typography.caption)
                .foregroundStyle(Aperture.Palette.critical)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One VoiceOver element with a composed label, so a non-visual user gets the whole
/// card in one utterance rather than five fragments.
struct FolderCard: View {
    let folder: Folder

    var body: some View {
        HStack(alignment: .top, spacing: Aperture.Spacing.m) {
            Image(systemName: "folder.fill")
                .font(.title2)
                .foregroundStyle(Aperture.Palette.accent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Aperture.Spacing.s) {
                Text(folder.name).font(Aperture.Typography.value)
                Text("\(folder.persons.count) people · \(folder.documentCount) documents")
                    .font(Aperture.Typography.caption)
                    .foregroundStyle(Aperture.Palette.onSurfaceSecondary)

                if let summary = folder.cases.first {
                    CompactProgressCounters(counters: summary.counters)
                    CaseStateChip(state: summary.state)
                }
            }

            Spacer(minLength: Aperture.Spacing.xs)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct CompactProgressCounters: View {
    let counters: ProgressCounters

    var body: some View {
        HStack(spacing: Aperture.Spacing.s) {
            counter(
                value: "\(counters.fieldsFilled) / \(counters.fieldsRequired)",
                label: "Fields",
                icon: "list.bullet.clipboard"
            )
            counter(
                value: "\(counters.documentsCollected) / \(counters.documentsRequired)",
                label: "Documents",
                icon: "doc.on.doc"
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(counters.fieldsFilled) of \(counters.fieldsRequired) form fields filled. "
            + "\(counters.documentsCollected) of \(counters.documentsRequired) documents collected."
        )
    }

    private func counter(value: String, label: LocalizedStringKey, icon: String) -> some View {
        HStack(spacing: Aperture.Spacing.s) {
            Image(systemName: icon)
                .foregroundStyle(Aperture.Palette.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(Aperture.Typography.value)
                Text(label)
                    .font(Aperture.Typography.caption)
                    .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Aperture.Spacing.s)
        .background(
            Aperture.Palette.surface.opacity(0.52),
            in: RoundedRectangle(cornerRadius: Aperture.Radius.control, style: .continuous)
        )
    }
}

/// Deliberately neutral-toned. A green "approved-looking" badge would be an implied
/// outcome representation.
struct CaseStateChip: View {
    let state: CaseState

    var body: some View {
        Text(label)
            .font(Aperture.Typography.caption)
            .padding(.horizontal, Aperture.Spacing.s)
            .padding(.vertical, Aperture.Spacing.xs)
            .background(Aperture.Palette.surfaceSecondary)
            .foregroundStyle(state.isBlockedPendingHuman ? Aperture.Palette.warning
                                                         : Aperture.Palette.onSurfaceSecondary)
            .clipShape(Capsule())
    }

    private var label: String {
        switch state {
        case .collecting: "Collecting"
        case .interviewing: "Answering questions"
        case .validating: "Checking"
        case .inReview: "In review"
        case .approved, .generated: "Ready to file"
        case .delivered: "Sent"
        case .quarantinedFormDrift: "Form updated — needs you"
        case .onHold: "On hold"
        case .draft: "Draft"
        case .closed: "Closed"
        case .abandoned: "Stopped"
        }
    }
}
