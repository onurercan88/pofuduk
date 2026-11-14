import Foundation
import Observation
import PofudukCore

@MainActor
@Observable
final class HomeViewModel {
    enum LoadState: Equatable {
        case idle, loading, loaded
        case failed(String)
        /// No place yet: waiting for the user's location choice.
        case needsLocation
    }

    enum LocationPrompt: Identifiable, Equatable {
        case explanation
        case issue(LocationIssue)
        var id: String {
            switch self {
            case .explanation: return "explanation"
            case .issue(let i): return "issue-\(i)"
            }
        }
    }

    private(set) var loadState: LoadState = .idle
    private(set) var snapshot: WeatherSnapshot?
    private(set) var analysis: WeatherAnalysis?
    private(set) var briefing: Briefing?
    private(set) var track = SubtitleTrack()
    private(set) var warningAvailability: WarningAvailability?
    private(set) var isWaking = false
    private(set) var voiceMissing = false
    /// nil = live data. Non-nil only in labelled demo mode.
    private(set) var demoScenario: MockWeatherData.Scenario?
    private(set) var isSoundOn: Bool {
        didSet { defaults.set(isSoundOn, forKey: Self.soundKey) }
    }
    var showTranscript = false
    var locationPrompt: LocationPrompt?
    var showLocationPicker = false
    var showClothing = false
    var showNotificationSettings = false
    var showTravel = false
    var showWarnings = false
    let travel: TravelWeatherViewModel
    private(set) var isMorningBriefing = false
    var notifications: NotificationCoordinator { container.notifications }
    private(set) var clothingToday: ClothingRecommendation?
    /// What the bubble currently speaks/shows: the main briefing or the latest answer.
    private(set) var spoken: Briefing?
    let conversation: ConversationViewModel

    private let container: DependencyContainer
    private let defaults: UserDefaults
    private var hasAppeared = false
    private static let soundKey = "pofuduk.soundOn"

    init(container: DependencyContainer, defaults: UserDefaults = .standard) {
        self.container = container
        self.defaults = defaults
        self.isSoundOn = defaults.object(forKey: Self.soundKey) as? Bool ?? true
        self.demoScenario = container.initialDemoScenario
        self.conversation = ConversationViewModel(service: WeatherQueryService(container: container),
                                                  recognizer: container.speechRecognizer, now: container.now)
        self.travel = TravelWeatherViewModel(service: TravelWeatherService(container: container), now: container.now)
        container.speech.onEvent = { [weak self] event in self?.handle(event) }
        travel.origin = { [weak self] in self?.snapshot?.place }
        travel.demoScenario = { [weak self] in self?.demoScenario }
        travel.onSpeak = { [weak self] briefing in self?.present(briefing) }
        conversation.currentPlace = { [weak self] in self?.snapshot?.place }
        conversation.demoScenario = { [weak self] in self?.demoScenario }
        conversation.onAnswer = { [weak self] answer in self?.present(answer) }
        conversation.willListen = { [weak self] in self?.container.speech.stop() }
    }

    // MARK: - Derived state

    var appearance: CharacterAppearance {
        let theme = briefing?.theme ?? .cloudy
        if isWaking { return CharacterAppearance(mood: .sleeping, theme: theme, isMorningGreeting: true) }
        if conversation.isListening { return CharacterAppearance(mood: .listening, theme: theme) }
        if conversation.isThinking { return CharacterAppearance(mood: .thinking, theme: theme) }
        switch loadState {
        case .loading, .idle: return CharacterAppearance(mood: .thinking, theme: theme)
        case .failed: return CharacterAppearance(mood: .error, theme: theme)
        case .needsLocation: return CharacterAppearance(mood: .listening, theme: .cloudy)
        case .loaded: break
        }
        if track.status == .speaking { return CharacterAppearance(mood: .speaking, theme: theme) }
        // Any verified official warning for this place puts Pofuduk in warning mode.
        if !activeWarnings.isEmpty { return CharacterAppearance(mood: .warning, theme: theme) }
        // A serious main briefing keeps warning mode even after a casual answer.
        let resting: CharacterMood = briefing?.restingMood == .warning ? .warning : (spoken ?? briefing)?.restingMood ?? .idle
        return CharacterAppearance(mood: resting, theme: theme)
    }

