import Foundation

/// Builds a `WeatherSnapshot` from Apple Weather (WeatherKit) data. WeatherKit types only exist on Apple
/// platforms, so the app's adapter converts them into these plain values (metric units) and all mapping
/// rules live here, where they are unit-tested.
public enum AppleWeatherSnapshotBuilder {
    public struct Current: Sendable {
        public var time: Date
        public var temperature: Double
        public var feelsLike: Double
        /// `WeatherKit.WeatherCondition.rawValue`
        public var condition: String
        /// 0...1
        public var humidity: Double
        public var windKmh: Double
        public var gustKmh: Double?
        public var windDirectionDegrees: Double?
        public var uvIndex: Int
        public var isDaylight: Bool
        public var precipitationIntensityMmPerHour: Double

        public init(time: Date, temperature: Double, feelsLike: Double, condition: String, humidity: Double,
                    windKmh: Double, gustKmh: Double?, windDirectionDegrees: Double?, uvIndex: Int,
                    isDaylight: Bool, precipitationIntensityMmPerHour: Double) {
            self.time = time
            self.temperature = temperature
            self.feelsLike = feelsLike
            self.condition = condition
            self.humidity = humidity
            self.windKmh = windKmh
            self.gustKmh = gustKmh
            self.windDirectionDegrees = windDirectionDegrees
            self.uvIndex = uvIndex
            self.isDaylight = isDaylight
            self.precipitationIntensityMmPerHour = precipitationIntensityMmPerHour
        }
    }

    public struct Hour: Sendable {
        public var time: Date
        public var temperature: Double
        public var feelsLike: Double
        public var condition: String
        /// 0...1
        public var precipitationChance: Double
        public var precipitationMm: Double
        public var windKmh: Double
        public var gustKmh: Double?
        public var uvIndex: Int

        public init(time: Date, temperature: Double, feelsLike: Double, condition: String, precipitationChance: Double,
                    precipitationMm: Double, windKmh: Double, gustKmh: Double?, uvIndex: Int) {
            self.time = time
            self.temperature = temperature
            self.feelsLike = feelsLike
            self.condition = condition
            self.precipitationChance = precipitationChance
            self.precipitationMm = precipitationMm
            self.windKmh = windKmh
            self.gustKmh = gustKmh
            self.uvIndex = uvIndex
        }
    }

    public struct Day: Sendable {
        public var date: Date
        public var low: Double
        public var high: Double
        public var condition: String
        /// 0...1
        public var precipitationChance: Double
        public var sunrise: Date?
        public var sunset: Date?

        public init(date: Date, low: Double, high: Double, condition: String, precipitationChance: Double,
                    sunrise: Date?, sunset: Date?) {
            self.date = date
            self.low = low
            self.high = high
            self.condition = condition
            self.precipitationChance = precipitationChance
            self.sunrise = sunrise
            self.sunset = sunset
        }
    }

    /// Unknown Apple conditions fall back to cloudy (same as unknown codes from other providers).
    static func condition(_ raw: String) -> WeatherCondition {
        AppleWeatherConditionMapper.condition(rawValue: raw) ?? .cloudy
    }

    static func percent(_ chance: Double) -> Int {
        Int((min(1, max(0, chance)) * 100).rounded())
    }

    /// Daily rain total, strongest wind and UV come from the hourly values of that local day
    /// (nil for days beyond the hourly range).
    public static func snapshot(place: Place, current: Current, hours: [Hour], days: [Day],
                                retrievedAt: Date, lifetime: TimeInterval) throws -> WeatherSnapshot {
        guard !hours.isEmpty || !days.isEmpty else { throw WeatherError.noData }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = place.timeZone

        let hourly = hours.map { h in
            HourlyForecast(time: h.time, temperature: h.temperature, feelsLike: h.feelsLike,
                           condition: condition(h.condition), precipitationProbability: percent(h.precipitationChance),
                           precipitationMm: max(0, h.precipitationMm), windSpeedKmh: h.windKmh,
                           windGustKmh: h.gustKmh, uvIndex: Double(h.uvIndex))
        }
        let hoursByDay = Dictionary(grouping: hourly) { calendar.startOfDay(for: $0.time) }

        let daily = days.map { d -> DailyForecast in
            let day = calendar.startOfDay(for: d.date)
            let dayHours = hoursByDay[day] ?? []
            return DailyForecast(
                date: day, minTemperature: d.low, maxTemperature: d.high, condition: condition(d.condition),
                precipitationProbability: percent(d.precipitationChance),
                precipitationSumMm: dayHours.isEmpty ? nil : dayHours.reduce(0) { $0 + ($1.precipitationMm ?? 0) },
                maxWindKmh: dayHours.compactMap(\.windSpeedKmh).max(),
                uvIndexMax: dayHours.compactMap(\.uvIndex).max(),
                sunrise: d.sunrise, sunset: d.sunset)
        }

        let observation = CurrentConditionsObservation(condition: condition(current.condition),
                                                       precipitationIntensityMmPerHour: current.precipitationIntensityMmPerHour,
                                                       observedAt: current.time)
        let now = CurrentWeather(
            time: current.time, temperature: current.temperature, feelsLike: current.feelsLike,
            condition: CurrentConditionsReconciler.effectiveCondition(observation),
            humidity: Int((min(1, max(0, current.humidity)) * 100).rounded()),
            windSpeedKmh: current.windKmh, windGustKmh: current.gustKmh,
            windDirectionDegrees: current.windDirectionDegrees.map { Int($0.rounded()) % 360 },
            uvIndex: Double(current.uvIndex), isDay: current.isDaylight)

        return WeatherSnapshot(place: place, current: now, hourly: hourly, daily: daily, source: .appleWeather,
                               retrievedAt: retrievedAt, expiresAt: retrievedAt.addingTimeInterval(lifetime))
    }
}
