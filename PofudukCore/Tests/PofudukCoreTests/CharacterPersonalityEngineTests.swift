import XCTest
@testable import PofudukCore

final class CharacterPersonalityEngineTests: XCTestCase {
    let now = TestClock.date(hour: 9)
    let summary = WeatherSummaryEngine()

    private func briefing(_ scenario: MockWeatherData.Scenario, style: PersonalityStyle = .friendly,
                          warnings: [OfficialWarning] = []) -> Briefing {
        let a = summary.analyze(MockWeatherData.snapshot(scenario, now: now), now: now)
        return CharacterPersonalityEngine(style: style).briefing(for: a, warnings: warnings)
    }

    func testMorningGreetingAndDemoDisclosure() {
        let b = briefing(.sunny)
        XCTAssertTrue(b.sentences[0].hasPrefix("Günaydın"))
        XCTAssertTrue(b.fullText.contains("örnek verilerle"))
    }

    func testRainyAfternoonMentionsStartTimeAndUmbrella() {
        let b = briefing(.rainyAfternoon)
        XCTAssertTrue(b.fullText.contains("Saat 14.00 civarında yağmur başlaması bekleniyor"))
        XCTAssertTrue(b.fullText.contains("Orta şiddette"))
        XCTAssertTrue(b.fullText.contains("Şemsiye"))
        XCTAssertEqual(b.theme, .rainy)
    }

    func testStormIsSeriousEvenInPlayfulStyle() {
        let b = briefing(.stormy, style: .playful)
        XCTAssertEqual(b.restingMood, .warning)
        XCTAssertEqual(b.theme, .stormy)
        XCTAssertFalse(b.fullText.contains("suçlama"))
        XCTAssertTrue(b.fullText.contains("dikkatli"))
    }

    func testPossibleHoursAreNotMergedIntoLikelyPeriod() {
        // Stormy mock: 40% drizzle-level hours until 12:00, thunderstorm 12–18.
        let a = summary.analyze(MockWeatherData.snapshot(.stormy, now: now), now: now)
        XCTAssertEqual(a.precipitation?.start, TestClock.date(hour: 12))
        XCTAssertEqual(a.precipitation?.durationHours, 7)
        XCTAssertFalse(briefing(.stormy).fullText.contains("Şu sıralar"))
    }

    func testRainUntilEndOfDayIsNotGivenFakeDuration() {
        let b = briefing(.snowy)
        XCTAssertTrue(b.fullText.contains("gün sonuna kadar"))
    }

    func testOrangeWarningIsFirstAfterGreeting() {
        let w = OfficialWarning(id: "1", level: .orange, hazard: "Kuvvetli yağış", description: "",
                                provinces: ["İstanbul"], validFrom: now.addingTimeInterval(-3600),
                                validUntil: now.addingTimeInterval(3600), sourceURL: URL(string: "https://www.mgm.gov.tr")!)
        let b = briefing(.sunny, style: .playful, warnings: [w])
        let firstFact = b.sentences.firstIndex { $0.contains("turuncu") }
        let current = b.sentences.firstIndex { $0.contains("şu an") }
        XCTAssertNotNil(firstFact)
        XCTAssertLessThan(firstFact!, current!)
        XCTAssertEqual(b.restingMood, .warning)
    }

    func testExpiredWarningIsNotSpoken() {
        let w = OfficialWarning(id: "1", level: .red, hazard: "Fırtına", description: "",
                                provinces: ["İstanbul"], validFrom: now.addingTimeInterval(-7200),
                                validUntil: now.addingTimeInterval(-3600), sourceURL: URL(string: "https://www.mgm.gov.tr")!)
        XCTAssertFalse(briefing(.sunny, warnings: [w]).fullText.contains("MGM"))
    }

    func testSnowAndWindThemes() {
        XCTAssertEqual(briefing(.snowy).theme, .snowy)
        XCTAssertTrue(briefing(.snowy).fullText.contains("eksi"))
        XCTAssertEqual(briefing(.windy).theme, .windy)
        XCTAssertTrue(briefing(.windy).fullText.contains("kilometre"))
    }

    func testEveryNumberInBriefingComesFromData() {
        // Current temp in the sunny scenario at 09:00 must appear verbatim.
        let snap = MockWeatherData.snapshot(.sunny, now: now)
        let b = briefing(.sunny)
        XCTAssertTrue(b.fullText.contains(TurkishFormatting.temperature(snap.current.temperature)))
    }

    func testTurkishLocative() {
        XCTAssertEqual(TurkishGrammar.locative("İstanbul"), "İstanbul'da")
        XCTAssertEqual(TurkishGrammar.locative("İzmir"), "İzmir'de")
        XCTAssertEqual(TurkishGrammar.locative("Kars"), "Kars'ta")
        XCTAssertEqual(TurkishGrammar.locative("Rize"), "Rize'de")
        XCTAssertEqual(TurkishGrammar.locative("Bursa"), "Bursa'da")
    }
}
