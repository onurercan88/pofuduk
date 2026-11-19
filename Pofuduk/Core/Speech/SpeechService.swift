import AVFoundation
import PofudukCore

enum SpeechEvent: Equatable {
    case started(sentence: Int)
    case willSpeak(TextRange, sentence: Int)
    case finished(sentence: Int)
    case paused
    case resumed
    case cancelled
    /// No Turkish voice installed; subtitles still work.
    case voiceUnavailable
}

/// Abstraction over speech synthesis so view models are testable and the engine replaceable.
struct VoiceOption: Identifiable, Hashable {
    let id: String
    let name: String
    /// "Gelişmiş" / "Premium" / "Standart"
    let qualityName: String
}

@MainActor
protocol SpeechServicing: AnyObject {
    var onEvent: ((SpeechEvent) -> Void)? { get set }
    var hasTurkishVoice: Bool { get }
    /// Installed Turkish voices, best first.
    func turkishVoices() -> [VoiceOption]
    /// nil = best installed Turkish voice.
    func setVoice(_ identifier: String?)
    func speak(_ sentences: [String], rate: Float)
    func pause()
    func resume()
    func stop()
}

/// AVSpeechSynthesizer adapter. One utterance per sentence → exact sentence sync via `didStart`,
/// word highlight via `willSpeakRangeOfSpeechString`. No timing estimates.
@MainActor
final class SpeechService: NSObject, SpeechServicing {
    var onEvent: ((SpeechEvent) -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    /// Set by `stop()`; the next `speak()` waits until the stop has really completed. Utterances queued
    /// while `stopSpeaking(at: .immediate)` is still in progress can be silently dropped (answers stuck at
    /// "hazırlanıyor" — seen in the CI tour recording). Replacing the synthesizer instead left audio stalled.
    private var stopInProgress = false
    private var pendingSpeak: Task<Void, Never>?
    private var indexByUtterance: [ObjectIdentifier: Int] = [:]
    private var voice: AVSpeechSynthesisVoice?
    private var interruptionObserver: NSObjectProtocol?

    /// Device testing: the system default sounded slow in Turkish; ~7% faster is close to everyday speech.
    /// The settings slider still scales this (0.8×–1.25×).
    static let defaultRate: Float = AVSpeechUtteranceDefaultSpeechRate * 1.07

    override init() {
        voice = Self.preferredTurkishVoice()
        super.init()
        synthesizer.delegate = self
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            // Pause on interruptions (calls, Siri). The user resumes explicitly.
            MainActor.assumeIsolated { self?.pause() }
        }
    }

    deinit {
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
    }

    var hasTurkishVoice: Bool { voice != nil }

    func turkishVoices() -> [VoiceOption] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == "tr-TR" }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
            .map { v in
                let quality: String
                switch v.quality {
                case .premium: quality = "Premium"
                case .enhanced: quality = "Gelişmiş"
                default: quality = "Standart"
                }
                return VoiceOption(id: v.identifier, name: v.name, qualityName: quality)
            }
    }

    func setVoice(_ identifier: String?) {
        voice = identifier.flatMap(AVSpeechSynthesisVoice.init(identifier:)) ?? Self.preferredTurkishVoice()
    }

    /// Prefers the highest-quality installed tr-TR voice.
    static func preferredTurkishVoice() -> AVSpeechSynthesisVoice? {
        let turkish = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "tr-TR" }
        return turkish.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: "tr-TR")
    }

    func speak(_ sentences: [String], rate: Float = SpeechService.defaultRate) {
        stop()
        guard let voice else {
            onEvent?(.voiceUnavailable)
            return
        }
        let utterances = sentences.enumerated().map { index, sentence -> AVSpeechUtterance in
            let utterance = AVSpeechUtterance(string: sentence)
            utterance.voice = voice
            utterance.rate = rate
            utterance.pitchMultiplier = 1.12
            utterance.postUtteranceDelay = 0.22
            indexByUtterance[ObjectIdentifier(utterance)] = index
            return utterance
        }
        let mustWait = stopInProgress
        stopInProgress = false
        pendingSpeak = Task { [weak self] in
            guard let self else { return }
            if mustWait {
                // Let the interrupted speech finish cancelling (max ~1 s) before queueing new utterances.
                try? await Task.sleep(for: .milliseconds(100))
                var waited = 0
                while self.synthesizer.isSpeaking && waited < 45 {
                    try? await Task.sleep(for: .milliseconds(20))
                    waited += 1
                }
            }
            guard !Task.isCancelled else { return }
            self.activateAudioSession()
            utterances.forEach { self.synthesizer.speak($0) }
        }
    }

    func pause() {
        if synthesizer.isSpeaking { synthesizer.pauseSpeaking(at: .word) }
    }

    func resume() {
        if synthesizer.isPaused { synthesizer.continueSpeaking() }
    }

    /// Reports `.cancelled` synchronously (once). Late delegate cancel callbacks are ignored, so they
    /// can never disturb a briefing that starts right after.
    func stop() {
        let wasActive = !indexByUtterance.isEmpty
        indexByUtterance.removeAll()
        pendingSpeak?.cancel()   // an answer still waiting to be queued is dropped too
        pendingSpeak = nil
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
            stopInProgress = true
        }
        if wasActive { onEvent?(.cancelled) }
    }

    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    fileprivate func handle(_ id: ObjectIdentifier, _ make: (Int) -> SpeechEvent) {
        guard let index = indexByUtterance[id] else { return }
        onEvent?(make(index))
    }

    fileprivate func handleFinish(_ id: ObjectIdentifier) {
        guard let index = indexByUtterance.removeValue(forKey: id) else { return }
        onEvent?(.finished(sentence: index))
        if indexByUtterance.isEmpty { deactivateAudioSession() }
    }
}

extension SpeechService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.handle(id) { .started(sentence: $0) } }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, willSpeakRangeOfSpeechString range: NSRange,
                                       utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        let r = TextRange(location: range.location, length: range.length)
        Task { @MainActor in self.handle(id) { .willSpeak(r, sentence: $0) } }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.handleFinish(id) }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        Task { @MainActor in self.onEvent?(.paused) }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        Task { @MainActor in self.onEvent?(.resumed) }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if self.indexByUtterance.isEmpty { self.deactivateAudioSession() }
        }
    }
}
