import CoreLocation
import PofudukCore
import WeatherKit

/// Apple Weather (WeatherKit) current conditions, used only to cross-check "now" — the forecast
/// still comes from WeatherAPI/Open-Meteo. Needs the WeatherKit capability on the App ID and the
/// `com.apple.developer.weatherkit` entitlement; without them the call fails and is ignored.
struct AppleWeatherConditionsProvider: CurrentConditionsProvider {
    var source: WeatherDataSource { .appleWeather }

    func currentConditions(for place: Place) async throws -> CurrentConditionsObservation {
        // ~1 km precision is enough for current conditions and shares less location.
        let location = CLLocation(latitude: (place.coordinate.latitude * 100).rounded() / 100,
                                  longitude: (place.coordinate.longitude * 100).rounded() / 100)
        let current = try await WeatherService.shared.weather(for: location, including: .current)
        guard let condition = AppleWeatherConditionMapper.condition(rawValue: current.condition.rawValue) else {
            throw PofudukCore.WeatherError.invalidResponse
        }
        // m/s → mm/h
        let mmPerHour = current.precipitationIntensity.converted(to: .metersPerSecond).value * 3_600_000
        return CurrentConditionsObservation(condition: condition, precipitationIntensityMmPerHour: mmPerHour,
                                            observedAt: current.date)
    }
}
