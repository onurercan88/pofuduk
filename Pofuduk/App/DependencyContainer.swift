import Foundation
import PofudukCore

/// Composition root. Features receive protocols only.
@MainActor
final class DependencyContainer {
    let speech: SpeechServicing
    let speechRecognizer: SpeechRecognizing
    let location: LocationServicing
    let alertRepository: WeatherAlertRepository
    let summaryEngine: WeatherSummaryEngine
    let personality: CharacterPersonalityEngine
    let now: () -> Date
    let notifications: NotificationCoordinator
    /// Non-nil = start in clearly labelled demo mode (previews, tests, CI screenshots).
    let initialDemoScenario: MockWeatherData.Scenario?
    private let liveRepository: WeatherRepository

    init(speech: SpeechServicing? = nil,
         speechRecognizer: SpeechRecognizing? = nil,
         location: LocationServicing? = nil,
         notifications: NotificationCoordinator? = nil,
         alertRepository: WeatherAlertRepository = UnavailableMGMAlertRepository(),
         summaryEngine: WeatherSummaryEngine = WeatherSummaryEngine(),
         personality: CharacterPersonalityEngine = CharacterPersonalityEngine(),
         liveRepository: WeatherRepository? = nil,
         initialDemoScenario: MockWeatherData.Scenario? = nil,
         now: @escaping () -> Date = { Date() }) {
        // Created here (main actor) rather than as default arguments, which are evaluated nonisolated.
        let keychain = KeychainSecretStore()
        keychain.seedFromEnvironmentInDebug()
        let http = URLSessionHTTPClient()
        self.speech = speech ?? SpeechService()
        self.speechRecognizer = speechRecognizer ?? SpeechRecognitionService()
        self.location = location ?? LocationService(ipProvider: Self.makeIPProvider(keychain: keychain, http: http))
        self.alertRepository = alertRepository
        self.summaryEngine = summaryEngine
        self.personality = personality
        self.initialDemoScenario = initialDemoScenario
        self.now = now
        self.liveRepository = liveRepository ?? Self.makeLiveRepository(keychain: keychain, http: http)
        self.notifications = notifications ?? NotificationCoordinator(
            scheduler: UserNotificationService(), store: NotificationPreferenceStore(),
            log: UserDefaultsNotificationLog(), now: now)
    }

    /// Background refresh (best effort): fresh forecast for the last known place → replan notifications.
    /// Never asks for location in the background and never runs in demo mode.
    func backgroundRefresh() async {
        guard initialDemoScenario == nil, notifications.preferences.isEnabled,
              let place = location.backgroundPlace,
              let snapshot = try? await liveRepository.snapshot(for: place, forceRefresh: true) else { return }
        let warnings: [OfficialWarning]
        if case .available(let list) = await alertRepository.warnings(for: place, at: now()) { warnings = list } else { warnings = [] }
        await notifications.refresh(snapshot: snapshot, warnings: warnings)
    }

    /// Production container: live data unless the launch argument `-pofuduk.demoScenario <name>` is given.
    static func app() -> DependencyContainer {
        let defaults = UserDefaults.standard
        #if DEBUG
        // CI/dev only: `-pofuduk.manualPlate 6` preselects a province (skips the permission flow).
        if let plate = defaults.string(forKey: "pofuduk.manualPlate").flatMap(Int.init),
           let province = TurkishProvinces.all.first(where: { $0.plate == plate }) {
            UserDefaultsLocationPreferenceStore().save(LocationPreference(mode: .manual, manualPlace: province.place))
        }
        #endif
        let raw = defaults.string(forKey: "pofuduk.demoScenario")
        return DependencyContainer(initialDemoScenario: raw.flatMap(MockWeatherData.Scenario.init(rawValue:)))
    }

    /// WeatherAPI first (commercial use allowed on free plan) when a key is configured; Open-Meteo as fallback.
    private static func makeLiveRepository(keychain: KeychainSecretStore, http: HTTPClient) -> WeatherRepository {
        var providers: [WeatherProvider] = []
        if keychain.value(for: KeychainSecretStore.weatherAPIKey) != nil {
            providers.append(WeatherAPIProvider(http: http, apiKey: { keychain.value(for: KeychainSecretStore.weatherAPIKey) }))
        }
        providers.append(OpenMeteoProvider(http: http))
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Weather")
        return CachedWeatherRepository(engine: WeatherProviderFallbackEngine(providers: providers),
                                       cache: FileWeatherCacheStore(directory: cacheDir))
    }

    /// IP lookup is offered only when a WeatherAPI key exists (no other IP service is used).
    private static func makeIPProvider(keychain: KeychainSecretStore, http: HTTPClient) -> LocationProvider? {
        guard keychain.value(for: KeychainSecretStore.weatherAPIKey) != nil else { return nil }
        return WeatherAPIIPLocationProvider(http: http, apiKey: { keychain.value(for: KeychainSecretStore.weatherAPIKey) })
    }

    func weatherRepository(demoScenario: MockWeatherData.Scenario?) -> WeatherRepository {
        if let demoScenario { return DemoWeatherRepository(scenario: demoScenario) }
        return liveRepository
    }

    var demoPlace: Place { MockWeatherData.istanbul }

    func makeHomeViewModel() -> HomeViewModel {
        HomeViewModel(container: self)
    }
}
