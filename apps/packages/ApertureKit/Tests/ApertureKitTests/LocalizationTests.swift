import Foundation
import Testing
import ApertureDomain
import ApertureUI

@Suite("Explicit package localization")
struct LocalizationTests {
    @Test("Compliance copy follows an explicitly selected locale")
    func complianceCopyUsesSelectedLocale() {
        #expect(
            ApertureString("disclosure.notALawFirm", locale: Locale(identifier: "en"))
                == "LaPluma is not a law firm and does not give legal advice."
        )
        #expect(
            ApertureString("disclosure.notALawFirm", locale: Locale(identifier: "es"))
                == "LaPluma no es un bufete de abogados y no da asesoría legal."
        )
    }

    @Test("Every service-backed label resolves in English and Spanish")
    func dynamicFamiliesAreComplete() {
        var keys = CaseState.allCases.map(\.localizationKey)
        keys += InterviewModality.allCases.map(\.localizationKey)
        keys += InboxItem.Category.allCases.map(\.localizationKey)
        keys += ConsentRecord.Purpose.allCases.flatMap {
            [$0.localizationKey, $0.consequenceKey]
        }
        keys += [
            DocumentProcessingState.uploaded,
            .scanning,
            .quarantined,
            .sanitized,
            .classifying,
            .needsClassification,
            .extracting,
            .extracted,
            .extractionFailed,
            .opaqueStored,
            .deleted
        ].map(\.localizationKey)

        for key in keys {
            let localizationKey = String.LocalizationValue(key)
            #expect(ApertureString(localizationKey, locale: Locale(identifier: "en")) != key)
            #expect(ApertureString(localizationKey, locale: Locale(identifier: "es")) != key)
        }
    }

    @Test("Localized count formatting never exposes a printf token")
    func countFormatDoesNotLeakRawToken() {
        for locale in [Locale(identifier: "en"), Locale(identifier: "es")] {
            let value = ApertureFormat("progress.itemsNeedAttention", locale: locale, 2)
            #expect(value.contains("2"))
            #expect(!value.contains("%lld"))
        }
    }

    @Test("Load and empty-state copy resolves in every supported locale")
    func loadStateCopyIsLocalized() {
        let keys = [
            "error.reviewLoadFailed",
            "error.requirementsLoadFailed",
            "error.folderLoadFailed",
            "review.empty",
            "catalog.requirementsEmpty",
            "folder.empty",
            "folder.peopleEmpty",
            "folder.documentsEmpty",
            "folder.casesEmpty"
        ]

        for locale in [Locale(identifier: "en"), Locale(identifier: "es")] {
            for key in keys {
                #expect(ApertureString(String.LocalizationValue(key), locale: locale) != key)
            }
        }
    }

    @Test("A load state exposes content only after a successful load")
    func loadStateExposesOnlyLoadedValue() {
        let idle: ApertureLoadState<[String]> = .idle
        let loading: ApertureLoadState<[String]> = .loading
        let empty: ApertureLoadState<[String]> = .empty
        let failed: ApertureLoadState<[String]> = .failed
        let loaded: ApertureLoadState<[String]> = .loaded(["saved"])

        #expect(idle.value == nil)
        #expect(loading.value == nil)
        #expect(empty.value == nil)
        #expect(failed.value == nil)
        #expect(loaded.value == ["saved"])
        #expect(loading.isLoading)
        #expect(!loaded.isLoading)
    }
}
