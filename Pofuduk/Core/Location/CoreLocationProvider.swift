import CoreLocation
import PofudukCore

/// One-shot device location (When In Use only, ~1 km accuracy). No continuous tracking, no "Always".
@MainActor
final class CoreLocationProvider: NSObject {
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var authContinuation: CheckedContinuation<LocationPermission, Never>?
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var permission: LocationPermission { Self.map(manager.authorizationStatus) }

    /// Shows the system prompt only if undecided; must be called after Pofuduk's own explanation.
    func requestWhenInUse() async -> LocationPermission {
        guard manager.authorizationStatus == .notDetermined else { return permission }
        return await withCheckedContinuation { continuation in
            authContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    /// How long to wait for a fix. A cold start indoors can take several seconds.
    static let fixTimeout: Duration = .seconds(12)
    /// A system-cached fix this recent is used right away.
    nonisolated static let freshFixAge: TimeInterval = 2 * 60
    /// On timeout, a cached fix up to this old is still better than "konumunu bulamadım".
    nonisolated static let fallbackFixAge: TimeInterval = 30 * 60
    private var request = 0

    /// `requestLocation()` gives up on the first `locationUnknown` (common right after launch with a cold
    /// GPS; "Tekrar dene" then worked). Instead: use a fresh cached fix, else keep updating until the
    /// first usable fix or the timeout.
    func currentPlace() async throws -> Place {
        guard permission == .authorized else { throw LocationError.permissionDenied }
        if let cached = manager.location, Self.isUsable(cached, maxAge: Self.freshFixAge) {
            return await place(for: cached)
        }
        finish(.failure(LocationError.unavailable))
        request += 1
        let id = request
        let location: CLLocation = try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.startUpdatingLocation()
            Task { [weak self] in
                try? await Task.sleep(for: Self.fixTimeout)
                guard let self, self.request == id, self.locationContinuation != nil else { return }
                if let cached = self.manager.location, Self.isUsable(cached, maxAge: Self.fallbackFixAge) {
                    self.finish(.success(cached))
                } else {
                    self.finish(.failure(LocationError.unavailable))
                }
            }
        }
        return await place(for: location)
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        guard let continuation = locationContinuation else { return }
        locationContinuation = nil
        manager.stopUpdatingLocation()
        continuation.resume(with: result)
    }

    nonisolated static func isUsable(_ location: CLLocation, maxAge: TimeInterval) -> Bool {
        location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 5_000
            && abs(location.timestamp.timeIntervalSinceNow) <= maxAge
    }

    private func place(for location: CLLocation) async -> Place {
        let coordinate = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        let placemark = try? await geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "tr_TR")).first
        let province = placemark?.administrativeArea
        let district = placemark?.subAdministrativeArea ?? placemark?.locality
        return Place(name: province ?? district ?? "Bulunduğun konum", district: district, province: province,
                     coordinate: coordinate,
                     timeZoneIdentifier: placemark?.timeZone?.identifier ?? TimeZone.current.identifier,
                     source: .gps)
    }

    nonisolated static func map(_ status: CLAuthorizationStatus) -> LocationPermission {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorizedWhenInUse, .authorizedAlways: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .denied
        }
    }
}

extension CoreLocationProvider: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = Self.map(manager.authorizationStatus)
        Task { @MainActor in
            guard status != .notDetermined, let c = self.authContinuation else { return }
            self.authContinuation = nil
            c.resume(returning: status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Skip stale or invalid fixes; keep waiting for a usable one (or the timeout).
        guard let location = locations.last(where: { Self.isUsable($0, maxAge: Self.freshFixAge) }) else { return }
        Task { @MainActor in self.finish(.success(location)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let code = (error as? CLError)?.code
        // "Unable to retrieve a location right away": Core Location keeps trying, so keep waiting.
        guard code != .locationUnknown else { return }
        Task { @MainActor in
            self.finish(.failure(code == .denied ? LocationError.permissionDenied : LocationError.unavailable))
        }
    }
}
