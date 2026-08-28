import Foundation
import ApertureDomain

/// Package-driven initial state for a newly created case (TODO T-61).
///
/// `createCase` used to persist only a summary and pinned forms, so every
/// per-case endpoint — reviewable fields, missing items, interview batches —
/// returned empty collections and a new case was a dead-end shell only the
/// hand-seeded fixture could escape. A template describes what a package
/// requires *structurally*: which roles must be filled by people, which
/// canonical fields the review screen must collect, and how those gaps are
/// presented as missing items. Values are never part of a template — a new
/// case starts with nothing confirmed and no proposals, because no document
/// has been read and no human has answered anything.
///
/// Only `FAMILY_I130` carries a template today, deliberately: T-61's
/// dependency note says to prove one package end to end before activating
/// more. A package without a template keeps the previous shell behaviour.
struct CaseInitializationTemplate: Sendable {

    /// One reviewable field the package requires, attributed to a role rather
    /// than a person — the role is resolved against the folder when the case
    /// is created.
    struct FieldSpec: Sendable {
        let role: String
        let canonicalPath: CanonicalPath
        let localizedLabel: String
        let englishFormLabel: String
        let formReference: String
    }

    /// Roles that must resolve to a person before the case can exist. A case
    /// whose required fields cannot be attributed to anyone is exactly the
    /// dead-end this type exists to remove, so creation fails closed instead.
    let requiredRoles: [String]
    /// Where an evidence requirement's `personRole` names no resolved role
    /// (for example "BOTH"), the item is assigned to this role's person.
    let evidenceFallbackRole: String
    let fields: [FieldSpec]
    /// Citation target for field-kind missing items: the agency's own
    /// instructions document, per AP-5 (an item without a citation is
    /// dropped, not shown).
    let instructionsTitle: String
    let instructionsURL: URL

    static func template(for packageCode: String) -> CaseInitializationTemplate? {
        packageCode == "FAMILY_I130" ? familyI130 : nil
    }

    /// Resolves a role to a person from the folder's recorded relationships,
    /// used only for roles the caller did not assign explicitly. Ambiguity is
    /// not guessed away: two candidates for one role mean no inference.
    static func inferredPerson(
        for role: String,
        among persons: [Person],
        excluding assigned: Set<PersonID>
    ) -> Person? {
        let kind: Relationship.Kind?
        switch role {
        case "PETITIONER": kind = .petitionerFor
        case "BENEFICIARY": kind = .beneficiaryOf
        case "SPONSOR": kind = .sponsorFor
        default: kind = nil
        }
        guard let kind else { return nil }
        let candidates = persons.filter { person in
            !assigned.contains(person.id)
                && person.relationships.contains { $0.kind == kind }
        }
        return candidates.count == 1 ? candidates.first : nil
    }

    /// The I-130 starter set mirrors the fields the interview script and the
    /// seeded fixture already exercise, plus the petitioner's name so both
    /// roles own work from the first day. It is a fixture floor, not the real
    /// 218-field map — `fieldsRequired` still reports the requirement count.
    static let familyI130 = CaseInitializationTemplate(
        requiredRoles: ["PETITIONER", "BENEFICIARY"],
        evidenceFallbackRole: "PETITIONER",
        fields: [
            FieldSpec(
                role: "PETITIONER",
                canonicalPath: CanonicalPath("person.name.family"),
                localizedLabel: "Apellido",
                englishFormLabel: "Family Name (Last Name)",
                formReference: "I-130 Part 1, Item 4.a"
            ),
            FieldSpec(
                role: "BENEFICIARY",
                canonicalPath: CanonicalPath("person.name.family"),
                localizedLabel: "Apellido",
                englishFormLabel: "Family Name (Last Name)",
                formReference: "I-130 Part 2, Item 1.a"
            ),
            FieldSpec(
                role: "BENEFICIARY",
                canonicalPath: CanonicalPath("person.birth.date"),
                localizedLabel: "Fecha de nacimiento",
                englishFormLabel: "Date of Birth",
                formReference: "I-130 Part 2, Item 8"
            ),
            FieldSpec(
                role: "BENEFICIARY",
                canonicalPath: CanonicalPath("person.birth.city"),
                localizedLabel: "Ciudad de nacimiento",
                englishFormLabel: "City/Town/Village of Birth",
                formReference: "I-130 Part 2, Item 9"
            ),
            FieldSpec(
                role: "BENEFICIARY",
                canonicalPath: CanonicalPath("person.document.passportNumber"),
                localizedLabel: "Número de pasaporte",
                englishFormLabel: "Passport Number",
                formReference: "I-130 Part 2, Item 22"
            ),
            FieldSpec(
                role: "BENEFICIARY",
                canonicalPath: CanonicalPath("person.entry.lastDate"),
                localizedLabel: "Fecha de última entrada",
                englishFormLabel: "Date of Last Arrival",
                formReference: "I-130 Part 4, Item 46.a"
            )
        ],
        instructionsTitle: "Instructions for Form I-130",
        instructionsURL: URL(string: "https://www.uscis.gov/i-130")!
    )
}

