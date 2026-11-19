import XCTest
@testable import PofudukCore

private struct FixedRepository: WeatherRepository {
    let snapshot: WeatherSnapshot
    func snapshot(for place: Place, forceRefresh: Bool) async throws -> WeatherSnapshot { snapshot }
}

private actor CallCounter {
    var count = 0
    func increment() { count += 1 }
}

private struct StubChecker: CurrentConditionsProvider {
    var source: WeatherDataSource { .appleWeather }
    let result: Result<CurrentConditionsObservation, Error>
    var delaySeconds: Double = 0
    var counter: CallCounter? = nil

    func currentConditions(for place: Place) async throws -> CurrentConditionsObservation {
        await counter?.increment()
        if delaySeconds > 0 { try await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000)) }
        return try result.get()
    }
}

final class CrossCheckTests: XCTestCase {
    private let now = TestClock.date(hour: 15)

    private func current(_ condition: WeatherCondition) -> CurrentWeather {
        CurrentWeather(time: now, temperature: 12, feelsLike: 11, condition: condition, humidity: 80, windSpeedKmh: 10)
    }

    private func observation(_ condition: WeatherCondition, mm: Double? = nil, minutesAgo: Double = 0) -> CurrentConditionsObservation {
        CurrentConditionsObservation(condition: condition, precipitationIntensityMmPerHour: mm,
                                     observedAt: now.addingTimeInterval(-minutesAgo * 60))
    }

    // MARK: Reconciler

    func testObservedRainReplacesCloudy() {
        let merged = CurrentConditionsReconciler.reconcile(current(.cloudy), with: observation(.rain), now: now)
        XCTAssertEqual(merged.condition, .rain)
        XCTAssertEqual(merged.temperature, 12, "only the condition changes")
    }

    func testIntensityTurnsCloudyObservationIntoPrecipitation() {
        XCTAssertEqual(CurrentConditionsReconciler.reconcile(current(.cloudy), with: observation(.cloudy, mm: 0.3), now: now).condition, .drizzle)
        XCTAssertEqual(CurrentConditionsReconciler.reconcile(current(.clear), with: observation(.cloudy, mm: 1.2), now: now).condition, .rain)
        XCTAssertEqual(CurrentConditionsReconciler.reconcile(current(.cloudy), with: observation(.cloudy, mm: 0.05), now: now).condition, .cloudy)
    }

    func testDryObservationNeverRemovesProviderPrecipitation() {
        XCTAssertEqual(CurrentConditionsReconciler.reconcile(current(.rain), with: observation(.clear, mm: 0), now: now).condition, .rain)
    }

    func testOnlyHeavierPrecipitationReplacesLighter() {
        XCTAssertEqual(CurrentConditionsReconciler.reconcile(current(.drizzle), with: observation(.thunderstorm), now: now).condition, .thunderstorm)
        XCTAssertEqual(CurrentConditionsReconciler.reconcile(current(.heavyRain), with: observation(.drizzle), now: now).condition, .heavyRain)
        XCTAssertEqual(CurrentConditionsReconciler.reconcile(current(.snow), with: observation(.rain), now: now).condition, .snow)
    }

    func testOldObservationIsIgnored() {
        XCTAssertEqual(CurrentConditionsReconciler.reconcile(current(.cloudy), with: observation(.rain, minutesAgo: 45), now: now).condition, .cloudy)
    }

    func testAppleConditionMapping() {
        XCTAssertEqual(AppleWeatherConditionMapper.condition(rawValue: "mostlyCloudy"), .cloudy)
        XCTAssertEqual(AppleWeatherConditionMapper.condition(rawValue: "sunShowers"), .rain)
        XCTAssertEqual(AppleWeatherConditionMapper.condition(rawValue: "heavyRain"), .heavyRain)
        XCTAssertEqual(AppleWeatherConditionMapper.condition(rawValue: "scatteredThunderstorms"), .thunderstorm)
        XCTAssertEqual(AppleWeatherConditionMapper.condition(rawValue: "wintryMix"), .sleet)
        XCTAssertEqual(AppleWeatherConditionMapper.condition(rawValue: "flurries"), .snow)
        XCTAssertEqual(AppleWeatherConditionMapper.condition(rawValue: "haze"), .fog)
        XCTAssertNil(AppleWeatherConditionMapper.condition(rawValue: "somethingNew"))
    }

