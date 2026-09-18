import Foundation
import Testing
import CoreGraphics
@testable import ApertureDomain
@testable import ApertureUI

@Suite("On-Device Neural Vision Smart Loupe & ICAO 9303 MRZ Engine Tests")
struct SmartLoupeVisionTests {

    @Test("Parses ICAO Doc 9303 TD3 Passport MRZ and verifies check digits accurately")
    func td3PassportParsingAndCheckDigits() {
        let line1 = "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<"
        let line2 = "L898902C36UTO7408122F1204159ZE184226B<<<<<10"

        let parsed = SmartLoupeVisionEngine.parseMRZ(lines: [line1, line2])

        #expect(parsed != nil)
        #expect(parsed?.format == .td3)
        #expect(parsed?.documentType == "P")
        #expect(parsed?.issuingCountry == "UTO")
        #expect(parsed?.surname == "ERIKSSON")
        #expect(parsed?.givenNames == "ANNA MARIA")
        #expect(parsed?.documentNumber == "L898902C3")
        #expect(parsed?.documentNumberCheckValid == true)
        #expect(parsed?.nationality == "UTO")
        #expect(parsed?.birthDate == "740812")
        #expect(parsed?.birthDateCheckValid == true)
        #expect(parsed?.expirationDate == "120415")
        #expect(parsed?.expirationDateCheckValid == true)
    }

    @Test("Parses ICAO Doc 9303 TD1 Permanent Resident Card MRZ accurately")
    func td1PermanentResidentCardParsing() {
        let line1 = "C1USA1234567897<<<<<<<<<<<<<<<"
        let line2 = "8001014M3001015USA<<<<<<<<<<<8"
        let line3 = "DOE<<JOHN<<<<<<<<<<<<<<<<<<<<<"

        let parsed = SmartLoupeVisionEngine.parseMRZ(lines: [line1, line2, line3])

        #expect(parsed != nil)
        #expect(parsed?.format == .td1)
        #expect(parsed?.documentType == "C1")
        #expect(parsed?.issuingCountry == "USA")
        #expect(parsed?.surname == "DOE")
        #expect(parsed?.givenNames == "JOHN")
        #expect(parsed?.documentNumber == "123456789")
        #expect(parsed?.documentNumberCheckValid == true)
        #expect(parsed?.nationality == "USA")
    }

    @Test("Check digit verification computes 7-3-1 weight modulo 10 properly")
    func checkDigitComputation() {
        // "L898902C3" with check digit 6:
        // L(21)*7 + 8*3 + 9*1 + 8*7 + 9*3 + 0*1 + 2*7 + C(12)*3 + 3*1 =
        // 147 + 24 + 9 + 56 + 27 + 0 + 14 + 36 + 3 = 316 % 10 = 6.
        let valid = SmartLoupeVisionEngine.verifyCheckDigit(value: "L898902C3", checkChar: "6")
        #expect(valid == true)

        let invalid = SmartLoupeVisionEngine.verifyCheckDigit(value: "L898902C3", checkChar: "7")
        #expect(invalid == false)
    }

    @Test("Zero-cloud-leakage local PII redaction masks SSN and Alien Registration Numbers")
    func piiRedactionPatterns() {
        let inputSSN = "Applicant SSN is 123-45-6789 on the cover sheet."
        let redactedSSN = SmartLoupeVisionEngine.redactPII(from: inputSSN)
        #expect(!redactedSSN.contains("123-45-6789"))
        #expect(redactedSSN.contains("•••-••-6789"))

        let inputANumber = "Alien Registration Number: A123456789 confirmed."
        let redactedANumber = SmartLoupeVisionEngine.redactPII(from: inputANumber)
        #expect(!redactedANumber.contains("A123456789"))
        #expect(redactedANumber.contains("A••••6789"))
    }

    @Test("SmartLoupeVisionEngine processes recognized text lines and flags classification")
    @MainActor
    func visionEngineTextProcessing() {
        let engine = SmartLoupeVisionEngine()
        #expect(engine.classification == .unknown)
        #expect(engine.isAligned == false)

        let lines = [
            ("P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<", CGRect(x: 0.1, y: 0.8, width: 0.8, height: 0.05)),
            ("L898902C36UTO7408122F1204159ZE184226B<<<<<10", CGRect(x: 0.1, y: 0.85, width: 0.8, height: 0.05)),
            ("SSN: 987-65-4321", CGRect(x: 0.1, y: 0.3, width: 0.4, height: 0.04))
        ]

        engine.processRecognizedLines(lines)

        #expect(engine.isAligned == true)
        #expect(engine.confidenceScore > 0.9)
        #expect(engine.detectedPII.count == 1)
        #expect(engine.detectedPII.first?.type == .ssn)
        #expect(engine.detectedPII.first?.redactedValue == "•••-••-4321")

        if case .passport(let country, let docNum, let surname, _) = engine.classification {
            #expect(country == "UTO")
            #expect(docNum == "L898902C3")
            #expect(surname == "ERIKSSON")
        } else {
            Issue.record("Expected passport classification, got \(engine.classification)")
        }

        engine.reset()
        #expect(engine.classification == .unknown)
        #expect(engine.detectedPII.isEmpty)
    }

    @Test("SmartLoupeVisionEngine classifies USCIS I-797 notices and extracts receipt number")
    @MainActor
    func uscisNoticeClassification() {
        let engine = SmartLoupeVisionEngine()
        let lines = [
            ("USCIS Form I-797C Notice of Action", CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.05)),
            ("Receipt Number: IOE1234567890", CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.04))
        ]

        engine.processRecognizedLines(lines)

        #expect(engine.isAligned == true)
        if case .uscisNotice(let formType, let receipt) = engine.classification {
            #expect(formType.contains("I-797"))
            #expect(receipt == "IOE1234567890")
        } else {
            Issue.record("Expected uscisNotice classification, got \(engine.classification)")
        }
    }
}
