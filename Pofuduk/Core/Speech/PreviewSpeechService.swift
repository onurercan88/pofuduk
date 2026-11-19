import Foundation
import PofudukCore

/// Silent speech stand-in for SwiftUI previews and tests. Emits the same event sequence as real speech,
/// synchronously, so subtitle progression can be verified deterministically.
@MainActor
final class PreviewSpeechService: SpeechServicing {
    var onEvent: ((SpeechEvent) -> Void)?
    var hasTurkishVoice: Bool
    private(set) var spokenSentences: [String] = []
    private(set) var isPaused = false
    /// When false, `speak` only starts the first sentence (lets tests inspect mid-speech state).
    var autoFinish: Bool
    /// Simulates the synthesizer silently dropping queued utterances (no events at all).
    var dropsUtterances = false

    init(hasTurkishVoice: Bool = true, autoFinish: Bool = false) {
        self.hasTurkishVoice = hasTurkishVoice
        self.autoFinish = autoFinish
    }

    private(set) var lastRate: Float = 0
    private(set) var selectedVoice: String?

    func turkishVoices() -> [VoiceOption] {
        hasTurkishVoice ? [VoiceOption(id: "preview.tr", name: "Önizleme", qualityName: "Standart")] : []
    }

    func setVoice(_ identifier: String?) { selectedVoice = identifier }

    func speak(_ sentences: [String], rate: Float) {
        lastRate = rate
        stop()
        spokenSentences = sentences
        guard !sentences.isEmpty, !dropsUtterances else { return }
        onEvent?(.started(sentence: 0))
        guard autoFinish else { return }
        for i in sentences.indices {
            if i > 0 { onEvent?(.started(sentence: i)) }
            onEvent?(.finished(sentence: i))
        }
        spokenSentences = []
    }

    func pause() { isPaused = true; onEvent?(.paused) }
    func resume() { isPaused = false; onEvent?(.resumed) }

    func stop() {
        if !spokenSentences.isEmpty { onEvent?(.cancelled) }
        spokenSentences = []
    }
}
