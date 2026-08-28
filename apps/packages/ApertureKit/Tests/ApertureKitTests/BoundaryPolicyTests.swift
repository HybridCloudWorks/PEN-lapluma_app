import Foundation
import Testing
import ApertureDomain
import ApertureAPI

/// T-71: pin the exact boundaries of single-test policy code, so a drifted
/// threshold or a changed fallback fails a test instead of shipping silently.
@Suite("Policy boundaries")
struct BoundaryPolicyTests {

    // MARK: Metered capture transfer

    @Test("Deferral triggers strictly above the threshold, never at it")
    func transferThresholdBoundary() {
        let policy = CaptureTransferPolicy()
        let threshold = CaptureTransferPolicy.defaultLargeUploadThresholdBytes

        #expect(!policy.shouldDefer(
            sizeBytes: threshold, waitsForWiFi: true,
            networkIsExpensive: true, networkIsConstrained: true
        ))
        #expect(policy.shouldDefer(
            sizeBytes: threshold + 1, waitsForWiFi: true,
            networkIsExpensive: true, networkIsConstrained: false
        ))
        #expect(policy.shouldDefer(
            sizeBytes: threshold + 1, waitsForWiFi: true,
            networkIsExpensive: false, networkIsConstrained: true
        ))
    }

    @Test("A cheap unconstrained network or an opted-out user never defers")
    func transferNetworkAndPreferenceMatrix() {
        let policy = CaptureTransferPolicy()
        let large = CaptureTransferPolicy.defaultLargeUploadThresholdBytes + 1

        // The user's choice wins even for a large transfer on the worst network.
        #expect(!policy.shouldDefer(
            sizeBytes: large, waitsForWiFi: false,
            networkIsExpensive: true, networkIsConstrained: true
        ))
        // A good network never defers, whatever the size.
        #expect(!policy.shouldDefer(
            sizeBytes: large, waitsForWiFi: true,
            networkIsExpensive: false, networkIsConstrained: false
        ))
    }

    // MARK: Guided Finish plan fallbacks

    private func item(
        id: String,
        kind: MissingItem.Kind = .field,
        minimumEstimatedMinutes: Int? = nil,
        paths: [ResolutionPath] = []
    ) -> MissingItem {
        MissingItem(
            id: MissingItemID(id), kind: kind, severity: .blocking,
            assignedPersonID: PersonID("p_test"), assignedPersonLabel: "Test person",
            title: "Item \(id)", whyRequired: "Required by the instructions.",
            citation: nil, resolutionPaths: paths, batchID: nil, ageDays: 1,
            minimumEstimatedMinutes: minimumEstimatedMinutes
        )
    }

    private func relay(for itemID: String, status: EvidenceRelayStatus) -> EvidenceRelay {
        EvidenceRelay(
            id: EvidenceRelayID("relay_\(itemID)"), caseID: CaseID("c_test"),
            missingItemID: MissingItemID(itemID), requirementCode: "REQ-1",
            requestedTitle: "Requested document", subjectPersonID: PersonID("p_test"),
            createdBy: UserID("u_test"), createdAt: Date(),
            expiresAt: Date().addingTimeInterval(3_600), status: status
        )
    }

    @Test("An unsupported minutes budget falls back to ten")
    func unsupportedBudgetFallsBackToTen() {
        for (requested, expected) in [(7, 10), (0, 10), (-5, 10), (5, 5), (10, 10), (20, 20)] {
            let plan = GuidedFinishPolicy.makePlan(
                caseID: CaseID("c_test"), minutesBudget: requested,
                items: [item(id: "mi_1")], batches: [], relays: []
            )
            #expect(plan.minutesBudget == expected)
        }
    }

    @Test("The estimate falls back from the item, to its cheapest path, to its kind")
    func estimateFallbackChain() {
        let items = [
            item(id: "mi_explicit", minimumEstimatedMinutes: 3,
                 paths: [ResolutionPath(kind: .scan, label: "Scan", estimatedMinutes: 9)]),
            item(id: "mi_paths", paths: [
                ResolutionPath(kind: .scan, label: "Scan", estimatedMinutes: 4),
                ResolutionPath(kind: .importFile, label: "Import", estimatedMinutes: 2)
            ]),
            item(id: "mi_field_default", kind: .field),
            item(id: "mi_evidence_default", kind: .evidence)
        ]
        let plan = GuidedFinishPolicy.makePlan(
            caseID: CaseID("c_test"), minutesBudget: 20,
            items: items, batches: [], relays: []
        )
        let byItem = Dictionary(uniqueKeysWithValues: plan.steps.map { ($0.itemIDs[0].rawValue, $0) })
        #expect(byItem["mi_explicit"]?.estimatedMinutes == 3)
        #expect(byItem["mi_paths"]?.estimatedMinutes == 2)
        #expect(byItem["mi_field_default"]?.estimatedMinutes == 2)
        #expect(byItem["mi_evidence_default"]?.estimatedMinutes == 4)
    }

    @Test("Every relay status maps to its step status, and dead relays leave the item actionable")
    func relayStatusMapping() {
        let expectations: [(EvidenceRelayStatus, GuidedFinishStep.Status)] = [
            (.active, .waitingForRelay),
            (.locked, .relayLocked),
            (.received, .relayNeedsReview),
            (.expired, .actionable),
            (.revoked, .actionable)
        ]
        for (relayStatus, stepStatus) in expectations {
            let plan = GuidedFinishPolicy.makePlan(
                caseID: CaseID("c_test"), minutesBudget: 20,
                items: [item(id: "mi_r")], batches: [],
                relays: [relay(for: "mi_r", status: relayStatus)]
            )
            #expect(plan.steps.first?.status == stepStatus)
        }
    }

    // MARK: Delivery link liveness

    @Test("A delivery link dies at its download cap, its expiry, or revocation — not before")
    func deliveryLinkBoundaries() {
        func link(expiresIn seconds: TimeInterval, downloads: Int, max: Int, revoked: Bool) -> DeliveryLink {
            DeliveryLink(
                id: "dl_test", expiresAt: Date().addingTimeInterval(seconds),
                maxDownloads: max, downloadCount: downloads, revoked: revoked
            )
        }
        #expect(link(expiresIn: 60, downloads: 4, max: 5, revoked: false).isLive)
        #expect(!link(expiresIn: 60, downloads: 5, max: 5, revoked: false).isLive)
        #expect(!link(expiresIn: -1, downloads: 0, max: 5, revoked: false).isLive)
        #expect(!link(expiresIn: 60, downloads: 0, max: 5, revoked: true).isLive)
    }
}
