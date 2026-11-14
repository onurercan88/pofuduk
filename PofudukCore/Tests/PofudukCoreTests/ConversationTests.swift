import XCTest
@testable import PofudukCore

final class WeatherQueryParserTests: XCTestCase {
    let parser = WeatherQueryParser()

    func testExampleQuestions() {
        XCTAssertEqual(parser.parse("Yarın hava nasıl?"), WeatherIntent(topic: .overview, date: .tomorrow))
        XCTAssertEqual(parser.parse("Bugün yağmur yağacak mı?").topic, .rain)
        XCTAssertEqual(parser.parse("Yağmur saat kaçta başlayacak?").topic, .rainTiming)
        XCTAssertEqual(parser.parse("Akşam dışarı çıkabilir miyim?").topic, .goingOut)
        XCTAssertEqual(parser.parse("Akşam dışarı çıkabilir miyim?").dayPart, .evening)
        XCTAssertEqual(parser.parse("Şemsiye almam gerekiyor mu?").topic, .umbrella)
        XCTAssertEqual(parser.parse("Bugün ne giysem?").topic, .clothing)
        XCTAssertEqual(parser.parse("İnce mont yeterli mi?").topic, .clothing)
        XCTAssertEqual(parser.parse("Hafta sonu hava nasıl?").date, .weekend)
        XCTAssertEqual(parser.parse("Bugün güneş kremi kullanmalı mıyım?").topic, .uv)
        XCTAssertEqual(parser.parse("Sabah hava kaç derece?").topic, .temperature)
        XCTAssertEqual(parser.parse("Sabah hava kaç derece?").dayPart, .morning)
        XCTAssertEqual(parser.parse("Saat 17.00'de hava nasıl olacak?").dayPart, .hour(17))
        XCTAssertEqual(parser.parse("Rüzgar çok mu esecek?").topic, .wind)
    }

    func testCityWithTurkishSuffixes() {
        let q = parser.parse("Yarın Bursa'da hava nasıl?")
        XCTAssertEqual(q.province?.name, "Bursa")
        XCTAssertEqual(q.date, .tomorrow)
        XCTAssertEqual(parser.parse("Hafta sonu Antalya'ya gitmek istiyorum").province?.name, "Antalya")
        XCTAssertEqual(parser.parse("İzmirde yağmur var mı").province?.name, "İzmir")
        XCTAssertEqual(parser.parse("İstanbul'dan Ankara'ya yolculuk yapacağım").province?.name, "Ankara", "Destination wins")
    }

    func testHourHeuristicsAndWeekdays() {
        XCTAssertEqual(parser.parse("saat 5'te yağmur var mı").dayPart, .hour(17))
        XCTAssertEqual(parser.parse("sabah saat 6 da hava").dayPart, .hour(6))
        XCTAssertEqual(parser.parse("Pazartesi hava nasıl").date, .weekday(2))
        XCTAssertEqual(parser.parse("Cumartesi yağmur var mı").date, .weekday(7))
        XCTAssertEqual(parser.parse("Cuma günü hava").date, .weekday(6))
        XCTAssertEqual(parser.parse("yarından sonra hava").date, .inDays(2))
    }

    func testFollowUpDetection() {
        XCTAssertTrue(parser.parse("Peki yağmur var mı?").isFollowUp)
        XCTAssertNil(parser.parse("Peki yağmur var mı?").date)
        XCTAssertFalse(parser.parse("Yarın İzmir'de hava").isFollowUp)
    }
}

final class ConversationFlowTests: XCTestCase {
    let now = TestClock.date(hour: 9)
    let answers = WeatherAnswerEngine()

    private func snapshot(_ scenario: MockWeatherData.Scenario = .rainyAfternoon) -> WeatherSnapshot {
        var s = MockWeatherData.snapshot(scenario, now: now)
        s.source = .openMeteo
        return s
    }

    func testTomorrowsWeather() {
        var m = ConversationManager()
        let q = m.interpret("Yarın hava nasıl?", now: now)
        let text = answers.answer(q, snapshot: snapshot(), now: now).fullText
        XCTAssertTrue(text.hasPrefix("Yarın İstanbul'da"), text)
        XCTAssertTrue(text.contains("derece"))
    }

    func testRainTime() {
        var m = ConversationManager()
        let q = m.interpret("Yağmur saat kaçta başlayacak?", now: now)
        let text = answers.answer(q, snapshot: snapshot(), now: now).fullText
        XCTAssertTrue(text.contains("saat 14.00 civarında yağmur bekleniyor"), text)
    }

    func testFollowUpKeepsTomorrow() {
        var m = ConversationManager()
        _ = m.interpret("Yarın hava nasıl?", now: now)
        let q = m.interpret("Peki yağmur var mı?", now: now.addingTimeInterval(30))
        XCTAssertEqual(q.date, .tomorrow)
        XCTAssertEqual(q.topic, .rain)
        XCTAssertTrue(answers.answer(q, snapshot: snapshot(), now: now).fullText.hasPrefix("Yarın"))
    }

    func testFollowUpWithDayPart() {
        var m = ConversationManager()
        _ = m.interpret("Yarın Bursa'da hava nasıl?", now: now)
        let q = m.interpret("Peki akşam?", now: now)
        XCTAssertEqual(q.date, .tomorrow)
        XCTAssertEqual(q.dayPart, .evening)
        XCTAssertEqual(q.province?.name, "Bursa")
    }

