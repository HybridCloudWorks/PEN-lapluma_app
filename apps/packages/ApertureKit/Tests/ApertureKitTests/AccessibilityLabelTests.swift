import Foundation
import Testing
import ApertureDomain
@testable import ApertureUI

/// The combined VoiceOver labels must carry everything the visible layout shows.
/// Both views override `.combine` with an explicit label, so an omission here is
/// silent for sighted users and total for VoiceOver users.
@Suite("Combined accessibility labels")
@MainActor
struct AccessibilityLabelTests {
    @Test("Counters label speaks the blocking-items warning and the caveat")
    func countersLabelIncludesBlockingItems() {
        let counters = ProgressCounters(
            fieldsFilled: 174, fieldsRequired: 218,
            documentsCollected: 7, documentsRequired: 11,
            blockingItems: 6, advisoryItems: 3
        )
        let label = ProgressCountersView(counters).accessibilityText

        let attention = String.localizedStringWithFormat(
            ApertureString("progress.itemsNeedAttention"), 6
        )
        #expect(label.contains(attention))
        #expect(label.contains(ApertureString("disclosure.readinessNotPrediction")))
        // The warning branch is exclusive with readiness.
        #expect(!label.contains(ApertureString("progress.readyToFile")))
    }

    @Test("Counters label speaks readiness when nothing blocks")
    func countersLabelIncludesReadiness() {
        let counters = ProgressCounters(
            fieldsFilled: 218, fieldsRequired: 218,
            documentsCollected: 11, documentsRequired: 11,
            blockingItems: 0, advisoryItems: 3
        )
        #expect(counters.isReadyToFile)
        let label = ProgressCountersView(counters).accessibilityText
        #expect(label.contains(ApertureString("progress.readyToFile")))
    }

    @Test("Counters label omits the caveat only when the view does")
    func countersLabelHonorsCaveatVisibility() {
        let counters = ProgressCounters(
            fieldsFilled: 1, fieldsRequired: 2,
            documentsCollected: 1, documentsRequired: 2,
            blockingItems: 0, advisoryItems: 0
        )
        let caveat = ApertureString("disclosure.readinessNotPrediction")
        #expect(ProgressCountersView(counters, showsCaveat: true)
            .accessibilityText.contains(caveat))
        #expect(!ProgressCountersView(counters, showsCaveat: false)
            .accessibilityText.contains(caveat))
    }

    @Test("Bilingual label speaks primary, English, and the form reference")
    func bilingualLabelIncludesFormReference() {
        let label = BilingualLabel(
            primary: "Apellido",
            english: "Family name",
            formReference: "I-130 Part 2, Item 4"
        ).accessibilityText
        #expect(label == "Apellido. Family name. I-130 Part 2, Item 4")
    }

    @Test("Bilingual label does not repeat identical languages or invent a reference")
    func bilingualLabelOmitsAbsentParts() {
        #expect(BilingualLabel(primary: "Name", english: "Name").accessibilityText == "Name")
        #expect(BilingualLabel(primary: "Nombre", english: "Given name")
            .accessibilityText == "Nombre. Given name")
    }
}
