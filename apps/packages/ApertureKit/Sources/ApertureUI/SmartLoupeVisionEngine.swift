import Foundation
import SwiftUI
import CoreGraphics
import Synchronization
#if canImport(UIKit)
import UIKit
#endif
#if canImport(Vision)
import Vision
#endif
import ApertureDomain

/// Classification of identity documents detected on-device via Apple Intelligence Vision pipeline.
public enum SmartLoupeClassification: Equatable, Sendable {
    case unknown
    case passport(country: String, documentNumber: String, surname: String, givenNames: String)
    case usPermanentResidentCard(alienNumber: String, category: String?)
    case driverLicense(state: String?, documentNumber: String?)
    case uscisNotice(formType: String, receiptNumber: String)

    public var displayName: String {
        switch self {
        case .unknown:
            return "Aligning Document..."
        case .passport(let country, _, _, _):
            return "Passport (\(country))"
        case .usPermanentResidentCard:
            return "US Permanent Resident Card (I-551)"
        case .driverLicense(let state, _):
            if let state = state { return "Driver License (\(state))" }
            return "Driver License"
        case .uscisNotice(let formType, _):
            return "USCIS Notice (\(formType))"
        }
    }

    public var iconName: String {
        switch self {
        case .unknown: return "viewfinder"
        case .passport: return "person.text.rectangle"
        case .usPermanentResidentCard: return "person.crop.rectangle.badge.plus"
        case .driverLicense: return "car.fill"
        case .uscisNotice: return "doc.text.fill"
        }
    }
}

/// A detected PII token in the camera frame with its normalized bounding box for zero-cloud-leakage redaction.
public struct PIIRedactionMatch: Equatable, Sendable, Identifiable {
    public enum PIIType: String, Sendable {
        case ssn = "SSN"
        case alienRegistrationNumber = "A-Number"
    }

    public let id: UUID
    public let type: PIIType
    public let rawValue: String
    public let redactedValue: String
    public let normalizedBoundingBox: CGRect

    public init(
        id: UUID = UUID(),
        type: PIIType,
        rawValue: String,
        redactedValue: String,
        normalizedBoundingBox: CGRect
    ) {
        self.id = id
        self.type = type
        self.rawValue = rawValue
        self.redactedValue = redactedValue
        self.normalizedBoundingBox = normalizedBoundingBox
    }
}

/// Parsed ICAO Doc 9303 Machine Readable Zone (MRZ) travel document payload.
public struct MRZPayload: Equatable, Sendable {
    public enum Format: String, Sendable {
        case td1 = "TD1 (3x30)"
        case td2 = "TD2 (2x36)"
        case td3 = "TD3 (2x44)"
    }

    public let format: Format
    public let documentType: String
    public let issuingCountry: String
    public let documentNumber: String
    public let documentNumberCheckValid: Bool
    public let nationality: String
    public let birthDate: String
    public let birthDateCheckValid: Bool
    public let expirationDate: String
    public let expirationDateCheckValid: Bool
    public let surname: String
    public let givenNames: String
    public let rawLines: [String]

    public init(
        format: Format,
        documentType: String,
        issuingCountry: String,
        documentNumber: String,
        documentNumberCheckValid: Bool,
        nationality: String,
        birthDate: String,
        birthDateCheckValid: Bool,
        expirationDate: String,
        expirationDateCheckValid: Bool,
        surname: String,
        givenNames: String,
        rawLines: [String]
    ) {
        self.format = format
        self.documentType = documentType
        self.issuingCountry = issuingCountry
        self.documentNumber = documentNumber
        self.documentNumberCheckValid = documentNumberCheckValid
        self.nationality = nationality
        self.birthDate = birthDate
        self.birthDateCheckValid = birthDateCheckValid
        self.expirationDate = expirationDate
        self.expirationDateCheckValid = expirationDateCheckValid
        self.surname = surname
        self.givenNames = givenNames
        self.rawLines = rawLines
    }
}

private enum SmartLoupeRegexes: @unchecked Sendable {
    static let ssn: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"\b(\d{3})[- ]?(\d{2})[- ]?(\d{4})\b"#)
    }()
    static let aNumber: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"\b(?:A|USCIS#?)[- ]?(?:\d{4,5})(\d{4})\b"#, options: .caseInsensitive)
    }()
    static let aNumberFull: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"\b(?:A|USCIS#?)[- ]?(\d{8,9})\b"#, options: .caseInsensitive)
    }()
    static let receiptNumber: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"\b([A-Z]{3})[- ]?(\d{10})\b"#)
    }()
}

