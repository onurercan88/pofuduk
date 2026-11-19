import Foundation

/// A second, independent reading of the weather right now (Apple Weather via WeatherKit).
/// Used only to correct the forecast provider's "now" when it misses precipitation.
public struct CurrentConditionsObservation: Equatable, Sendable {
    public var condition: WeatherCondition
    /// Millimetres per hour; nil when the service doesn't report it.
    public var precipitationIntensityMmPerHour: Double?
    public var observedAt: Date

    public init(condition: WeatherCondition, precipitationIntensityMmPerHour: Double? = nil, observedAt: Date) {
        self.condition = condition
        self.precipitationIntensityMmPerHour = precipitationIntensityMmPerHour
        self.observedAt = observedAt
    }
}

public protocol CurrentConditionsProvider: Sendable {
    var source: WeatherDataSource { get }
    func currentConditions(for place: Place) async throws -> CurrentConditionsObservation
}

/// Merges a cross-check observation into the provider's current weather.
/// Rule: precipitation reported by either source wins (a missed shower is worse than an extra umbrella);
/// a dry observation never removes the provider's precipitation, and only a heavier kind replaces a lighter one.
public enum CurrentConditionsReconciler {
    /// Older observations are ignored.
    public static let maxObservationAge: TimeInterval = 30 * 60

    public static func reconcile(_ current: CurrentWeather, with observation: CurrentConditionsObservation,
                                 now: Date) -> CurrentWeather {
        guard abs(now.timeIntervalSince(observation.observedAt)) <= maxObservationAge else { return current }
        let observed = effectiveCondition(observation)
        guard observed.isPrecipitation, severity(observed) > severity(current.condition) else { return current }
        var merged = current
        merged.condition = observed
        return merged
    }

    /// A non-precipitation condition with a measurable intensity counts as drizzle/rain
    /// (same thresholds as the Open-Meteo current-condition correction).
    static func effectiveCondition(_ observation: CurrentConditionsObservation) -> WeatherCondition {
        guard !observation.condition.isPrecipitation,
              let mm = observation.precipitationIntensityMmPerHour, mm >= 0.1 else { return observation.condition }
        return mm < 0.5 ? .drizzle : .rain
    }

    static func severity(_ condition: WeatherCondition) -> Int {
        switch condition {
        case .drizzle: return 1
        case .rain, .snow, .sleet: return 2
        case .heavyRain: return 3
        case .thunderstorm: return 4
        default: return 0
        }
    }
}

/// Maps Apple Weather (`WeatherKit.WeatherCondition.rawValue`) to Pofuduk conditions. Unknown → nil.
public enum AppleWeatherConditionMapper {
    public static func condition(rawValue: String) -> WeatherCondition? {
        switch rawValue {
        case "clear", "mostlyClear", "hot", "frigid": return .clear
        case "partlyCloudy": return .partlyCloudy
        case "mostlyCloudy", "cloudy": return .cloudy
        case "foggy", "haze", "smoky": return .fog
        case "breezy", "windy", "blowingDust": return .windy
        case "drizzle", "freezingDrizzle": return .drizzle
        case "rain", "sunShowers", "freezingRain": return .rain
        case "heavyRain": return .heavyRain
        case "isolatedThunderstorms", "scatteredThunderstorms", "thunderstorms", "strongStorms",
             "tropicalStorm", "hurricane": return .thunderstorm
        case "snow", "heavySnow", "flurries", "sunFlurries", "blizzard", "blowingSnow": return .snow
        case "sleet", "wintryMix", "hail": return .sleet
        default: return nil
        }
    }
}

/// Wraps the forecast repository and cross-checks "now" against a second source.
/// The cross-check is best effort: failures, timeouts, demo and stale data leave the snapshot unchanged,
/// and it is skipped when the forecast already comes from the checking source.
/// Observations are reused for `observationTTL` per ~1 km cell to limit calls.
public struct CrossCheckedWeatherRepository: WeatherRepository {
    private let base: WeatherRepository
    private let checker: CurrentConditionsProvider
    private let cache = ObservationCache()
    private let now: @Sendable () -> Date
    public var timeout: TimeInterval
    public var observationTTL: TimeInterval

    public init(base: WeatherRepository, checker: CurrentConditionsProvider, timeout: TimeInterval = 5,
                observationTTL: TimeInterval = 10 * 60, now: @escaping @Sendable () -> Date = { Date() }) {
        self.base = base
        self.checker = checker
        self.timeout = timeout
        self.observationTTL = observationTTL
        self.now = now
    }

    public func snapshot(for place: Place, forceRefresh: Bool) async throws -> WeatherSnapshot {
        var snapshot = try await base.snapshot(for: place, forceRefresh: forceRefresh)
        let current = now()
        guard snapshot.source != .demo, snapshot.source != checker.source, !snapshot.isStale(at: current),
              let observation = await observation(for: place, at: current) else { return snapshot }
        snapshot.current = CurrentConditionsReconciler.reconcile(snapshot.current, with: observation, now: current)
        snapshot.crossCheckSource = checker.source
        return snapshot
    }

    private func observation(for place: Place, at date: Date) async -> CurrentConditionsObservation? {
        let key = CachedWeatherRepository.key(for: place)
        if let cached = await cache.value(for: key, at: date, ttl: observationTTL) { return cached }
        let checker = self.checker
        let timeout = self.timeout
        let fetched = await withTaskGroup(of: CurrentConditionsObservation?.self) { group in
            group.addTask { try? await checker.currentConditions(for: place) }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        if let fetched { await cache.store(fetched, for: key, at: date) }
        return fetched
    }
}

private actor ObservationCache {
    private var entries: [String: (observation: CurrentConditionsObservation, storedAt: Date)] = [:]

    func value(for key: String, at date: Date, ttl: TimeInterval) -> CurrentConditionsObservation? {
        guard let entry = entries[key], date.timeIntervalSince(entry.storedAt) < ttl else { return nil }
        return entry.observation
    }

    func store(_ observation: CurrentConditionsObservation, for key: String, at date: Date) {
        entries[key] = (observation, date)
    }
}
