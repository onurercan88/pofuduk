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

    init(speech: SpeechServicing? = nil,
         alertRepository: WeatherAlertRepository = UnavailableMGMAlertRepository(),
         summaryEngine: WeatherSummaryEngine = WeatherSummaryEngine(),
         personality: CharacterPersonalityEngine = CharacterPersonalityEngine(),
         now: @escaping () -> Date = { Date() }) {
        // Created here (main actor) rather than as a default argument, which is evaluated nonisolated.
        self.speech = speech ?? SpeechService()
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
