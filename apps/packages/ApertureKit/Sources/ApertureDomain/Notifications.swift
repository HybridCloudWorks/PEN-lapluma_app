import Foundation

/// An in-app inbox item. **The inbox is the only surface where content appears.**
///
/// The corresponding push payload carries no case content, no form identifier and no
/// person name — only a localisation key meaning "You have an update in Aperture"
/// plus the notification id. A contract test asserts every generated APNs payload
/// matches that shape (NT-002).
public struct InboxItem: Identifiable, Codable, Sendable, Hashable {
    public enum Category: String, Codable, Sendable, CaseIterable {
        case actionRequired = "ACTION_REQUIRED"
        case documentProcessed = "DOCUMENT_PROCESSED"
        case discrepancyFound = "DISCREPANCY_FOUND"
        case reviewStatus = "REVIEW_STATUS"
        case packageReady = "PACKAGE_READY"
        case security = "SECURITY"
        case formEditionChange = "FORM_EDITION_CHANGE"
        case system = "SYSTEM"

        /// Security notifications cannot be muted, and the product says so plainly
        /// rather than silently overriding the user's preference.
        public var isSuppressible: Bool { self != .security }
        public var localizationKey: String { "notification.category.\(rawValue)" }
    }

    public let id: NotificationID
    public let category: Category
    public let title: String
    public let body: String
    public let deepLink: URL?
    public let createdAt: Date
    public var readAt: Date?

    public init(
        id: NotificationID,
        category: Category,
        title: String,
        body: String,
        deepLink: URL?,
        createdAt: Date,
        readAt: Date? = nil
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.body = body
        self.deepLink = deepLink
        self.createdAt = createdAt
        self.readAt = readAt
    }

    public var isUnread: Bool { readAt == nil }
}

/// Per-category channel preferences, quiet hours, digest and a global pause.
public struct NotificationPreferences: Codable, Sendable, Hashable {
    public enum Digest: String, Codable, Sendable, CaseIterable {
        case immediate = "IMMEDIATE"
        case daily = "DAILY"
        case weekly = "WEEKLY"
    }

    public var pushEnabled: Set<String>
    public var emailEnabled: Set<String>
    public var quietHoursStart: Int?
    public var quietHoursEnd: Int?
    public var digest: Digest
    public var pausedUntil: Date?

    public init(
        pushEnabled: Set<String> = [],
        emailEnabled: Set<String> = [],
        quietHoursStart: Int? = nil,
        quietHoursEnd: Int? = nil,
        digest: Digest = .immediate,
        pausedUntil: Date? = nil
    ) {
        self.pushEnabled = pushEnabled
        self.emailEnabled = emailEnabled
        self.quietHoursStart = quietHoursStart
        self.quietHoursEnd = quietHoursEnd
        self.digest = digest
        self.pausedUntil = pausedUntil
    }

    public var isPaused: Bool {
        guard let pausedUntil else { return false }
        return pausedUntil > Date()
    }
}

/// Granular, versioned, withdrawable per purpose. Every consent records the exact
/// notice text hash shown, and every withdrawal states its consequence *before* the
/// user confirms.
public struct ConsentRecord: Identifiable, Codable, Sendable, Hashable {
    public enum Purpose: String, Codable, Sendable, CaseIterable {
        case serviceTerms = "SERVICE_TERMS"
        case aiProcessing = "AI_PROCESSING"
        case voiceRecording = "VOICE_RECORDING"
        case voiceClipRetention = "VOICE_CLIP_RETENTION"
        case analytics = "ANALYTICS"
        case helperAccess = "HELPER_ACCESS"
        case marketing = "MARKETING"

        /// Analytics defaults to off and the product is fully functional without it.
        public var defaultsToGranted: Bool { self == .serviceTerms }
        public var isWithdrawable: Bool { self != .serviceTerms }
        public var localizationKey: String { "consent.\(rawValue)" }
        public var consequenceKey: String { "consent.\(rawValue).consequence" }
    }

    public var id: String { purpose.rawValue }
    public let purpose: Purpose
    public let granted: Bool
    public let noticeVersion: String
    public let grantedAt: Date?
    public let withdrawnAt: Date?

    public init(
        purpose: Purpose,
        granted: Bool,
        noticeVersion: String,
        grantedAt: Date?,
        withdrawnAt: Date? = nil
    ) {
        self.purpose = purpose
        self.granted = granted
        self.noticeVersion = noticeVersion
        self.grantedAt = grantedAt
        self.withdrawnAt = withdrawnAt
    }
}
