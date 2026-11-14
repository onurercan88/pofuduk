import XCTest
@testable import PofudukCore

final class StubHTTPClient: HTTPClient, @unchecked Sendable {
    var responses: [HTTPResponse]
    var error: Error?
    private(set) var requestedURLs: [URL] = []

    init(json: String = "{}", status: Int = 200, error: Error? = nil) {
        responses = [HTTPResponse(data: Data(json.utf8), statusCode: status)]
        self.error = error
    }

    func get(_ url: URL) async throws -> HTTPResponse {
        requestedURLs.append(url)
        if let error { throw error }
        return responses.count > 1 ? responses.removeFirst() : responses[0]
    }
}

enum Fixtures {
    static let openMeteo = """
    {"utc_offset_seconds":10800,
     "current":{"time":"2026-11-14T09:15","temperature_2m":18.4,"apparent_temperature":16.9,"relative_humidity_2m":71,
                "is_day":1,"weather_code":2,"wind_speed_10m":14.2,"wind_gusts_10m":30.1,"wind_direction_10m":200},
     "hourly":{"time":["2026-11-14T09:00","2026-11-14T10:00","2026-11-14T14:00"],
               "temperature_2m":[18.1,19.0,21.5],"apparent_temperature":[17.0,18.0,20.0],
               "precipitation_probability":[5,10,75],"precipitation":[0.0,0.0,3.1],"weather_code":[2,3,63],
               "wind_speed_10m":[14,15,20],"wind_gusts_10m":[30,31,40],"uv_index":[2.5,3.0,null]},
     "daily":{"time":["2026-11-14","2026-11-15"],"weather_code":[63,0],"temperature_2m_max":[22.0,20.0],
              "temperature_2m_min":[13.0,11.0],"precipitation_sum":[6.2,0.0],"precipitation_probability_max":[80,5],
              "wind_speed_10m_max":[25,12],"uv_index_max":[3.5,4.0],
              "sunrise":["2026-11-14T07:02","2026-11-15T07:03"],"sunset":["2026-11-14T16:52","2026-11-15T16:51"]}}
    """

    static let weatherAPI = """
    {"location":{"tz_id":"Europe/Istanbul"},
     "current":{"last_updated_epoch":1794636900,"temp_c":18.0,"feelslike_c":17.0,"condition":{"code":1003},
                "humidity":70,"wind_kph":14.4,"gust_kph":28.0,"wind_degree":210,"uv":3.0,"is_day":1},
     "forecast":{"forecastday":[{"date":"2026-11-14",
        "day":{"maxtemp_c":22.0,"mintemp_c":13.0,"totalprecip_mm":5.0,"daily_chance_of_rain":80,"daily_chance_of_snow":0,
               "maxwind_kph":25.0,"uv":3.0,"condition":{"code":1189}},
        "astro":{"sunrise":"07:02 AM","sunset":"04:52 PM"},
        "hour":[{"time_epoch":1794632400,"temp_c":17.5,"feelslike_c":16.5,"condition":{"code":1003},"chance_of_rain":5,
                 "chance_of_snow":0,"precip_mm":0.0,"wind_kph":14.0,"gust_kph":27.0,"uv":2.0},
                {"time_epoch":1794650400,"temp_c":21.0,"condition":{"code":1195},"chance_of_rain":85,"chance_of_snow":0,
                 "precip_mm":8.4,"wind_kph":20.0,"gust_kph":38.0,"uv":1.0}]}]}}
    """
}

final class OpenMeteoProviderTests: XCTestCase {
    let place = MockWeatherData.istanbul
    let now = TestClock.date(hour: 9, minute: 20)

    func testMapsCurrentHourlyDailyInLocalTime() async throws {
        let http = StubHTTPClient(json: Fixtures.openMeteo)
        let snap = try await OpenMeteoProvider(http: http, now: { [now] in now }).fetchSnapshot(for: place)
        XCTAssertEqual(snap.source, .openMeteo)
        XCTAssertEqual(snap.current.temperature, 18.4)
        XCTAssertEqual(snap.current.condition, .partlyCloudy)
        XCTAssertEqual(snap.current.uvIndex, 2.5, "Current UV comes from the current hour")
        XCTAssertEqual(snap.hourly.count, 3)
        XCTAssertEqual(snap.hourly[2].time, TestClock.date(hour: 14))
        XCTAssertEqual(snap.hourly[2].precipitationProbability, 75)
        XCTAssertEqual(snap.hourly[2].condition, .rain)
        XCTAssertNil(snap.hourly[2].uvIndex)
        XCTAssertEqual(snap.daily.first?.date, TestClock.date(hour: 0))
        XCTAssertEqual(snap.daily.first?.sunset, TestClock.date(hour: 16, minute: 52))
        XCTAssertEqual(snap.expiresAt, now.addingTimeInterval(1800))
    }