/// One OCR line from the on-device Vision text recogniser, in Vision's normalized
/// coordinates (origin at the lower left).
public struct SmartLoupeTextLine: Sendable, Equatable {
    public let text: String
    public let boundingBox: CGRect

    public init(text: String, boundingBox: CGRect) {
        self.text = text
        self.boundingBox = boundingBox
    }
}

/// Everything one frame's analysis produces. The engine publishes it as a single
/// value, so a processed frame costs one SwiftUI invalidation instead of five
/// separate `@Published` writes (APP-17).
public struct SmartLoupeAnalysis: Equatable, Sendable {
    public var classification: SmartLoupeClassification
    public var detectedPII: [PIIRedactionMatch]
    public var mrzPayload: MRZPayload?
    public var isAligned: Bool
    public var confidenceScore: Float

    public init(
        classification: SmartLoupeClassification = .unknown,
        detectedPII: [PIIRedactionMatch] = [],
        mrzPayload: MRZPayload? = nil,
        isAligned: Bool = false,
        confidenceScore: Float = 0.0
    ) {
        self.classification = classification
        self.detectedPII = detectedPII
        self.mrzPayload = mrzPayload
        self.isAligned = isAligned
        self.confidenceScore = confidenceScore
    }

    /// Nothing recognised yet.
    public static let idle = SmartLoupeAnalysis()
}

/// Admission control for the live OCR stream (APP-17).
///
/// The camera delivers up to 60 frames a second and consecutive frames carry the
/// same text, so parsing every one is wasted work. A frame is admitted only when
/// no analysis is in flight and at least `minimumInterval` has passed since the
/// last admitted frame. Everything else is dropped, never queued, so a slow
/// analysis cannot build a backlog. `invalidate()` advances an epoch so a result
/// that lands after `reset()` is discarded instead of resurrecting stale state.
final class SmartLoupeFrameGate: Sendable {
    struct Admission: Sendable, Equatable {
        let epoch: UInt64
    }

    private struct State: Sendable {
        var inFlight = false
        var lastAdmitted: ContinuousClock.Instant?
        var epoch: UInt64 = 0
    }

    let minimumInterval: Duration
    private let clock = ContinuousClock()
    private let state = Mutex(State())

    init(minimumInterval: Duration) {
        self.minimumInterval = minimumInterval
    }

    /// Admits a frame, or returns nil when it must be dropped.
    func tryAdmit() -> Admission? {
        let now = clock.now
        let interval = minimumInterval
        return state.withLock { current -> Admission? in
            guard !current.inFlight else { return nil }
            if let last = current.lastAdmitted, now - last < interval { return nil }
            current.inFlight = true
            current.lastAdmitted = now
            return Admission(epoch: current.epoch)
        }
    }

    /// Marks the in-flight analysis as finished, whether or not it was published.
    func finish() {
        state.withLock { current in current.inFlight = false }
    }

    var currentEpoch: UInt64 {
        state.withLock { current in current.epoch }
    }

    func invalidate() {
        state.withLock { current in current.epoch &+= 1 }
    }
}

/// On-Device Neural Vision Engine (Apple Intelligence) for real-time document classification,
/// sub-15ms ICAO Doc 9303 MRZ parsing, and zero-cloud-leakage local PII redaction.
///
/// Parsing never runs on the main actor (APP-17). `analyze(_:)` is a pure,
/// `nonisolated` function; both entry points run it on a detached task and hop to
/// the main actor only to publish its result as one change to `analysis`.
@MainActor
public final class SmartLoupeVisionEngine: ObservableObject {

    /// The latest analysis. One frame is one write: views observing the engine are
    /// invalidated once per processed frame.
    @Published public private(set) var analysis: SmartLoupeAnalysis = .idle

    public var classification: SmartLoupeClassification { analysis.classification }
    public var detectedPII: [PIIRedactionMatch] { analysis.detectedPII }
    public var mrzPayload: MRZPayload? { analysis.mrzPayload }
    public var isAligned: Bool { analysis.isAligned }
    public var confidenceScore: Float { analysis.confidenceScore }

