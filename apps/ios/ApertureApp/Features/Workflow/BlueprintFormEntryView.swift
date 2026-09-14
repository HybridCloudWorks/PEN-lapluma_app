import SwiftUI
import ApertureAPI
import ApertureDomain
import ApertureUI

/// Dynamic Blueprint-driven entry and guidance rendering view (APP-05).
///
/// Renders declarative fields, repeated and conditional sections, and evidence requests
/// without bespoke per-form screens. Cites official guidance and statutory fee references
/// using the pastel visual system.
struct BlueprintFormEntryView: View {
    let caseID: CaseID
    let blueprint: BlueprintDefinition
    let guidance: DocumentGuidance?

    @Environment(AppSession.self) private var session
    @State private var values: [String: String] = [:]
    @State private var repeatedCounts: [String: Int] = [:]
    @State private var isSubmitting: Bool = false
    @State private var statusMessage: String?
    @State private var activeConflict: ConflictDetails?
    @State private var showConflictSheet: Bool = false

    struct ConflictDetails: Identifiable {
        var id: String { sectionId }
        let sectionId: String
        let baseRevision: Int
        let localValues: [String: String]
        let serverValues: [String: String]
    }

    var body: some View {
        Form {
            if let guidance {
                guidanceSection(guidance)
            }

            ForEach(blueprint.sections) { section in
                if section.isVisible(against: values) {
                    renderSection(section)
                }
            }

            if !blueprint.evidenceRequirements.isEmpty {
                evidenceSection()
            }

            Section {
                Button {
                    Task { await commitAll() }
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else {
                        Text(LaPlumaString("blueprint.entry.commit"))
                            .font(Aperture.Typography.label)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSubmitting)

                if let statusMessage {
                    Text(verbatim: statusMessage)
                        .font(Aperture.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(blueprint.title)
        .sheet(isPresented: $showConflictSheet) {
            if let conflict = activeConflict {
                ConflictResolutionSheet(
                    conflict: conflict,
                    onKeepLocal: {
                        values.merge(conflict.localValues) { _, new in new }
                        showConflictSheet = false
                        activeConflict = nil
                        Task { await commitSection(sectionId: conflict.sectionId, forceRevision: conflict.baseRevision + 1) }
                    },
                    onAcceptServer: {
                        values.merge(conflict.serverValues) { _, new in new }
                        showConflictSheet = false
                        activeConflict = nil
                        statusMessage = LaPlumaString("blueprint.conflict.acceptServer")
                        session.dataDidChange()
                    },
                    onDismiss: {
                        showConflictSheet = false
                    }
                )
            }
        }
    }

    // MARK: - Guidance Section

    @ViewBuilder
    private func guidanceSection(_ g: DocumentGuidance) -> Section<some View, some View> {
        Section {
            VStack(alignment: .leading, spacing: Aperture.Spacing.s) {
                if let url = g.officialInstructionsUrl {
                    Link(destination: url) {
                        Label(LaPlumaString("blueprint.guidance.officialInstructions"), systemImage: "arrow.up.right.square")
                    }
                    .font(Aperture.Typography.action)
                }

                if let citationUrl = g.feeScheduleCitationUrl {
                    Link(destination: citationUrl) {
                        Label(LaPlumaString("blueprint.guidance.feeCitation"), systemImage: "dollarsign.circle")
                    }
                    .font(Aperture.Typography.action)
                }

                if let notes = g.feeNotes, !notes.isEmpty {
                    Text(verbatim: notes)
                        .font(Aperture.Typography.caption)
                        .foregroundStyle(.secondary)
                }

                if let instNotes = g.institutionGuidanceNotes, !instNotes.isEmpty {
                    HStack {
                        Image(systemName: "building.columns.fill")
                            .foregroundStyle(ApertureTone.blue.actionToken)
                        Text(LaPlumaString("blueprint.guidance.institutionNotes"))
                            .font(Aperture.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(verbatim: instNotes)
                        .font(Aperture.Typography.body)
                }
            }
            .padding(Aperture.Spacing.xs)
        } header: {
            Text(LaPlumaString("blueprint.guidance.header"))
        }
    }

    // MARK: - Dynamic Section Rendering

    @ViewBuilder
    private func renderSection(_ section: BlueprintSection) -> some View {
        let count = repeatedCounts[section.sectionId] ?? 1

        Section {
            if let desc = section.description, !desc.isEmpty {
                Text(verbatim: desc)
                    .font(Aperture.Typography.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(0..<count, id: \.self) { index in
                let prefix = section.isRepeatable ? "[\(index)]." : ""
                ForEach(blueprint.fields.filter { $0.sectionId == section.sectionId }) { field in
                    let fieldKey = prefix + field.canonicalPath
                    if field.isVisible(against: values) {
                        renderField(field, key: fieldKey)
                    }
                }
            }

            if section.isRepeatable {
                HStack {
                    if count < section.maxOccurs {
                        Button {
                            ApertureHaptics.playFeedback(.light)
                            repeatedCounts[section.sectionId] = count + 1
                        } label: {
                            Label(LaPlumaString("blueprint.entry.repeatableAdd"), systemImage: "plus.circle")
                        }
                    }

                    if count > 1 {
                        Button(role: .destructive) {
                            ApertureHaptics.playFeedback(.medium)
                            repeatedCounts[section.sectionId] = count - 1
                        } label: {
                            Label(LaPlumaString("blueprint.entry.repeatableRemove"), systemImage: "minus.circle")
                        }
                    }
                }
            }
        } header: {
            Text(verbatim: section.title)
        }
    }

    // MARK: - Field Control Rendering

    @ViewBuilder
    private func renderField(_ field: BlueprintField, key: String) -> some View {
        VStack(alignment: .leading, spacing: Aperture.Spacing.xxs) {
            switch field.type {
            case .string, .number, .date:
                TextField(
                    field.label,
                    text: Binding(
                        get: { values[key] ?? "" },
                        set: { values[key] = $0 }
                    )
                )
            case .boolean:
                Toggle(
                    field.label,
                    isOn: Binding(
                        get: { (values[key] ?? "").lowercased() == "true" },
                        set: { values[key] = $0 ? "true" : "false" }
                    )
                )
            case .choice:
                Picker(
                    field.label,
                    selection: Binding(
                        get: { values[key] ?? "" },
                        set: { values[key] = $0 }
                    )
                ) {
                    Text(verbatim: "").tag("")
                    ForEach(field.choices ?? [], id: \.self) { choice in
                        Text(verbatim: choice).tag(choice)
                    }
                }
            case .signature:
                Toggle(
                    field.label,
                    isOn: Binding(
                        get: { (values[key] ?? "").lowercased() == "true" },
                        set: { values[key] = $0 ? "true" : "false" }
                    )
                )
            }
        }
    }

    // MARK: - Evidence Requirements Section

    @ViewBuilder
    private func evidenceSection() -> Section<some View, some View> {
        Section {
            ForEach(blueprint.evidenceRequirements) { req in
                if req.isRequired(against: values) {
                    HStack {
                        Image(systemName: "doc.badge.ellipsis")
                            .foregroundStyle(ApertureTone.blue.actionToken)
                        VStack(alignment: .leading) {
                            Text(verbatim: req.title)
                                .font(Aperture.Typography.body)
                            Text(verbatim: req.attributedRole)
                                .font(Aperture.Typography.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text(LaPlumaString("blueprint.guidance.evidenceChecklist"))
        }
    }

    // MARK: - Commit Actions

    private func commitAll() async {
        isSubmitting = true
        defer { isSubmitting = false }

        for section in blueprint.sections {
            await commitSection(sectionId: section.sectionId, forceRevision: nil)
        }
    }

    private func commitSection(sectionId: String, forceRevision: Int?) async {
        let secFields = blueprint.fields.filter { $0.sectionId == sectionId }.map(\.canonicalPath)
        var commitValues: [String: String] = [:]
        for (k, v) in values {
            if secFields.contains(where: { k.hasSuffix($0) }) {
                commitValues[k] = v
            }
        }

        let baseRev = forceRevision ?? 1
        do {
            let result = try await session.api.commitSection(
                caseID: caseID,
                sectionID: sectionId,
                baseRevision: baseRev,
                values: commitValues,
                idempotencyKey: IdempotencyKey.make()
            )
            ApertureHaptics.playFeedback(.success)
            if result.invalidatedApproval {
                statusMessage = LaPlumaString("blueprint.entry.approvalInvalidated")
            } else if result.reopenedReview {
                statusMessage = LaPlumaString("blueprint.entry.reviewReopened")
            } else {
                statusMessage = LaPlumaString("blueprint.entry.committed")
            }
            session.dataDidChange()
        } catch let problem as ProblemDetails where problem.status == 412 {
            ApertureHaptics.playFeedback(.error)
            statusMessage = LaPlumaString("blueprint.entry.conflictDetected")
            activeConflict = ConflictDetails(
                sectionId: sectionId,
                baseRevision: baseRev,
                localValues: commitValues,
                serverValues: [:]
            )
            showConflictSheet = true
        } catch {
            ApertureHaptics.playFeedback(.error)
            statusMessage = LaPlumaString("The section changed elsewhere. Reload before committing.")
        }
    }
}

/// Conflict resolution comparison sheet (APP-06).
struct ConflictResolutionSheet: View {
    let conflict: BlueprintFormEntryView.ConflictDetails
    let onKeepLocal: () -> Void
    let onAcceptServer: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(LaPlumaString("blueprint.conflict.explanation"))
                        .font(Aperture.Typography.body)
                        .foregroundStyle(.secondary)
                }

                Section {
                    ForEach(Array(conflict.localValues.keys.sorted()), id: \.self) { key in
                        VStack(alignment: .leading, spacing: Aperture.Spacing.xxs) {
                            Text(verbatim: key)
                                .font(Aperture.Typography.label)
                            HStack {
                                Text(LaPlumaString("blueprint.conflict.localVersion"))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(verbatim: conflict.localValues[key] ?? "")
                                    .bold()
                            }
                            .font(Aperture.Typography.caption)
                        }
                    }
                } header: {
                    Text(LaPlumaString("blueprint.conflict.localVersion"))
                }

                Section {
                    Button {
                        onKeepLocal()
                    } label: {
                        Text(LaPlumaString("blueprint.conflict.keepLocal"))
                            .font(Aperture.Typography.action)
                    }

                    Button {
                        onAcceptServer()
                    } label: {
                        Text(LaPlumaString("blueprint.conflict.acceptServer"))
                            .font(Aperture.Typography.action)
                    }
                }
            }
            .navigationTitle(LaPlumaString("blueprint.conflict.title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LaPlumaString("blueprint.conflict.close")) {
                        onDismiss()
                    }
                }
            }
        }
    }
}
