import Foundation

/// Decides how to obtain the place for the forecast. Pure policy, independent of weather providers.
/// - Never requests location without an explanation first.
/// - Never falls back to IP silently: IP is used only when the user chose `.ipApproximate`.
public struct LocationResolver: Sendable {
    public init() {}

    public func resolve(
        preference: LocationPreference,
        permission: LocationPermission,
        gps: () async throws -> Place,
        ip: (() async throws -> Place)?
    ) async -> LocationResolution {
        switch preference.mode {
        case .manual:
            guard let place = preference.manualPlace else { return .needsUserChoice(.noManualPlace) }
            return .resolved(place)

        case .ipApproximate:
            guard let ip else { return .needsUserChoice(.ipUnavailable) }
            do {
                var place = try await ip()
                place.source = .ipApproximate
                return .resolved(place)
            } catch {
                return .needsUserChoice(.ipUnavailable)
            }

        case .automatic:
            switch permission {
            case .notDetermined: return .needsPermissionExplanation
            case .denied, .restricted: return .needsUserChoice(.permissionDenied)
            case .servicesDisabled: return .needsUserChoice(.servicesDisabled)
            case .authorized:
                do {
                    var place = try await gps()
                    place.source = .gps
                    return .resolved(place)
                } catch LocationError.permissionDenied {
                    return .needsUserChoice(.permissionDenied)
                } catch {
                    return .needsUserChoice(.gpsUnavailable)
                }
            }
        }
    }
}

/// Persists the user's location preference.
public protocol LocationPreferenceStore: Sendable {
    func load() -> LocationPreference
    func save(_ preference: LocationPreference)
    func clear()
}

public final class UserDefaultsLocationPreferenceStore: LocationPreferenceStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "pofuduk.locationPreference"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> LocationPreference {
        guard let data = defaults.data(forKey: key),
              let pref = try? JSONDecoder().decode(LocationPreference.self, from: data) else { return LocationPreference() }
        return pref
    }

    public func save(_ preference: LocationPreference) {
        if let data = try? JSONEncoder().encode(preference) { defaults.set(data, forKey: key) }
    }

    public func clear() { defaults.removeObject(forKey: key) }
}
