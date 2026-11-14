import Foundation

/// Tries providers in priority order and returns the first successful snapshot.
public struct WeatherProviderFallbackEngine: Sendable {
    public let providers: [WeatherProvider]

    public init(providers: [WeatherProvider]) {
        self.providers = providers
    }

    public struct Outcome: Sendable {
        public var snapshot: WeatherSnapshot
        /// Providers that failed before the successful one (for diagnostics; contains no secrets).
        public var failures: [(WeatherDataSource, WeatherError)]
    }

    public func fetch(for place: Place) async throws -> Outcome {
        var failures: [(WeatherDataSource, WeatherError)] = []
        for provider in providers {
            do {
                let snapshot = try await provider.fetchSnapshot(for: place)
                return Outcome(snapshot: snapshot, failures: failures)
            } catch {
                failures.append((provider.source, (error as? WeatherError) ?? .network))
            }
        }
        // Report the most informative error: a configuration/rate problem beats a generic network failure.
        let errors = failures.map(\.1)
        throw errors.first { $0 != .network && $0 != .missingAPIKey } ?? errors.last ?? .noData
    }
}
