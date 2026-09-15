import Foundation

/// Declarative condition operator for conditional Blueprint sections, fields and evidence.
public enum BlueprintConditionOperator: String, Codable, Sendable, CaseIterable {
    case equals = "equals"
    case notEquals = "not_equals"
    case isSet = "is_set"
    case isNotSet = "is_not_set"
    case inValues = "in"
}

/// Declarative condition evaluated against canonical and draft form field values.
public struct BlueprintCondition: Codable, Sendable, Hashable {
    public let field: String
    public let `operator`: BlueprintConditionOperator
    public let value: String?
    public let values: [String]?

    public init(field: String, operator: BlueprintConditionOperator, value: String? = nil, values: [String]? = nil) {
        self.field = field
        self.operator = `operator`
        self.value = value
        self.values = values
    }

    /// Evaluates the condition against current field values.
    public func evaluate(against fieldValues: [String: String]) -> Bool {
        let current = fieldValues[field]?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch `operator` {
        case .equals:
            guard let current, !current.isEmpty else { return false }
            return current.caseInsensitiveCompare(value ?? "") == .orderedSame
        case .notEquals:
            guard let current, !current.isEmpty else { return true }
            return current.caseInsensitiveCompare(value ?? "") != .orderedSame
        case .isSet:
            return current != nil && !(current!.isEmpty)
        case .isNotSet:
            return current == nil || current!.isEmpty
        case .inValues:
            guard let current, !current.isEmpty, let allowed = values else { return false }
            return allowed.contains { $0.caseInsensitiveCompare(current) == .orderedSame }
        }
    }
}

/// Strategy for repeated collections exceeding primary form capacity.
public enum BlueprintOverflowStrategy: String, Codable, Sendable, CaseIterable {
    case attachmentAddendum = "ATTACHMENT_ADDENDUM"
    case truncateError = "TRUNCATE_ERROR"
    case splitPages = "SPLIT_PAGES"
}

/// Declarative section in a Document Blueprint.
public struct BlueprintSection: Identifiable, Codable, Sendable, Hashable {
    public var id: String { sectionId }

    public let sectionId: String
    public let title: String
    public let description: String?
    public let isRepeatable: Bool
    public let maxOccurs: Int
    public let overflowStrategy: BlueprintOverflowStrategy?
    public let condition: BlueprintCondition?

    public init(
        sectionId: String,
        title: String,
        description: String? = nil,
        isRepeatable: Bool = false,
        maxOccurs: Int = 1,
        overflowStrategy: BlueprintOverflowStrategy? = nil,
        condition: BlueprintCondition? = nil
    ) {
        self.sectionId = sectionId
        self.title = title
        self.description = description
        self.isRepeatable = isRepeatable
        self.maxOccurs = maxOccurs
        self.overflowStrategy = overflowStrategy
        self.condition = condition
    }

    public func isVisible(against fieldValues: [String: String]) -> Bool {
        guard let condition else { return true }
        return condition.evaluate(against: fieldValues)
    }
}

/// Declarative data types for Blueprint fields.
public enum BlueprintFieldType: String, Codable, Sendable, CaseIterable {
    case string = "string"
    case date = "date"
    case boolean = "boolean"
    case choice = "choice"
    case signature = "signature"
    case number = "number"
}

/// Declarative field in a Document Blueprint.
public struct BlueprintField: Identifiable, Codable, Sendable, Hashable {
    public var id: String { canonicalPath }

    public let canonicalPath: String
    public let sectionId: String
    public let type: BlueprintFieldType
    public let label: String
    public let required: Bool
    public let maxLength: Int?
    public let characterSet: String?
    public let choices: [String]?
    public let attributedRole: String?
    public let pdfFieldMapping: String?
    public let condition: BlueprintCondition?

    public init(
        canonicalPath: String,
        sectionId: String,
        type: BlueprintFieldType,
        label: String,
        required: Bool = false,
        maxLength: Int? = nil,
        characterSet: String? = nil,
        choices: [String]? = nil,
        attributedRole: String? = nil,
        pdfFieldMapping: String? = nil,
        condition: BlueprintCondition? = nil
    ) {
        self.canonicalPath = canonicalPath
        self.sectionId = sectionId
        self.type = type
        self.label = label
        self.required = required
        self.maxLength = maxLength
        self.characterSet = characterSet
        self.choices = choices
        self.attributedRole = attributedRole
        self.pdfFieldMapping = pdfFieldMapping
        self.condition = condition
    }

    public func isVisible(against fieldValues: [String: String]) -> Bool {
        guard let condition else { return true }
        return condition.evaluate(against: fieldValues)
    }
}

/// Declarative validation rule in a Document Blueprint.
public struct BlueprintValidationRule: Identifiable, Codable, Sendable, Hashable {
    public var id: String { ruleId }

    public let ruleId: String
    public let type: String
    public let expression: String
    public let errorMessage: String?

