import Foundation
import Observation
import PofudukCore

/// Text + voice questions. Owns conversation context; hands answers to the home screen for speech.
@MainActor
@Observable
final class ConversationViewModel {
    struct Message: Identifiable, Equatable {
        let id = UUID()
        let fromUser: Bool
        let text: String
    }

    var inputText = ""
    private(set) var history: [Message] = []
    private(set) var isThinking = false
    private(set) var isListening = false
    private(set) var microphoneMessage: String?

    static let suggestions = ["Yarın hava nasıl?", "Şemsiye gerekir mi?", "Bugün ne giysem?", "Akşam yağmur var mı?"]

    // Wiring set by HomeViewModel.
    @ObservationIgnored var currentPlace: () -> Place? = { nil }
    @ObservationIgnored var demoScenario: () -> MockWeatherData.Scenario? = { nil }
    @ObservationIgnored var onAnswer: (Briefing) -> Void = { _ in }
    @ObservationIgnored var willListen: () -> Void = {}

    @ObservationIgnored private var manager = ConversationManager()
    @ObservationIgnored private let service: WeatherQueryService
    @ObservationIgnored private let recognizer: SpeechRecognizing
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var listenTimeout: Task<Void, Never>?

    init(service: WeatherQueryService, recognizer: SpeechRecognizing, now: @escaping () -> Date) {
        self.service = service
        self.recognizer = recognizer
        self.now = now
    }

    var canSend: Bool { !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isThinking }

    func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking else { return }
        inputText = ""
        await ask(text)
    }

    func ask(_ text: String) async {
        history.append(Message(fromUser: true, text: text))
        isThinking = true
        let query = manager.interpret(text, now: now())
        let answer = await service.answer(query, currentPlace: currentPlace(), demoScenario: demoScenario())
        isThinking = false
        history.append(Message(fromUser: false, text: answer.fullText))
        onAnswer(answer)
    }

    /// Context is tied to a place; switching location starts a fresh conversation.
    func resetContext() { manager.reset() }

    func clearHistory() {
        history = []
        inputText = ""
        manager.reset()
    }

    // MARK: - Microphone

    func toggleListening() async {
        if isListening { finishListening(); return }
        microphoneMessage = nil
        guard await recognizer.requestAuthorization() else {
            microphoneMessage = "Sesli soru için mikrofon ve konuşma tanıma izni gerekiyor. Yazarak da sorabilirsin."
            return
        }
        willListen()
        isListening = true
        do {
            try await recognizer.start { [weak self] text, isFinal in
                guard let self, self.isListening else { return }
                // An error ends recognition with empty text; keep what was heard until then.
                if !text.isEmpty || !isFinal { self.inputText = text }
                if isFinal { self.finishListening() }
            }
        } catch {
            isListening = false
            recognizer.stop()
            microphoneMessage = "Şu an konuşma tanıma kullanılamıyor. Yazarak sorabilirsin."
            return
        }
        // Tapped again while the microphone was still starting.
        guard isListening else { recognizer.stop(); return }
        if !recognizer.isOnDeviceSupported {
            microphoneMessage = "Bu cihazda konuşman tanınmak üzere Apple'a gönderilir."
        }
        listenTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            self?.finishListening()
        }
    }

    private func finishListening() {
        guard isListening else { return }
        isListening = false
        listenTimeout?.cancel()
        recognizer.stop()
        if canSend {
            Task { await send() }
        } else if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            microphoneMessage = "Seni duyamadım. Tekrar dener misin? Yazarak da sorabilirsin."
        }
    }
}
