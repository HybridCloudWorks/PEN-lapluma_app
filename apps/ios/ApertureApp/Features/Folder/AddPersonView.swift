import SwiftUI
import ApertureUI
import ApertureAPI
import ApertureDomain

/// Records who a folder is about (T-75).
///
/// Until this existed, a folder created in the app held nobody, so a form package's
/// required roles had no one to attach to and the application could never be
/// created. Relationships are collected here rather than left for later because
/// role resolution reads them: a petition needs to know who is petitioning for whom.
///
/// What this screen deliberately does **not** do: grant anyone access. Writing a
/// person down and inviting them to sign in are separate acts with separate consent
/// (ADR-007), so nobody added here holds a credential, and the minor-no-login
/// constraint therefore cannot be violated from this surface.
struct AddPersonView: View {
    let folderID: FolderID
    let existingPeople: [Person]
    let onCreated: () -> Void

    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var isMinor = false
    @State private var relationshipKind: Relationship.Kind?
    @State private var relatedPersonID: PersonID?
    @State private var isSaving = false
    @State private var errorMessage: String?

    /// Only the kinds whose other side the model can also express, so a folder never
    /// ends up with a relationship that reads correctly from one direction only.
    private var offeredKinds: [Relationship.Kind] {
        Relationship.Kind.allCases.filter { $0.inverse != nil }
    }

    private var trimmedLabel: String {
        label.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ApertureCanvas {
                ScrollView {
                    VStack(alignment: .leading, spacing: Aperture.Spacing.l) {
                        VStack(alignment: .leading, spacing: Aperture.Spacing.s) {
                            Image(systemName: "person.badge.plus")
                                .font(.largeTitle)
                                .foregroundStyle(Aperture.Palette.accent)
                                .accessibilityHidden(true)
                            Text(aperture: "person.add.title")
                                .font(Aperture.Typography.sectionTitle)
                            Text(aperture: "person.add.body")
                                .font(Aperture.Typography.caption)
                                .foregroundStyle(Aperture.Palette.onSurface)
                        }

                        TextField(ApertureString("person.add.labelPlaceholder"), text: $label)
                            .textInputAutocapitalization(.words)
                            .padding(.horizontal, Aperture.Spacing.m)
                            .frame(minHeight: 56)
                            .apertureGlassCard(padding: 0)
                            .accessibilityIdentifier("person-label-field")

                        Toggle(isOn: $isMinor) {
                            Text(aperture: "person.add.isMinor")
                                .font(Aperture.Typography.body)
                        }
                        .accessibilityIdentifier("person-minor-toggle")

                        if !existingPeople.isEmpty {
                            relationshipSection
                        }

                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(Aperture.Palette.critical)
                        }

                        Button(ApertureString("person.add.save")) {
                            Task { await save() }
                        }
                        .fontWeight(.semibold)
                        .apertureMinimumTouchTarget(expandHorizontally: true)
                        .apertureGlassButton(prominent: true)
                        .disabled(trimmedLabel.isEmpty || isSaving)
                        .accessibilityIdentifier("person-save")

                        DisclosureFooter()
                    }
                    .padding(Aperture.Spacing.l)
                }
            }
            .navigationTitle(ApertureString("person.add.navigationTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ApertureString("common.cancel")) { dismiss() }
                }
            }
        }
    }

    @ViewBuilder private var relationshipSection: some View {
        VStack(alignment: .leading, spacing: Aperture.Spacing.s) {
            Text(aperture: "person.add.relationshipTitle")
                .font(Aperture.Typography.sectionTitle)
                .foregroundStyle(Aperture.StatusTone.information.foreground)
                .accessibilityAddTraits(.isHeader)

            Picker(ApertureString("person.add.relationshipKind"), selection: $relationshipKind) {
                Text(aperture: "person.add.noRelationship").tag(Relationship.Kind?.none)
                ForEach(offeredKinds, id: \.self) { kind in
                    Text(ApertureString(String.LocalizationValue(kind.localizationKey)))
                        .tag(Relationship.Kind?.some(kind))
                }
            }
            .accessibilityIdentifier("person-relationship-kind")

            if relationshipKind != nil {
                Picker(ApertureString("person.add.relationshipPerson"), selection: $relatedPersonID) {
                    Text(aperture: "person.add.choosePerson").tag(PersonID?.none)
                    ForEach(existingPeople) { person in
                        Text(person.displayLabel).tag(PersonID?.some(person.id))
                    }
                }
                .accessibilityIdentifier("person-relationship-person")
            }
        }
        .padding(Aperture.Spacing.m)
        .apertureGlassCard(padding: 0)
    }

    @MainActor private func save() async {
        isSaving = true
        defer { isSaving = false }
        // A half-specified relationship is dropped rather than guessed at: naming a
        // kind without a counterpart says nothing the model can record.
        let relationships: [Relationship]
        if let relationshipKind, let relatedPersonID {
            relationships = [Relationship(kind: relationshipKind, objectPersonID: relatedPersonID)]
        } else {
            relationships = []
        }
        do {
            _ = try await session.api.createPerson(
                folderID: folderID,
                displayLabel: trimmedLabel,
                isMinor: isMinor,
                relationships: relationships,
                idempotencyKey: IdempotencyKey.make()
            )
            onCreated()
            dismiss()
        } catch let problem as ProblemDetails {
            errorMessage = problem.title
        } catch {
            errorMessage = LaPlumaString("This person could not be added. Try again.")
        }
    }
}