    // MARK: Repository

    private func repository(base: WeatherSnapshot, checker: StubChecker, timeout: TimeInterval = 5) -> CrossCheckedWeatherRepository {
        let fixed = now
        return CrossCheckedWeatherRepository(base: FixedRepository(snapshot: base), checker: checker,
                                             timeout: timeout, now: { fixed })
    }

    func testRepositoryAppliesObservationAndMarksSource() async throws {
        let base = TestClock.snapshot(hourly: [], current: current(.cloudy), now: now)
        let repo = repository(base: base, checker: StubChecker(result: .success(observation(.rain))))
        let result = try await repo.snapshot(for: base.place, forceRefresh: false)
        XCTAssertEqual(result.current.condition, .rain)
        XCTAssertEqual(result.crossCheckSource, .appleWeather)
        XCTAssertEqual(result.source, .openMeteo)
    }

    func testRepositoryKeepsSnapshotWhenCheckFails() async throws {
        let base = TestClock.snapshot(hourly: [], current: current(.cloudy), now: now)
        let repo = repository(base: base, checker: StubChecker(result: .failure(WeatherError.network)))
        let result = try await repo.snapshot(for: base.place, forceRefresh: false)
        XCTAssertEqual(result, base)
    }

    func testRepositoryTimesOut() async throws {
        let base = TestClock.snapshot(hourly: [], current: current(.cloudy), now: now)
        let repo = repository(base: base, checker: StubChecker(result: .success(observation(.rain)), delaySeconds: 2), timeout: 0.1)
        let result = try await repo.snapshot(for: base.place, forceRefresh: false)
        XCTAssertEqual(result.current.condition, .cloudy)
        XCTAssertNil(result.crossCheckSource)
    }

    func testDemoStaleAndSameSourceSnapshotsAreNotCrossChecked() async throws {
        let counter = CallCounter()
        let checker = StubChecker(result: .success(observation(.rain)), counter: counter)
        let demo = TestClock.snapshot(hourly: [], current: current(.cloudy), now: now, source: .demo)
        let apple = TestClock.snapshot(hourly: [], current: current(.cloudy), now: now, source: .appleWeather)
        let stale = TestClock.snapshot(hourly: [], current: current(.cloudy), now: now,
                                       retrievedAt: now.addingTimeInterval(-7200), expiresIn: 1800)
        _ = try await repository(base: demo, checker: checker).snapshot(for: demo.place, forceRefresh: false)
        _ = try await repository(base: stale, checker: checker).snapshot(for: stale.place, forceRefresh: false)
        _ = try await repository(base: apple, checker: checker).snapshot(for: apple.place, forceRefresh: false)
        let calls = await counter.count
        XCTAssertEqual(calls, 0)
    }

    func testObservationIsReusedWithinTTL() async throws {
        let counter = CallCounter()
        let base = TestClock.snapshot(hourly: [], current: current(.cloudy), now: now)
        let repo = repository(base: base, checker: StubChecker(result: .success(observation(.rain)), counter: counter))
        _ = try await repo.snapshot(for: base.place, forceRefresh: false)
        _ = try await repo.snapshot(for: base.place, forceRefresh: true)
        let calls = await counter.count
        XCTAssertEqual(calls, 1)
    }

    func testSnapshotWithoutCrossCheckFieldStillDecodes() throws {
        let base = TestClock.snapshot(hourly: [], now: now)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(base)) as! [String: Any]
        json.removeValue(forKey: "crossCheckSource")
        let decoded = try JSONDecoder().decode(WeatherSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.crossCheckSource)
    }
}

