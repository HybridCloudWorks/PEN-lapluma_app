import Foundation
import Testing
import ApertureDomain
@testable import ApertureAPI

/// T-77. `CaseState.quarantinedFormDrift`, `PinnedForm.driftDetected` and the
/// FolderView warning that reads it have all existed since the aggregate was
/// written — but nothing ever computed the condition, no transition led into the
/// state, and so the protection had never once applied to a case.
@Suite("Form edition drift")
struct FormEditionDriftTests {

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar.date(from: components) ?? Date()
    }

    private func pinned(_ formNumber: String, _ edition: Date) -> PinnedForm {
        PinnedForm(formNumber: formNumber, editionDate: edition, sourceSHA256: "x", encoding: .acroForm)
    }

    private func catalogForm(_ formNumber: String, _ edition: Date) -> CatalogForm {
        CatalogForm(
            formNumber: formNumber, title: formNumber, editionDate: edition,
            encoding: .acroForm, pageCount: 1, activationState: .pilot, source: nil
        )
    }

    @Test("A pin that matches the catalog is not drift")
    func matchingEditionIsNotDrift() {
        let edition = date(2025, 11, 4)
        let drift = FormDriftPolicy.drift(
            pinnedForms: [pinned("I-130", edition)],
            against: [catalogForm("I-130", edition)]
        )
        #expect(drift.isEmpty)
    }

    @Test("A replaced edition is drift, and names both editions")
    func replacedEditionIsDrift() {
        let old = date(2025, 11, 4)
        let new = date(2026, 3, 1)
        let drift = FormDriftPolicy.drift(
            pinnedForms: [pinned("I-130", old)],
            against: [catalogForm("I-130", new)]
        )
        #expect(drift.count == 1)
        let entry = drift.first
        #expect(entry?.formNumber == "I-130")
        #expect(entry?.pinnedEdition == old)
        #expect(entry?.currentEdition == new)
        #expect(entry?.isWithdrawn == false)
    }

    @Test("A form the package no longer publishes is drift with no edition to move to")
    func withdrawnFormIsDrift() {
        let drift = FormDriftPolicy.drift(
            pinnedForms: [pinned("I-130A", date(2025, 11, 4))],
            against: [catalogForm("I-130", date(2025, 11, 4))]
        )
        #expect(drift.count == 1)
        #expect(drift.first?.isWithdrawn == true)
        #expect(drift.first?.currentEdition == nil)
    }

    @Test("Annotation marks only the drifted pins and leaves the editions alone")
    func annotationMarksWithoutRewriting() {
        let old = date(2025, 11, 4)
        let steady = date(2025, 1, 1)
        let annotated = FormDriftPolicy.annotated(
            pinnedForms: [pinned("I-130", old), pinned("I-130A", steady)],
            against: [catalogForm("I-130", date(2026, 3, 1)), catalogForm("I-130A", steady)]
        )
        #expect(annotated.first { $0.formNumber == "I-130" }?.driftDetected == true)
        #expect(annotated.first { $0.formNumber == "I-130A" }?.driftDetected == false)
        // The pin records what the case was prepared from. Rewriting it to the new
        // edition would erase the very fact the applicant has to be told about.
        #expect(annotated.first { $0.formNumber == "I-130" }?.editionDate == old)
    }

    @Test("The quarantine state can now be entered and left")
    func quarantineIsReachable() {
        // Before T-77 no edge led into this state, so the protection it stands for
        // could never apply to any case.
        #expect(WorkflowPolicy.allowedTransition(from: .collecting, to: .quarantinedFormDrift))
        #expect(WorkflowPolicy.allowedTransition(from: .approved, to: .quarantinedFormDrift))
        // Out again is a human accepting the migration, which returns the case to
        // collecting because the new edition's fields have to be reviewed again.
        #expect(WorkflowPolicy.allowedTransition(from: .quarantinedFormDrift, to: .collecting))
        #expect(!WorkflowPolicy.allowedTransition(from: .quarantinedFormDrift, to: .generated))
        #expect(!WorkflowPolicy.allowedTransition(from: .closed, to: .quarantinedFormDrift))
    }

    /// The realistic scenario, and the one `loadInitialStorage` is written for: a
    /// persisted case prepared against last year's edition, reopened after an app
    /// update that refreshed the catalog.
    private func clientWithDriftedCase() throws -> (StubAPIClient, URL, CaseID) {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "aperture-drift-\(UUID().uuidString).json")
        var storage = StubStorage.seeded()
        let caseID = CaseID("c_ramirez_i130")
        let index = try #require(storage.allCases.firstIndex { $0.id == caseID })
        let existing = storage.allCases[index]
        let stale = CaseSummary(
            id: existing.id, folderID: existing.folderID,
            packageCode: existing.packageCode, packageTitle: existing.packageTitle,
            state: existing.state, counters: existing.counters,
            pinnedForms: existing.pinnedForms.map {
                PinnedForm(
                    formNumber: $0.formNumber,
                    editionDate: date(2019, 1, 1),
                    sourceSHA256: $0.sourceSHA256,
                    encoding: $0.encoding
                )
            }
        )
        storage.allCases[index] = stale
        storage.folders = storage.folders.map { folder in
            Folder(
                id: folder.id, name: folder.name, ownerUserID: folder.ownerUserID,
                persons: folder.persons, documentCount: folder.documentCount,
                cases: folder.cases.map { $0.id == caseID ? stale : $0 }
            )
        }
        try JSONEncoder().encode(storage).write(to: url)
        return (StubAPIClient(persistenceURL: url), url, caseID)
    }

    @Test("A case pinned to a replaced edition is flagged on read and refused generation")
    func driftedCaseIsFlaggedAndRefused() async throws {
        let (api, url, caseID) = try clientWithDriftedCase()
        defer { try? FileManager.default.removeItem(at: url) }
        await api.setDelay(.zero)

        // The warning FolderView has always been ready to show now has something to
        // show: drift is derived against the current catalog on the way out.
        let summary = try await api.caseSummary(id: caseID)
        let everyPinFlagged = summary.pinnedForms.allSatisfy { $0.driftDetected }
        #expect(everyPinFlagged)
        let fromFolder = try await api.folder(id: summary.folderID)
        let folderCase = try #require(fromFolder.cases.first { $0.id == caseID })
        let everyPinFlaggedInFolder = folderCase.pinnedForms.allSatisfy { $0.driftDetected }
        #expect(everyPinFlaggedInFolder)

        let readiness = try await api.packageGenerationReadiness(caseID: caseID)
        #expect(readiness.formsWithEditionDrift == summary.pinnedForms.count)
        #expect(!readiness.canGenerate)

        do {
            _ = try await api.requestPackageGeneration(caseID: caseID, idempotencyKey: "drifted")
            Issue.record("Generation must refuse a case pinned to a replaced edition")
        } catch let problem as ProblemDetails {
            #expect(problem.status == 409)
            #expect(problem.type.hasSuffix("form-edition-drift"))
            #expect(problem.errors?.contains { $0.field == "I-130" } == true)
        }
    }

    @Test("Drift refuses generation even from a state that otherwise allows it")
    func driftDominatesAnOtherwiseReadyCase() async throws {
        let (api, url, caseID) = try clientWithDriftedCase()
        defer { try? FileManager.default.removeItem(at: url) }
        await api.setDelay(.zero)

        // Settle everything a human could settle: confirm every field and collect
        // every mandatory document. The case is then blocked on the catalog alone.
        let fields = try await api.reviewableFields(caseID: caseID)
        _ = try await api.confirmValues(
            caseID: caseID,
            confirmations: fields.map {
                ValueConfirmation(
                    personID: $0.subjectPersonID,
                    canonicalPath: $0.canonicalPath,
                    value: $0.displayValue ?? "Applicant response",
                    resolvesDiscrepancyID: $0.confirmed?.discrepancy?.id
                )
            },
            idempotencyKey: "drift-confirm"
        )
        for (offset, item) in try await api.missingItems(caseID: caseID).items
            .filter({ $0.kind == .evidence && $0.severity == .blocking }).enumerated() {
            _ = try await api.linkEvidence(
                caseID: caseID,
                requirementCode: try #require(item.requirementCode),
                documentID: DocumentID("d_greencard"),
                idempotencyKey: "drift-link-\(offset)"
            )
        }

        let readiness = try await api.packageGenerationReadiness(caseID: caseID)
        #expect(readiness.unconfirmedRequiredFields == 0)
        #expect(readiness.outstandingBlockingEvidence == 0)
        #expect(readiness.caseStateAllowsGeneration)
        #expect(readiness.formsWithEditionDrift > 0)
        #expect(!readiness.canGenerate)

        await #expect(throws: ProblemDetails.self) {
            _ = try await api.requestPackageGeneration(caseID: caseID, idempotencyKey: "drift-ready")
        }

        // And the case can actually be frozen now, which it could not be before.
        let quarantined = try await api.transition(
            caseID: caseID, to: .quarantinedFormDrift, idempotencyKey: "drift-quarantine"
        )
        #expect(quarantined.state == .quarantinedFormDrift)
        #expect(quarantined.state.isBlockedPendingHuman)
    }
}
