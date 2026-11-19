import XCTest
import PofudukCore
@testable import Pofuduk

/// Real AVSpeechSynthesizer, no UI (fast). Regression for answers that never started speaking when
/// they interrupted an ongoing briefing (stop → speak race), and for answers that started but never
/// finished (CI runs 44544503361 and earlier: `.started` seen, no `.finished` within 8 s).
///
/// Timing budgets are not tuned to a slow simulator on purpose: a short answer takes ~1 s on the CI
/// simulator (`testSpeakWhileSpeakingReplacesBriefing` runs start-to-end in ~1.3 s). `.finished` is awaited
/// for 8 s *after* the answer started, so missing it is a stall, not slowness — do not raise it or retry.
/// Failures print the event timeline and synthesizer state so the mechanism is visible in the CI log.
///
/// Those CI failures were the simulator's audio output stalling (run 44553791323: the process's very
/// first, uninterrupted speak never started, the main actor was blocked ~13 s, `[auext] Error in
/// destroying pipe`, later utterances "started" without a single word callback). So each test first
/// plays one plain sentence and skips — visibly, with the timeline — only if even that does not play.
/// Once the baseline plays, any stall in the stop → re-queue path still fails the test.
@MainActor
final class SpeechServiceTests: XCTestCase {
    private var events: [SpeechEvent] = []
    private var timeline: [String] = []
    private let start = Date()

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
        service.onEvent = { [weak self] in self?.record($0) }
        return service
    }

    private func record(_ event: SpeechEvent) {
        events.append(event)
        let name: String
        switch event {
        case .started(let i): name = "started(\(i))"
        case .willSpeak(_, let i): name = "word(\(i))"
        case .finished(let i): name = "finished(\(i))"
        default: name = "\(event)"
        }
        timeline.append(String(format: "+%.2f %@", Date().timeIntervalSince(start), name))
    }

    private func mark(_ step: String) {
        timeline.append(String(format: "+%.2f [%@]", Date().timeIntervalSince(start), step))
    }

    private func diagnostics(_ service: SpeechService) -> String {
        "timeline: \(timeline.joined(separator: ", ")) | \(service.debugState)"
    }

    /// Skips when a plain, uninterrupted sentence does not play: then the simulator's audio output itself
    /// is stalled, not the interrupt path under test. Also absorbs the first-speech voice warm-up.
    private func requireWorkingAudio(_ service: SpeechService) async throws {
        mark("probe")
        service.speak(["Deneme."], rate: SpeechService.defaultRate)
        let played = await waitFor(10) { events.contains(.finished(sentence: 0)) }
        guard played else {
            throw XCTSkip("Simulator audio output stalled before the scenario. \(diagnostics(service))")
        }
        events.removeAll()
    }

    private let briefing = [
        "Merhaba! Ben Pofuduk, havayı senin için kontrol ettim ve sana uzun bir özet anlatacağım.",
        "Bugün sıcaklık on altı ile yirmi dört derece arasında olacak, öğleden sonra yağmur bekleniyor."
    ]

    /// Three rounds: the race is timing-dependent, so one pass alone proves little.
    func testAnswerAfterStopDuringBriefingStarts() async throws {
        let service = try makeService()
        try await requireWorkingAudio(service)
        for round in 1...3 {
            events.removeAll()
            mark("round \(round): briefing")
            service.speak(briefing, rate: SpeechService.defaultRate)
            let briefingStarted = await waitFor(5) { events.contains(.started(sentence: 0)) }
            XCTAssertTrue(briefingStarted, diagnostics(service))

            // Same order as HomeViewModel.present(): stop, then speak the answer immediately.
            events.removeAll()
            mark("stop")
            service.stop()
            XCTAssertEqual(events, [.cancelled], diagnostics(service))
            events.removeAll()
            mark("answer")
            service.speak(["Yarın hava güzel."], rate: SpeechService.defaultRate)
            XCTAssertEqual(events, [], "Already stopped: nothing more to cancel")
            let answerStarted = await waitFor(5) { events.contains(.started(sentence: 0)) }
            XCTAssertTrue(answerStarted, "The interrupting answer must start speaking. \(diagnostics(service))")
            let answerFinished = await waitFor(8) { events.contains(.finished(sentence: 0)) || events.contains(.cancelled) }
            XCTAssertTrue(events.contains(.finished(sentence: 0)),
                          "The answer must play to the end (audio not stalled). \(diagnostics(service))")
            guard answerStarted, answerFinished else { break }
        }
        service.stop()
    }

    func testSpeakWhileSpeakingReplacesBriefing() async throws {
        let service = try makeService()
        try await requireWorkingAudio(service)
        mark("briefing")
        service.speak(briefing, rate: SpeechService.defaultRate)
        let briefingStarted = await waitFor(5) { events.contains(.started(sentence: 0)) }
        XCTAssertTrue(briefingStarted, diagnostics(service))
        events.removeAll()
        mark("answer")
        service.speak(["Kısa cevap."], rate: SpeechService.defaultRate)   // no explicit stop
        XCTAssertEqual(events, [.cancelled])   // the replaced briefing, reported synchronously
        events.removeAll()
        let answerStarted = await waitFor(5) { events.contains(.started(sentence: 0)) }
        XCTAssertTrue(answerStarted, diagnostics(service))
        _ = await waitFor(8) { events.contains(.finished(sentence: 0)) || events.contains(.cancelled) }
        XCTAssertTrue(events.contains(.finished(sentence: 0)),
                      "The answer must play to the end (audio not stalled). \(diagnostics(service))")
        XCTAssertFalse(events.contains(.started(sentence: 1)), "Old briefing sentences must not continue")
        service.stop()
    }
}
