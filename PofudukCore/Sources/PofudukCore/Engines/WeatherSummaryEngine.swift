import Foundation

public enum PrecipitationKind: String, Sendable, Equatable {
    case rain, snow, sleet, thunderstorm
}

public enum PrecipitationIntensity: String, Sendable, Equatable {
    /// Amount data missing and condition not specific → never call it heavy.
    case unknown, light, moderate, heavy
}

public struct PrecipitationOutlook: Equatable, Sendable {
    public var kind: PrecipitationKind
    public var start: Date
    /// Exclusive end of the last wet hour in the first continuous wet period.
    public var end: Date
    /// The period reaches the end of today's analysed window (it may continue beyond).
    public var lastsUntilEndOfDay: Bool
    public var intensity: PrecipitationIntensity
    public var maxProbability: Int?
    public var totalMm: Double?
    /// true = at or above the "likely" threshold; false = only "possible" (communicate uncertainty).
    public var isLikely: Bool

    public var durationHours: Int { max(1, Int((end.timeIntervalSince(start) / 3600).rounded())) }
}

public struct WindOutlook: Equatable, Sendable {
    public var maxSpeedKmh: Double
    public var maxGustKmh: Double?
    public var isStrong: Bool
}

public struct WeatherAnalysis: Equatable, Sendable {
    public var place: Place
    public var source: WeatherDataSource
    public var analyzedAt: Date
    public var isStale: Bool
    public var retrievedAt: Date

    public var current: CurrentWeather
    public var minTemperature: Double?
    public var maxTemperature: Double?
    public var feelsLikeIsNotable: Bool
    public var temperatureSwingIsNotable: Bool

    /// First continuous precipitation period in the rest of today, if any.
    public var precipitation: PrecipitationOutlook?
    /// Hourly data covers the rest of today, so "no rain expected" can be stated.
    public var hasHourlyCoverage: Bool
    public var wind: WindOutlook?
    public var uvMax: Double?
    public var isHighUV: Bool

    public var theme: WeatherTheme
}

/// Turns a snapshot into facts. Produces no wording; that is the personality engine's job.
public struct WeatherSummaryEngine: Sendable {
    public var thresholds: WeatherThresholds

    public init(thresholds: WeatherThresholds = .default) {
        self.thresholds = thresholds
    }

    public func analyze(_ snapshot: WeatherSnapshot, now: Date) -> WeatherAnalysis {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = snapshot.place.timeZone

        let hourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let dayInterval = calendar.dateInterval(of: .day, for: now)
        let dayEnd = dayInterval?.end ?? now.addingTimeInterval(86_400)
        let remaining = snapshot.hourly.filter { $0.time >= hourStart && $0.time < dayEnd }

        let today = snapshot.daily.first { calendar.isDate($0.date, inSameDayAs: now) }
        let todayHours = snapshot.hourly.filter { dayInterval?.contains($0.time) ?? false }
        let minT = today?.minTemperature ?? todayHours.map(\.temperature).min()
        let maxT = today?.maxTemperature ?? todayHours.map(\.temperature).max()

        let precipitation = precipitationOutlook(in: remaining, dayEnd: dayEnd)
        let wind = windOutlook(current: snapshot.current, hours: remaining)
        let uvValues = remaining.compactMap(\.uvIndex) + [snapshot.current.uvIndex, today?.uvIndexMax].compactMap { $0 }
        let uvMax = uvValues.max()

        let current = snapshot.current
        let feelsNotable = abs(current.feelsLike - current.temperature) >= thresholds.notableFeelsLikeDifference
        let swingNotable: Bool = {
            guard let minT, let maxT else { return false }
            return maxT - minT >= thresholds.notableTemperatureSwing
        }()

        // Coverage: hourly data reaches at least the last hour of today (or there is nothing left of today).
        let lastHourOfDay = dayEnd.addingTimeInterval(-3600)
        let coverage = !remaining.isEmpty && (remaining.last!.time >= lastHourOfDay)

        let theme = Self.theme(current: current, precipitation: precipitation, wind: wind)

        return WeatherAnalysis(
            place: snapshot.place,
            source: snapshot.source,
            analyzedAt: now,
            isStale: snapshot.isStale(at: now),
            retrievedAt: snapshot.retrievedAt,
            current: current,
            minTemperature: minT,
            maxTemperature: maxT,
            feelsLikeIsNotable: feelsNotable,
            temperatureSwingIsNotable: swingNotable,
            precipitation: precipitation,
            hasHourlyCoverage: coverage,
            wind: wind,
            uvMax: uvMax,
            isHighUV: (uvMax ?? 0) >= thresholds.highUVIndex,
            theme: theme
        )
    }

    // MARK: - Precipitation

    func effectiveProbability(_ hour: HourlyForecast) -> Int {
        if let p = hour.precipitationProbability { return p }
        // No probability given: trust an explicit precipitation condition or amount from the source.
        if hour.condition.isPrecipitation || (hour.precipitationMm ?? 0) >= thresholds.minimumWetHourMm {
            return thresholds.likelyPrecipitationProbability
        }
        return 0
    }