    func testRequestUsesPlaceTimeZoneAndNoKey() async throws {
        let http = StubHTTPClient(json: Fixtures.openMeteo)
        _ = try await OpenMeteoProvider(http: http).fetchSnapshot(for: place)
        let url = try XCTUnwrap(http.requestedURLs.first?.absoluteString)
        XCTAssertTrue(url.contains("timezone=Europe/Istanbul"))
        XCTAssertTrue(url.contains("latitude=40.9900"))
    }

    func testHTTPErrorsMap() async {
        await assertThrows(OpenMeteoProvider(http: StubHTTPClient(status: 429)), .rateLimited)
        await assertThrows(OpenMeteoProvider(http: StubHTTPClient(status: 500)), .invalidResponse)
        await assertThrows(OpenMeteoProvider(http: StubHTTPClient(json: "not json")), .invalidResponse)
        await assertThrows(OpenMeteoProvider(http: StubHTTPClient(json: "{}")), .noData)
    }

    func testWMOCodes() {
        XCTAssertEqual(OpenMeteoProvider.condition(wmo: 65), .heavyRain)
        XCTAssertEqual(OpenMeteoProvider.condition(wmo: 95), .thunderstorm)
        XCTAssertEqual(OpenMeteoProvider.condition(wmo: 75), .snow)
        XCTAssertEqual(OpenMeteoProvider.condition(wmo: 45), .fog)
    }

    private func assertThrows(_ provider: WeatherProvider, _ expected: WeatherError, line: UInt = #line) async {
        do {
            _ = try await provider.fetchSnapshot(for: place)
            XCTFail("Expected \(expected)", line: line)
        } catch {
            XCTAssertEqual(error as? WeatherError, expected, line: line)
        }
    }
}

final class WeatherAPIProviderTests: XCTestCase {
    let place = MockWeatherData.istanbul

    func testMapsResponse() async throws {
        let http = StubHTTPClient(json: Fixtures.weatherAPI)
        let snap = try await WeatherAPIProvider(http: http, apiKey: { "TESTKEY" }).fetchSnapshot(for: place)
        XCTAssertEqual(snap.source, .weatherAPI)
        XCTAssertEqual(snap.current.condition, .partlyCloudy)
        XCTAssertEqual(snap.hourly.count, 2)
        XCTAssertEqual(snap.hourly[1].condition, .heavyRain)
        XCTAssertEqual(snap.hourly[1].precipitationMm, 8.4)
        XCTAssertEqual(snap.daily.first?.date, TestClock.date(hour: 0))
        XCTAssertEqual(snap.daily.first?.sunrise, TestClock.date(hour: 7, minute: 2))
        XCTAssertEqual(snap.daily.first?.sunset, TestClock.date(hour: 16, minute: 52))
        XCTAssertEqual(snap.daily.first?.precipitationProbability, 80)
    }

    func testMissingKeyFailsWithoutNetworkCall() async {
        let http = StubHTTPClient(json: Fixtures.weatherAPI)
        do {
            _ = try await WeatherAPIProvider(http: http, apiKey: { nil }).fetchSnapshot(for: place)
            XCTFail("Expected missingAPIKey")
        } catch {
            XCTAssertEqual(error as? WeatherError, .missingAPIKey)
            XCTAssertTrue(http.requestedURLs.isEmpty)
        }
    }

    func testUnauthorizedMapsToMissingKey() async {
        do {
            _ = try await WeatherAPIProvider(http: StubHTTPClient(status: 401), apiKey: { "BAD" }).fetchSnapshot(for: place)
            XCTFail()
        } catch {
            XCTAssertEqual(error as? WeatherError, .missingAPIKey)
        }
    }

    func testProbabilityTakesMaxOfRainAndSnow() {
        XCTAssertEqual(WeatherAPIProvider.probability(rain: 20, snow: 60), 60)
        XCTAssertNil(WeatherAPIProvider.probability(rain: nil, snow: nil))
    }
}

