import Foundation
import Testing
@testable import ApertureDomain

@Suite("Interview Entity Extractor & Validation Tests")
struct InterviewValidationTests {

    @Test("1/32/2007 is strictly rejected because January only has 31 days")
    func rejectsJanuary32() {
        let question = InterviewQuestion(
            id: "q_last_entry_date",
            canonicalPath: CanonicalPath("person.entry.lastDate"),
            subjectPersonID: PersonID("p_carlos"),
            prompt: "When did you last enter the US?",
            englishFormLabel: "Date of Last Arrival",
            formReference: "I-130 Part 4, Item 46.a",
            inputKind: .date
        )

        let result = InterviewEntityExtractor.validate(answer: "1/32/2007", for: question, locale: "en_US")
        #expect(!result.isValid)
        if case let .invalid(prompt, raw) = result {
            #expect(raw == "1/32/2007")
            #expect(prompt.contains("31 days"))
            #expect(prompt.contains("not a valid calendar date"))
        } else {
            Issue.record("Expected 1/32/2007 to be invalid")
        }
    }

    @Test("Spanish rejection explains January days in Spanish")
    func rejectsJanuary32Spanish() {
        let question = InterviewQuestion(
            id: "q_last_entry_date",
            canonicalPath: CanonicalPath("person.entry.lastDate"),
            subjectPersonID: PersonID("p_carlos"),
            prompt: "¿En qué fecha entró por última vez?",
            englishFormLabel: "Date of Last Arrival",
            formReference: "I-130 Part 4, Item 46.a",
            inputKind: .date
        )

        let result = InterviewEntityExtractor.validate(answer: "1/32/2007", for: question, locale: "es_MX")
        #expect(!result.isValid)
        if case let .invalid(prompt, _) = result {
            #expect(prompt.contains("Enero solo tiene 31 días"))
        } else {
            Issue.record("Expected 1/32/2007 to be invalid in Spanish")
        }
    }

    @Test("February 29 in non-leap year 2023 is rejected")
    func rejectsFeb29NonLeapYear() {
        let result = InterviewEntityExtractor.validateDate(input: "02/29/2023", isSpanish: false)
        #expect(!result.isValid)
        if case let .invalid(prompt, _) = result {
            #expect(prompt.contains("February only had 28 days in 2023"))
        } else {
            Issue.record("Expected 02/29/2023 to be rejected")
        }
    }

    @Test("February 29 in leap year 2024 is accepted")
    func acceptsFeb29LeapYear() {
        let result = InterviewEntityExtractor.validateDate(input: "02/29/2024", isSpanish: false)
        #expect(result.isValid)
        #expect(result.normalizedValue == "02/29/2024")
    }

    @Test("Valid date formats normalize to MM/DD/YYYY")
    func normalizesValidDates() {
        let question = InterviewQuestion(
            id: "q_last_entry_date",
            canonicalPath: CanonicalPath("person.entry.lastDate"),
            subjectPersonID: PersonID("p_carlos"),
            prompt: "Arrival date",
            englishFormLabel: "Date of Last Arrival",
            formReference: "I-130",
            inputKind: .date
        )

        let r1 = InterviewEntityExtractor.validate(answer: "01/15/2007", for: question, locale: "en_US")
        #expect(r1.isValid)
        #expect(r1.normalizedValue == "01/15/2007")

        let r2 = InterviewEntityExtractor.validate(answer: "2020-03-04", for: question, locale: "en_US")
        #expect(r2.isValid)
        #expect(r2.normalizedValue == "03/04/2020")

        let r3 = InterviewEntityExtractor.validate(answer: "I arrived on January 15, 2007", for: question, locale: "en_US")
        #expect(r3.isValid)
        #expect(r3.normalizedValue == "01/15/2007")
    }

    @Test("Rejects gibberish and non-dates for date questions")
    func rejectsNonDates() {
        let question = InterviewQuestion(
            id: "q_last_entry_date",
            canonicalPath: CanonicalPath("person.entry.lastDate"),
            subjectPersonID: PersonID("p_carlos"),
            prompt: "Arrival date",
            englishFormLabel: "Date of Last Arrival",
            formReference: "I-130",
            inputKind: .date
        )

        let r1 = InterviewEntityExtractor.validate(answer: "blue", for: question, locale: "en_US")
        #expect(!r1.isValid)

        let r2 = InterviewEntityExtractor.validate(answer: "13/45/2020", for: question, locale: "en_US")
        #expect(!r2.isValid)
    }

    @Test("Name validation extracts valid names and rejects pure numbers")
    func validatesNames() {
        let question = InterviewQuestion(
            id: "q_family_name",
            canonicalPath: CanonicalPath("person.name.family"),
            subjectPersonID: PersonID("p_carlos"),
            prompt: "Family name",
            englishFormLabel: "Family Name",
            formReference: "I-130",
            inputKind: .text
        )

        let r1 = InterviewEntityExtractor.validate(answer: "Ramírez", for: question, locale: "en_US")
        #expect(r1.isValid)
        #expect(r1.normalizedValue == "Ramírez")

        let r2 = InterviewEntityExtractor.validate(answer: "My family name is Gomez", for: question, locale: "en_US")
        #expect(r2.isValid)
        #expect(r2.normalizedValue == "Gomez")

        let r3 = InterviewEntityExtractor.validate(answer: "12345", for: question, locale: "en_US")
        #expect(!r3.isValid)
    }

    @Test("City validation extracts city names and rejects invalid text")
    func validatesCities() {
        let question = InterviewQuestion(
            id: "q_birth_city",
            canonicalPath: CanonicalPath("person.birth.city"),
            subjectPersonID: PersonID("p_carlos"),
            prompt: "Birth city",
            englishFormLabel: "City of Birth",
            formReference: "I-130",
            inputKind: .text
        )

        let r1 = InterviewEntityExtractor.validate(answer: "Quetzaltenango", for: question, locale: "en_US")
        #expect(r1.isValid)
        #expect(r1.normalizedValue == "Quetzaltenango")

        let r2 = InterviewEntityExtractor.validate(answer: "Born in Monterrey", for: question, locale: "en_US")
        #expect(r2.isValid)
        #expect(r2.normalizedValue == "Monterrey")

        let r3 = InterviewEntityExtractor.validate(answer: "12345", for: question, locale: "en_US")
        #expect(!r3.isValid)
    }
}