    func isWetCandidate(_ hour: HourlyForecast) -> Bool {
        guard effectiveProbability(hour) >= thresholds.possiblePrecipitationProbability else { return false }
        // If the source gives an amount of ~0 and no precipitation condition, ignore the probability.
        if let mm = hour.precipitationMm, mm < thresholds.minimumWetHourMm, !hour.condition.isPrecipitation {
            return false
        }
        return true
    }

    func isLikelyWet(_ hour: HourlyForecast) -> Bool {
        isWetCandidate(hour) && effectiveProbability(hour) >= thresholds.likelyPrecipitationProbability
    }

    /// First continuous run of hours matching `predicate`.
    func firstRun(in hours: [HourlyForecast], where predicate: (HourlyForecast) -> Bool) -> [HourlyForecast] {
        guard let firstIndex = hours.firstIndex(where: predicate) else { return [] }
        var run: [HourlyForecast] = []
        for hour in hours[firstIndex...] {
            guard predicate(hour) else { break }
            if let last = run.last, hour.time.timeIntervalSince(last.time) > 3600 { break }
            run.append(hour)
        }
        return run
    }

    /// Prefers the first *likely* period; only if none exists reports a *possible* period.
    /// Possible hours are never merged into a likely period (that would overstate duration).
    func precipitationOutlook(in hours: [HourlyForecast], dayEnd: Date? = nil) -> PrecipitationOutlook? {
        var run = firstRun(in: hours, where: isLikelyWet)
        if run.isEmpty { run = firstRun(in: hours, where: isWetCandidate) }
        guard !run.isEmpty else { return nil }

        let probabilities = run.compactMap(\.precipitationProbability)
        let maxProbability = probabilities.max()
        let effectiveMax = run.map(effectiveProbability).max() ?? 0
        let amounts = run.compactMap(\.precipitationMm)
        let total: Double? = amounts.isEmpty ? nil : amounts.reduce(0, +)

        let kind: PrecipitationKind
        if run.contains(where: { $0.condition == .thunderstorm }) {
            kind = .thunderstorm
        } else if run.filter({ $0.condition == .snow }).count * 2 > run.count {
            kind = .snow
        } else if run.contains(where: { $0.condition == .sleet }) {
            kind = .sleet
        } else {
            kind = .rain
        }

        let end = run[run.count - 1].time.addingTimeInterval(3600)
        return PrecipitationOutlook(
            kind: kind,
            start: run[0].time,
            end: end,
            lastsUntilEndOfDay: dayEnd.map { end >= $0 } ?? false,
            intensity: intensity(for: run, maxRate: amounts.max()),
            maxProbability: maxProbability,
            totalMm: total,
            isLikely: effectiveMax >= thresholds.likelyPrecipitationProbability
        )
    }

    func intensity(for run: [HourlyForecast], maxRate: Double?) -> PrecipitationIntensity {
        if let rate = maxRate {
            if rate >= thresholds.heavyRainMmPerHour { return .heavy }
            if rate >= thresholds.moderateRainMmPerHour { return .moderate }
            return .light
        }
        // No amounts: only the provider's explicit condition may indicate intensity.
        if run.contains(where: { $0.condition == .heavyRain }) { return .heavy }
        if run.allSatisfy({ $0.condition == .drizzle }) { return .light }
        return .unknown
    }

    // MARK: - Wind

    func windOutlook(current: CurrentWeather, hours: [HourlyForecast]) -> WindOutlook? {
        let speeds = hours.compactMap(\.windSpeedKmh) + [current.windSpeedKmh]
        let gusts = hours.compactMap(\.windGustKmh) + [current.windGustKmh].compactMap { $0 }
        guard let maxSpeed = speeds.max() else { return nil }
        let maxGust = gusts.max()
        let strong = maxSpeed >= thresholds.strongWindKmh || (maxGust ?? 0) >= thresholds.strongGustKmh
        return WindOutlook(maxSpeedKmh: maxSpeed, maxGustKmh: maxGust, isStrong: strong)
    }

    // MARK: - Theme

    static func theme(current: CurrentWeather, precipitation: PrecipitationOutlook?, wind: WindOutlook?) -> WeatherTheme {
        if current.condition == .thunderstorm || (precipitation?.kind == .thunderstorm && precipitation?.isLikely == true) {
            return .stormy
        }
        if current.condition == .snow || current.condition == .sleet
            || (precipitation?.kind == .snow && precipitation?.isLikely == true) {
            return .snowy
        }
        if current.condition.isPrecipitation || precipitation?.isLikely == true { return .rainy }
        if wind?.isStrong == true || current.condition == .windy { return .windy }
        if !current.isDay { return .night }
        switch current.condition {
        case .clear, .partlyCloudy: return .sunny
        default: return .cloudy
        }
    }
}