    /// Clothing advice for today (offset 0) or tomorrow (offset 1); nil if the forecast doesn't cover it.
    func clothing(dayOffset: Int) -> ClothingRecommendation? {
        guard let snapshot else { return nil }
        if dayOffset == 0 { return clothingToday }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = snapshot.place.timeZone
        let now = container.now()
        guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now) else { return nil }
        return ClothingRecommendationEngine().recommend(for: snapshot, day: day, now: now)
    }

    func speakClothing(_ rec: ClothingRecommendation) {
        present(Briefing(sentences: rec.sentences, restingMood: .happy, theme: briefing?.theme ?? .cloudy))
    }

    /// Speaks an answer through the same subtitle/speech pipeline as the briefing.
    func present(_ answer: Briefing) {
        container.speech.stop()
        spoken = answer
        playOrReplay()
    }

    var isDemo: Bool { snapshot?.source == .demo }
    var isDemoMode: Bool { demoScenario != nil }
    var isFailed: Bool { failureReason != nil }
    var failureReason: String? { if case .failed(let reason) = loadState { return reason } else { return nil } }
    var isStale: Bool { analysis?.isStale ?? false }
    var needsLocation: Bool { loadState == .needsLocation }
    var isApproximateLocation: Bool { snapshot?.place.source == .ipApproximate }
    var isIPAvailable: Bool { container.location.isIPAvailable }

    var upcomingHours: [HourlyForecast] {
        guard let snapshot else { return [] }
        let start = snapshot.current.time.addingTimeInterval(-3600)
        return Array(snapshot.hourly.filter { $0.time > start }.prefix(12))
    }

    var tomorrow: DailyForecast? {
        guard let snapshot else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = snapshot.place.timeZone
        guard let date = calendar.date(byAdding: .day, value: 1, to: container.now()) else { return nil }
        return snapshot.daily.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    var activeWarnings: [OfficialWarning] {
        guard case .available(let list)? = warningAvailability else { return [] }
        let now = container.now()
        return list.filter { $0.isActive(at: now) }.sorted { $0.level > $1.level }
    }

    // MARK: - Intents

    func onAppear() async {
        guard !hasAppeared else { return }
        hasAppeared = true
        await load(autoSpeak: true, greetSleepily: true)
        #if DEBUG
        // CI screenshots: `-pofuduk.openClothing YES`
        if defaults.bool(forKey: "pofuduk.openClothing"), clothingToday != nil { showClothing = true }
        #endif
    }

    func refresh() async {
        await load(autoSpeak: false, greetSleepily: false, forceRefresh: true)
    }

    func retry() async {
        await load(autoSpeak: true, greetSleepily: false, forceRefresh: true)
    }

    // MARK: Location intents

    /// User agreed after Pofuduk's explanation → only now is the system prompt shown.
    func allowDeviceLocation() async {
        locationPrompt = nil
        await container.location.requestPermission()
        await load(autoSpeak: true, greetSleepily: false)
    }

    func useApproximateLocation() async {
        locationPrompt = nil
        showLocationPicker = false
        container.location.setMode(.ipApproximate)
        conversation.resetContext()
        await load(autoSpeak: true, greetSleepily: false)
    }

    func selectPlace(_ place: Place) async {
        locationPrompt = nil
        showLocationPicker = false
        container.location.selectManual(place)
        conversation.resetContext()
        await load(autoSpeak: true, greetSleepily: false, forceRefresh: true)
    }

    func chooseCityInstead() {
        locationPrompt = nil
        // Let the explanation sheet finish dismissing before presenting the picker.
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            showLocationPicker = true
        }
    }

    func openLocationPicker() {
        guard !isDemoMode else { return }
        showLocationPicker = true
    }

    func selectScenario(_ scenario: MockWeatherData.Scenario) async {
        guard isDemoMode, scenario != demoScenario || loadState != .loaded else { return }
        container.speech.stop()
        demoScenario = scenario
        await load(autoSpeak: true, greetSleepily: false)
    }

    func playOrReplay() {
        guard let briefing = spoken ?? briefing else { return }
        track.load(briefing.sentences)
        if isSoundOn, container.speech.hasTurkishVoice {
            container.speech.speak(briefing.sentences, rate: SpeechService.defaultRate)
        } else {
            voiceMissing = !container.speech.hasTurkishVoice
            track.showAllWithoutAudio()
        }
    }

    func togglePause() {
        switch track.status {
        case .speaking: container.speech.pause()
        case .paused: container.speech.resume()
        default: playOrReplay()
        }
    }

    func stop() {
        container.speech.stop()
    }

    func toggleSound() {
        isSoundOn.toggle()
        if !isSoundOn {
            container.speech.stop()
            track.showAllWithoutAudio()
        }
    }

    // MARK: - Loading

    private func load(autoSpeak: Bool, greetSleepily: Bool, forceRefresh: Bool = false) async {
        container.speech.stop()
        spoken = nil
        loadState = .loading

        let place: Place
        if demoScenario != nil {
            place = container.demoPlace
        } else {
            switch await container.location.resolve() {
            case .resolved(let resolved):
                place = resolved
            case .needsPermissionExplanation:
                enterNeedsLocation(.explanation)
                return
            case .needsUserChoice(let issue):
                enterNeedsLocation(.issue(issue))
                return
            }
        }

        let repository = container.weatherRepository(demoScenario: demoScenario)
        do {
            let snapshot = try await repository.snapshot(for: place, forceRefresh: forceRefresh)
            let now = container.now()
            let warnings = await container.alertRepository.warnings(for: place, at: now)
            let analysis = container.summaryEngine.analyze(snapshot, now: now)
            self.snapshot = snapshot
            self.analysis = analysis
            self.warningAvailability = warnings
            if demoScenario == nil {
                // Notifications are planned only from real forecasts, never demo data.
                await container.notifications.refresh(snapshot: snapshot, warnings: activeWarnings)
            }
            self.clothingToday = ClothingRecommendationEngine().recommend(for: snapshot, now: now)
            let notifications = container.notifications
            if notifications.shouldGreet(timeZone: snapshot.place.timeZone) {
                // "Pofuduk Günaydın": once per day, from the chosen time until noon.
                self.briefing = MorningBriefingEngine().briefing(snapshot: snapshot, analysis: analysis, warnings: activeWarnings,
                                                                 clothing: clothingToday, now: now)
                notifications.markGreeted(timeZone: snapshot.place.timeZone)
                isMorningBriefing = true
            } else {
                self.briefing = container.personality.briefing(for: analysis, warnings: activeWarnings, clothing: clothingToday)
                isMorningBriefing = false
            }
            loadState = .loaded
        } catch {
            snapshot = nil
            analysis = nil
            let reason = (error as? WeatherError)?.turkishExplanation ?? WeatherError.network.turkishExplanation
            briefing = container.personality.unavailableBriefing(reason: reason)
            loadState = .failed(reason)
        }
        track.load(briefing?.sentences ?? [])

        guard autoSpeak else { return }
        if (greetSleepily && isMorning) || isMorningBriefing {
            isWaking = true
            try? await Task.sleep(for: .milliseconds(1300))
            isWaking = false
        }
        if isMorningBriefing && !container.notifications.morning.speaksAutomatically {
            track.showAllWithoutAudio()   // text-only morning greeting
            return
        }
        playOrReplay()
    }

    /// Re-opening the app in the morning (from background) shows the daily greeting once.
    func sceneDidBecomeActive() async {
        guard hasAppeared, demoScenario == nil, loadState != .loading,
              let tz = snapshot?.place.timeZone, container.notifications.shouldGreet(timeZone: tz) else { return }
        await load(autoSpeak: true, greetSleepily: false)
    }

    /// No weather is shown or spoken until the user decides how to share their location.
    private func enterNeedsLocation(_ prompt: LocationPrompt) {
        snapshot = nil
        analysis = nil
        warningAvailability = nil
        briefing = container.personality.locationNeededBriefing()
        track.load(briefing?.sentences ?? [])
        track.showAllWithoutAudio()
        loadState = .needsLocation
        locationPrompt = prompt
    }

    private var isMorning: Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = snapshot?.place.timeZone ?? .current
        return (5..<11).contains(calendar.component(.hour, from: container.now()))
    }

    // MARK: - Speech events

    private func handle(_ event: SpeechEvent) {
        switch event {
        case .started(let i): track.didStart(sentenceAt: i)
        case .willSpeak(let range, let i): track.willSpeak(range, sentenceAt: i)
        case .finished(let i): track.didFinish(sentenceAt: i)
        case .paused: track.didPause()
        case .resumed: track.didResume()
        case .cancelled: track.didStop()
        case .voiceUnavailable:
            voiceMissing = true
            track.showAllWithoutAudio()
        }
    }
}