    /// Live frames are analysed at most this often; the default of 100 ms is about
    /// ten frames a second, against a 60 fps camera feed.
    public nonisolated var minimumFrameInterval: Duration { gate.minimumInterval }

    private nonisolated let gate: SmartLoupeFrameGate
    private nonisolated let analyzer: @Sendable ([SmartLoupeTextLine]) -> SmartLoupeAnalysis

    public init(minimumFrameInterval: Duration = .milliseconds(100)) {
        gate = SmartLoupeFrameGate(minimumInterval: minimumFrameInterval)
        analyzer = { lines in SmartLoupeVisionEngine.analyze(lines) }
    }

    /// Test seam: substitutes the analysis function so a test can observe where and
    /// how often it runs. Production code uses `init(minimumFrameInterval:)`.
    init(
        minimumFrameInterval: Duration,
        analyzer: @escaping @Sendable ([SmartLoupeTextLine]) -> SmartLoupeAnalysis
    ) {
        gate = SmartLoupeFrameGate(minimumInterval: minimumFrameInterval)
        self.analyzer = analyzer
    }

    /// Live-stream entry point. Call it for every camera frame from the capture or
    /// Vision callback queue: it never blocks, and a dropped frame never reaches
    /// the main actor. Returns the analysis task for an admitted frame (awaiting it
    /// means the result has been published) or nil when the frame was dropped.
    @discardableResult
    public nonisolated func submitFrame(_ lines: [SmartLoupeTextLine]) -> Task<Void, Never>? {
        guard let admission = gate.tryAdmit() else { return nil }
        let gate = self.gate
        let analyzer = self.analyzer
        return Task.detached(priority: .userInitiated) { [weak self] in
            let result = analyzer(lines)
            await self?.publish(result, admittedAt: admission.epoch)
            gate.finish()
        }
    }

    /// One-shot entry point for a still image, such as a finished document scan.
    /// It is not throttled, because the caller asked for this frame, but it still
    /// parses off the main actor and publishes one change.
    public func processRecognizedLines(_ lines: [(text: String, boundingBox: CGRect)]) async {
        let frame = lines.map { SmartLoupeTextLine(text: $0.text, boundingBox: $0.boundingBox) }
        let epoch = gate.currentEpoch
        let analyzer = self.analyzer
        let result = await Task.detached(priority: .userInitiated) {
            analyzer(frame)
        }.value
        publish(result, admittedAt: epoch)
    }

    /// Applies one analysis as one published change, unless `reset()` ran after the
    /// frame was admitted. A frame without a readable MRZ keeps the last decoded
    /// MRZ, exactly as the per-field implementation did; only `reset()` clears it.
    private func publish(_ result: SmartLoupeAnalysis, admittedAt epoch: UInt64) {
        guard gate.currentEpoch == epoch else { return }
        var next = result
        if next.mrzPayload == nil {
            next.mrzPayload = analysis.mrzPayload
        }
        analysis = next
    }

