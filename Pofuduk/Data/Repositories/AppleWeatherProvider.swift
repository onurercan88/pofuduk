import CoreLocation
import PofudukCore
import WeatherKit

/// Primary forecast source: Apple Weather via WeatherKit (commercial use allowed, 500k calls/month free).
/// Only converts WeatherKit values to metric plain values; mapping rules live in `AppleWeatherSnapshotBuilder`.
/// Any WeatherKit failure is reported as a network error so the fallback engine tries the next provider.
struct AppleWeatherProvider: WeatherProvider {
    let source = WeatherDataSource.appleWeather
    let maxForecastDays = 7
    var cacheLifetime: TimeInterval = 30 * 60

    func fetchSnapshot(for place: Place) async throws -> WeatherSnapshot {
        // ~1 km precision is enough for a forecast and shares less location.
        let location = CLLocation(latitude: (place.coordinate.latitude * 100).rounded() / 100,
                                  longitude: (place.coordinate.longitude * 100).rounded() / 100)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = place.timeZone
        let retrievedAt = Date()
        let start = calendar.startOfDay(for: retrievedAt)
        guard let end = calendar.date(byAdding: .day, value: maxForecastDays, to: start) else {
            throw PofudukCore.WeatherError.noData
        }

        let weather: (WeatherKit.CurrentWeather, Forecast<HourWeather>, Forecast<DayWeather>)
        do {
            weather = try await WeatherService.shared.weather(
                for: location,
                including: .current, .hourly(startDate: start, endDate: end), .daily(startDate: start, endDate: end))
        } catch {
            throw PofudukCore.WeatherError.network
        }
        let (now, hourly, daily) = weather

        let current = AppleWeatherSnapshotBuilder.Current(
            time: now.date, temperature: Self.celsius(now.temperature), feelsLike: Self.celsius(now.apparentTemperature),
            condition: now.condition.rawValue, humidity: now.humidity, windKmh: Self.kmh(now.wind.speed),
            gustKmh: now.wind.gust.map(Self.kmh),
            windDirectionDegrees: now.wind.direction.converted(to: .degrees).value,
            uvIndex: now.uvIndex.value, isDaylight: now.isDaylight,
            // m/s → mm/h
            precipitationIntensityMmPerHour: now.precipitationIntensity.converted(to: .metersPerSecond).value * 3_600_000)

        let hours = hourly.forecast.map { h in
            AppleWeatherSnapshotBuilder.Hour(
                time: h.date, temperature: Self.celsius(h.temperature), feelsLike: Self.celsius(h.apparentTemperature),
                condition: h.condition.rawValue, precipitationChance: h.precipitationChance,
                precipitationMm: h.precipitationAmount.converted(to: .millimeters).value,
                windKmh: Self.kmh(h.wind.speed), gustKmh: h.wind.gust.map(Self.kmh), uvIndex: h.uvIndex.value)
        }

        let days = daily.forecast.map { d in
            AppleWeatherSnapshotBuilder.Day(
                date: d.date, low: Self.celsius(d.lowTemperature), high: Self.celsius(d.highTemperature),
                condition: d.condition.rawValue, precipitationChance: d.precipitationChance,
                sunrise: d.sun.sunrise, sunset: d.sun.sunset)
        }

        return try AppleWeatherSnapshotBuilder.snapshot(place: place, current: current, hours: hours, days: days,
                                                        retrievedAt: retrievedAt, lifetime: cacheLifetime)
    }

    private static func celsius(_ t: Measurement<UnitTemperature>) -> Double { t.converted(to: .celsius).value }
    private static func kmh(_ s: Measurement<UnitSpeed>) -> Double { s.converted(to: .kilometersPerHour).value }
}
