import XCTest
import PofudukCore
@testable import Pofuduk

/// Real AVSpeechSynthesizer, no UI (fast). Regression for answers that never started speaking when
/// they interrupted an ongoing briefing (stop → speak race; fixed by using a fresh synthesizer).
@MainActor
final class SpeechServiceTests: XCTestCase {
    private var events: [SpeechEvent] = []

    private func waitFor(_ timeout: TimeInterval, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    private func makeService() throws -> SpeechService {
        let service = SpeechService()
        try XCTSkipUnless(service.hasTurkishVoice, "No Turkish voice on this simulator")
        service.onEvent = { [weak self] in self?.events.append($0) }
        return service
    }

    private let briefing = [
        "Merhaba! Ben Pofuduk, havayı senin için kontrol ettim ve sana uzun bir özet anlatacağım.",
        "Bugün sıcaklık on altı ile yirmi dört derece arasında olacak, öğleden sonra yağmur bekleniyor."
    ]

    func testAnswerAfterStopDuringBriefingStarts() async throws {
        let service = try makeService()
        service.speak(briefing, rate: SpeechService.defaultRate)
        let briefingStarted = await waitFor(5) { events.contains(.started(sentence: 0)) }
        XCTAssertTrue(briefingStarted)

        // Same order as HomeViewModel.present(): stop, then speak the answer immediately.
        events.removeAll()
        service.stop()
        XCTAssertEqual(events, [.cancelled])
        events.removeAll()
        service.speak(["Yarın hava güzel."], rate: SpeechService.defaultRate)
        let answerStarted = await waitFor(5) { events.contains(.started(sentence: 0)) }
        XCTAssertTrue(answerStarted, "The interrupting answer must start speaking")
        let answerFinished = await waitFor(8) { events.contains(.finished(sentence: 0)) }
        XCTAssertTrue(answerFinished)
        service.stop()
    }

    func testSpeakWhileSpeakingReplacesBriefing() async throws {
        let service = try makeService()
        service.speak(briefing, rate: SpeechService.defaultRate)
        let briefingStarted = await waitFor(5) { events.contains(.started(sentence: 0)) }
        XCTAssertTrue(briefingStarted)
        events.removeAll()
        service.speak(["Kısa cevap."], rate: SpeechService.defaultRate)   // no explicit stop
        let answerStarted = await waitFor(5) { events.contains(.started(sentence: 0)) }
        XCTAssertTrue(answerStarted)
        let answerFinished = await waitFor(8) { events.contains(.finished(sentence: 0)) }
        XCTAssertTrue(answerFinished, "The answer must play to the end (audio not stalled)")
        XCTAssertFalse(events.contains(.started(sentence: 1)), "Old briefing sentences must not continue")
        service.stop()
    }
}
