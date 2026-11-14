import Foundation
import PofudukCore

/// Finds destinations: offline province match first, then Apple geocoding (districts, cities abroad).
enum DestinationResolver {
    static func candidates(for text: String) async -> [Place] {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return [] }
        var results = TurkishProvinces.search(trimmed).prefix(5).map(\.place)
        if let named = WeatherQueryParser().province(in: trimmed), !results.contains(named.place) {
            results.insert(named.place, at: 0)
        }
        for place in await PlaceSearch.search(trimmed, turkeyOnly: false) where !results.contains(where: { $0.name == place.name && $0.district == place.district }) {
            results.append(place)
        }
        return Array(results.prefix(12))
    }
}

/// Fetches destination (and origin) forecasts and builds the travel summary.
@MainActor
final class TravelWeatherService {
    private let container: DependencyContainer
    private let engine = TravelWeatherSummaryEngine()

    init(container: DependencyContainer) {
        self.container = container
    }

    func summary(destination: Place, departure: Date, returnDate: Date?, origin: Place?,
                 demoScenario: MockWeatherData.Scenario?) async -> Result<TravelSummary, WeatherError> {
        let days = TravelWeatherSummaryEngine.travelDays(departure: departure, returnDate: returnDate, timeZone: destination.timeZone)
        return await summary(destination: destination, days: days, origin: origin, demoScenario: demoScenario)
    }

    func summary(destination: Place, reference: DateReference, origin: Place?,
                 demoScenario: MockWeatherData.Scenario?) async -> Result<TravelSummary, WeatherError> {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = destination.timeZone
        let days = ForecastDateResolver().days(for: reference, now: container.now(), timeZone: destination.timeZone)
            .map { calendar.dateComponents([.year, .month, .day], from: $0) }
        return await summary(destination: destination, days: days, origin: origin, demoScenario: demoScenario)
    }

    private func summary(destination: Place, days: [DateComponents], origin: Place?,
                         demoScenario: MockWeatherData.Scenario?) async -> Result<TravelSummary, WeatherError> {
        let repository = container.weatherRepository(demoScenario: demoScenario)
        do {
            var destinationSnapshot = try await repository.snapshot(for: destination, forceRefresh: false)
            destinationSnapshot.place = destination
            // The origin is optional context; its failure must not block the destination forecast.
            var originSnapshot: WeatherSnapshot?
            if let origin, origin != destination {
                originSnapshot = try? await repository.snapshot(for: origin, forceRefresh: false)
            }
            var summary = engine.summarize(destination: destinationSnapshot, origin: originSnapshot, days: days, now: container.now())
            if destinationSnapshot.source == .demo {
                summary.briefing.sentences.append("Bu cevap örnek verilere dayanıyor.")
            }
            return .success(summary)
        } catch {
            return .failure((error as? WeatherError) ?? .network)
        }
    }
}
