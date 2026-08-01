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
                Section("Language and reading") {
                    Toggle("Plain language", isOn: Binding(
                        get: { session.plainLanguageEnabled },
                        set: { session.plainLanguageEnabled = $0 }
                    ))
                    Text("Uses shorter sentences and simpler words everywhere, including the assistant.")
                        .font(Aperture.Typography.caption)
                        .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                }

                Section("Accessibility") {
                    Toggle("Voice first", isOn: Binding(
                        get: { session.accessibilityProfileEnabled },
                        set: { session.accessibilityProfileEnabled = $0 }
                    ))
                    Text("Makes speaking the default way to answer, uses larger buttons, and removes the voice time limit.")
                        .font(Aperture.Typography.caption)
                        .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                }

                Section("Notifications") {
                    NavigationLink("Notification settings") { NotificationPreferencesView() }
                }

                Section("Privacy and data") {
                    ForEach(consents) { record in
                        ConsentRow(record: record)
                    }
                    NavigationLink("Export all my data") { EmptyView() }
                    NavigationLink("Delete everything") { EmptyView() }
                }

                Section("Activity") {
                    NavigationLink("My activity log") { ActivityLogView() }
                }

                Section {
                    NavigationLink(ApertureString("catalog.findLegalHelp")) { LegalHelpDirectoryView() }
                }

                Section { DisclosureFooter().listRowBackground(Color.clear) }
            }
            .navigationTitle("Me")
            .task { consents = (try? await session.api.consents()) ?? [] }
        }
    }
}

/// Every consent shows its **consequence of withdrawal** before the user acts.
/// Analytics defaults to off and its consequence is honestly "none".
struct ConsentRow: View {
    let record: ConsentRecord
    @Environment(AppSession.self) private var session
    @State private var granted: Bool

    init(record: ConsentRecord) {
        self.record = record
        _granted = State(initialValue: record.granted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Aperture.Spacing.xs) {
            Toggle(ApertureString(String.LocalizationValue(record.purpose.localizationKey)), isOn: $granted)
                .disabled(!record.purpose.isWithdrawable)
                .onChange(of: granted) { _, newValue in
                    Task { _ = try? await session.api.setConsent(purpose: record.purpose, granted: newValue) }
                }
            Text(ApertureString(String.LocalizationValue(record.purpose.consequenceKey)))
                .font(Aperture.Typography.caption)
                .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
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
                    Text("\"You have an update in Aperture.\"")
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
            Text("Aperture support looked at your case to investigate a problem you reported. Two managers approved this and it lasted 40 minutes.")
        }
        .navigationTitle("My activity")
    }
}

/// S-12. The in-app inbox is the only surface where notification content appears.
struct InboxView: View {
    @Environment(AppSession.self) private var session
    @State private var items: [InboxItem] = []

    var body: some View {
        List(items) { item in
            VStack(alignment: .leading, spacing: Aperture.Spacing.xs) {
                Text(item.title).font(Aperture.Typography.value)
                Text(item.body).font(Aperture.Typography.body)
                Text(item.createdAt.formatted(.relative(presentation: .named)))
                    .font(Aperture.Typography.caption)
                    .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
            }
            .accessibilityElement(children: .combine)
        }
        .navigationTitle("Notifications")
        .task { items = (try? await session.api.inbox()) ?? [] }
    }
}