final class FallbackAndCacheTests: XCTestCase {
    let place = MockWeatherData.istanbul
    let now = TestClock.date(hour: 9)

    private func openMeteo(_ http: StubHTTPClient, now: Date) -> OpenMeteoProvider {
        OpenMeteoProvider(http: http, now: { now })
    }

    func testFallbackUsesSecondProviderWhenFirstFails() async throws {
        let primary = WeatherAPIProvider(http: StubHTTPClient(error: WeatherError.network), apiKey: { "K" })
        let secondary = openMeteo(StubHTTPClient(json: Fixtures.openMeteo), now: now)
        let outcome = try await WeatherProviderFallbackEngine(providers: [primary, secondary]).fetch(for: place)
        XCTAssertEqual(outcome.snapshot.source, .openMeteo)
        XCTAssertEqual(outcome.failures.count, 1)
    }

    func testAllProvidersFailingThrowsMostInformativeError() async {
        let a = WeatherAPIProvider(http: StubHTTPClient(status: 429), apiKey: { "K" })
        let b = openMeteo(StubHTTPClient(error: WeatherError.network), now: now)
        do {
            _ = try await WeatherProviderFallbackEngine(providers: [a, b]).fetch(for: place)
            XCTFail()
        } catch {
            XCTAssertEqual(error as? WeatherError, .rateLimited)
        }
    }

    func testFreshCacheAvoidsNetwork() async throws {
        let http = StubHTTPClient(json: Fixtures.openMeteo)
        let cache = InMemoryWeatherCacheStore()
        let repo = CachedWeatherRepository(engine: .init(providers: [openMeteo(http, now: now)]), cache: cache, now: { [now] in now })
        _ = try await repo.snapshot(for: place, forceRefresh: false)
        _ = try await repo.snapshot(for: place, forceRefresh: false)
        XCTAssertEqual(http.requestedURLs.count, 1)
    }

    func testStaleCacheIsReturnedMarkedStaleWhenOffline() async throws {
        let cache = InMemoryWeatherCacheStore()
        let online = CachedWeatherRepository(engine: .init(providers: [openMeteo(StubHTTPClient(json: Fixtures.openMeteo), now: now)]),
                                             cache: cache, now: { [now] in now })
        _ = try await online.snapshot(for: place, forceRefresh: false)

        let later = now.addingTimeInterval(2 * 3600)
        let offline = CachedWeatherRepository(engine: .init(providers: [openMeteo(StubHTTPClient(error: WeatherError.network), now: later)]),
                                              cache: cache, now: { later })
        let snap = try await offline.snapshot(for: place, forceRefresh: false)
        XCTAssertTrue(snap.isStale(at: later), "Old data must stay flagged as stale")
        let a = WeatherSummaryEngine().analyze(snap, now: later)
        XCTAssertTrue(CharacterPersonalityEngine().briefing(for: a).fullText.contains("güncel olmayabilir"))
    }

    func testTooOldCacheIsNotUsed() async throws {
        let cache = InMemoryWeatherCacheStore()
        let online = CachedWeatherRepository(engine: .init(providers: [openMeteo(StubHTTPClient(json: Fixtures.openMeteo), now: now)]),
                                             cache: cache, now: { [now] in now })
        _ = try await online.snapshot(for: place, forceRefresh: false)
        let muchLater = now.addingTimeInterval(7 * 3600)
        let offline = CachedWeatherRepository(engine: .init(providers: [openMeteo(StubHTTPClient(error: WeatherError.network), now: muchLater)]),
                                              cache: cache, now: { muchLater })
        do {
            _ = try await offline.snapshot(for: place, forceRefresh: false)
            XCTFail()
        } catch {
            XCTAssertEqual(error as? WeatherError, .network)
        }
    }

    func testFileCacheRoundTrip() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pofuduk-cache-\(UUID().uuidString)")
        let store = FileWeatherCacheStore(directory: dir)
        let snap = MockWeatherData.snapshot(.sunny, now: now)
        await store.save(snap, key: "k")
        let loaded = await store.load(key: "k")
        XCTAssertEqual(loaded, snap)
        await store.removeAll()
        let afterRemove = await store.load(key: "k")
        XCTAssertNil(afterRemove)
        try? FileManager.default.removeItem(at: dir)
    }
}
