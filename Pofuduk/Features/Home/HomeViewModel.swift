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
    /// If speech hasn't started by then (synthesizer dropped the utterances), show the text instead of
    /// leaving "Pofuduk konuşmaya hazırlanıyor…" on screen forever.
    var speechStartTimeout: Duration = .seconds(4)
    @ObservationIgnored private var speechStartWatchdog: Task<Void, Never>?
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
    var showTravel = false
    var showWarnings = false
    var showSettings = false
    private(set) var preferences: UserPreferences
    /// Fun reaction to a tap while not speaking (nil when none is playing).
    private(set) var tapReaction: TapReactionPlayback?
    var isReacting: Bool { tapReaction != nil }
    private var tapCount = 0
    /// Word being spoken (wall-clock start, matched against the character's animation clock).
    private(set) var speechCue: SpokenWordCue?

    /// Style/length come from the user's preferences; facts never depend on them.
    var personality: CharacterPersonalityEngine {
        CharacterPersonalityEngine(style: preferences.style, length: preferences.briefingLength)
    }
    var speechRate: Float { SpeechService.defaultRate * Float(preferences.clampedSpeechRate) }
    var availableVoices: [VoiceOption] { container.speech.turkishVoices() }
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
        // bool(forKey:) also understands launch arguments like `-pofuduk.soundOn NO` (UI tests).
        self.isSoundOn = defaults.object(forKey: Self.soundKey) == nil ? true : defaults.bool(forKey: Self.soundKey)
        self.demoScenario = container.initialDemoScenario
        let prefs = container.preferencesStore.load()
        self.preferences = prefs
        container.speech.setVoice(prefs.voiceIdentifier)
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
        if let tapReaction {
            return CharacterAppearance(mood: .celebrating, theme: loadState == .needsLocation ? .cloudy : theme,
                                       tapReaction: tapReaction)
        }
        if conversation.isThinking { return CharacterAppearance(mood: .thinking, theme: theme) }
        switch loadState {
        case .loading, .idle: return CharacterAppearance(mood: .thinking, theme: theme)
        case .failed: return CharacterAppearance(mood: .error, theme: theme)
        case .needsLocation: return CharacterAppearance(mood: .listening, theme: .cloudy)
        case .loaded: break
        }
        if track.status == .speaking { return CharacterAppearance(mood: .speaking, theme: theme, speechCue: speechCue) }
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

    // MARK: - Personalization

    func updatePreferences(_ change: (inout UserPreferences) -> Void) {
        let old = preferences
        change(&preferences)
        container.preferencesStore.save(preferences)
        if old.voiceIdentifier != preferences.voiceIdentifier { container.speech.setVoice(preferences.voiceIdentifier) }
        // Re-word the current briefing in the new style/length (facts unchanged).
        if (old.style != preferences.style || old.briefingLength != preferences.briefingLength),
           let analysis, !isMorningBriefing, loadState == .loaded {
            briefing = personality.briefing(for: analysis, warnings: activeWarnings, clothing: clothingToday)
            if spoken == nil, !track.isActive { track.load(briefing?.sentences ?? []); track.showAllWithoutAudio() }
        }
    }

    /// Lets the user hear the selected voice and speed.
    func previewVoice() {
        present(Briefing(sentences: ["Merhaba! Ben Pofuduk.", "Sesim ve konuşma hızım şimdi böyle."],
                         restingMood: .happy, theme: briefing?.theme ?? .cloudy))
    }

    /// Tapping Pofuduk: pause/resume while speaking; otherwise a just-for-fun reaction — glasses tossed,
    /// umbrella played with, or a dance — with a giggle (spoken when sound is on; subtitles untouched).
    func tapCharacter() {
        if track.isActive { togglePause(); return }
        guard tapReaction == nil else { return }
        let current = appearance
        let playback = TapReactionPlayback(reaction: .choose(for: current.theme, mood: current.mood),
                                           laugh: TapReaction.laugh(forTap: tapCount), startedAt: Date())
        tapCount += 1
        tapReaction = playback
        if isSoundOn, container.speech.hasTurkishVoice { container.speech.playEffect(playback.laugh) }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(TapReaction.duration))
            self?.tapReaction = nil
        }
    }

    /// "Verilerimi sil" — clears everything stored on this device, then starts fresh.
    func deleteAllData() async {
        container.speech.stop()
        await container.deleteAllData()
        preferences = UserPreferences()
        container.speech.setVoice(nil)
        isSoundOn = true
        defaults.removeObject(forKey: Self.soundKey)
        conversation.clearHistory()
        spoken = nil
        showSettings = false
        await load(autoSpeak: false, greetSleepily: false, forceRefresh: true)
    }

    /// Speaks an answer through the same subtitle/speech pipeline as the briefing.
    func present(_ answer: Briefing) {
        container.speech.stop()
        spoken = answer
        playOrReplay()
    }

    var isDemo: Bool { snapshot?.source == .demo }
    var isDemoMode: Bool { demoScenario != nil }
    /// Header clock: the wall clock, unless a DEBUG screenshot run froze the container clock.
    func headerDate(_ wallClock: Date) -> Date { container.isClockFixed ? container.now() : wallClock }
    /// App Store screenshots only (DEBUG launch argument `-pofuduk.storeScreenshots YES`): hides the demo
    /// badge and scenario picker. Release builds always show them.
    var hidesDemoChrome: Bool {
        #if DEBUG
        return isDemoMode && defaults.bool(forKey: "pofuduk.storeScreenshots")
        #else
        return false
        #endif
    }
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
        if defaults.bool(forKey: "pofuduk.openSettings") { showSettings = true }
        #endif
    }

    /// Pull to refresh is an explicit request → Pofuduk tells the updated weather (text only when muted).
    func refresh() async {
        await load(autoSpeak: true, greetSleepily: false, forceRefresh: true)
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
            container.speech.speak(briefing.sentences, rate: speechRate)
            startSpeechWatchdog()
        } else {
            voiceMissing = !container.speech.hasTurkishVoice
            track.showAllWithoutAudio()
        }
    }

    private func startSpeechWatchdog() {
        speechStartWatchdog?.cancel()
        let sentences = track.sentences
        let timeout = speechStartTimeout
        speechStartWatchdog = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard let self, !Task.isCancelled, self.track.status == .idle, self.track.sentences == sentences else { return }
            self.container.speech.stop()
            self.track.showAllWithoutAudio()
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
                self.briefing = personality.briefing(for: analysis, warnings: activeWarnings, clothing: clothingToday)
                isMorningBriefing = false
            }
            loadState = .loaded
        } catch {
            snapshot = nil
            analysis = nil
            let reason = (error as? WeatherError)?.turkishExplanation ?? WeatherError.network.turkishExplanation
            briefing = personality.unavailableBriefing(reason: reason)
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
        briefing = personality.locationNeededBriefing()
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
        case .willSpeak(let range, let i):
            track.willSpeak(range, sentenceAt: i)
            speechCue = Self.word(in: track.sentences, sentence: i, range: range).map {
                SpokenWordCue(word: $0, startedAt: Date(), rateMultiplier: preferences.clampedSpeechRate)
            }
        case .finished(let i):
            track.didFinish(sentenceAt: i)
            speechCue = nil
        case .paused:
            track.didPause()
            speechCue = nil
        case .resumed: track.didResume()
        case .cancelled:
            track.didStop()
            speechCue = nil
        case .voiceUnavailable:
            voiceMissing = true
            track.showAllWithoutAudio()
        }
    }

    /// The word the synthesizer reported (UTF-16 range, as AVSpeechSynthesizer gives it).
    static func word(in sentences: [String], sentence index: Int, range: TextRange) -> String? {
        guard sentences.indices.contains(index) else { return nil }
        let utf16 = sentences[index].utf16
        guard range.location >= 0, range.length > 0, range.location + range.length <= utf16.count else { return nil }
        let start = utf16.index(utf16.startIndex, offsetBy: range.location)
        let end = utf16.index(start, offsetBy: range.length)
        return String(sentences[index][start..<end])
    }
}