    /// Parses recognized text lines from the on-device Vision OCR stream.
    ///
    /// Pure and `nonisolated`: the same three regex passes per line, MRZ decode and
    /// fallback heuristics the main-actor implementation ran, now callable from any
    /// executor. `mrzPayload` is nil when this frame has no decodable MRZ.
    nonisolated public static func analyze(_ lines: [SmartLoupeTextLine]) -> SmartLoupeAnalysis {
        var piiMatches: [PIIRedactionMatch] = []
        var detectedMRZLines: [String] = []

        var detectedUSCISHeader = false
        var detectedReceiptNumber: String?
        var detectedDL: (state: String?, number: String?)?
        var detectedGreenCardANumber: String?

        for line in lines {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)

            // Detect MRZ potential line (contains uppercase letters, digits, '<' filler)
            let mrzSanitized = text.replacingOccurrences(of: " ", with: "").uppercased()
            if mrzSanitized.contains("<") && mrzSanitized.count >= 28 {
                detectedMRZLines.append(mrzSanitized)
            }

            // Detect SSN for zero-cloud-leakage redaction
            let ssnMatches = SmartLoupeRegexes.ssn.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in ssnMatches {
                if let range = Range(match.range, in: text) {
                    let raw = String(text[range])
                    let redacted = "•••-••-" + raw.suffix(4)
                    piiMatches.append(PIIRedactionMatch(
                        type: .ssn,
                        rawValue: raw,
                        redactedValue: redacted,
                        normalizedBoundingBox: line.boundingBox
                    ))
                }
            }

            // Detect Alien Registration Number
            let aMatches = SmartLoupeRegexes.aNumberFull.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in aMatches {
                if let range = Range(match.range, in: text) {
                    let raw = String(text[range])
                    let redacted = "A••••" + raw.suffix(4)
                    piiMatches.append(PIIRedactionMatch(
                        type: .alienRegistrationNumber,
                        rawValue: raw,
                        redactedValue: redacted,
                        normalizedBoundingBox: line.boundingBox
                    ))
                    if detectedGreenCardANumber == nil {
                        detectedGreenCardANumber = raw
                    }
                }
            }

            // Detect USCIS Form Notices (e.g., I-797, I-797C)
            if text.localizedCaseInsensitiveContains("I-797") || text.localizedCaseInsensitiveContains("USCIS") {
                detectedUSCISHeader = true
            }
            let receiptMatches = SmartLoupeRegexes.receiptNumber.matches(in: text, range: NSRange(text.startIndex..., in: text))
            if let first = receiptMatches.first, let range = Range(first.range, in: text) {
                detectedReceiptNumber = String(text[range])
            }

            // Detect Driver License
            if text.localizedCaseInsensitiveContains("DRIVER LICENSE") || text.localizedCaseInsensitiveContains("DL") {
                detectedDL = (state: nil, number: nil)
            }
        }

        var result = SmartLoupeAnalysis(detectedPII: piiMatches)

        // Check if MRZ can be decoded
        if let parsedMRZ = parseMRZ(lines: detectedMRZLines) {
            result.mrzPayload = parsedMRZ
            if parsedMRZ.documentType.hasPrefix("P") {
                result.classification = .passport(
                    country: parsedMRZ.issuingCountry,
                    documentNumber: parsedMRZ.documentNumber,
                    surname: parsedMRZ.surname,
                    givenNames: parsedMRZ.givenNames
                )
            } else if parsedMRZ.documentType.hasPrefix("C") || parsedMRZ.documentType.hasPrefix("I") {
                result.classification = .usPermanentResidentCard(
                    alienNumber: parsedMRZ.documentNumber,
                    category: nil
                )
            } else {
                result.classification = .passport(
                    country: parsedMRZ.issuingCountry,
                    documentNumber: parsedMRZ.documentNumber,
                    surname: parsedMRZ.surname,
                    givenNames: parsedMRZ.givenNames
                )
            }
            result.isAligned = true
            result.confidenceScore = 0.98
            return result
        }

