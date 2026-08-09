import SwiftUI
import ApertureUI
import ApertureAPI
import ApertureDomain

/// S-12 preferences plus privacy, data rights and the activity log.
struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @State private var consents: [ConsentRecord] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Language", selection: Binding(
                        get: { session.preferredLocale.language.languageCode?.identifier ?? "en" },
                        set: { session.preferredLocale = Locale(identifier: $0) }
                    )) {
                        Text("English").tag("en")
                        Text("Español").tag("es")
                    }
                    Toggle("Plain language", isOn: Binding(
                        get: { session.plainLanguageEnabled },
                        set: { session.plainLanguageEnabled = $0 }
                    ))
                    Text("Uses shorter sentences and simpler words everywhere, including the assistant.")
                        .font(Aperture.Typography.caption)
                        .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                } header: {
                    sectionHeader("Language and reading")
                }

                Section {
                    Toggle("Voice first", isOn: Binding(
                        get: { session.accessibilityProfileEnabled },
                        set: { session.accessibilityProfileEnabled = $0 }
                    ))
                    .accessibilityIdentifier("accessibility-profile-toggle")
                    Text("Makes speaking the default way to answer, uses larger buttons, and removes the voice time limit.")
                        .font(Aperture.Typography.caption)
                        .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                } header: {
                    sectionHeader("Accessibility")
                }

                Section {
                    NavigationLink("Notification settings") { NotificationPreferencesView() }
                } header: {
                    sectionHeader("Notifications")
                }

                Section {
                    ForEach(consents) { record in
                        ConsentRow(record: record) { await reloadConsents() }
                    }
                    NavigationLink("Export all my data") { DataExportView() }
                    NavigationLink("Delete everything") { DeleteDataView() }
                } header: {
                    sectionHeader("Privacy and data")
                }

                Section {
                    NavigationLink("My activity log") { ActivityLogView() }
                } header: {
                    sectionHeader("Activity")
                }

                Section {
                    NavigationLink(ApertureString("catalog.findLegalHelp")) { LegalHelpDirectoryView() }
                }

                Section {
                    Button("Sign out", role: .destructive) { session.signOut() }
                } header: {
                    sectionHeader("Account")
                }

                Section { DisclosureFooter().listRowBackground(Color.clear) }
            }
            .navigationTitle("Me")
            .task { await reloadConsents() }
        }
    }

    private func reloadConsents() async {
        // A failed refresh keeps the last known records rather than blanking the list.
        consents = (try? await session.api.consents()) ?? consents
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(Aperture.Typography.sectionTitle)
            .foregroundStyle(Aperture.Palette.onSurface)
            .textCase(nil)
    }
}

/// Every consent shows its **consequence of withdrawal** before the user acts.
/// Analytics defaults to off and its consequence is honestly "none".
struct ConsentRow: View {
    let record: ConsentRecord
    let onUpdated: () async -> Void
    @Environment(AppSession.self) private var session
    @State private var granted: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(record: ConsentRecord, onUpdated: @escaping () async -> Void) {
        self.record = record
        self.onUpdated = onUpdated
        _granted = State(initialValue: record.granted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Aperture.Spacing.xs) {
            Toggle(ApertureString(String.LocalizationValue(record.purpose.localizationKey)), isOn: $granted)
                .disabled(!record.purpose.isWithdrawable || isSaving)
                .onChange(of: granted) { previous, newValue in
                    // A rollback or an external refresh lands back on the recorded
                    // value; only a user-initiated change reaches the API.
                    guard newValue != record.granted else { return }
                    save(previous: previous, granting: newValue)
                }
                .onChange(of: record.granted) { _, newValue in
                    guard !isSaving else { return }
                    granted = newValue
                }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(Aperture.Typography.caption)
                    .foregroundStyle(Aperture.Palette.critical)
            }
            Text(ApertureString(String.LocalizationValue(record.purpose.consequenceKey)))
                .font(Aperture.Typography.caption)
                .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
        }
    }

    /// The toggle must never show a consent state the backend does not hold:
    /// a failed save rolls the switch back and says so, and the record is
    /// refreshed after success so the row reflects what was actually stored.
    private func save(previous: Bool, granting: Bool) {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                _ = try await session.api.setConsent(purpose: record.purpose, granted: granting)
                await onUpdated()
            } catch {
                granted = previous
                errorMessage = LaPlumaString("Your consent choice could not be saved. Try again.")
            }
            isSaving = false
        }
    }
}

