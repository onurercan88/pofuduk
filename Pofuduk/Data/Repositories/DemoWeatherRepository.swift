import Foundation
import PofudukCore

/// Serves built-in sample data (source `.demo`). Used until real providers are integrated (Phase 3).
/// The UI and the briefing always disclose that this is not a real forecast.
struct DemoWeatherRepository: WeatherRepository {
    let scenario: MockWeatherData.Scenario
    var now: @Sendable () -> Date = { Date() }

    func snapshot(for place: Place, forceRefresh: Bool) async throws -> WeatherSnapshot {
        MockWeatherData.snapshot(scenario, now: now(), place: place)
    }
}

/// No authorized machine-readable MGM source is integrated yet → never fabricate; report unavailability.
struct UnavailableMGMAlertRepository: WeatherAlertRepository {
    static let officialPage = URL(string: "https://www.mgm.gov.tr/")!

    func warnings(for place: Place, at date: Date) async -> WarningAvailability {
        .unavailable(reason: "Resmi MGM uyarıları için yetkili bir veri bağlantısı henüz yok.",
                     officialPage: Self.officialPage)
    }
}
