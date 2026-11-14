import Foundation
import PofudukCore

/// Serves built-in sample data (source `.demo`). The UI and the briefing always disclose that this
/// is not a real forecast. Demo mode never produces official (MGM) warnings.
struct DemoWeatherRepository: WeatherRepository {
    let scenario: MockWeatherData.Scenario
    var now: @Sendable () -> Date = { Date() }

    func snapshot(for place: Place, forceRefresh: Bool) async throws -> WeatherSnapshot {
        MockWeatherData.snapshot(scenario, now: now(), place: place)
    }
}
