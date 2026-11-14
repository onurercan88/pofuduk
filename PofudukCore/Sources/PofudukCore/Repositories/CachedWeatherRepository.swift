import Foundation

/// Persists the last successful snapshot per location.
public protocol WeatherCacheStore: Sendable {
    func load(key: String) async -> WeatherSnapshot?
    func save(_ snapshot: WeatherSnapshot, key: String) async
    func removeAll() async
}

public actor InMemoryWeatherCacheStore: WeatherCacheStore {
    private var storage: [String: WeatherSnapshot] = [:]
    public init() {}
    public func load(key: String) -> WeatherSnapshot? { storage[key] }
    public func save(_ snapshot: WeatherSnapshot, key: String) { storage[key] = snapshot }
    public func removeAll() { storage.removeAll() }
}

/// JSON files in a caches directory. Contains only forecast data + the place the user selected.
public actor FileWeatherCacheStore: WeatherCacheStore {
    private let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func file(_ key: String) -> URL { directory.appendingPathComponent("forecast-\(key).json") }

    public func load(key: String) -> WeatherSnapshot? {
        guard let data = try? Data(contentsOf: file(key)) else { return nil }
        return try? decoder.decode(WeatherSnapshot.self, from: data)
    }

    public func save(_ snapshot: WeatherSnapshot, key: String) {
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: file(key), options: .atomic)
    }

    public func removeAll() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for f in files where f.lastPathComponent.hasPrefix("forecast-") { try? FileManager.default.removeItem(at: f) }
    }
}

/// Fresh cache → returned without network. Otherwise fetch via fallback providers.
/// If every provider fails, a cached snapshot younger than `maxStaleAge` is returned — it stays marked
/// stale by its `expiresAt`, so the UI and briefing disclose it. Never presents old data as live.
public struct CachedWeatherRepository: WeatherRepository {
    private let engine: WeatherProviderFallbackEngine
    private let cache: WeatherCacheStore
    private let now: @Sendable () -> Date
    public var maxStaleAge: TimeInterval

    public init(engine: WeatherProviderFallbackEngine, cache: WeatherCacheStore,
                maxStaleAge: TimeInterval = 6 * 3600, now: @escaping @Sendable () -> Date = { Date() }) {
        self.engine = engine
        self.cache = cache
        self.maxStaleAge = maxStaleAge
        self.now = now
    }

    /// ~1 km grid so nearby requests share a cache entry.
    static func key(for place: Place) -> String {
        String(format: "%.2f_%.2f", place.coordinate.latitude, place.coordinate.longitude)
    }

    public func snapshot(for place: Place, forceRefresh: Bool) async throws -> WeatherSnapshot {
        let key = Self.key(for: place)
        let cached = await cache.load(key: key)
        let current = now()
        if !forceRefresh, let cached, !cached.isStale(at: current) {
            return withPlace(cached, place)
        }
        do {
            let outcome = try await engine.fetch(for: place)
            await cache.save(outcome.snapshot, key: key)
            return outcome.snapshot
        } catch {
            if let cached, current.timeIntervalSince(cached.retrievedAt) < maxStaleAge {
                return withPlace(cached, place)
            }
            throw error
        }
    }

    /// Cached data keeps its provenance but shows the currently selected place name.
    private func withPlace(_ snapshot: WeatherSnapshot, _ place: Place) -> WeatherSnapshot {
        var s = snapshot
        s.place = place
        return s
    }
}
