import Foundation

/// Spec: IWeatherProvider. Adapter for one external forecast service.
public protocol WeatherProvider: Sendable {
    var source: WeatherDataSource { get }
    /// Maximum number of forecast days this provider/plan returns.
    var maxForecastDays: Int { get }
    func fetchSnapshot(for place: Place) async throws -> WeatherSnapshot
}

/// Spec: IWeatherRepository. Combines providers, cache and fallback.
public protocol WeatherRepository: Sendable {
    func snapshot(for place: Place, forceRefresh: Bool) async throws -> WeatherSnapshot
}

/// Spec: ILocationProvider.
public protocol LocationProvider: Sendable {
    func currentPlace() async throws -> Place
}

/// Spec: IMGMWarningProvider. Only authorized official sources may implement this.
public protocol MGMWarningProvider: Sendable {
    func warnings() async -> WarningAvailability
}

/// Spec: IWeatherAlertRepository.
public protocol WeatherAlertRepository: Sendable {
    func warnings(for place: Place, at date: Date) async -> WarningAvailability
}

public enum WeatherError: Error, Equatable, Sendable {
    case network
    case invalidResponse
    case rateLimited
    case missingAPIKey
    case outOfForecastRange
    case noData
}
