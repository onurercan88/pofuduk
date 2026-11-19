import XCTest
@testable import PofudukCore

final class AppleWeatherSnapshotBuilderTests: XCTestCase {
    private let now = TestClock.date(hour: 15)
    private var place: Place { var p = MockWeatherData.istanbul; p.source = .manual; return p }

    private func current(_ condition: String = "cloudy", intensity: Double = 0) -> AppleWeatherSnapshotBuilder.Current {
        .init(time: now, temperature: 12.4, feelsLike: 10.9, condition: condition, humidity: 0.81, windKmh: 18,
              gustKmh: 31, windDirectionDegrees: 365, uvIndex: 2, isDaylight: true,
              precipitationIntensityMmPerHour: intensity)
    }

    private func hours(day: Int = 14, rainMm: Double = 0.5) -> [AppleWeatherSnapshotBuilder.Hour] {
        (0..<24).map { h in
            .init(time: TestClock.date(hour: h, day: day), temperature: 10 + Double(h % 6), feelsLike: 9,
                  condition: h >= 14 ? "rain" : "mostlyCloudy", precipitationChance: h >= 14 ? 0.8 : 0.1,
                  precipitationMm: h >= 14 ? rainMm : 0, windKmh: Double(h), gustKmh: nil, uvIndex: h == 12 ? 4 : 1)
        }
    }

    private func day(_ d: Int) -> AppleWeatherSnapshotBuilder.Day {
        .init(date: TestClock.date(hour: 0, day: d), low: 8, high: 16, condition: "rain", precipitationChance: 0.75,
              sunrise: TestClock.date(hour: 7, day: d), sunset: TestClock.date(hour: 17, day: d))
    }

    private func build(current: AppleWeatherSnapshotBuilder.Current? = nil) throws -> WeatherSnapshot {
        try AppleWeatherSnapshotBuilder.snapshot(place: place, current: current ?? self.current(), hours: hours(),
                                                 days: [day(14), day(15)], retrievedAt: now, lifetime: 1800)
    }

    func testMapsUnitsAndSource() throws {
        let s = try build()
        XCTAssertEqual(s.source, .appleWeather)
        XCTAssertEqual(s.current.humidity, 81)
        XCTAssertEqual(s.current.windDirectionDegrees, 5, "365° wraps to 5°")
        XCTAssertEqual(s.current.condition, .cloudy)
        XCTAssertEqual(s.hourly.count, 24)
        XCTAssertEqual(s.hourly[15].precipitationProbability, 80)
        XCTAssertEqual(s.hourly[15].condition, .rain)
        XCTAssertEqual(s.hourly[3].condition, .cloudy, "mostlyCloudy → cloudy")
        XCTAssertEqual(s.expiresAt, now.addingTimeInterval(1800))
    }

    func testDailyTotalsComeFromThatDaysHours() throws {
        let s = try build()
        XCTAssertEqual(s.daily.count, 2)
        XCTAssertEqual(s.daily[0].precipitationSumMm!, 5.0, accuracy: 1e-9, "10 wet hours × 0.5 mm")
        XCTAssertEqual(s.daily[0].maxWindKmh, 23)
        XCTAssertEqual(s.daily[0].uvIndexMax, 4)
        XCTAssertEqual(s.daily[0].precipitationProbability, 75)
        XCTAssertNil(s.daily[1].precipitationSumMm, "No hourly data for that day")
    }

    func testMeasuredRainOverridesDryCurrentCondition() throws {
        XCTAssertEqual(try build(current: current("cloudy", intensity: 0.8)).current.condition, .rain)
        XCTAssertEqual(try build(current: current("cloudy", intensity: 0.2)).current.condition, .drizzle)
        XCTAssertEqual(try build(current: current("thunderstorms")).current.condition, .thunderstorm)
    }

    func testUnknownConditionFallsBackToCloudy() {
        XCTAssertEqual(AppleWeatherSnapshotBuilder.condition("somethingNew"), .cloudy)
    }

    func testEmptyForecastIsNoData() {
        XCTAssertThrowsError(try AppleWeatherSnapshotBuilder.snapshot(place: place, current: current(), hours: [], days: [],
                                                                      retrievedAt: now, lifetime: 1800)) {
            XCTAssertEqual($0 as? WeatherError, .noData)
        }
    }

    func testWorksWithBriefingEngine() throws {
        let analysis = WeatherSummaryEngine().analyze(try build(), now: now)
        XCTAssertEqual(analysis.source, .appleWeather)
    }
}
