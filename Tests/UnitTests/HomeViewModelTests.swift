import XCTest
import PofudukCore
@testable import Pofuduk

@MainActor
final class HomeViewModelTests: XCTestCase {
    private func makeViewModel(speech: PreviewSpeechService, hour: Int = 15) -> HomeViewModel {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: hour))!
        let defaults = UserDefaults(suiteName: "HomeViewModelTests")!
        defaults.removePersistentDomain(forName: "HomeViewModelTests")
        let container = DependencyContainer(speech: speech, now: { now })
        return HomeViewModel(container: container, defaults: defaults)
    }

    func testAppearLoadsDemoBriefingAndStartsSpeaking() async {
        let speech = PreviewSpeechService()
        let vm = makeViewModel(speech: speech)
        await vm.onAppear()
        XCTAssertEqual(vm.loadState, .loaded)
        XCTAssertTrue(vm.isDemo)
        XCTAssertEqual(vm.track.status, .speaking)
        XCTAssertEqual(vm.appearance.mood, .speaking)
        XCTAssertEqual(speech.spokenSentences, vm.briefing?.sentences, "Subtitles must equal spoken text")
    }

    func testPauseResumeStop() async {
        let speech = PreviewSpeechService()
        let vm = makeViewModel(speech: speech)
        await vm.onAppear()
        vm.togglePause()
        XCTAssertEqual(vm.track.status, .paused)
        vm.togglePause()
        XCTAssertEqual(vm.track.status, .speaking)
        vm.stop()
        XCTAssertEqual(vm.track.status, .stopped)
        XCTAssertNotNil(vm.track.currentSentence, "Subtitle stays visible after stop")
    }

    func testSoundDisabledShowsFullTextWithoutSpeaking() async {
        let speech = PreviewSpeechService()
        let vm = makeViewModel(speech: speech)
        vm.toggleSound()
        await vm.onAppear()
        XCTAssertTrue(speech.spokenSentences.isEmpty)
        XCTAssertEqual(vm.track.status, .finished)
        XCTAssertEqual(vm.track.spokenSentences, vm.briefing?.sentences)
    }

    func testMissingTurkishVoiceFallsBackToSubtitles() async {
        let vm = makeViewModel(speech: PreviewSpeechService(hasTurkishVoice: false))
        await vm.onAppear()
        XCTAssertTrue(vm.voiceMissing)
        XCTAssertEqual(vm.track.status, .finished)
    }

    func testStormScenarioPutsCharacterInWarningMode() async {
        let vm = makeViewModel(speech: PreviewSpeechService(autoFinish: true))
        await vm.onAppear()
        await vm.selectScenario(.stormy)
        XCTAssertEqual(vm.appearance.theme, .stormy)
        XCTAssertEqual(vm.appearance.mood, .warning)
    }

    func testMGMUnavailableIsReportedNotFabricated() async {
        let vm = makeViewModel(speech: PreviewSpeechService())
        await vm.onAppear()
        guard case .unavailable? = vm.warningAvailability else { return XCTFail("Expected unavailable") }
        XCTAssertTrue(vm.activeWarnings.isEmpty)
    }
}
