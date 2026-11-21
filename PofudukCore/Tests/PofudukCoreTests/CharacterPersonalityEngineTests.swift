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
        // 09.00 is still dry: the look shows now, the words cover the afternoon rain.
        XCTAssertNotEqual(b.theme, .rainy)
    }

    func testLookFollowsTheWeatherNow() {
        let at = TestClock.date(hour: 15)
        let a = summary.analyze(MockWeatherData.snapshot(.stormy, now: at), now: at)
        XCTAssertEqual(a.theme, .stormy)
        let rain = summary.analyze(MockWeatherData.snapshot(.rainyAfternoon, now: at), now: at)
        XCTAssertEqual(rain.theme, .rainy)
    }

    func testStormIsSeriousEvenInPlayfulStyle() {
        // Storm expected from 12.00; at 09.00 the message is already serious.
        let b = briefing(.stormy, style: .playful)
        XCTAssertEqual(b.restingMood, .warning)
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

    // MARK: - Time of day

    private func briefing(_ scenario: MockWeatherData.Scenario, at hour: Int) -> Briefing {
        let at = TestClock.date(hour: hour)
        let a = summary.analyze(MockWeatherData.snapshot(scenario, now: at), now: at)
        return CharacterPersonalityEngine().briefing(for: a)
    }

    func testMorningTellsTheWholeDay() {
        let text = briefing(.sunny, at: 9).fullText
        XCTAssertTrue(text.contains("Bugün sıcaklık"))
        XCTAssertFalse(text.contains("Yarın"))
    }

    func testEveningSkipsTodaysRangeAndTellsTonightAndTomorrow() {
        let b = briefing(.sunny, at: 17)
        let text = b.fullText
        XCTAssertFalse(text.contains("Bugün sıcaklık"), text)
        XCTAssertTrue(text.contains("Bu gece sıcaklık"), text)
        XCTAssertTrue(text.contains("Yarın sıcaklık"), text)
        XCTAssertTrue(text.contains("Bu akşam için yağış beklenmiyor"), text)
        XCTAssertFalse(text.contains("Dışarı çıkmak için"), text)
        XCTAssertFalse(b.advice.contains { $0.contains("gün içinde") })
    }

    func testPrecipitationNowWithDryEveningDoesNotContradict() {
        // Seen on a device: "hava gök gürültülü sağanaklı" followed by "Bu akşam için yağış beklenmiyor."
        let at = TestClock.date(hour: 18)
        var snap = MockWeatherData.snapshot(.sunny, now: at)
        snap.current.condition = .thunderstorm
        let text = CharacterPersonalityEngine().briefing(for: summary.analyze(snap, now: at)).fullText
        XCTAssertTrue(text.contains("gök gürültülü sağanaklı"), text)
        XCTAssertFalse(text.contains("Bu akşam için yağış beklenmiyor"), text)
        XCTAssertTrue(text.contains("Şu anki yağışın ardından bu akşam başka yağış beklenmiyor."), text)
    }

    func testAfternoonTalksAboutTheRestOfTheDay() {
        let text = briefing(.sunny, at: 14).fullText
        XCTAssertFalse(text.contains("Bugün sıcaklık"), text)
        XCTAssertTrue(text.contains("Günün geri kalanında") || text.contains("Akşama doğru"), text)
        XCTAssertFalse(text.contains("Yarın"), text)
    }

    func testTomorrowRainIsTold() {
        let at = TestClock.date(hour: 19)
        var snap = MockWeatherData.snapshot(.sunny, now: at)
        let tomorrow = TestClock.date(hour: 0, day: 15)
        snap.daily = [DailyForecast(date: tomorrow, minTemperature: 9, maxTemperature: 14, condition: .rain,
                                    precipitationProbability: 80, precipitationSumMm: 6)]
        let text = CharacterPersonalityEngine().briefing(for: summary.analyze(snap, now: at)).fullText
        XCTAssertTrue(text.contains("Yarın sıcaklık 9 ile 14 derece arasında; yağış bekleniyor, ihtimali yüzde 80."), text)
    }

    func testTurkishLocative() {
        XCTAssertEqual(TurkishGrammar.locative("İstanbul"), "İstanbul'da")
        XCTAssertEqual(TurkishGrammar.locative("İzmir"), "İzmir'de")
        XCTAssertEqual(TurkishGrammar.locative("Kars"), "Kars'ta")
        XCTAssertEqual(TurkishGrammar.locative("Rize"), "Rize'de")
        XCTAssertEqual(TurkishGrammar.locative("Bursa"), "Bursa'da")
    }
}
