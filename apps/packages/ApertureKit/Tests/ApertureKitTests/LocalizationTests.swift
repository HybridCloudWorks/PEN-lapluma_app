import Foundation
import Testing
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
}