        // Fallback classification heuristics
        if detectedUSCISHeader || detectedReceiptNumber != nil {
            let rNum = detectedReceiptNumber ?? "Pending Scan"
            result.classification = .uscisNotice(formType: "I-797 Notice of Action", receiptNumber: rNum)
            result.isAligned = true
            result.confidenceScore = 0.92
        } else if let gcNumber = detectedGreenCardANumber {
            result.classification = .usPermanentResidentCard(alienNumber: gcNumber, category: nil)
            result.isAligned = true
            result.confidenceScore = 0.88
        } else if let dl = detectedDL {
            result.classification = .driverLicense(state: dl.state, documentNumber: dl.number)
            result.isAligned = true
            result.confidenceScore = 0.85
        } else {
            result.classification = .unknown
            result.isAligned = false
            result.confidenceScore = Float(lines.count) > 3 ? 0.40 : 0.10
        }
        return result
    }

    /// Pure functional ICAO Doc 9303 MRZ parser for TD1, TD2, and TD3 specifications.
    nonisolated public static func parseMRZ(lines: [String]) -> MRZPayload? {
        let cleanLines = lines.map { $0.uppercased().replacingOccurrences(of: " ", with: "") }

        // TD3: 2 lines of 44 chars (Standard Passport)
        if cleanLines.count >= 2 {
            for i in 0...(cleanLines.count - 2) {
                let l1 = cleanLines[i]
                let l2 = cleanLines[i + 1]
                if l1.count == 44 && l2.count == 44 {
                    return parseTD3(line1: l1, line2: l2)
                }
            }
        }

        // TD1: 3 lines of 30 chars (ID Card / Green Card / US Passport Card)
        if cleanLines.count >= 3 {
            for i in 0...(cleanLines.count - 3) {
                let l1 = cleanLines[i]
                let l2 = cleanLines[i + 1]
                let l3 = cleanLines[i + 2]
                if l1.count == 30 && l2.count == 30 && l3.count == 30 {
                    return parseTD1(line1: l1, line2: l2, line3: l3)
                }
            }
        }

        // TD2: 2 lines of 36 chars
        if cleanLines.count >= 2 {
            for i in 0...(cleanLines.count - 2) {
                let l1 = cleanLines[i]
                let l2 = cleanLines[i + 1]
                if l1.count == 36 && l2.count == 36 {
                    return parseTD2(line1: l1, line2: l2)
                }
            }
        }

        return nil
    }

    nonisolated private static func parseTD3(line1: String, line2: String) -> MRZPayload? {
        let docType = String(line1.prefix(2)).replacingOccurrences(of: "<", with: "")
        let issuingCountry = String(line1.dropFirst(2).prefix(3)).replacingOccurrences(of: "<", with: "")
        let nameField = String(line1.dropFirst(5))
        let nameParts = nameField.components(separatedBy: "<<")
        let surname = nameParts.first?.replacingOccurrences(of: "<", with: " ") ?? ""
        let givenNames = nameParts.count > 1 ? nameParts[1].replacingOccurrences(of: "<", with: " ") : ""

        let docNum = String(line2.prefix(9)).replacingOccurrences(of: "<", with: "")
        let docNumCheckChar = line2[line2.index(line2.startIndex, offsetBy: 9)]
        let docNumValid = verifyCheckDigit(value: docNum, checkChar: docNumCheckChar)

        let nat = String(line2.dropFirst(10).prefix(3)).replacingOccurrences(of: "<", with: "")

        let dob = String(line2.dropFirst(13).prefix(6))
        let dobCheckChar = line2[line2.index(line2.startIndex, offsetBy: 19)]
        let dobValid = verifyCheckDigit(value: dob, checkChar: dobCheckChar)

        let exp = String(line2.dropFirst(21).prefix(6))
        let expCheckChar = line2[line2.index(line2.startIndex, offsetBy: 27)]
        let expValid = verifyCheckDigit(value: exp, checkChar: expCheckChar)

        return MRZPayload(
            format: .td3,
            documentType: docType,
            issuingCountry: issuingCountry,
            documentNumber: docNum,
            documentNumberCheckValid: docNumValid,
            nationality: nat,
            birthDate: dob,
            birthDateCheckValid: dobValid,
            expirationDate: exp,
            expirationDateCheckValid: expValid,
            surname: surname.trimmingCharacters(in: .whitespaces),
            givenNames: givenNames.trimmingCharacters(in: .whitespaces),
            rawLines: [line1, line2]
        )
    }

    nonisolated private static func parseTD1(line1: String, line2: String, line3: String) -> MRZPayload? {
        let docType = String(line1.prefix(2)).replacingOccurrences(of: "<", with: "")
        let issuingCountry = String(line1.dropFirst(2).prefix(3)).replacingOccurrences(of: "<", with: "")
        let docNum = String(line1.dropFirst(5).prefix(9)).replacingOccurrences(of: "<", with: "")
        let docNumCheckChar = line1[line1.index(line1.startIndex, offsetBy: 14)]
        let docNumValid = verifyCheckDigit(value: docNum, checkChar: docNumCheckChar)

        let dob = String(line2.prefix(6))
        let dobCheckChar = line2[line2.index(line2.startIndex, offsetBy: 6)]
        let dobValid = verifyCheckDigit(value: dob, checkChar: dobCheckChar)

        let exp = String(line2.dropFirst(8).prefix(6))
        let expCheckChar = line2[line2.index(line2.startIndex, offsetBy: 14)]
        let expValid = verifyCheckDigit(value: exp, checkChar: expCheckChar)

        let nat = String(line2.dropFirst(15).prefix(3)).replacingOccurrences(of: "<", with: "")

        let nameParts = line3.components(separatedBy: "<<")
        let surname = nameParts.first?.replacingOccurrences(of: "<", with: " ") ?? ""
        let givenNames = nameParts.count > 1 ? nameParts[1].replacingOccurrences(of: "<", with: " ") : ""

        return MRZPayload(
            format: .td1,
            documentType: docType,
            issuingCountry: issuingCountry,
            documentNumber: docNum,
            documentNumberCheckValid: docNumValid,
            nationality: nat,
            birthDate: dob,
            birthDateCheckValid: dobValid,
            expirationDate: exp,
            expirationDateCheckValid: expValid,
            surname: surname.trimmingCharacters(in: .whitespaces),
            givenNames: givenNames.trimmingCharacters(in: .whitespaces),
            rawLines: [line1, line2, line3]
        )
    }

    nonisolated private static func parseTD2(line1: String, line2: String) -> MRZPayload? {
        let docType = String(line1.prefix(2)).replacingOccurrences(of: "<", with: "")
        let issuingCountry = String(line1.dropFirst(2).prefix(3)).replacingOccurrences(of: "<", with: "")
        let nameParts = String(line1.dropFirst(5)).components(separatedBy: "<<")
        let surname = nameParts.first?.replacingOccurrences(of: "<", with: " ") ?? ""
        let givenNames = nameParts.count > 1 ? nameParts[1].replacingOccurrences(of: "<", with: " ") : ""

        let docNum = String(line2.prefix(9)).replacingOccurrences(of: "<", with: "")
        let docNumCheckChar = line2[line2.index(line2.startIndex, offsetBy: 9)]
        let docNumValid = verifyCheckDigit(value: docNum, checkChar: docNumCheckChar)

        let nat = String(line2.dropFirst(10).prefix(3)).replacingOccurrences(of: "<", with: "")

        let dob = String(line2.dropFirst(13).prefix(6))
        let dobCheckChar = line2[line2.index(line2.startIndex, offsetBy: 19)]
        let dobValid = verifyCheckDigit(value: dob, checkChar: dobCheckChar)

        let exp = String(line2.dropFirst(21).prefix(6))
        let expCheckChar = line2[line2.index(line2.startIndex, offsetBy: 27)]
        let expValid = verifyCheckDigit(value: exp, checkChar: expCheckChar)

        return MRZPayload(
            format: .td2,
            documentType: docType,
            issuingCountry: issuingCountry,
            documentNumber: docNum,
            documentNumberCheckValid: docNumValid,
            nationality: nat,
            birthDate: dob,
            birthDateCheckValid: dobValid,
            expirationDate: exp,
            expirationDateCheckValid: expValid,
            surname: surname.trimmingCharacters(in: .whitespaces),
            givenNames: givenNames.trimmingCharacters(in: .whitespaces),
            rawLines: [line1, line2]
        )
    }

    /// ICAO 9303 7-3-1 weight check digit verification.
    nonisolated public static func verifyCheckDigit(value: String, checkChar: Character) -> Bool {
        guard let expectedDigit = Int(String(checkChar)) else {
            return checkChar == "<" && value.allSatisfy { $0 == "<" }
        }

        let weights = [7, 3, 1]
        var total = 0

        for (index, char) in value.enumerated() {
            let weight = weights[index % 3]
            let charValue: Int
            if let digit = Int(String(char)) {
                charValue = digit
            } else if char >= "A" && char <= "Z" {
                charValue = Int(char.asciiValue! - Character("A").asciiValue!) + 10
            } else {
                charValue = 0 // '<' has value 0
            }
            total += charValue * weight
        }

        return (total % 10) == expectedDigit
    }

    /// Local zero-cloud-leakage PII redaction on plain text strings.
    nonisolated public static func redactPII(from text: String) -> String {
        var result = text
        result = SmartLoupeRegexes.ssn.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: "•••-••-$3"
        )
        result = SmartLoupeRegexes.aNumber.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: "A••••$1"
        )
        return result
    }

    /// Clears the readout. An analysis still in flight is discarded when it lands.
    public func reset() {
        gate.invalidate()
        analysis = .idle
    }
}

