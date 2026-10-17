import Combine
import Foundation
import Testing
import CoreGraphics
import Synchronization
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
    func visionEngineTextProcessing() async {
        let engine = SmartLoupeVisionEngine()
        #expect(engine.classification == .unknown)
        #expect(engine.isAligned == false)

        let lines = [
            ("P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<", CGRect(x: 0.1, y: 0.8, width: 0.8, height: 0.05)),
            ("L898902C36UTO7408122F1204159ZE184226B<<<<<10", CGRect(x: 0.1, y: 0.85, width: 0.8, height: 0.05)),
            ("SSN: 987-65-4321", CGRect(x: 0.1, y: 0.3, width: 0.4, height: 0.04))
        ]

        await engine.processRecognizedLines(lines)

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
    func uscisNoticeClassification() async {
        let engine = SmartLoupeVisionEngine()
        let lines = [
            ("USCIS Form I-797C Notice of Action", CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.05)),
            ("Receipt Number: IOE1234567890", CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.04))
        ]

        await engine.processRecognizedLines(lines)

        #expect(engine.isAligned == true)
        if case .uscisNotice(let formType, let receipt) = engine.classification {
            #expect(formType.contains("I-797"))
            #expect(receipt == "IOE1234567890")
        } else {
            Issue.record("Expected uscisNotice classification, got \(engine.classification)")
        }
    }

    // MARK: - APP-17: off-main parsing, throttling, one coalesced update

    private static let passportFrame = [
        SmartLoupeTextLine(text: "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<", boundingBox: CGRect(x: 0.1, y: 0.8, width: 0.8, height: 0.05)),
        SmartLoupeTextLine(text: "L898902C36UTO7408122F1204159ZE184226B<<<<<10", boundingBox: CGRect(x: 0.1, y: 0.85, width: 0.8, height: 0.05)),
        SmartLoupeTextLine(text: "SSN: 987-65-4321", boundingBox: CGRect(x: 0.1, y: 0.3, width: 0.4, height: 0.04))
    ]

    private static var passportTuples: [(text: String, boundingBox: CGRect)] {
        passportFrame.map { (text: $0.text, boundingBox: $0.boundingBox) }
    }

    @Test("Parsing runs off the main actor and a processed frame publishes exactly once")
    @MainActor
    func parsingRunsOffMainActorAndPublishesOnce() async {
        let probe = AnalysisProbe()
        let engine = SmartLoupeVisionEngine(minimumFrameInterval: .zero) { lines in
            probe.record(onMainThread: Thread.isMainThread)
            return SmartLoupeVisionEngine.analyze(lines)
        }
        let publishes = PublishCounter()
        let subscription = engine.objectWillChange.sink { _ in publishes.value += 1 }
        defer { subscription.cancel() }

        await engine.processRecognizedLines(Self.passportTuples)

        // The analyzer ran once, and not on the main thread.
        #expect(probe.mainThreadFlags == [false])
        // Classification, PII, MRZ, alignment and confidence changed together:
        // one invalidation, where the per-field implementation emitted five.
        #expect(publishes.value == 1)
        #expect(engine.isAligned)
        #expect(engine.confidenceScore > 0.9)
        #expect(engine.detectedPII.count == 1)
        #expect(engine.mrzPayload?.documentNumber == "L898902C3")
    }

    @Test("Live frames are dropped, not queued, while one is in flight or inside the interval")
    @MainActor
    func liveFramesAreThrottledAndCoalesced() async {
        let probe = AnalysisProbe()
        let engine = SmartLoupeVisionEngine(minimumFrameInterval: .seconds(60)) { lines in
            probe.record(onMainThread: Thread.isMainThread)
            return SmartLoupeVisionEngine.analyze(lines)
        }
        let publishes = PublishCounter()
        let subscription = engine.objectWillChange.sink { _ in publishes.value += 1 }
        defer { subscription.cancel() }

        // One second of a 60 fps camera feed.
        let admitted = engine.submitFrame(Self.passportFrame)
        #expect(admitted != nil)
        var dropped = 0
        for _ in 1..<60 {
            if engine.submitFrame(Self.passportFrame) == nil {
                dropped += 1
            }
        }
        #expect(dropped == 59)

        await admitted?.value

        #expect(probe.mainThreadFlags == [false])
        #expect(publishes.value == 1)
        #expect(engine.isAligned)
        // Still inside the interval after the admitted frame finished.
        #expect(engine.submitFrame(Self.passportFrame) == nil)
    }

    @Test("The frame gate admits again once the in-flight frame finishes and the interval passes")
    func frameGateReadmitsAfterFinishAndInterval() {
        let gate = SmartLoupeFrameGate(minimumInterval: .zero)
        #expect(gate.tryAdmit() != nil)
        #expect(gate.tryAdmit() == nil, "a second frame must be dropped while one is in flight")
        gate.finish()
        #expect(gate.tryAdmit() != nil)
        gate.finish()

        let throttled = SmartLoupeFrameGate(minimumInterval: .seconds(60))
        #expect(throttled.tryAdmit() != nil)
        throttled.finish()
        #expect(throttled.tryAdmit() == nil, "a frame inside the minimum interval must be dropped")
    }

    @Test("reset() discards an analysis that lands after it")
    @MainActor
    func resetDiscardsInFlightAnalysis() async {
        let engine = SmartLoupeVisionEngine(minimumFrameInterval: .zero)
        let inFlight = engine.submitFrame(Self.passportFrame)
        engine.reset()
        await inFlight?.value

        #expect(engine.classification == .unknown)
        #expect(engine.detectedPII.isEmpty)
        #expect(engine.mrzPayload == nil)
        #expect(engine.isAligned == false)
    }

    @Test("A frame without an MRZ keeps the last decoded MRZ, as the per-field engine did")
    @MainActor
    func lastDecodedMRZIsHeldUntilReset() async {
        let engine = SmartLoupeVisionEngine(minimumFrameInterval: .zero)
        await engine.processRecognizedLines(Self.passportTuples)
        await engine.processRecognizedLines([
            ("USCIS Form I-797C Notice of Action", CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.05))
        ])

        if case .uscisNotice = engine.classification {} else {
            Issue.record("Expected uscisNotice classification, got \(engine.classification)")
        }
        #expect(engine.mrzPayload?.documentNumber == "L898902C3")

        engine.reset()
        #expect(engine.mrzPayload == nil)
    }

    @Test("analyze(_:) is pure: the same frame yields the same classification on any executor")
    func analyzeIsPureAndExecutorIndependent() async {
        let onMain = await MainActor.run { SmartLoupeVisionEngine.analyze(Self.passportFrame) }
        let detached = await Task.detached { SmartLoupeVisionEngine.analyze(Self.passportFrame) }.value
        #expect(onMain.classification == detached.classification)
        #expect(onMain.mrzPayload == detached.mrzPayload)
        #expect(onMain.detectedPII.map(\.redactedValue) == detached.detectedPII.map(\.redactedValue))
        #expect(onMain.isAligned == detached.isAligned)
        #expect(onMain.confidenceScore == detached.confidenceScore)
    }
}

/// Records, from whichever thread the analyzer runs on, whether that was the main thread.
private final class AnalysisProbe: Sendable {
    private let flags = Mutex<[Bool]>([])

    func record(onMainThread: Bool) {
        flags.withLock { $0.append(onMainThread) }
    }

    var mainThreadFlags: [Bool] {
        flags.withLock { $0 }
    }
}

/// Counts `objectWillChange` emissions; only touched on the main actor.
@MainActor
private final class PublishCounter {
    var value = 0
}
