import Foundation
@testable import PofudukCore

enum TestClock {
    static let istanbul = TimeZone(identifier: "Europe/Istanbul")!

    /// 2026-11-14 at the given local Istanbul time.
    static func date(hour: Int, minute: Int = 0, day: Int = 14) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = istanbul
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    /// Hourly entries starting at local midnight; `configure` returns the hour for a given index.
    static func hours(_ count: Int = 24, _ configure: (Int, Date) -> HourlyForecast) -> [HourlyForecast] {
        let start = date(hour: 0)
        return (0..<count).map { configure($0, start.addingTimeInterval(Double($0) * 3600)) }
    }

    static func snapshot(hourly: [HourlyForecast], current: CurrentWeather? = nil, now: Date,
                         daily: [DailyForecast] = [], retrievedAt: Date? = nil, expiresIn: TimeInterval = 1800,
                         source: WeatherDataSource = .openMeteo) -> WeatherSnapshot {
        let retrieved = retrievedAt ?? now
        let cur = current ?? CurrentWeather(time: now, temperature: 20, feelsLike: 20, condition: .clear,
                                            humidity: 50, windSpeedKmh: 10)
        var place = MockWeatherData.istanbul
        place.source = .manual
        return WeatherSnapshot(place: place, current: cur, hourly: hourly, daily: daily, source: source,
                               retrievedAt: retrieved, expiresAt: retrieved.addingTimeInterval(expiresIn))
    }
}
