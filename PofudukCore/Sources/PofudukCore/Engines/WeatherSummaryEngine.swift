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

/// Part of the day the briefing is given in. Decides which hours are worth talking about.
public enum BriefingTime: String, Sendable, Equatable {
    /// 00.00–12.59: the whole day is still ahead.
    case morning
    /// 13.00–16.59: talk about the rest of the day.
    case afternoon
    /// 17.00–21.59: talk about tonight and tomorrow.
    case evening
    /// 22.00–23.59: talk about the night and tomorrow.
    case night

    public init(hour: Int) {
        switch hour {
        case 13..<17: self = .afternoon
        case 17..<22: self = .evening
        case 22...23: self = .night
        default: self = .morning
        }
    }

    public var looksAhead: Bool { self == .evening || self == .night }
}

public struct TomorrowOutlook: Equatable, Sendable {
    public var low: Double
    public var high: Double
    public var condition: WeatherCondition
    public var precipitationProbability: Int?
    /// At or above the "likely" threshold (with an amount, if the source gives one).
    public var precipitationLikely: Bool
    /// Between the "possible" and "likely" thresholds.
    public var precipitationPossible: Bool
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

    public var briefingTime: BriefingTime
    /// Lowest / highest temperature from the current hour to the end of today.
    public var restOfDayLow: Double?
    public var restOfDayHigh: Double?
    /// Lowest temperature from now until 07.00 tomorrow (evening and night briefings).
    public var tonightLow: Double?
    public var tomorrow: TomorrowOutlook?

    /// Character look: the weather now (and precipitation starting within the hour).
    public var theme: WeatherTheme
    /// The rest of today (precipitation at any later hour counts). Drives wording, not the look.
    public var outlookTheme: WeatherTheme
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

        let theme = Self.theme(current: current, precipitation: precipitation, wind: wind, now: now)
        let outlookTheme = Self.theme(current: current, precipitation: precipitation, wind: wind, now: now,
                                      leadTime: .infinity)

        let briefingTime = BriefingTime(hour: calendar.component(.hour, from: now))
        let remainingTemps = remaining.map(\.temperature) + [current.temperature]
        let tonightEnd = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: dayEnd) ?? dayEnd
        let tonightTemps = snapshot.hourly.filter { $0.time >= hourStart && $0.time < tonightEnd }.map(\.temperature)
            + [current.temperature]
        let tomorrow = tomorrowOutlook(snapshot.daily.first { calendar.isDate($0.date, inSameDayAs: dayEnd) })

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
            briefingTime: briefingTime,
            restOfDayLow: remaining.isEmpty ? nil : remainingTemps.min(),
            restOfDayHigh: remaining.isEmpty ? nil : remainingTemps.max(),
            tonightLow: tonightTemps.count > 1 ? tonightTemps.min() : nil,
            tomorrow: tomorrow,
            theme: theme,
            outlookTheme: outlookTheme
        )
    }

    // MARK: - Tomorrow

    func tomorrowOutlook(_ day: DailyForecast?) -> TomorrowOutlook? {
        guard let day else { return nil }
        let p = day.precipitationProbability ?? (day.condition.isPrecipitation ? thresholds.likelyPrecipitationProbability : 0)
        // Amount given and ~0 → the probability alone does not make it a wet day.
        let dryByAmount = (day.precipitationSumMm.map { $0 < thresholds.minimumWetHourMm } ?? false) && !day.condition.isPrecipitation
        let likely = !dryByAmount && p >= thresholds.likelyPrecipitationProbability
        let possible = !dryByAmount && !likely && p >= thresholds.possiblePrecipitationProbability
        return TomorrowOutlook(low: day.minTemperature, high: day.maxTemperature, condition: day.condition,
                               precipitationProbability: day.precipitationProbability,
                               precipitationLikely: likely, precipitationPossible: possible)
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

    /// How soon forecast precipitation must start to change the character's look.
    /// The look shows the weather *now*; rain expected later is told in words, not shown.
    static let themePrecipitationLeadTime: TimeInterval = 60 * 60

    static func theme(current: CurrentWeather, precipitation: PrecipitationOutlook?, wind: WindOutlook?,
                      now: Date, leadTime: TimeInterval = themePrecipitationLeadTime) -> WeatherTheme {
        let imminent = precipitation.flatMap { p in
            p.isLikely && p.start.timeIntervalSince(now) <= leadTime ? p : nil
        }
        if current.condition == .thunderstorm || imminent?.kind == .thunderstorm {
            return .stormy
        }
        if current.condition == .snow || current.condition == .sleet || imminent?.kind == .snow {
            return .snowy
        }
        if current.condition.isPrecipitation || imminent != nil { return .rainy }
        if wind?.isStrong == true || current.condition == .windy { return .windy }
        if !current.isDay { return .night }
        switch current.condition {
        case .clear, .partlyCloudy: return .sunny
        default: return .cloudy
        }
    }
}
