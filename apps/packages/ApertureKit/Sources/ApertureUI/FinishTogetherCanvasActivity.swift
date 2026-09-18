import Foundation
import SwiftUI
#if canImport(GroupActivities)
import GroupActivities
#endif
import ApertureDomain

/// Participant role in synchronous FaceTime SharePlay co-review session.
public enum CoReviewRole: String, Codable, Sendable {
    case caseworker = "Caseworker"
    case client = "Client"
}

/// Real-time live pointer position transmitted across SharePlay participants.
public struct CanvasPointer: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let participantName: String
    public let role: CoReviewRole
    public let normalizedX: Double
    public let normalizedY: Double
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        participantName: String,
        role: CoReviewRole,
        normalizedX: Double,
        normalizedY: Double,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.participantName = participantName
        self.role = role
        self.normalizedX = normalizedX
        self.normalizedY = normalizedY
        self.timestamp = timestamp
    }
}

/// Collaborative vector stroke drawn synchronously on the shared form canvas.
public struct CanvasStroke: Codable, Sendable, Identifiable, Equatable {
    public struct Point: Codable, Sendable, Equatable {
        public let x: Double
        public let y: Double
        public let pressure: Double

        public init(x: Double, y: Double, pressure: Double = 1.0) {
            self.x = x
            self.y = y
            self.pressure = pressure
        }
    }

    public let id: UUID
    public let authorName: String
    public let authorRole: CoReviewRole
    public let points: [Point]
    public let strokeWidth: Double
    public let colorHex: String

    public init(
        id: UUID = UUID(),
        authorName: String,
        authorRole: CoReviewRole,
        points: [Point],
        strokeWidth: Double = 2.5,
        colorHex: String = "#185ABC"
    ) {
        self.id = id
        self.authorName = authorName
        self.authorRole = authorRole
        self.points = points
        self.strokeWidth = strokeWidth
        self.colorHex = colorHex
    }
}

#if canImport(GroupActivities)
/// GroupActivity enabling synchronous caseworker-applicant "Finish Together" live session over FaceTime.
public struct FinishTogetherCanvasActivity: GroupActivity {
    public static let activityIdentifier = "app.lapluma.finish-together.canvas"

    public let caseID: String
    public let packageTitle: String

    public init(caseID: String, packageTitle: String) {
        self.caseID = caseID
        self.packageTitle = packageTitle
    }

    public var metadata: GroupActivityMetadata {
        var meta = GroupActivityMetadata()
        meta.title = "Finish Together: \(packageTitle)"
        meta.type = .generic
        return meta
    }
}
#endif

/// State manager for the SharePlay Synchronous Caseworker-Client Live Review Canvas.
@MainActor
public final class SharePlayLiveCanvasModel: ObservableObject {
    @Published public private(set) var isSharePlayActive: Bool = false
    @Published public private(set) var activeParticipants: [CanvasPointer] = []
    @Published public private(set) var strokes: [CanvasStroke] = []
    @Published public private(set) var activePage: Int = 1
    @Published public var focusedFieldCanonicalPath: String?

    public let caseID: String
    public let localParticipantName: String
    public let localRole: CoReviewRole

    public init(
        caseID: String,
        localParticipantName: String = "Saul (Caseworker)",
        localRole: CoReviewRole = .caseworker
    ) {
        self.caseID = caseID
        self.localParticipantName = localParticipantName
        self.localRole = localRole
    }

    public func startLocalSession() {
        isSharePlayActive = true
    }

    public func updateLocalPointer(x: Double, y: Double) {
        let pointer = CanvasPointer(
            participantName: localParticipantName,
            role: localRole,
            normalizedX: x,
            normalizedY: y
        )
        // Update local state and prepare for broadcast
        if let idx = activeParticipants.firstIndex(where: { $0.participantName == localParticipantName }) {
            activeParticipants[idx] = pointer
        } else {
            activeParticipants.append(pointer)
        }
    }

    public func appendStroke(_ stroke: CanvasStroke) {
        strokes.append(stroke)
    }

    public func clearStrokes() {
        strokes.removeAll()
    }

    public func setPage(_ page: Int) {
        activePage = page
    }

    public func endSession() {
        isSharePlayActive = false
        activeParticipants.removeAll()
        strokes.removeAll()
    }
}
