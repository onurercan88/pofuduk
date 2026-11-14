import XCTest
@testable import PofudukCore

final class ClothingRecommendationEngineTests: XCTestCase {
    let engine = ClothingRecommendationEngine()
    let now = TestClock.date(hour: 8)

    private func snap(_ make: (Int, Date) -> HourlyForecast) -> WeatherSnapshot {
        TestClock.snapshot(hourly: TestClock.hours(48, make), now: now)
    }
    private func ids(_ r: ClothingRecommendation?) -> Set<String> { Set(r?.items.map(\.id) ?? []) }

    func testHotWeather() throws {
        let s = snap { _, t in HourlyForecast(time: t, temperature: 31, feelsLike: 33, condition: .clear,
                                               precipitationProbability: 0, precipitationMm: 0, windSpeedKmh: 8, uvIndex: 8) }
        let r = try XCTUnwrap(engine.recommend(for: s, now: now))
        XCTAssertTrue(ids(r).isSuperset(of: ["lightClothes", "sunscreen", "sunglasses"]))
        XCTAssertFalse(ids(r).contains("coat"))
        XCTAssertTrue(r.summary.contains("hafif"), r.summary)
        XCTAssertTrue(r.summary.contains("güneşten korunmayı"))
        XCTAssertTrue(r.isNoteworthy)
    }

    func testColdWeather() throws {
        let s = snap { _, t in HourlyForecast(time: t, temperature: 0, feelsLike: -3, condition: .cloudy,
                                               precipitationProbability: 0, precipitationMm: 0, windSpeedKmh: 10) }
        let r = try XCTUnwrap(engine.recommend(for: s, now: now))
        XCTAssertTrue(ids(r).isSuperset(of: ["thickCoat", "scarf", "gloves", "beanie", "sweater"]))
        XCTAssertTrue(r.summary.contains("Kalın bir mont"), r.summary)
        XCTAssertTrue(r.summary.contains("eksi 3 derece"), r.summary)
    }

    func testWindyWeatherExplainsChill() throws {
        let s = snap { _, t in HourlyForecast(time: t, temperature: 18, feelsLike: 14, condition: .partlyCloudy,
                                               precipitationProbability: 0, precipitationMm: 0, windSpeedKmh: 45, windGustKmh: 65) }
        let r = try XCTUnwrap(engine.recommend(for: s, now: now))
        XCTAssertTrue(ids(r).contains("windbreaker"))
        XCTAssertTrue(r.summary.contains("rüzgâr nedeniyle"), r.summary)
        XCTAssertTrue(r.reasons.contains { $0.contains("Rüzgâr saatte 45") })
    }

    func testRainyWeather() throws {
        let s = snap { i, t in
            let wet = (14...16).contains(i)
            return HourlyForecast(time: t, temperature: 17, feelsLike: 17, condition: wet ? .rain : .cloudy,
                                  precipitationProbability: wet ? 85 : 5, precipitationMm: wet ? 2 : 0, windSpeedKmh: 10)
        }
        let r = try XCTUnwrap(engine.recommend(for: s, now: now))
        XCTAssertTrue(ids(r).isSuperset(of: ["umbrella", "waterproofShoes"]))
        XCTAssertTrue(r.reasons.contains { $0.contains("Saat 14.00 civarında yağış") })
    }

    func testLargeMorningEveningDifferenceSuggestsLayers() throws {
        let s = snap { i, t in
            let h = i % 24
            let temp = h < 11 ? 7.0 : (h < 18 ? 19.0 : 9.0)
            return HourlyForecast(time: t, temperature: temp, feelsLike: temp, condition: .clear,
                                  precipitationProbability: 0, precipitationMm: 0, windSpeedKmh: 5)
        }
        let r = try XCTUnwrap(engine.recommend(for: s, now: now))
        XCTAssertTrue(r.suggestsLayers)
        XCTAssertTrue(r.summary.contains("Katmanlı"), r.summary)
        XCTAssertTrue(r.reasons.contains { $0.contains("gün içinde fark büyük") })
    }

    func testMildDayIsNotNoteworthy() throws {
        let s = snap { _, t in HourlyForecast(time: t, temperature: 22, feelsLike: 22, condition: .clear,
                                               precipitationProbability: 0, precipitationMm: 0, windSpeedKmh: 8, uvIndex: 3) }
        let r = try XCTUnwrap(engine.recommend(for: s, now: now))
        XCTAssertFalse(r.isNoteworthy)
        let a = WeatherSummaryEngine().analyze(s, now: now)
        XCTAssertFalse(CharacterPersonalityEngine().briefing(for: a, clothing: r).fullText.contains("tişört"))
    }

    func testNoHourlyDataMeansNoRecommendation() {
        XCTAssertNil(engine.recommend(for: TestClock.snapshot(hourly: [], now: now), now: now))
    }

    func testTomorrowAndBriefingIntegration() throws {
        let s = MockWeatherData.snapshot(.snowy, now: now)
        let tomorrow = TestClock.date(hour: 12, day: 15)
        let r = try XCTUnwrap(engine.recommend(for: s, day: tomorrow, now: now))
        XCTAssertTrue(r.briefingSentence.hasPrefix("Yarın"))
        let today = try XCTUnwrap(engine.recommend(for: s, now: now))
        let a = WeatherSummaryEngine().analyze(s, now: now)
        XCTAssertTrue(CharacterPersonalityEngine().briefing(for: a, clothing: today).sentences.contains(today.briefingSentence))
    }
}