extension StubStorage {

    /// Materialises a template for a case that already exists in `allCases`
    /// and its folder: reviewable fields, field- and evidence-kind missing
    /// items, one interview batch covering the field items, the value-history
    /// baseline, and recomputed counters. Callers run this inside the same
    /// `commit` that records the case, so the case and its initial state are
    /// durable — or absent — as one unit.
    mutating func initializeCase(
        _ summary: CaseSummary,
        template: CaseInitializationTemplate,
        personsForRoles: [String: Person],
        requirementSet: RequirementSet?
    ) {
        let caseID = summary.id

        reviewable[caseID] = template.fields.compactMap { spec in
            guard let person = personsForRoles[spec.role] else { return nil }
            return ReviewableField(
                subjectPersonID: person.id,
                canonicalPath: spec.canonicalPath,
                localizedLabel: spec.localizedLabel,
                englishFormLabel: spec.englishFormLabel,
                formReference: spec.formReference,
                confirmed: nil,
                openProposal: nil
            )
        }

        let fieldCitation = Citation(
            sourceURL: template.instructionsURL,
            documentTitle: template.instructionsTitle
        )
        let batchID = BatchID("mib_\(caseID.rawValue)")
        var items: [MissingItem] = []
        for (offset, spec) in template.fields.enumerated() {
            guard let person = personsForRoles[spec.role] else { continue }
            items.append(MissingItem(
                id: MissingItemID("mi_\(caseID.rawValue)_f\(offset)"),
                kind: .field,
                severity: .blocking,
                assignedPersonID: person.id,
                assignedPersonLabel: person.displayLabel,
                title: "\(spec.englishFormLabel) — \(person.displayLabel)",
                whyRequired: "The form asks for this at \(spec.formReference).",
                citation: fieldCitation,
                resolutionPaths: [
                    ResolutionPath(kind: .answer, label: "Answer this question", estimatedMinutes: 2),
                    ResolutionPath(kind: .type, label: "Type it in", estimatedMinutes: 2)
                ],
                batchID: batchID,
                ageDays: 0,
                canonicalPath: spec.canonicalPath,
                minimumEstimatedMinutes: 2
            ))
        }
        let fieldItemCount = items.count

        for requirement in requirementSet?.evidence ?? [] {
            guard let person = personsForRoles[requirement.personRole]
                ?? personsForRoles[template.evidenceFallbackRole] else { continue }
            items.append(MissingItem(
                id: MissingItemID("mi_\(caseID.rawValue)_\(requirement.code.lowercased())"),
                kind: .evidence,
                // The agency's own conditional language stays conditional: the
                // platform cannot resolve "if you were previously married" for
                // the user, so a conditional requirement is advisory until a
                // human says it applies.
                severity: requirement.isConditional ? .advisory : .blocking,
                assignedPersonID: person.id,
                assignedPersonLabel: person.displayLabel,
                title: requirement.requirementDescription,
                whyRequired: requirement.conditionText
                    ?? "The form instructions require this evidence.",
                citation: requirement.citation,
                resolutionPaths: [
                    ResolutionPath(kind: .scan, label: "Take a photo", estimatedMinutes: 4),
                    ResolutionPath(kind: .importFile, label: "Choose a file you already have", estimatedMinutes: 3),
                    ResolutionPath(kind: .privateRelay, label: "Ask someone to send it", estimatedMinutes: 2),
                    ResolutionPath(kind: .cannotObtain, label: "I can't get this", estimatedMinutes: 5)
                ],
                batchID: nil,
                ageDays: 0,
                requirementCode: requirement.code,
                minimumEstimatedMinutes: 2
            ))
        }

        missingItems[caseID] = items
        // itemCount is a promise the questionnaire has to keep: it counts only
        // the field items the batch actually contains, never the evidence items.
        batches[caseID] = [MissingItemBatch(
            id: batchID,
            itemCount: fieldItemCount,
            estimatedMinutes: fieldItemCount * 2,
            supportedModalities: [.chat, .voice, .form]
        )]
        ensureValueHistory(caseID: caseID)
        bumpCounters(caseID: caseID, incrementsFilledCounter: false)
    }
}
