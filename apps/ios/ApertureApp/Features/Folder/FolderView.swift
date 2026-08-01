import SwiftUI
import ApertureUI
import ApertureAPI
import ApertureDomain

/// S-04. People, documents, cases — and **who has access**.
///
/// The Access tab is a *safety* surface, not an admin surface. It is written for
/// someone checking whether another person can see their information, which in this
/// population is a question with real stakes (TA-2).
struct FolderView: View {
    let folderID: FolderID
    @Environment(AppSession.self) private var session
    @State private var folder: Folder?
    @State private var documents: [CaseDocument] = []
    @State private var tab = Tab.people

    enum Tab: String, CaseIterable { case people, documents, cases, access }

    var body: some View {
        VStack {
            Picker("Section", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Aperture.Spacing.m)

            List {
                switch tab {
                case .people: peopleSection
                case .documents: documentsSection
                case .cases: casesSection
                case .access: accessSection
                }
            }
        }
        .navigationTitle(folder?.name ?? "Folder")
        .task {
            folder = try? await session.api.folder(id: folderID)
            documents = (try? await session.api.documents(folderID: folderID)) ?? []
        }
    }

    @ViewBuilder private var peopleSection: some View {
        ForEach(folder?.persons ?? []) { person in
            VStack(alignment: .leading, spacing: Aperture.Spacing.xs) {
                Text(person.displayLabel).font(Aperture.Typography.value)
                if person.participation == .inactive {
                    // Quiet Exit: no reason, no precise date, and no notification was
                    // ever generated to anyone (ADR-007).
                    Text("Participant no longer active")
                        .font(Aperture.Typography.caption)
                        .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                } else if person.holdsOwnCredential {
                    Label("Has their own sign-in", systemImage: "person.badge.key")
                        .font(Aperture.Typography.caption)
                        .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private var documentsSection: some View {
        ForEach(documents) { document in
            NavigationLink { DocumentDetailView(document: document) } label: {
                HStack {
                    Image(systemName: document.isOpaque ? "lock.doc" : "doc.text")
                        .foregroundStyle(document.isOpaque ? Aperture.Palette.warning
                                                           : Aperture.Palette.accent)
                    VStack(alignment: .leading, spacing: Aperture.Spacing.xs) {
                        Text(document.originalName).font(Aperture.Typography.body)
                        if document.isOpaque {
                            Text(aperture: "document.sealed.badge")
                                .font(Aperture.Typography.caption)
                                .foregroundStyle(Aperture.Palette.warning)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder private var casesSection: some View {
        ForEach(folder?.cases ?? []) { summary in
            NavigationLink { CaseOverviewView(summary: summary) } label: {
                VStack(alignment: .leading, spacing: Aperture.Spacing.s) {
                    Text(summary.packageTitle).font(Aperture.Typography.value)
                    ProgressCountersView(summary.counters, showsCaveat: false)
                }
            }
        }
    }

    @ViewBuilder private var accessSection: some View {
        Section {
            Text("This is everyone who can see anything in this folder, and exactly what they can see.")
                .font(Aperture.Typography.caption)
        }
        // In the real client this is populated from FolderMembership, showing scoped
        // persons and sections per member, plus a Revoke action that propagates within
        // 60 seconds. Private Annex items belonging to other people are not listed —
        // and not counted — because their *existence* must not be visible.
        Text("You — full access to this folder")
        Text("Casa Legal (reviewer) — can review, cannot approve")
    }
}

struct DocumentDetailView: View {
    let document: CaseDocument

    var body: some View {
        List {
            if document.isOpaque {
                Section {
                    Label(ApertureString("document.sealed.notice"), systemImage: "lock.doc")
                        .font(Aperture.Typography.body)
                        .foregroundStyle(Aperture.Palette.warning)
                }
            } else {
                Section("Preview") {
                    // Previews are rasterised server-side; the client never parses an
                    // unsanitised original (C-15).
                    RoundedRectangle(cornerRadius: Aperture.Radius.card)
                        .fill(Aperture.Palette.surfaceSecondary)
                        .frame(height: 220)
                        .overlay { Text("Server-rasterised preview").font(Aperture.Typography.caption) }
                }
            }

            Section("Details") {
                LabeledContent("Type", value: document.documentSubtype ?? "Not yet classified")
                LabeledContent("Status", value: document.processingState.rawValue)
                LabeledContent("Added", value: document.uploadedAt.formatted(date: .abbreviated, time: .omitted))
            }
        }
        .navigationTitle(document.originalName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CaseOverviewView: View {
    let summary: CaseSummary

    var body: some View {
        List {
            Section { ProgressCountersView(summary.counters) }

            Section("Forms") {
                ForEach(summary.pinnedForms, id: \.formNumber) { form in
                    VStack(alignment: .leading, spacing: Aperture.Spacing.xs) {
                        Text(form.formNumber).font(Aperture.Typography.value)
                        Text(ApertureString("catalog.editionDate \(form.editionDate.formatted(date: .abbreviated, time: .omitted))"))
                            .font(Aperture.Typography.caption)
                            .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                        if form.driftDetected {
                            Label(ApertureString("error.formDrift"), systemImage: "arrow.triangle.2.circlepath")
                                .font(Aperture.Typography.caption)
                                .foregroundStyle(Aperture.Palette.warning)
                        }
                    }
                }
            }

            Section {
                NavigationLink("What's missing") { MissingItemsView(caseID: summary.id) }
                NavigationLink("Review information") { ReviewView(caseID: summary.id) }
                NavigationLink("Forms and export") { PackageView(caseID: summary.id) }
            }

            Section { DisclosureFooter().listRowBackground(Color.clear) }
        }
        .navigationTitle(summary.packageTitle)
    }
}
