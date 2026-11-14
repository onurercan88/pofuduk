import XCTest
@testable import PofudukCore

final class LocationResolverTests: XCTestCase {
    let resolver = LocationResolver()
    let gpsPlace = Place(name: "Kadıköy", coordinate: Coordinate(latitude: 40.99, longitude: 29.03),
                         timeZoneIdentifier: "Europe/Istanbul", source: .manual)
    let ipPlace = Place(name: "Ankara", coordinate: Coordinate(latitude: 39.93, longitude: 32.86),
                        timeZoneIdentifier: "Europe/Istanbul", source: .manual)

    final class Counter: @unchecked Sendable { var gps = 0, ip = 0 }

    private func resolve(_ mode: LocationMode, _ permission: LocationPermission, manual: Place? = nil,
                         gpsFails: Error? = nil, ipFails: Bool = false, ipAvailable: Bool = true,
                         counter: Counter = Counter()) async -> LocationResolution {
        let gps = gpsPlace, ip = ipPlace
        return await resolver.resolve(
            preference: LocationPreference(mode: mode, manualPlace: manual),
            permission: permission,
            gps: { counter.gps += 1; if let gpsFails { throw gpsFails }; return gps },
            ip: ipAvailable ? { counter.ip += 1; if ipFails { throw LocationError.notFound }; return ip } : nil)
    }

    func testPermissionNotDeterminedAsksForExplanationFirst() async {
        let counter = Counter()
        let r = await resolve(.automatic, .notDetermined, counter: counter)
        XCTAssertEqual(r, .needsPermissionExplanation)
        XCTAssertEqual(counter.gps, 0)
    }

    func testPermissionGrantedUsesGPS() async {
        guard case .resolved(let place) = await resolve(.automatic, .authorized) else { return XCTFail() }
        XCTAssertEqual(place.name, "Kadıköy")
        XCTAssertEqual(place.source, .gps)
    }

    func testPermissionDeniedNeverFallsBackToIPSilently() async {
        let counter = Counter()
        let r = await resolve(.automatic, .denied, counter: counter)
        XCTAssertEqual(r, .needsUserChoice(.permissionDenied))
        XCTAssertEqual(counter.ip, 0)
        XCTAssertEqual(counter.gps, 0)
    }

    func testRestrictedAndServicesDisabled() async {
        let restricted = await resolve(.automatic, .restricted)
        XCTAssertEqual(restricted, .needsUserChoice(.permissionDenied))
        let disabled = await resolve(.automatic, .servicesDisabled)
        XCTAssertEqual(disabled, .needsUserChoice(.servicesDisabled))
    }

    func testLocationServiceUnavailable() async {
        let r = await resolve(.automatic, .authorized, gpsFails: LocationError.unavailable)
        XCTAssertEqual(r, .needsUserChoice(.gpsUnavailable))
    }

    func testIPSelectedIsMarkedApproximate() async {
        guard case .resolved(let place) = await resolve(.ipApproximate, .denied) else { return XCTFail() }
        XCTAssertEqual(place.source, .ipApproximate)
    }

    func testIPFailureOrUnavailable() async {
        let failed = await resolve(.ipApproximate, .denied, ipFails: true)
        XCTAssertEqual(failed, .needsUserChoice(.ipUnavailable))
        let unavailable = await resolve(.ipApproximate, .denied, ipAvailable: false)
        XCTAssertEqual(unavailable, .needsUserChoice(.ipUnavailable))
    }

    func testManualCitySelected() async {
        let bursa = TurkishProvinces.search("bursa")[0].place
        let counter = Counter()
        let r = await resolve(.manual, .denied, manual: bursa, counter: counter)
        XCTAssertEqual(r, .resolved(bursa))
        XCTAssertEqual(counter.gps + counter.ip, 0)
    }

    func testManualWithoutPlaceAsksUser() async {
        let r = await resolve(.manual, .authorized)
        XCTAssertEqual(r, .needsUserChoice(.noManualPlace))
    }

    func testPreferenceStoreRoundTrip() {
        let defaults = UserDefaults(suiteName: "LocationResolverTests")!
        defaults.removePersistentDomain(forName: "LocationResolverTests")
        let store = UserDefaultsLocationPreferenceStore(defaults: defaults)
        XCTAssertEqual(store.load(), LocationPreference())
        let pref = LocationPreference(mode: .manual, manualPlace: TurkishProvinces.all[33].place)
        store.save(pref)
        XCTAssertEqual(store.load(), pref)
        store.clear()
        XCTAssertEqual(store.load().mode, .automatic)
    }
}

final class TurkishProvincesTests: XCTestCase {
    func testAll81UniqueAndInsideTurkey() {
        XCTAssertEqual(TurkishProvinces.all.count, 81)
        XCTAssertEqual(Set(TurkishProvinces.all.map(\.plate)), Set(1...81))
        for p in TurkishProvinces.all {
            XCTAssertTrue((35.8...42.2).contains(p.coordinate.latitude), p.name)
            XCTAssertTrue((25.6...44.9).contains(p.coordinate.longitude), p.name)
        }
    }

    func testTurkishAwareSearch() {
        XCTAssertEqual(TurkishProvinces.search("istanbul").first?.name, "İstanbul")
        XCTAssertEqual(TurkishProvinces.search("sanliurfa").first?.name, "Şanlıurfa")
        XCTAssertEqual(TurkishProvinces.search("IĞDIR").first?.name, "Iğdır")
        XCTAssertEqual(TurkishProvinces.search("35").first?.name, "İzmir")
    }
}

final class IPLocationProviderTests: XCTestCase {
    func testParsesApproximateCity() async throws {
        let http = StubHTTPClient(json: #"{"city":"Ankara","region":"Ankara","lat":39.93,"lon":32.86,"tz_id":"Europe/Istanbul"}"#)
        let place = try await WeatherAPIIPLocationProvider(http: http, apiKey: { "K" }).currentPlace()
        XCTAssertEqual(place.name, "Ankara")
        XCTAssertEqual(place.source, .ipApproximate)
        XCTAssertTrue(http.requestedURLs[0].absoluteString.contains("q=auto:ip"))
    }

    func testNoKeyMeansUnavailableWithoutRequest() async {
        let http = StubHTTPClient()
        do {
            _ = try await WeatherAPIIPLocationProvider(http: http, apiKey: { nil }).currentPlace()
            XCTFail()
        } catch {
            XCTAssertEqual(error as? LocationError, .unavailable)
            XCTAssertTrue(http.requestedURLs.isEmpty)
        }
    }
}
