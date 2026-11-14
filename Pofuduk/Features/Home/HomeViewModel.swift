import Foundation
import Observation
import PofudukCore

@MainActor
@Observable
final class HomeViewModel {
    enum LoadState: Equatable {
        case idle, loading, loaded
        case failed(String)
    }

    private(set) var loadState: LoadState = .idle
    private(set) var snapshot: WeatherSnapshot?
    private(set) var analysis: WeatherAnalysis?
    private(set) var briefing: Briefing?
    private(set) var track = SubtitleTrack()
    private(set) var warningAvailability: WarningAvailability?
    private(set) var isWaking = false
    private(set) var voiceMissing = false
    private(set) var demoScenario: MockWeatherData.Scenario = .rainyAfternoon
    private(set) var isSoundOn: Bool {
        didSet { defaults.set(isSoundOn, forKey: Self.soundKey) }
    }
    var showTranscript = false

    private let container: DependencyContainer
    private let defaults: UserDefaults
    private var hasAppeared = false
    private static let soundKey = "pofuduk.soundOn"

    init(container: DependencyContainer, defaults: UserDefaults = .standard) {
        self.container = container
        self.defaults = defaults
        self.isSoundOn = defaults.object(forKey: Self.soundKey) as? Bool ?? true
        container.speech.onEvent = { [weak self] event in self?.handle(event) }
    }

    // MARK: - Derived state

    var appearance: CharacterAppearance {
        let theme = briefing?.theme ?? .cloudy
        if isWaking { return CharacterAppearance(mood: .sleeping, theme: theme, isMorningGreeting: true) }
        switch loadState {
        case .loading, .idle: return CharacterAppearance(mood: .thinking, theme: theme)
        case .failed: return CharacterAppearance(mood: .error, theme: theme)
        case .loaded: break
        }
        if track.status == .speaking { return CharacterAppearance(mood: .speaking, theme: theme) }
        return CharacterAppearance(mood: briefing?.restingMood ?? .idle, theme: theme)
    }

    var isDemo: Bool { snapshot?.source == .demo }
    var isStale: Bool { analysis?.isStale ?? false }

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
    }

    func refresh() async {
        await load(autoSpeak: false, greetSleepily: false)
    }

    func selectScenario(_ scenario: MockWeatherData.Scenario) async {
        guard scenario != demoScenario || loadState != .loaded else { return }
        container.speech.stop()
        demoScenario = scenario
        await load(autoSpeak: true, greetSleepily: false)
    }

    func playOrReplay() {
        guard let briefing else { return }
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

    private func load(autoSpeak: Bool, greetSleepily: Bool) async {
        loadState = .loading
        let place = container.defaultPlace
        let repository = container.weatherRepository(demoScenario: demoScenario)
        do {
            let snapshot = try await repository.snapshot(for: place, forceRefresh: false)
            let now = container.now()
            let warnings = await container.alertRepository.warnings(for: place, at: now)
            let analysis = container.summaryEngine.analyze(snapshot, now: now)
            self.snapshot = snapshot
            self.analysis = analysis
            self.warningAvailability = warnings
            self.briefing = container.personality.briefing(for: analysis, warnings: activeWarnings)
            loadState = .loaded
        } catch {
            snapshot = nil
            analysis = nil
            briefing = container.personality.unavailableBriefing(reason: "İnternet bağlantını kontrol edebilirsin.")
            loadState = .failed("Hava durumu alınamadı.")
        }
        track.load(briefing?.sentences ?? [])

        guard autoSpeak else { return }
        if greetSleepily, isMorning {
            isWaking = true
            try? await Task.sleep(for: .milliseconds(1300))
            isWaking = false
        }
        playOrReplay()
    }

    private var isMorning: Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = container.defaultPlace.timeZone
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
