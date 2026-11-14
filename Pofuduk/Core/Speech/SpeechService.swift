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
@MainActor
protocol SpeechServicing: AnyObject {
    var onEvent: ((SpeechEvent) -> Void)? { get set }
    var hasTurkishVoice: Bool { get }
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
    private var indexByUtterance: [ObjectIdentifier: Int] = [:]
    private let voice: AVSpeechSynthesisVoice?
    private var interruptionObserver: NSObjectProtocol?

    static let defaultRate: Float = AVSpeechUtteranceDefaultSpeechRate * 0.98

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
        activateAudioSession()
        for (index, sentence) in sentences.enumerated() {
            let utterance = AVSpeechUtterance(string: sentence)
            utterance.voice = voice
            utterance.rate = rate
            utterance.pitchMultiplier = 1.12
            utterance.postUtteranceDelay = 0.22
            indexByUtterance[ObjectIdentifier(utterance)] = index
            synthesizer.speak(utterance)
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
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
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
