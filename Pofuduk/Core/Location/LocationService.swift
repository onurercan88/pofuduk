import Foundation
import MapKit
import PofudukCore

/// App-facing location API. Policy lives in `LocationResolver` (PofudukCore).
@MainActor
protocol LocationServicing: AnyObject {
    var preference: LocationPreference { get }
    var isIPAvailable: Bool { get }
    func resolve() async -> LocationResolution
    func requestPermission() async
    func setMode(_ mode: LocationMode)
    func selectManual(_ place: Place)
}

@MainActor
final class LocationService: LocationServicing {
    private let device: CoreLocationProvider
    private let ipProvider: LocationProvider?
    private let store: LocationPreferenceStore
    private let resolver = LocationResolver()
    private(set) var preference: LocationPreference

    init(device: CoreLocationProvider = CoreLocationProvider(), ipProvider: LocationProvider?,
         store: LocationPreferenceStore = UserDefaultsLocationPreferenceStore()) {
        self.device = device
        self.ipProvider = ipProvider
        self.store = store
        self.preference = store.load()
    }

    var isIPAvailable: Bool { ipProvider != nil }

    func resolve() async -> LocationResolution {
        let device = self.device
        var ip: (() async throws -> Place)?
        if let provider = ipProvider {
            ip = { try await provider.currentPlace() }
        }
        return await resolver.resolve(
            preference: preference,
            permission: device.permission,
            gps: { try await device.currentPlace() },
            ip: ip)
    }

    func requestPermission() async {
        setMode(.automatic)
        _ = await device.requestWhenInUse()
    }

    func setMode(_ mode: LocationMode) {
        preference.mode = mode
        store.save(preference)
    }

    func selectManual(_ place: Place) {
        var p = place
        p.source = .manual
        preference = LocationPreference(mode: .manual, manualPlace: p)
        store.save(preference)
    }
}

/// District/city search via Apple's geocoding (no API key), limited to Turkey.
enum PlaceSearch {
    static func search(_ text: String) async -> [Place] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = .address
        request.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 39.0, longitude: 35.2),
                                            span: MKCoordinateSpan(latitudeDelta: 8, longitudeDelta: 20))
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        return response.mapItems.compactMap { item in
            let pm = item.placemark
            guard pm.isoCountryCode == "TR" else { return nil }
            let province = pm.administrativeArea
            let district = pm.subAdministrativeArea ?? pm.locality ?? item.name
            return Place(name: province ?? district ?? "Seçilen konum", district: district, province: province,
                         coordinate: Coordinate(latitude: pm.coordinate.latitude, longitude: pm.coordinate.longitude),
                         timeZoneIdentifier: item.timeZone?.identifier ?? "Europe/Istanbul", source: .manual)
        }
    }
}
