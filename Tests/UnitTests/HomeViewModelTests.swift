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
        var backgroundPlace: Place? { preference.backgroundPlace }
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

    @MainActor
    final class StubRecognizer: SpeechRecognizing {
        var authorized = true
        var isOnDeviceSupported = true
        private(set) var onResult: ((String, Bool) -> Void)?
        func requestAuthorization() async -> Bool { authorized }
        func start(onResult: @escaping (String, Bool) -> Void) throws { self.onResult = onResult }
        func stop() {}
    }

    private func makeDemoViewModel(speech: PreviewSpeechService, recognizer: StubRecognizer? = nil) -> HomeViewModel {
        let recognizer = recognizer ?? StubRecognizer()
        let defaults = UserDefaults(suiteName: "HomeViewModelTests")!
        defaults.removePersistentDomain(forName: "HomeViewModelTests")
        let container = DependencyContainer(speech: speech, speechRecognizer: recognizer,
                                            location: StubLocationService(.resolved(MockWeatherData.istanbul)),
                                            liveRepository: FailingRepository(), initialDemoScenario: .rainyAfternoon)
        return HomeViewModel(container: container, defaults: defaults)
    }

    func testTypedQuestionIsAnsweredAndSpokenWithMatchingSubtitles() async {
        let speech = PreviewSpeechService()
        let vm = makeDemoViewModel(speech: speech)
        await vm.onAppear()
        vm.conversation.inputText = "Yarın hava nasıl?"
        await vm.conversation.send()
        XCTAssertTrue(vm.spoken?.sentences.first?.hasPrefix("Yarın İstanbul'da") == true, vm.spoken?.fullText ?? "")
        XCTAssertEqual(speech.spokenSentences, vm.spoken?.sentences)
        XCTAssertEqual(vm.track.sentences, vm.spoken?.sentences)
        XCTAssertEqual(vm.conversation.history.count, 2)
    }

    func testFollowUpQuestionKeepsTomorrow() async {
        let vm = makeDemoViewModel(speech: PreviewSpeechService())
        await vm.onAppear()
        await vm.conversation.ask("Yarın hava nasıl?")
        await vm.conversation.ask("Peki yağmur var mı?")
        XCTAssertTrue(vm.spoken?.fullText.hasPrefix("Yarın") == true, vm.spoken?.fullText ?? "")
    }

    func testClothingRecommendationIsAvailableAndSpeakable() async throws {
        let speech = PreviewSpeechService()
        let vm = makeDemoViewModel(speech: speech)
        await vm.onAppear()
        let today = try XCTUnwrap(vm.clothingToday)
        XCTAssertFalse(today.items.isEmpty)
        XCTAssertNotNil(vm.clothing(dayOffset: 1), "Demo data covers tomorrow")
        vm.speakClothing(today)
        XCTAssertEqual(speech.spokenSentences, today.sentences)
    }

    // MARK: - Notifications

    @MainActor
    final class StubScheduler: NotificationScheduling {
        var status: NotificationPermission
        var grantOnRequest: Bool
        private(set) var requests = 0
        private(set) var scheduled: [PlannedNotification] = []
        init(status: NotificationPermission, grantOnRequest: Bool = true) {
            self.status = status
            self.grantOnRequest = grantOnRequest
        }
        func permission() async -> NotificationPermission { status }
        func requestAuthorization() async -> Bool {
            requests += 1
            status = grantOnRequest ? .authorized : .denied
            return grantOnRequest
        }
        func replacePending(with planned: [PlannedNotification], now: Date) async { scheduled = planned }
    }

    struct FixedScenarioRepository: WeatherRepository {
        let scenario: MockWeatherData.Scenario
        let now: Date
        func snapshot(for place: Place, forceRefresh: Bool) async throws -> WeatherSnapshot {
            var s = MockWeatherData.snapshot(scenario, now: now, place: place)
            s.source = .openMeteo
            return s
        }
    }

    private func makeNotificationViewModel(scheduler: StubScheduler, demo: MockWeatherData.Scenario? = nil,
                                           enabled: Bool, hour: Int = 13, morning: MorningBriefingSettings? = nil,
                                           speech: PreviewSpeechService? = nil) -> HomeViewModel {
        let suite = "HomeViewModelTests.notifications"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = NotificationPreferenceStore(defaults: defaults)
        var prefs = NotificationPreferences()
        prefs.isEnabled = enabled
        prefs.quietHours.enabled = false
        store.save(prefs)
        let morningStore = MorningBriefingStore(defaults: defaults)
        morningStore.save(morning ?? MorningBriefingSettings())
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: hour))!
        let coordinator = NotificationCoordinator(scheduler: scheduler, store: store, morningStore: morningStore,
                                                  log: InMemoryNotificationLog(), now: { now })
        let container = DependencyContainer(speech: speech ?? PreviewSpeechService(), speechRecognizer: StubRecognizer(),
                                            location: StubLocationService(.resolved(MockWeatherData.istanbul)),
                                            notifications: coordinator,
                                            liveRepository: FixedScenarioRepository(scenario: .rainyAfternoon, now: now),
                                            initialDemoScenario: demo, now: { now })
        return HomeViewModel(container: container, defaults: defaults)
    }

    // MARK: - Morning briefing

    func testMorningGreetingShownOncePerDay() async {
        let vm = makeNotificationViewModel(scheduler: StubScheduler(status: .notDetermined), demo: .rainyAfternoon,
                                           enabled: false, hour: 8)
        await vm.onAppear()
        XCTAssertTrue(vm.isMorningBriefing)
        XCTAssertEqual(vm.briefing?.sentences.first, "Günaydın!")
        await vm.refresh()
        XCTAssertFalse(vm.isMorningBriefing, "Only the first opening of the day gets the greeting")
    }

    func testNoMorningGreetingBeforeChosenTime() async {
        var m = MorningBriefingSettings()
        m.minuteOfDay = 9 * 60
        let vm = makeNotificationViewModel(scheduler: StubScheduler(status: .notDetermined), demo: .sunny,
                                           enabled: false, hour: 8, morning: m)
        await vm.onAppear()
        XCTAssertFalse(vm.isMorningBriefing)
    }

    func testTextOnlyMorningGreeting() async {
        var m = MorningBriefingSettings()
        m.speaksAutomatically = false
        let speech = PreviewSpeechService()
        let vm = makeNotificationViewModel(scheduler: StubScheduler(status: .notDetermined), demo: .sunny,
                                           enabled: false, hour: 8, morning: m, speech: speech)
        await vm.onAppear()
        XCTAssertTrue(vm.isMorningBriefing)
        XCTAssertTrue(speech.spokenSentences.isEmpty)
        XCTAssertEqual(vm.track.status, .finished, "Full text shown without speaking")
    }

    func testMorningNotificationScheduledWhenOptedIn() async throws {
        var m = MorningBriefingSettings()
        m.sendsNotification = true
        let scheduler = StubScheduler(status: .authorized)
        let vm = makeNotificationViewModel(scheduler: scheduler, enabled: true, hour: 21, morning: m)
        await vm.onAppear()
        let n = try XCTUnwrap(scheduler.scheduled.first { $0.category == .morningBriefing })
        XCTAssertEqual(n.title, "Günaydın! ☀️")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        XCTAssertEqual(calendar.dateComponents([.day, .hour, .minute], from: n.fireDate), DateComponents(day: 15, hour: 7, minute: 30))
    }

    func testLiveForecastSchedulesRainNotification() async throws {
        let scheduler = StubScheduler(status: .authorized)
        let vm = makeNotificationViewModel(scheduler: scheduler, enabled: true)
        await vm.onAppear()
        let rain = try XCTUnwrap(scheduler.scheduled.first { $0.category == .rainSoon })
        XCTAssertTrue(rain.body.contains("yağmur bekleniyor"), rain.body)
        XCTAssertTrue(rain.body.contains("Kaynak:"), "Source is always stated")
    }

    func testDemoDataNeverSchedulesNotifications() async {
        let scheduler = StubScheduler(status: .authorized)
        let vm = makeNotificationViewModel(scheduler: scheduler, demo: .rainyAfternoon, enabled: true)
        await vm.onAppear()
        XCTAssertTrue(scheduler.scheduled.isEmpty)
    }

    func testNotificationPermissionDeniedKeepsFeatureOff() async {
        let scheduler = StubScheduler(status: .notDetermined, grantOnRequest: false)
        let vm = makeNotificationViewModel(scheduler: scheduler, enabled: false)
        await vm.onAppear()
        await vm.notifications.setEnabled(true)
        XCTAssertEqual(scheduler.requests, 1, "Permission asked only when the user turns it on")
        XCTAssertFalse(vm.notifications.preferences.isEnabled)
        XCTAssertEqual(vm.notifications.permission, .denied)
        XCTAssertTrue(scheduler.scheduled.isEmpty)
    }

    func testMicrophoneDeniedExplainsAndDoesNotListen() async {
        let recognizer = StubRecognizer()
        recognizer.authorized = false
        let vm = makeDemoViewModel(speech: PreviewSpeechService(), recognizer: recognizer)
        await vm.conversation.toggleListening()
        XCTAssertFalse(vm.conversation.isListening)
        XCTAssertNotNil(vm.conversation.microphoneMessage)
    }

    func testVoiceQuestionShowsListeningThenAnswers() async throws {
        let recognizer = StubRecognizer()
        recognizer.isOnDeviceSupported = false
        let vm = makeDemoViewModel(speech: PreviewSpeechService(), recognizer: recognizer)
        await vm.onAppear()
        await vm.conversation.toggleListening()
        XCTAssertTrue(vm.conversation.isListening)
        XCTAssertEqual(vm.appearance.mood, .listening)
        XCTAssertNotNil(vm.conversation.microphoneMessage, "Server-based recognition must be disclosed")
        recognizer.onResult?("Bugün şemsiye gerekir mi", true)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(vm.conversation.isListening)
        XCTAssertTrue(vm.spoken?.fullText.contains("şemsiye") == true, vm.spoken?.fullText ?? "")
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
