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

    func currentPlace() async throws -> Place {
        guard permission == .authorized else { throw LocationError.permissionDenied }
        locationContinuation?.resume(throwing: LocationError.unavailable)
        let location: CLLocation = try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
        return await place(for: location)
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

    static func map(_ status: CLAuthorizationStatus) -> LocationPermission {
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
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.locationContinuation?.resume(returning: location)
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let denied = (error as? CLError)?.code == .denied
        Task { @MainActor in
            self.locationContinuation?.resume(throwing: denied ? LocationError.permissionDenied : LocationError.unavailable)
            self.locationContinuation = nil
        }
    }
}
