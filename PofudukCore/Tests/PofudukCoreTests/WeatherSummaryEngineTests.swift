import XCTest
@testable import PofudukCore

final class WeatherSummaryEngineTests: XCTestCase {
    let engine = WeatherSummaryEngine()
    let now = TestClock.date(hour: 9)

    func testSunnyDayHasNoPrecipitationAndSunnyTheme() {
        let snap = MockWeatherData.snapshot(.sunny, now: now)
        let a = engine.analyze(snap, now: now)
        XCTAssertNil(a.precipitation)
        XCTAssertTrue(a.hasHourlyCoverage)
        XCTAssertEqual(a.theme, .sunny)
        XCTAssertTrue(a.isHighUV)
    }

    func testRainBeginningAt14() {
        let hourly = TestClock.hours { i, t in
            let wet = (14...16).contains(i)
            return HourlyForecast(time: t, temperature: 22, condition: wet ? .rain : .clear,
                                  precipitationProbability: wet ? 80 : 5, precipitationMm: wet ? 1.5 : 0)
        }
        let a = engine.analyze(TestClock.snapshot(hourly: hourly, now: now), now: now)
        let p = try! XCTUnwrap(a.precipitation)
        XCTAssertEqual(p.start, TestClock.date(hour: 14))
        XCTAssertEqual(p.durationHours, 3)
        XCTAssertEqual(p.intensity, .light)
        XCTAssertTrue(p.isLikely)
        XCTAssertEqual(a.theme, .rainy)
    }

    func testHeavyPrecipitationRequiresAmounts() {
        let hourly = TestClock.hours { i, t in
            HourlyForecast(time: t, temperature: 18, condition: i == 12 ? .rain : .cloudy,
                           precipitationProbability: i == 12 ? 95 : 0, precipitationMm: i == 12 ? 12 : 0)
        }
        let a = engine.analyze(TestClock.snapshot(hourly: hourly, now: now), now: now)
        XCTAssertEqual(a.precipitation?.intensity, .heavy)
    }

    func testHighProbabilityWithoutAmountsIsNeverHeavy() {
        let hourly = TestClock.hours { i, t in
            HourlyForecast(time: t, temperature: 18, condition: i == 12 ? .rain : .cloudy,
                           precipitationProbability: i == 12 ? 100 : 0, precipitationMm: nil)
        }
        let a = engine.analyze(TestClock.snapshot(hourly: hourly, now: now), now: now)
        XCTAssertEqual(a.precipitation?.intensity, .unknown)
    }

    func testLowRainProbabilityIsIgnored() {
        let hourly = TestClock.hours { _, t in
            HourlyForecast(time: t, temperature: 18, condition: .cloudy, precipitationProbability: 20, precipitationMm: 0)
        }
        let a = engine.analyze(TestClock.snapshot(hourly: hourly, now: now), now: now)
        XCTAssertNil(a.precipitation)
    }

    func testPossibleRainIsMarkedUncertain() {
        let hourly = TestClock.hours { i, t in
            HourlyForecast(time: t, temperature: 18, condition: .cloudy,
                           precipitationProbability: i == 15 ? 40 : 0, precipitationMm: i == 15 ? 0.3 : 0)
        }
        let a = engine.analyze(TestClock.snapshot(hourly: hourly, now: now), now: now)
        XCTAssertEqual(a.precipitation?.isLikely, false)
    }

    func testStrongWind() {
        let hourly = TestClock.hours { _, t in
            HourlyForecast(time: t, temperature: 15, condition: .partlyCloudy,
                           precipitationProbability: 0, precipitationMm: 0, windSpeedKmh: 30, windGustKmh: 70)
        }
        let a = engine.analyze(TestClock.snapshot(hourly: hourly, now: now), now: now)
        XCTAssertEqual(a.wind?.isStrong, true)
        XCTAssertEqual(a.theme, .windy)
    }

    func testTemperatureSwing() {
        let hourly = TestClock.hours { i, t in
            HourlyForecast(time: t, temperature: i < 12 ? 8 : 21, condition: .clear,
                           precipitationProbability: 0, precipitationMm: 0)
        }
        let a = engine.analyze(TestClock.snapshot(hourly: hourly, now: now), now: now)
        XCTAssertEqual(a.minTemperature, 8)
        XCTAssertEqual(a.maxTemperature, 21)
        XCTAssertTrue(a.temperatureSwingIsNotable)
    }

    func testMissingForecastMeansNoCoverageAndNoClaims() {
        let a = engine.analyze(TestClock.snapshot(hourly: [], now: now), now: now)
        XCTAssertFalse(a.hasHourlyCoverage)
        XCTAssertNil(a.precipitation)
        let briefing = CharacterPersonalityEngine().briefing(for: a)
        XCTAssertFalse(briefing.fullText.contains("yağış beklenmiyor"))
    }

    func testStaleForecastIsFlagged() {
        let retrieved = TestClock.date(hour: 6)
        let snap = TestClock.snapshot(hourly: [], now: now, retrievedAt: retrieved, expiresIn: 1800)
        let a = engine.analyze(snap, now: now)
        XCTAssertTrue(a.isStale)
        XCTAssertTrue(CharacterPersonalityEngine().briefing(for: a).fullText.contains("güncel olmayabilir"))
    }

    func testPastRainIsIgnored() {
        let hourly = TestClock.hours { i, t in
            HourlyForecast(time: t, temperature: 18, condition: i == 5 ? .rain : .clear,
                           precipitationProbability: i == 5 ? 90 : 0, precipitationMm: i == 5 ? 2 : 0)
        }
        let a = engine.analyze(TestClock.snapshot(hourly: hourly, now: now), now: now)
        XCTAssertNil(a.precipitation)
    }
}
