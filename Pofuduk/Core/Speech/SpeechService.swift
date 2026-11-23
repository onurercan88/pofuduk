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
    /// The voice in use, if it is an installed Turkish voice (its quality drives the settings hint).
    var activeVoice: VoiceOption? { get }
    /// Briefing/answer pitch (`VoiceTone.pitchMultiplier`); giggles keep their own pitch.
    func setPitch(_ pitch: Float)
    func speak(_ sentences: [String], rate: Float)
    func pause()
    func resume()
    func stop()
    /// Short fun sound (a giggle) on a separate channel: no events, never touches subtitles.
    func playEffect(_ text: String)
}

/// AVSpeechSynthesizer adapter. One utterance per sentence → exact sentence sync via `didStart`,
/// word highlight via `willSpeakRangeOfSpeechString`. No timing estimates.
@MainActor
final class SpeechService: NSObject, SpeechServicing {
    var onEvent: ((SpeechEvent) -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    /// Separate synthesizer (no delegate) for giggles, so they never emit briefing events.
    private let effectsSynthesizer = AVSpeechSynthesizer()
    /// Set by `stop()`; the next `speak()` waits until the stop has really completed. Utterances queued
    /// while `stopSpeaking(at: .immediate)` is still in progress can be silently dropped (answers stuck at
    /// "hazırlanıyor" — seen in the CI tour recording). Replacing the synthesizer instead left audio stalled.
    /// Cleared by the interrupted utterance's cancel/finish callback — the synthesizer's own "stop done"
    /// signal — rather than by polling `isSpeaking` after a fixed 100 ms.
    private var stopInProgress = false
    private var pendingSpeak: Task<Void, Never>?
    /// Sentences of the current `speak()` that have not finished yet. The utterances are held strongly and
    /// every delegate callback keeps its own utterance alive until handled, so a late callback of an
    /// interrupted utterance can never alias a new one at a reused address (it did when only the
    /// `ObjectIdentifier` was captured).
    /// `spoken` maps the synthesizer's word ranges back to the subtitle sentence.
    private var pending: [ObjectIdentifier: (utterance: AVSpeechUtterance, index: Int, spoken: SpokenText)] = [:]
    private var voice: AVSpeechSynthesisVoice?
    private var pitch: Float = VoiceTone.pofuduk.pitchMultiplier
    private var interruptionObserver: NSObjectProtocol?

    /// Device testing: the system default sounded slow in Turkish; ~7% faster is close to everyday speech.
    /// The settings slider still scales this (0.8×–1.25×).
    nonisolated static let defaultRate: Float = AVSpeechUtteranceDefaultSpeechRate * 1.07
    /// Pofuduk's default voice (the user can switch to the natural pitch); giggles higher and quicker still.
    nonisolated static let briefingPitch: Float = VoiceTone.pofuduk.pitchMultiplier
    nonisolated static let effectPitch: Float = 1.5
    nonisolated static let effectRate: Float = defaultRate * 1.1

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

    func setPitch(_ pitch: Float) { self.pitch = pitch }

    var activeVoice: VoiceOption? {
        guard let voice else { return nil }
        return turkishVoices().first { $0.id == voice.identifier }
    }

    /// Prefers the highest-quality installed tr-TR voice.
    nonisolated static func preferredTurkishVoice() -> AVSpeechSynthesisVoice? {
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
            // Subtitles keep the written form; the voice gets the speech-friendly one ("14.00" → "14").
            let spoken = SpeechTextNormalizer.spoken(sentence)
            let utterance = AVSpeechUtterance(string: spoken.text)
            utterance.voice = voice
            utterance.rate = rate
            utterance.pitchMultiplier = pitch
            utterance.postUtteranceDelay = 0.22
            pending[ObjectIdentifier(utterance)] = (utterance, index, spoken)
            return utterance
        }
        let mustWait = stopInProgress
        pendingSpeak = Task { [weak self] in
            guard let self else { return }
            if mustWait { await self.waitForStopToComplete() }
            guard !Task.isCancelled else { return }
            self.activateAudioSession()
            utterances.forEach { self.synthesizer.speak($0) }
        }
    }

    /// Lets the interrupted speech finish cancelling (max ~1 s) before new utterances are queued.
    private func waitForStopToComplete() async {
        let deadline = ContinuousClock.now + .seconds(1)
        while (stopInProgress || synthesizer.isSpeaking) && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
            if Task.isCancelled { return }
        }
        stopInProgress = false
    }

    /// Internal state for test failure messages.
    var debugState: String {
        "pending=\(pending.values.map(\.index).sorted()) stopInProgress=\(stopInProgress) "
            + "isSpeaking=\(synthesizer.isSpeaking) isPaused=\(synthesizer.isPaused)"
    }

    func playEffect(_ text: String) {
        guard let voice, !synthesizer.isSpeaking else { return }
        if effectsSynthesizer.isSpeaking { effectsSynthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = Self.effectRate
        utterance.pitchMultiplier = Self.effectPitch
        activateAudioSession()
        effectsSynthesizer.speak(utterance)
        // Release the session (un-duck other audio) once the giggle is over and no briefing started.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !self.effectsSynthesizer.isSpeaking, !self.synthesizer.isSpeaking,
                  self.pending.isEmpty else { return }
            self.deactivateAudioSession()
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
        if effectsSynthesizer.isSpeaking { effectsSynthesizer.stopSpeaking(at: .immediate) }
        let wasActive = !pending.isEmpty
        pending.removeAll()      // callbacks of everything queued so far are now stale
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

    /// The callback's `utterance` is alive here (captured), and so is every `pending` one, so equal
    /// identifiers mean the same object.
    fileprivate func pendingIndex(of utterance: AVSpeechUtterance) -> Int? {
        pending[ObjectIdentifier(utterance)]?.index
    }

    fileprivate func handle(_ utterance: AVSpeechUtterance, _ make: (Int) -> SpeechEvent) {
        guard let index = pendingIndex(of: utterance) else { return }
        onEvent?(make(index))
    }

    fileprivate func handleFinish(_ utterance: AVSpeechUtterance) {
        guard let index = pendingIndex(of: utterance) else {
            stopInProgress = false   // the interrupted utterance is done
            return
        }
        pending[ObjectIdentifier(utterance)] = nil
        onEvent?(.finished(sentence: index))
        if pending.isEmpty { deactivateAudioSession() }
    }

    fileprivate func handleCancel(_ utterance: AVSpeechUtterance) {
        guard pendingIndex(of: utterance) != nil else {
            stopInProgress = false   // the stop has really completed
            if pending.isEmpty { deactivateAudioSession() }
            return
        }
        // Only `stop()` cancels, and it clears `pending` first. A current sentence cancelled anyway was
        // dropped by the synthesizer: report it instead of waiting forever for its `.finished`.
        stop()
    }
}

// Callbacks capture the utterance itself (not just its identifier) so it stays alive until handled.
extension SpeechService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.handle(utterance) { .started(sentence: $0) } }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, willSpeakRangeOfSpeechString range: NSRange,
                                       utterance: AVSpeechUtterance) {
        let r = TextRange(location: range.location, length: range.length)
        Task { @MainActor in
            guard let entry = self.pending[ObjectIdentifier(utterance)] else { return }
            self.onEvent?(.willSpeak(entry.spoken.subtitleRange(for: r), sentence: entry.index))
        }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.handleFinish(utterance) }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        Task { @MainActor in self.onEvent?(.paused) }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        Task { @MainActor in self.onEvent?(.resumed) }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.handleCancel(utterance) }
    }
}
