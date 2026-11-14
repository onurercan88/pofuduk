import Foundation
import PofudukCore

/// Composition root. Features receive protocols only.
@MainActor
final class DependencyContainer {
    let speech: SpeechServicing
    let alertRepository: WeatherAlertRepository
    let summaryEngine: WeatherSummaryEngine
    let personality: CharacterPersonalityEngine
    let now: () -> Date
    /// Non-nil = start in clearly labelled demo mode (previews, tests, CI screenshots).
    let initialDemoScenario: MockWeatherData.Scenario?
    private let liveRepository: WeatherRepository

    init(speech: SpeechServicing? = nil,
         alertRepository: WeatherAlertRepository = UnavailableMGMAlertRepository(),
         summaryEngine: WeatherSummaryEngine = WeatherSummaryEngine(),
         personality: CharacterPersonalityEngine = CharacterPersonalityEngine(),
         liveRepository: WeatherRepository? = nil,
         initialDemoScenario: MockWeatherData.Scenario? = nil,
         now: @escaping () -> Date = { Date() }) {
        // Created here (main actor) rather than as a default argument, which is evaluated nonisolated.
        self.speech = speech ?? SpeechService()
        self.alertRepository = alertRepository
        self.summaryEngine = summaryEngine
        self.personality = personality
        self.initialDemoScenario = initialDemoScenario
        self.now = now
        self.liveRepository = liveRepository ?? Self.makeLiveRepository()
    }

    /// Production container: live data unless the launch argument `-pofuduk.demoScenario <name>` is given.
    static func app() -> DependencyContainer {
        let raw = UserDefaults.standard.string(forKey: "pofuduk.demoScenario")
        return DependencyContainer(initialDemoScenario: raw.flatMap(MockWeatherData.Scenario.init(rawValue:)))
    }

    /// WeatherAPI first (commercial use allowed on free plan) when a key is configured; Open-Meteo as fallback.
    private static func makeLiveRepository() -> WeatherRepository {
        let keychain = KeychainSecretStore()
        keychain.seedFromEnvironmentInDebug()
        let http = URLSessionHTTPClient()
        var providers: [WeatherProvider] = []
        if keychain.value(for: KeychainSecretStore.weatherAPIKey) != nil {
            providers.append(WeatherAPIProvider(http: http, apiKey: { keychain.value(for: KeychainSecretStore.weatherAPIKey) }))
        }
        providers.append(OpenMeteoProvider(http: http))
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Weather")
        return CachedWeatherRepository(engine: WeatherProviderFallbackEngine(providers: providers),
                                       cache: FileWeatherCacheStore(directory: cacheDir))
    }

    func weatherRepository(demoScenario: MockWeatherData.Scenario?) -> WeatherRepository {
        if let demoScenario { return DemoWeatherRepository(scenario: demoScenario) }
        return liveRepository
    }

    /// Phase 4 replaces this with the LocationResolver result.
    var defaultPlace: Place {
        var place = MockWeatherData.istanbul
        place.source = initialDemoScenario == nil ? .manual : .demo
        return place
    }

    func makeHomeViewModel() -> HomeViewModel {
        HomeViewModel(container: self)
    }
}
