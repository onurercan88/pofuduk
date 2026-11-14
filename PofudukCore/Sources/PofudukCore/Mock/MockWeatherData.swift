import Foundation

/// Deterministic sample data for previews, tests and the clearly labelled demo mode.
/// Never use as production weather information.
public enum MockWeatherData {
    public enum Scenario: String, CaseIterable, Sendable {
        case sunny, rainyAfternoon, stormy, snowy, cloudy, windy
    }

    public static let istanbul = Place(
        name: "İstanbul", district: "Kadıköy", province: "İstanbul",
        coordinate: Coordinate(latitude: 40.99, longitude: 29.03),
        timeZoneIdentifier: "Europe/Istanbul", source: .demo
    )

    /// Builds a snapshot whose hourly data starts at local midnight of `now` and spans 48 hours.
    public static func snapshot(_ scenario: Scenario, now: Date, place: Place = istanbul) -> WeatherSnapshot {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = place.timeZone
        let dayStart = calendar.startOfDay(for: now)

        let hourly: [HourlyForecast] = (0..<48).map { i in
            let time = dayStart.addingTimeInterval(Double(i) * 3600)
            return hour(scenario, index: i % 24, time: time)
        }
        let currentHour = calendar.component(.hour, from: now)
        let h = hourly[currentHour]
        let current = CurrentWeather(
            time: now, temperature: h.temperature, feelsLike: h.feelsLike ?? h.temperature,
            condition: h.condition, humidity: scenario == .sunny ? 45 : 78,
            windSpeedKmh: h.windSpeedKmh ?? 10, windGustKmh: h.windGustKmh,
            windDirectionDegrees: 200, uvIndex: h.uvIndex, isDay: (6..<19).contains(currentHour)
        )
        let daily: [DailyForecast] = (0..<5).map { d in
            let date = calendar.date(byAdding: .day, value: d, to: dayStart) ?? dayStart
            let temps = (0..<24).map { hour(scenario, index: $0, time: date).temperature + Double(d % 2) }
            let base = hour(scenario, index: 15, time: date)
            return DailyForecast(
                date: date, minTemperature: temps.min() ?? 0, maxTemperature: temps.max() ?? 0,
                condition: base.condition, precipitationProbability: base.precipitationProbability,
                precipitationSumMm: scenario == .sunny ? 0 : 6,
                maxWindKmh: base.windSpeedKmh, uvIndexMax: scenario == .sunny ? 7 : 3,
                sunrise: date.addingTimeInterval(7 * 3600), sunset: date.addingTimeInterval(17.5 * 3600)
            )
        }
        return WeatherSnapshot(
            place: place, current: current, hourly: hourly, daily: daily, source: .demo,
            retrievedAt: now, expiresAt: now.addingTimeInterval(30 * 60)
        )
    }

    private static func hour(_ scenario: Scenario, index i: Int, time: Date) -> HourlyForecast {
        // Smooth daily temperature curve peaking at 15:00.
        let curve = cos(Double(i - 15) / 24 * 2 * .pi)
        switch scenario {
        case .sunny:
            let t = 19 + 6 * curve
            return HourlyForecast(time: time, temperature: t, feelsLike: t, condition: .clear,
                                  precipitationProbability: 0, precipitationMm: 0,
                                  windSpeedKmh: 8, windGustKmh: 15, uvIndex: (9...16).contains(i) ? 7 : 1)
        case .rainyAfternoon:
            let t = 20 + 4 * curve
            let wet = (14...17).contains(i)
            return HourlyForecast(time: time, temperature: t, feelsLike: t - 1,
                                  condition: wet ? .rain : (i < 12 ? .clear : .partlyCloudy),
                                  precipitationProbability: wet ? 80 : 10, precipitationMm: wet ? 3.2 : 0,
                                  windSpeedKmh: 14, windGustKmh: 25, uvIndex: 3)
        case .stormy:
            let t = 16 + 3 * curve
            let storm = (12...18).contains(i)
            return HourlyForecast(time: time, temperature: t, feelsLike: t - 2,
                                  condition: storm ? .thunderstorm : .cloudy,
                                  precipitationProbability: storm ? 90 : 40, precipitationMm: storm ? 9.0 : 0.2,
                                  windSpeedKmh: storm ? 45 : 25, windGustKmh: storm ? 70 : 35, uvIndex: 1)
        case .snowy:
            let t = -1 + 3 * curve
            return HourlyForecast(time: time, temperature: t, feelsLike: t - 4, condition: .snow,
                                  precipitationProbability: 85, precipitationMm: 1.0,
                                  windSpeedKmh: 15, windGustKmh: 25, uvIndex: 1)
        case .cloudy:
            let t = 14 + 3 * curve
            return HourlyForecast(time: time, temperature: t, feelsLike: t, condition: .cloudy,
                                  precipitationProbability: 15, precipitationMm: 0,
                                  windSpeedKmh: 12, windGustKmh: 20, uvIndex: 2)
        case .windy:
            let t = 15 + 4 * curve
            return HourlyForecast(time: time, temperature: t, feelsLike: t - 4, condition: .partlyCloudy,
                                  precipitationProbability: 10, precipitationMm: 0,
                                  windSpeedKmh: 42, windGustKmh: 65, uvIndex: 3)
        }
    }
}