    func testContextExpires() {
        var m = ConversationManager()
        _ = m.interpret("Yarın hava nasıl?", now: now)
        let q = m.interpret("Peki yağmur var mı?", now: now.addingTimeInterval(3600))
        XCTAssertEqual(q.date, .today)
    }

    func testAmbiguousDateDefaultsToToday() {
        var m = ConversationManager()
        let q = m.interpret("Hava nasıl olacak?", now: now)
        XCTAssertEqual(q.date, .today)
        XCTAssertTrue(answers.answer(q, snapshot: snapshot(), now: now).fullText.contains("şu an"))
    }

    func testUnknownPlaceFallsBackToCurrentPlaceAndNamesIt() {
        var m = ConversationManager()
        let q = m.interpret("Yarın Kaş'ta hava nasıl?", now: now)   // district not in province list
        XCTAssertNil(q.province)
        XCTAssertTrue(answers.answer(q, snapshot: snapshot(), now: now).fullText.contains("İstanbul'da"),
                      "Answer must name which place it describes")
    }

    func testClothingAnswerUsesData() {
        var m = ConversationManager()
        let q = m.interpret("Bugün ne giysem?", now: now)
        let text = answers.answer(q, snapshot: snapshot(.snowy), now: now).fullText
        XCTAssertTrue(text.contains("Kalın bir mont"), text)
    }

    func testOutOfRangeIsHonest() {
        let q = ResolvedQuery(topic: .overview, date: .inDays(10), dayPart: nil, province: nil)
        let text = answers.answer(q, snapshot: snapshot(), now: now).fullText
        XCTAssertTrue(text.contains("henüz bir tahminim yok"))
        XCTAssertFalse(text.contains("derece"))
    }

    func testSpecificHourTemperature() {
        let q = ResolvedQuery(topic: .temperature, date: .today, dayPart: .hour(17), province: nil)
        let snap = snapshot()
        let text = answers.answer(q, snapshot: snap, now: now).fullText
        let h17 = snap.hourly[17].temperature
        XCTAssertTrue(text.contains("saat 17.00 civarında"), text)
        XCTAssertTrue(text.contains(TurkishFormatting.temperature(h17)), text)
    }

    func testNaturalTodayLabelsAndNoRepeatedDay() {
        var m = ConversationManager()
        let evening = answers.answer(m.interpret("Akşam dışarı çıkabilir miyim?", now: now), snapshot: snapshot(), now: now).fullText
        XCTAssertTrue(evening.hasPrefix("Bu akşam"), evening)
        let tomorrow = answers.answer(m.interpret("Yarın hava nasıl?", now: now), snapshot: snapshot(), now: now)
        XCTAssertEqual(tomorrow.sentences.filter { $0.hasPrefix("Yarın") }.count, 1, tomorrow.fullText)
    }

    func testNoRainSaysSo() {
        let q = ResolvedQuery(topic: .rain, date: .tomorrow, dayPart: nil, province: nil)
        XCTAssertEqual(answers.answer(q, snapshot: snapshot(.sunny), now: now).sentences, ["Yarın yağış beklenmiyor."])
    }
}

final class ForecastDateResolverTests: XCTestCase {
    let r = ForecastDateResolver()
    let tz = TestClock.istanbul

    func testWeekendFromSaturdayAndWeekday() {
        // 2026-11-14 is a Saturday.
        let sat = TestClock.date(hour: 9)
        XCTAssertEqual(r.days(for: .weekend, now: sat, timeZone: tz), [TestClock.date(hour: 0), TestClock.date(hour: 0, day: 15)])
        let wed = TestClock.date(hour: 9, day: 11)
        XCTAssertEqual(r.days(for: .weekend, now: wed, timeZone: tz), [TestClock.date(hour: 0, day: 14), TestClock.date(hour: 0, day: 15)])
    }

    func testWeekdayTodayAndNext() {
        let sat = TestClock.date(hour: 9)
        XCTAssertEqual(r.days(for: .weekday(7), now: sat, timeZone: tz), [TestClock.date(hour: 0)])
        XCTAssertEqual(r.days(for: .weekday(2), now: sat, timeZone: tz), [TestClock.date(hour: 0, day: 16)])
    }

    func testMidnightTransitionUsesPlaceTimeZone() {
        // 23:30 in Istanbul is still "today" there even though it is a different UTC hour.
        let late = TestClock.date(hour: 23, minute: 30)
        XCTAssertEqual(r.days(for: .tomorrow, now: late, timeZone: tz), [TestClock.date(hour: 0, day: 15)])
    }

    func testDifferentTimeZoneDestination() {
        // 01:00 Istanbul (UTC+3) is still the previous day in London (UTC+0).
        let early = TestClock.date(hour: 1)
        let london = TimeZone(identifier: "Europe/London")!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = london
        let day = r.days(for: .today, now: early, timeZone: london)[0]
        XCTAssertEqual(cal.component(.day, from: day), 13)
    }

    func testDSTDayHasCorrectStart() {
        // Europe/Berlin switches to summer time on 2026-03-29.
        let berlin = TimeZone(identifier: "Europe/Berlin")!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = berlin
        let now = cal.date(from: DateComponents(year: 2026, month: 3, day: 28, hour: 20))!
        let tomorrow = r.days(for: .tomorrow, now: now, timeZone: berlin)[0]
        XCTAssertEqual(cal.dateComponents([.day, .hour], from: tomorrow), DateComponents(day: 29, hour: 0))
    }
}