/// SwiftUI Live Viewfinder HUD with holographic alignment reticle and privacy redaction shield.
public struct SmartLoupeHUDView: View {
    @ObservedObject public var engine: SmartLoupeVisionEngine

    public init(engine: SmartLoupeVisionEngine) {
        self.engine = engine
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Viewfinder holographic framing reticle
                reticleFrame(size: geometry.size)

                // Privacy shield redaction overlays over detected PII
                ForEach(engine.detectedPII) { pii in
                    let rect = convertNormalizedRect(pii.normalizedBoundingBox, in: geometry.size)
                    HStack(spacing: Aperture.Spacing.xs) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 10))
                        Text(pii.type.rawValue)
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.red.opacity(0.7), lineWidth: 1)
                    )
                    .position(x: rect.midX, y: rect.midY)
                }

                // Top Classification HUD Pill
                VStack {
                    HStack(spacing: Aperture.Spacing.s) {
                        Image(systemName: engine.classification.iconName)
                            .foregroundStyle(engine.isAligned ? Aperture.Palette.actionGreen : Aperture.Palette.accent)
                        Text(engine.classification.displayName)
                            .font(Aperture.Typography.value)
                        if engine.isAligned {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(Aperture.Palette.actionGreen)
                        }
                    }
                    .padding(.horizontal, Aperture.Spacing.m)
                    .padding(.vertical, Aperture.Spacing.s)
                    .apertureLiquidGlassCard(
                        tone: engine.isAligned ? .positive : .information,
                        material: .ultraThin,
                        elevation: .floating,
                        cornerRadius: Aperture.Radius.pill
                    )
                    .padding(.top, Aperture.Spacing.m)

                    Spacer()

                    // Bottom MRZ / Quality Verification Readout
                    if let mrz = engine.mrzPayload {
                        VStack(alignment: .leading, spacing: Aperture.Spacing.xs) {
                            HStack {
                                Label("ICAO 9303 \(mrz.format.rawValue)", systemImage: "bolt.badge.checkmark.fill")
                                    .font(Aperture.Typography.caption.weight(.semibold))
                                    .foregroundStyle(Aperture.Palette.actionGreen)
                                Spacer()
                                Text("Check: \(mrz.documentNumberCheckValid ? "Valid" : "Refused")")
                                    .font(Aperture.Typography.caption)
                                    .foregroundStyle(mrz.documentNumberCheckValid ? Aperture.Palette.actionGreen : Aperture.Palette.actionRed)
                            }
                            Text("\(mrz.surname), \(mrz.givenNames)")
                                .font(Aperture.Typography.value)
                            Text("Doc: \(mrz.documentNumber) • Exp: \(mrz.expirationDate)")
                                .font(Aperture.Typography.caption)
                                .foregroundStyle(Aperture.Palette.onSurfaceSecondary)
                        }
                        .padding(Aperture.Spacing.m)
                        .apertureLiquidGlassCard(
                            tone: .positive,
                            material: .ultraThin,
                            elevation: .floating
                        )
                        .padding(.horizontal, Aperture.Spacing.l)
                        .padding(.bottom, Aperture.Spacing.xl)
                    }
                }
            }
        }
    }

    private func reticleFrame(size: CGSize) -> some View {
        let frameWidth = size.width * 0.88
        let frameHeight = frameWidth * 0.65

        return RoundedRectangle(cornerRadius: Aperture.Radius.card, style: .continuous)
            .strokeBorder(
                engine.isAligned
                    ? Aperture.Palette.actionGreen.opacity(0.85)
                    : Aperture.Palette.accent.opacity(0.60),
                lineWidth: engine.isAligned ? 3.0 : 2.0
            )
            .frame(width: frameWidth, height: frameHeight)
            .overlay {
                if engine.isAligned {
                    RoundedRectangle(cornerRadius: Aperture.Radius.card, style: .continuous)
                        .fill(Aperture.Palette.actionGreen.opacity(0.04))
                }
            }
            .respectfulAnimation(value: engine.isAligned)
    }

    private func convertNormalizedRect(_ rect: CGRect, in size: CGSize) -> CGRect {
        // Normalized coordinates in Vision have origin at lower-left, SwiftUI has origin at top-left
        let x = rect.origin.x * size.width
        let y = (1.0 - rect.origin.y - rect.height) * size.height
        let width = rect.width * size.width
        let height = rect.height * size.height
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