    public init(ruleId: String, type: String, expression: String, errorMessage: String? = nil) {
        self.ruleId = ruleId
        self.type = type
        self.expression = expression
        self.errorMessage = errorMessage
    }
}

/// Declarative evidence requirement in a Document Blueprint.
public struct BlueprintEvidenceRequirement: Identifiable, Codable, Sendable, Hashable {
    public var id: String { code }

    public let code: String
    public let title: String
    public let attributedRole: String
    public let isConditional: Bool
    public let acceptedMimeTypes: [String]
    public let condition: BlueprintCondition?

    public init(
        code: String,
        title: String,
        attributedRole: String,
        isConditional: Bool = false,
        acceptedMimeTypes: [String] = ["application/pdf", "image/jpeg", "image/png"],
        condition: BlueprintCondition? = nil
    ) {
        self.code = code
        self.title = title
        self.attributedRole = attributedRole
        self.isConditional = isConditional
        self.acceptedMimeTypes = acceptedMimeTypes
        self.condition = condition
    }

    public func isRequired(against fieldValues: [String: String]) -> Bool {
        if !isConditional { return true }
        guard let condition else { return true }
        return condition.evaluate(against: fieldValues)
    }
}

/// Complete declarative Document Blueprint conforming to document-blueprint.schema.json (INF-17, APP-05).
public struct BlueprintDefinition: Identifiable, Codable, Sendable, Hashable {
    public var id: String { "\(namespace)/\(blueprintId)@r\(revision)" }

    public let namespace: String
    public let blueprintId: String
    public let revision: Int
    public let title: String
    public let issuer: String
    public let officialEditionDate: Date?
    public let preparationMode: PreparationMode
    public let artifactType: BlueprintArtifactType
    public let accessScope: String
    public let sourceUrl: URL?
    public let sourceSha256: String?
    public let sections: [BlueprintSection]
    public let fields: [BlueprintField]
    public let validationRules: [BlueprintValidationRule]
    public let evidenceRequirements: [BlueprintEvidenceRequirement]

    public init(
        namespace: String,
        blueprintId: String,
        revision: Int,
        title: String,
        issuer: String,
        officialEditionDate: Date? = nil,
        preparationMode: PreparationMode,
        artifactType: BlueprintArtifactType,
        accessScope: String = "SHARED_OFFICIAL",
        sourceUrl: URL? = nil,
        sourceSha256: String? = nil,
        sections: [BlueprintSection] = [],
        fields: [BlueprintField] = [],
        validationRules: [BlueprintValidationRule] = [],
        evidenceRequirements: [BlueprintEvidenceRequirement] = []
    ) {
        self.namespace = namespace
        self.blueprintId = blueprintId
        self.revision = revision
        self.title = title
        self.issuer = issuer
        self.officialEditionDate = officialEditionDate
        self.preparationMode = preparationMode
        self.artifactType = artifactType
        self.accessScope = accessScope
        self.sourceUrl = sourceUrl
        self.sourceSha256 = sourceSha256
        self.sections = sections
        self.fields = fields
        self.validationRules = validationRules
        self.evidenceRequirements = evidenceRequirements
    }

    /// Verifies declarative safety: rejects any configuration that contains executable behavior (APP-05).
    public static func validateDeclarativeSafety(_ blueprint: BlueprintDefinition) throws {
        let suspicious = ["<script", "javascript:", "eval\u{0028}", "exec\u{0028}", "__import__", "os.system"]
        let allText = [
            blueprint.namespace,
            blueprint.blueprintId,
            blueprint.title,
            blueprint.issuer,
            blueprint.accessScope,
            blueprint.sourceUrl?.absoluteString ?? "",
            blueprint.sourceSha256 ?? ""
        ] + blueprint.sections.map { "\($0.sectionId) \($0.title) \($0.description ?? "")" }
          + blueprint.fields.map { "\($0.canonicalPath) \($0.label) \($0.characterSet ?? "") \($0.pdfFieldMapping ?? "")" }
          + blueprint.validationRules.map { "\($0.ruleId) \($0.type) \($0.expression) \($0.errorMessage ?? "")" }
          + blueprint.evidenceRequirements.map { "\($0.code) \($0.title) \($0.attributedRole)" }

        for text in allText {
            let lower = text.lowercased()
            for token in suspicious {
                if lower.contains(token) {
                    throw BlueprintSafetyError.executableConfigurationRejected(
                        detail: "Blueprint configuration may not contain executable code or script references."
                    )
                }
            }
        }
    }
}

/// Errors raised during Blueprint validation and safety checks (APP-05).
public enum BlueprintSafetyError: Error, Sendable, LocalizedError {
    case executableConfigurationRejected(detail: String)

    public var errorDescription: String? {
        switch self {
        case .executableConfigurationRejected(let detail):
            return "Executable Blueprint configuration rejected: \(detail)"
        }
    }
}