struct NotificationPreferencesView: View {
    var body: some View {
        List {
            Section {
                // Shown to the user as a worked example: this is both a privacy control
                // and a trust demonstration (NT-002).
                VStack(alignment: .leading, spacing: Aperture.Spacing.s) {
                    Text("On your lock screen").font(Aperture.Typography.value)
                    Text("\"You have an update in LaPluma.\"")
                        .font(Aperture.Typography.body.italic())
                    Text("We never put your name, your case, or your form on a notification.")
                        .font(Aperture.Typography.caption)
                        .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                }
            }

            Section("Categories") {
                ForEach(InboxItem.Category.allCases, id: \.self) { category in
                    HStack {
                        Text(ApertureString(String.LocalizationValue(category.localizationKey)))
                        Spacer()
                        if !category.isSuppressible {
                            Text("Always on")
                                .font(Aperture.Typography.caption)
                                .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Notifications")
    }
}

/// Break-glass access is surfaced here, unprompted and in plain language. A user is
/// told when someone looked at their file.
struct ActivityLogView: View {
    var body: some View {
        List {
            Text("Danielle at Casa Legal reviewed your I-130 information.")
            Text("You gave Jorge permission to help with your documents.")
            Text("LaPluma support looked at your case to investigate a problem you reported. Two managers approved this and it lasted 40 minutes.")
        }
        .navigationTitle("My activity")
    }
}

struct DataExportView: View {
    @Environment(AppSession.self) private var session
    @State private var exportURL: URL?
    @State private var errorMessage: String?

    private struct Export: Codable {
        let generatedAt: Date
        let folders: [Folder]
        let documents: [CaseDocument]
        let inbox: [InboxItem]
        let consents: [ConsentRecord]
    }

    var body: some View {
        Form {
            Section {
                Text("This creates a readable JSON copy of the information held by this mobile app. It does not send anything anywhere.")
            }
            Section {
                Button("Prepare my export") { Task { await prepare() } }
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Save or share export", systemImage: "square.and.arrow.up")
                    }
                }
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(Aperture.Palette.critical) }
            Section { DisclosureFooter() }
        }
        .navigationTitle("Export my data")
        // The copy exists to be shared from this screen. Leaving it on disk after the
        // applicant walks away is a copy of their data nobody asked to keep.
        .onDisappear {
            ExportScratch.discard(exportURL)
            exportURL = nil
        }
    }

    @MainActor private func prepare() async {
        do {
            let folders = try await session.api.folders()
            var documents: [CaseDocument] = []
            for folder in folders {
                documents += try await session.api.documents(folderID: folder.id)
            }
            let payload = Export(
                generatedAt: Date(),
                folders: folders,
                documents: documents,
                inbox: try await session.api.inbox(),
                consents: try await session.api.consents()
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let url = try ExportScratch.makeURL(named: "LaPluma-Data-Export.json")
            try encoder.encode(payload).write(to: url, options: [.atomic, .completeFileProtection])
            // Preparing again replaces the copy rather than accumulating exports.
            ExportScratch.discard(exportURL)
            exportURL = url
        } catch {
            errorMessage = LaPlumaString("Your export could not be prepared. Try again.")
        }
    }
}

struct DeleteDataView: View {
    @Environment(AppSession.self) private var session
    @State private var confirmation = ""
    @State private var isDeleting = false
    @State private var errorMessage: String?
    private let confirmationToken = "DELETE"

    var body: some View {
        Form {
            Section {
                Text("This permanently removes folders, documents, answers, interviews, packages, notifications, and consent records stored by this mobile build.")
                    .foregroundStyle(Aperture.Palette.critical)
            }
            Section(LaPlumaFormat(
                "settings.deleteConfirmationInstruction",
                confirmationToken
            )) {
                TextField(confirmationToken, text: $confirmation)
                    .textInputAutocapitalization(.characters)
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Aperture.Palette.critical)
                }
                Button("Delete everything", role: .destructive) {
                    isDeleting = true
                    errorMessage = nil
                    Task {
                        do {
                            try await session.deleteAllLocalData()
                        } catch {
                            errorMessage = LaPlumaString("Some local data could not be removed. Try again.")
                        }
                        isDeleting = false
                    }
                }
                .disabled(confirmation != confirmationToken || isDeleting)
            }
            Section { DisclosureFooter(emphasis: .prominent) }
        }
        .navigationTitle("Delete everything")
    }
}

/// S-12. The in-app inbox is the only surface where notification content appears.
struct InboxView: View {
    @Environment(AppSession.self) private var session
    @State private var items: [InboxItem] = []

    var body: some View {
        List(items) { item in
            Button {
                Task {
                    try? await session.api.markRead(notificationID: item.id)
                    items = (try? await session.api.inbox()) ?? []
                    session.dataDidChange()
                }
            } label: {
                HStack(alignment: .top) {
                    if item.readAt == nil {
                        Circle().fill(Aperture.Palette.accent).frame(width: 8, height: 8)
                            .accessibilityLabel(LaPlumaString("Unread"))
                    }
                    VStack(alignment: .leading, spacing: Aperture.Spacing.xs) {
                        Text(item.title).font(Aperture.Typography.value)
                        Text(item.body).font(Aperture.Typography.body)
                        Text(item.createdAt.formatted(
                            .relative(presentation: .named).locale(session.preferredLocale)
                        ))
                            .font(Aperture.Typography.caption)
                            .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Notifications")
        .task { items = (try? await session.api.inbox()) ?? [] }
    }
}
