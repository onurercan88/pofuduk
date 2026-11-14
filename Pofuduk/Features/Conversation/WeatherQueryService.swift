import Foundation
import PofudukCore

/// Fetches the forecast for the place a question refers to and builds the spoken answer.
@MainActor
final class WeatherQueryService {
    private let container: DependencyContainer
    private let engine = WeatherAnswerEngine()

    init(container: DependencyContainer) {
        self.container = container
    }

    func answer(_ query: ResolvedQuery, currentPlace: Place?, demoScenario: MockWeatherData.Scenario?) async -> Briefing {
        if query.topic == .travel {
            return await travelAnswer(query, currentPlace: currentPlace, demoScenario: demoScenario)
        }
        guard let place = query.province?.place ?? currentPlace else {
            return Briefing(sentences: ["Önce bir konum seçmen gerekiyor.", "İstersen sorunda bir il adı da söyleyebilirsin."],
                            restingMood: .idle, theme: .cloudy)
        }
        let repository = container.weatherRepository(demoScenario: demoScenario)
        do {
            let snapshot = try await repository.snapshot(for: place, forceRefresh: false)
            var briefing = engine.answer(query, snapshot: snapshot, now: container.now())
            if snapshot.source == .demo {
                briefing.sentences.append("Bu cevap örnek verilere dayanıyor.")
            }
            return briefing
        } catch {
            let reason = (error as? WeatherError)?.turkishExplanation ?? WeatherError.network.turkishExplanation
            return container.personality.unavailableBriefing(reason: reason)
        }
    }

    /// "Yarın Bursa'ya gideceğim. Hava nasıl?" → destination forecast compared with the current place.
    private func travelAnswer(_ query: ResolvedQuery, currentPlace: Place?, demoScenario: MockWeatherData.Scenario?) async -> Briefing {
        guard let destination = query.province?.place else {
            return Briefing(sentences: ["Nereye gideceğini anlayamadım.",
                                        "Örneğin \"Yarın Bursa'ya gideceğim\" diyebilir ya da Seyahat Hava Durumu ekranından ilçe arayabilirsin."],
                            restingMood: .thinking, theme: .cloudy)
        }
        let result = await TravelWeatherService(container: container)
            .summary(destination: destination, reference: query.date, origin: currentPlace, demoScenario: demoScenario)
        switch result {
        case .success(let summary): return summary.briefing
        case .failure(let error): return container.personality.unavailableBriefing(reason: error.turkishExplanation)
        }
    }
}
