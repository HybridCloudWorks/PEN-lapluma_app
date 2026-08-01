import Foundation

public enum InterviewModality: String, Codable, Sendable, CaseIterable {
    case chat = "CHAT"
    case voice = "VOICE"
    /// The always-available fallback. Works with every model offline.
    case form = "FORM"

    public var localizationKey: String { "modality.\(rawValue)" }
}

/// A question bound to exactly one canonical field or evidence item.
///
/// Every question declares the single field it is asking about and shows the
/// authoritative English form label alongside the user's language — the applicant is
/// filling an English form, so the English label is a correctness requirement, not a
/// courtesy.
public struct InterviewQuestion: Identifiable, Codable, Sendable, Hashable {
    public enum InputKind: String, Codable, Sendable {
        case text = "TEXT"
        case date = "DATE"
        case number = "NUMBER"
        case choice = "CHOICE"
        case address = "ADDRESS"
        case yesNo = "YES_NO"
    }

    public let id: String
    public let canonicalPath: CanonicalPath
    public let subjectPersonID: PersonID
    /// In the user's language.
    public let prompt: String
    /// The authoritative English form-field label.
    public let englishFormLabel: String
    public let formReference: String
    public let inputKind: InputKind
    public let choices: [String]?
    public let maxLength: Int?
    public let helpText: String?
    public let citation: Citation?

    public init(
        id: String,
        canonicalPath: CanonicalPath,
        subjectPersonID: PersonID,
        prompt: String,
        englishFormLabel: String,
        formReference: String,
        inputKind: InputKind,
        choices: [String]? = nil,
        maxLength: Int? = nil,
        helpText: String? = nil,
        citation: Citation? = nil
    ) {
        self.id = id
        self.canonicalPath = canonicalPath
        self.subjectPersonID = subjectPersonID
        self.prompt = prompt
        self.englishFormLabel = englishFormLabel
        self.formReference = formReference
        self.inputKind = inputKind
        self.choices = choices
        self.maxLength = maxLength
        self.helpText = helpText
        self.citation = citation
    }
}

/// One turn in an interview transcript.
public struct InterviewTurn: Identifiable, Codable, Sendable, Hashable {
    public enum Role: String, Codable, Sendable {
        case assistant
        case user
    }

    public let id: String
    public let role: Role
    public let text: String
    public let question: InterviewQuestion?
    /// True when the text is a pre-written refusal rather than generated output.
    /// A generated refusal could itself drift into advice, so refusals are static,
    /// reviewed and localised (09 §9.3).
    public let isDeterministic: Bool
    /// Set when the guardrail chain blocked a candidate utterance.
    public let guardrailBlocked: Bool
    public let timestamp: Date

    public init(
        id: String,
        role: Role,
        text: String,
        question: InterviewQuestion? = nil,
        isDeterministic: Bool = false,
        guardrailBlocked: Bool = false,
        timestamp: Date
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.question = question
        self.isDeterministic = isDeterministic
        self.guardrailBlocked = guardrailBlocked
        self.timestamp = timestamp
    }
}

/// An interview session, scoped to exactly one `Person`.
///
/// The scope is enforced at the data layer, not by prompt instruction: a query for
/// another person's answers returns empty because of the query scope (ADR-007).
public struct InterviewSession: Identifiable, Codable, Sendable {
    public let id: SessionID
    public let caseID: CaseID
    public let personID: PersonID
    public let modality: InterviewModality
    public let batchID: BatchID
    public let locale: String
    public var turns: [InterviewTurn]
    public var budget: VoiceBudget?
    public let startedAt: Date

    public init(
        id: SessionID,
        caseID: CaseID,
        personID: PersonID,
        modality: InterviewModality,
        batchID: BatchID,
        locale: String,
        turns: [InterviewTurn] = [],
        budget: VoiceBudget? = nil,
        startedAt: Date
    ) {
        self.id = id
        self.caseID = caseID
        self.personID = personID
        self.modality = modality
        self.batchID = batchID
        self.locale = locale
        self.turns = turns
        self.budget = budget
        self.startedAt = startedAt
    }
}

/// Voice is metered because real-time speech-to-speech is the most expensive primitive
/// in the stack and the natural user behaviour maximises exactly that cost (C-11).
/// The budget is surfaced honestly and never silently truncates a session.
public struct VoiceBudget: Codable, Sendable, Hashable {
    public let secondsRemaining: Int
    public let targetSeconds: Int
    /// Waived for the accessibility profile, where voice is the default modality.
    public let isWaived: Bool

    public init(secondsRemaining: Int, targetSeconds: Int, isWaived: Bool) {
        self.secondsRemaining = secondsRemaining
        self.targetSeconds = targetSeconds
        self.isWaived = isWaived
    }

    public var isExhausted: Bool { !isWaived && secondsRemaining <= 0 }
}

/// Recorded before any audio is captured. Carries the exact disclosure version shown,
/// the modality, the retention choice and the jurisdiction basis, because some states
/// require all-party consent to record a conversation (C-07).
public struct VoiceConsent: Codable, Sendable, Hashable {
    public let noticeVersion: String
    public let noticeSHA256: String
    public let spokenAndDisplayed: Bool
    /// Defaults to false. Audio is discarded at session end unless explicitly retained.
    public let retainAudioClips: Bool
    public let grantedAt: Date

    public init(
        noticeVersion: String,
        noticeSHA256: String,
        spokenAndDisplayed: Bool,
        retainAudioClips: Bool,
        grantedAt: Date
    ) {
        self.noticeVersion = noticeVersion
        self.noticeSHA256 = noticeSHA256
        self.spokenAndDisplayed = spokenAndDisplayed
        self.retainAudioClips = retainAudioClips
        self.grantedAt = grantedAt
    }
}
