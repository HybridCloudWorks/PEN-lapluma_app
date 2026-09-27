import Foundation
import AVFAudio
import Speech
import Observation
import SwiftUI
import ApertureDomain
import ApertureUI

/// Coordinates native iOS speech synthesis (TTS) and speech recognition (STT)
/// for conversational interview sessions.
@Observable
@MainActor
public final class VoiceCoordinator: NSObject, AVSpeechSynthesizerDelegate {
    public enum State: Sendable, Equatable {
        case idle
        case speaking
        case listening
        case processing
        case permissionDenied
        case error(String)
    }

    public var state: State = .idle
    public var liveTranscript: String = ""
    public var audioLevel: Float = 0.0
    public var isAuthorized = false

    private let synthesizer = AVSpeechSynthesizer()
    private var audioEngine: AVAudioEngine?
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var onSpeechFinished: (() -> Void)?

    public override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Requests user authorization for microphone access and speech recognition.
    public func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else {
            state = .permissionDenied
            isAuthorized = false
            return false
        }

        let micGranted: Bool
        if #available(iOS 17.0, *) {
            micGranted = await AVAudioApplication.requestRecordPermission()
        } else {
            micGranted = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }

        guard micGranted else {
            state = .permissionDenied
            isAuthorized = false
            return false
        }

        isAuthorized = true
        return true
    }

    /// Speaks the given text using native AVSpeechSynthesizer in the user's language.
    public func speak(text: String, locale: String, onFinished: (() -> Void)? = nil) {
        stopListening()
        self.onSpeechFinished = onFinished
        state = .speaking

        let utterance = AVSpeechUtterance(string: text)
        let langCode = locale.lowercased().hasPrefix("es") ? "es-US" : "en-US"
        utterance.voice = AVSpeechSynthesisVoice(language: langCode) ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        utterance.pitchMultiplier = 1.0

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            // Fallback continues with system default route
        }

        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(utterance)
    }

    /// Interrupts speech synthesis immediately.
    public func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        if state == .speaking {
            state = .idle
        }
    }

    /// Starts audio recording and real-time speech-to-text recognition.
    public func startListening(locale: String) async -> Bool {
        stopSpeaking()

        if !isAuthorized {
            let granted = await requestPermissions()
            guard granted else { return false }
        }

        stopListening()

        let langIdentifier = locale.lowercased().hasPrefix("es") ? "es-US" : "en-US"
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: langIdentifier))
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            state = .error("Speech recognition is unavailable")
            return false
        }

        let engine = AVAudioEngine()
        audioEngine = engine
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let inputNode = engine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                request.append(buffer)

                // Compute audio RMS level for visual waveform
                guard let channelData = buffer.floatChannelData?[0] else { return }
                let frameLength = UInt(buffer.frameLength)
                var sum: Float = 0.0
                for i in 0..<Int(frameLength) {
                    let sample = channelData[i]
                    sum += sample * sample
                }
                let rms = sqrt(sum / Float(frameLength))
                let normalized = min(max(rms * 5.0, 0.05), 1.0)
                Task { @MainActor [weak self] in
                    self?.audioLevel = normalized
                }
            }

            engine.prepare()
            try engine.start()

            liveTranscript = ""
            state = .listening

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                if let result {
                    Task { @MainActor in
                        self.liveTranscript = result.bestTranscription.formattedString
                    }
                }
                if error != nil {
                    Task { @MainActor in
                        if self.state == .listening {
                            self.stopListening()
                        }
                    }
                }
            }
            return true
        } catch {
            state = .error("Could not start audio recording")
            return false
        }
    }

    /// Stops audio capture and finishes speech recognition, returning the final transcript.
    @discardableResult
    public func stopListening() -> String {
        recognitionTask?.cancel()
        recognitionTask = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        if let engine = audioEngine, engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        audioEngine = nil

        let transcript = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        audioLevel = 0.0
        if state == .listening {
            state = .idle
        }
        return transcript
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if self.state == .speaking {
                self.state = .idle
            }
            self.onSpeechFinished?()
            self.onSpeechFinished = nil
        }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if self.state == .speaking {
                self.state = .idle
            }
            self.onSpeechFinished = nil
        }
    }
}
