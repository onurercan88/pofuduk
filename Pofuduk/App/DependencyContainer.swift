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

    init(speech: SpeechServicing = SpeechService(),
         alertRepository: WeatherAlertRepository = UnavailableMGMAlertRepository(),
         summaryEngine: WeatherSummaryEngine = WeatherSummaryEngine(),
         personality: CharacterPersonalityEngine = CharacterPersonalityEngine(),
         now: @escaping () -> Date = { Date() }) {
        self.speech = speech
        self.alertRepository = alertRepository
        self.summaryEngine = summaryEngine
        self.personality = personality
        self.now = now
    }

    /// Phase 3 replaces this with the real provider-backed repository.
    func weatherRepository(demoScenario: MockWeatherData.Scenario) -> WeatherRepository {
        DemoWeatherRepository(scenario: demoScenario)
    }

    /// Phase 4 replaces this with the LocationResolver result.
    var defaultPlace: Place { MockWeatherData.istanbul }

    func makeHomeViewModel() -> HomeViewModel {
        HomeViewModel(container: self)
    }
}
