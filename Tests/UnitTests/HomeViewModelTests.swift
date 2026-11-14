import XCTest
import PofudukCore
@testable import Pofuduk

@MainActor
final class HomeViewModelTests: XCTestCase {
    struct FailingRepository: WeatherRepository {
        func snapshot(for place: Place, forceRefresh: Bool) async throws -> WeatherSnapshot { throw WeatherError.network }
    }

    struct DemoLikeRepository: WeatherRepository {
        func snapshot(for place: Place, forceRefresh: Bool) async throws -> WeatherSnapshot {
            var s = MockWeatherData.snapshot(.sunny, now: Date(), place: place)
            s.source = .openMeteo
            return s
        }
    }

    @MainActor
    final class StubLocationService: LocationServicing {
        var preference = LocationPreference()
        var isIPAvailable = false
        var resolution: LocationResolution
        private(set) var permissionRequests = 0
        init(_ resolution: LocationResolution) { self.resolution = resolution }
        func resolve() async -> LocationResolution {
            if preference.mode == .manual, let p = preference.manualPlace { return .resolved(p) }
            return resolution
        }
        func requestPermission() async { permissionRequests += 1 }
        func setMode(_ mode: LocationMode) { preference.mode = mode }
        func selectManual(_ place: Place) { preference = LocationPreference(mode: .manual, manualPlace: place) }
    }

    private func makeLiveViewModel(location: StubLocationService,
                                   repository: WeatherRepository = DemoLikeRepository()) -> HomeViewModel {
        let defaults = UserDefaults(suiteName: "HomeViewModelTests")!
        defaults.removePersistentDomain(forName: "HomeViewModelTests")
        let container = DependencyContainer(speech: PreviewSpeechService(), location: location, liveRepository: repository)
        return HomeViewModel(container: container, defaults: defaults)
    }

    func testFirstLaunchExplainsBeforeAskingPermission() async {
        let location = StubLocationService(.needsPermissionExplanation)
        let vm = makeLiveViewModel(location: location)
        await vm.onAppear()
        XCTAssertEqual(vm.loadState, .needsLocation)
        XCTAssertEqual(vm.locationPrompt, .explanation)
        XCTAssertEqual(location.permissionRequests, 0, "System prompt only after the user agrees")
        XCTAssertNil(vm.snapshot)
        XCTAssertFalse(vm.briefing?.fullText.contains("derece") == true)
    }

    func testPermissionDeniedOffersAlternatives() async {
        let vm = makeLiveViewModel(location: StubLocationService(.needsUserChoice(.permissionDenied)))
        await vm.onAppear()
        XCTAssertEqual(vm.locationPrompt, .issue(.permissionDenied))
    }

    func testManualCitySelectionLoadsWeatherForThatCity() async {
        let vm = makeLiveViewModel(location: StubLocationService(.needsUserChoice(.permissionDenied)))
        await vm.onAppear()
        let bursa = TurkishProvinces.search("Bursa")[0].place
        await vm.selectPlace(bursa)
        XCTAssertEqual(vm.loadState, .loaded)
        XCTAssertEqual(vm.snapshot?.place.name, "Bursa")
        XCTAssertNil(vm.locationPrompt)
    }

    func testAllowLocationRequestsPermissionOnce() async {
        let location = StubLocationService(.needsPermissionExplanation)
        let vm = makeLiveViewModel(location: location)
        await vm.onAppear()
        location.resolution = .resolved(MockWeatherData.istanbul)
        await vm.allowDeviceLocation()
        XCTAssertEqual(location.permissionRequests, 1)
        XCTAssertEqual(vm.loadState, .loaded)
    }

    func testApproximateLocationIsLabelled() async {
        var ankara = TurkishProvinces.search("Ankara")[0].place
        ankara.source = .ipApproximate
        let vm = makeLiveViewModel(location: StubLocationService(.resolved(ankara)))
        await vm.onAppear()
        XCTAssertTrue(vm.isApproximateLocation)
    }

    private func makeViewModel(speech: PreviewSpeechService, hour: Int = 15,
                               demo: MockWeatherData.Scenario? = .rainyAfternoon) -> HomeViewModel {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: hour))!
        let defaults = UserDefaults(suiteName: "HomeViewModelTests")!
        defaults.removePersistentDomain(forName: "HomeViewModelTests")
        let container = DependencyContainer(speech: speech,
                                            location: StubLocationService(.resolved(MockWeatherData.istanbul)),
                                            liveRepository: FailingRepository(),
                                            initialDemoScenario: demo, now: { now })
        return HomeViewModel(container: container, defaults: defaults)
    }

    func testLiveFailureShowsErrorWithoutInventingData() async {
        let speech = PreviewSpeechService()
        let vm = makeViewModel(speech: speech, demo: nil)
        await vm.onAppear()
        XCTAssertTrue(vm.isFailed)
        XCTAssertNil(vm.snapshot)
        XCTAssertEqual(vm.appearance.theme, .cloudy)
        XCTAssertTrue(vm.briefing?.fullText.contains("ulaşamadım") == true)
        XCTAssertFalse(vm.briefing?.fullText.contains("derece") == true, "No temperatures without data")
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
