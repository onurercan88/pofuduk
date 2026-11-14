import Foundation

/// How the user wants their location determined. IP is only ever used when explicitly chosen.
public enum LocationMode: String, Codable, Sendable, CaseIterable {
    /// Device location (When In Use permission only).
    case automatic
    /// Approximate, IP-based. User opt-in; always labelled approximate.
    case ipApproximate
    /// A city/district the user picked.
    case manual
}

public enum LocationPermission: Equatable, Sendable {
    case notDetermined, authorized, denied, restricted, servicesDisabled
}

/// Why a location could not be resolved automatically; the UI offers alternatives.
public enum LocationIssue: Equatable, Sendable {
    case permissionDenied
    case servicesDisabled
    case gpsUnavailable
    case ipUnavailable
    case noManualPlace

    public var turkishExplanation: String {
        switch self {
        case .permissionDenied:
            return "Konum izni verilmedi. Sorun değil! İstersen bir şehir seçebilir ya da yaklaşık konumunu kullanabilirsin."
        case .servicesDisabled:
            return "Cihazında konum servisleri kapalı. Bir şehir seçerek devam edebilirsin."
        case .gpsUnavailable:
            return "Şu an konumunu belirleyemedim. Tekrar deneyebilir ya da bir şehir seçebilirsin."
        case .ipUnavailable:
            return "Yaklaşık konumunu bulamadım. Bir şehir seçerek devam edebilirsin."
        case .noManualPlace:
            return "Havayı anlatabilmem için bir şehir seçmen yeterli."
        }
    }
}

public enum LocationResolution: Equatable, Sendable {
    case resolved(Place)
    /// Show Pofuduk's explanation *before* the system permission prompt.
    case needsPermissionExplanation
    case needsUserChoice(LocationIssue)
}

public enum LocationError: Error, Equatable, Sendable {
    case permissionDenied, unavailable, notFound
}

/// Persisted user choice. Contains only what the user selected; GPS fixes are not stored.
public struct LocationPreference: Codable, Equatable, Sendable {
    public var mode: LocationMode
    public var manualPlace: Place?
    /// Last place used for a forecast, coarsened to ~1 km (2 decimals). Used only for background
    /// notification refresh, which cannot ask for location.
    public var lastPlace: Place?

    public init(mode: LocationMode = .automatic, manualPlace: Place? = nil, lastPlace: Place? = nil) {
        self.mode = mode
        self.manualPlace = manualPlace
        self.lastPlace = lastPlace
    }

    /// Place for background work: the user's manual choice, else the last (coarsened) place.
    public var backgroundPlace: Place? { mode == .manual ? manualPlace : lastPlace }

    public static func coarsened(_ place: Place) -> Place {
        var p = place
        p.coordinate = Coordinate(latitude: (place.coordinate.latitude * 100).rounded() / 100,
                                  longitude: (place.coordinate.longitude * 100).rounded() / 100)
        return p
    }
}
