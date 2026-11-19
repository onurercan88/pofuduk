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
    let preferencesStore: UserPreferencesStore
    /// Non-nil = start in clearly labelled demo mode (previews, tests, CI screenshots).
    let initialDemoScenario: MockWeatherData.Scenario?
    private let liveRepository: WeatherRepository
    private let cacheStore: WeatherCacheStore

    init(speech: SpeechServicing? = nil,
         speechRecognizer: SpeechRecognizing? = nil,
         location: LocationServicing? = nil,
         notifications: NotificationCoordinator? = nil,
         preferencesStore: UserPreferencesStore? = nil,
         alertRepository: WeatherAlertRepository? = nil,
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
            ?? MGMAlertRepository(provider: ConfiguredMGMWarningProvider(feedURL: Self.mgmFeedURL, http: http))
        self.summaryEngine = summaryEngine
        self.personality = personality
        self.initialDemoScenario = initialDemoScenario
        self.now = now
        let cache: WeatherCacheStore = liveRepository == nil
            ? FileWeatherCacheStore(directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Weather"))
            : InMemoryWeatherCacheStore()
        self.cacheStore = cache
        self.liveRepository = liveRepository ?? Self.makeLiveRepository(keychain: keychain, http: http, cache: cache)
        self.preferencesStore = preferencesStore ?? UserPreferencesStore()
        self.notifications = notifications ?? NotificationCoordinator(
            scheduler: UserNotificationService(), store: NotificationPreferenceStore(),
            morningStore: MorningBriefingStore(), log: UserDefaultsNotificationLog(), now: now)
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
    /// "Now" is cross-checked against Apple Weather (WeatherKit) so a missed shower doesn't show as cloudy.
    private static func makeLiveRepository(keychain: KeychainSecretStore, http: HTTPClient, cache: WeatherCacheStore) -> WeatherRepository {
        var providers: [WeatherProvider] = []
        if keychain.value(for: KeychainSecretStore.weatherAPIKey) != nil {
            providers.append(WeatherAPIProvider(http: http, apiKey: { keychain.value(for: KeychainSecretStore.weatherAPIKey) }))
        }
        providers.append(OpenMeteoProvider(http: http))
        let forecast = CachedWeatherRepository(engine: WeatherProviderFallbackEngine(providers: providers), cache: cache)
        return CrossCheckedWeatherRepository(base: forecast, checker: AppleWeatherConditionsProvider())
    }

    /// "Verilerimi sil": cached forecasts, location choice and last place, notification + morning settings
    /// and delivery log (pending notifications cancelled), personalization and sound preference.
    /// The developer API key in the Keychain is not user data and is kept.
    func deleteAllData() async {
        await cacheStore.removeAll()
        location.reset()
        await notifications.reset()
        preferencesStore.clear()
        UserDefaults.standard.removeObject(forKey: "pofuduk.soundOn")
    }

    /// Authorized MGM CAP feed URL from Info.plist (`MGMWarningFeedURL`). Empty until MGM grants written
    /// permission → the app shows "unavailable" + the official MGM page. See API_INTEGRATIONS.md.
    private static var mgmFeedURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "MGMWarningFeedURL") as? String,
              !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return URL(string: raw)
    }

    /// IP lookup is offered only when a WeatherAPI key exists (no other IP service is used).
    private static func makeIPProvider(keychain: KeychainSecretStore, http: HTTPClient) -> LocationProvider? {
        guard keychain.value(for: KeychainSecretStore.weatherAPIKey) != nil else { return nil }
        return WeatherAPIIPLocationProvider(http: http, apiKey: { keychain.value(for: KeychainSecretStore.weatherAPIKey) })
    }

    func weatherRepository(demoScenario: MockWeatherData.Scenario?) -> WeatherRepository {
        if let demoScenario {
            let fixed = now()   // demo data follows the container clock (deterministic tests/previews)
            return DemoWeatherRepository(scenario: demoScenario, now: { fixed })
        }
        return liveRepository
    }

    var demoPlace: Place { MockWeatherData.istanbul }

    func makeHomeViewModel() -> HomeViewModel {
        HomeViewModel(container: self)
    }
}
