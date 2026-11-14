import XCTest
@testable import PofudukCore

final class TravelWeatherTests: XCTestCase {
    let engine = TravelWeatherSummaryEngine()
    let now = TestClock.date(hour: 10)

    private func snapshot(_ place: Place, scenario: MockWeatherData.Scenario, shift: Double = 0) -> WeatherSnapshot {
        var s = MockWeatherData.snapshot(scenario, now: now, place: place)
        s.source = .openMeteo
        s.daily = s.daily.map { var d = $0; d.minTemperature += shift; d.maxTemperature += shift; return d }
        s.hourly = s.hourly.map { var h = $0; h.temperature += shift; return h }
        return s
    }

    private var istanbul: Place { TurkishProvinces.search("İstanbul")[0].place }
    private var bursa: Place { TurkishProvinces.search("Bursa")[0].place }

    func testDestinationResolvedFromQuestion() {
        let parser = WeatherQueryParser()
        XCTAssertEqual(parser.parse("Yarın Bursa'ya gideceğim. Hava nasıl?").topic, .travel)
        XCTAssertEqual(parser.province(in: "Yarın Bursa'ya gideceğim")?.name, "Bursa")
        XCTAssertEqual(parser.parse("Hafta sonu Antalya'ya gitmek istiyorum. Hava uygun mu?").date, .weekend)
        XCTAssertEqual(parser.province(in: "İstanbul'dan Ankara'ya yolculuk yapacağım")?.name, "Ankara")
    }

    func testDestinationNotFound() {
        XCTAssertNil(WeatherQueryParser().province(in: "Yarın Atlantis'e gideceğim"))
    }

    func testComparisonWithOrigin() {
        let tomorrow = TravelWeatherSummaryEngine.travelDays(departure: TestClock.date(hour: 12, day: 15), returnDate: nil,
                                                             timeZone: TestClock.istanbul)
        let summary = engine.summarize(destination: snapshot(bursa, scenario: .rainyAfternoon, shift: -3),
                                       origin: snapshot(istanbul, scenario: .rainyAfternoon), days: tomorrow, now: now)
        let text = summary.briefing.fullText
        XCTAssertTrue(text.hasPrefix("Yarın Bursa'da hava İstanbul'dan biraz daha serin olacak"), text)
        XCTAssertTrue(text.contains("Öğleden sonra yağış bekleniyor."), text)
        XCTAssertTrue(text.contains("Yanına") && text.contains("şemsiye"), text)
        XCTAssertEqual(summary.days.count, 1)
    }

    func testMultipleTravelDates() {
        let days = TravelWeatherSummaryEngine.travelDays(departure: TestClock.date(hour: 9, day: 15), returnDate: TestClock.date(hour: 9, day: 17),
                                                         timeZone: TestClock.istanbul)
        XCTAssertEqual(days.count, 3)
        let summary = engine.summarize(destination: snapshot(bursa, scenario: .sunny), origin: nil, days: days, now: now)
        XCTAssertEqual(summary.days.count, 3)
        XCTAssertTrue(summary.briefing.sentences.contains { $0.hasPrefix("Pazartesi") }, summary.briefing.fullText)
        XCTAssertTrue(summary.briefing.fullText.contains("daha belirsiz"), "Day +3 is flagged as less certain")
    }

    func testMissingFutureForecast() {
        let days = TravelWeatherSummaryEngine.travelDays(departure: TestClock.date(hour: 9, day: 25), returnDate: nil, timeZone: TestClock.istanbul)
        let summary = engine.summarize(destination: snapshot(bursa, scenario: .sunny), origin: nil, days: days, now: now)
        XCTAssertTrue(summary.days.isEmpty)
        XCTAssertEqual(summary.unavailableDays.count, 1)
        XCTAssertTrue(summary.briefing.fullText.contains("henüz tahmin yok"))
        XCTAssertFalse(summary.briefing.fullText.contains("derece"))
    }

    func testPartlyCoveredTrip() {
        let days = TravelWeatherSummaryEngine.travelDays(departure: TestClock.date(hour: 9, day: 17), returnDate: TestClock.date(hour: 9, day: 20),
                                                         timeZone: TestClock.istanbul)
        let summary = engine.summarize(destination: snapshot(bursa, scenario: .cloudy), origin: nil, days: days, now: now)
        XCTAssertEqual(summary.days.count, 2)           // mock covers 5 days: 14–18
        XCTAssertEqual(summary.unavailableDays.count, 2)
        XCTAssertTrue(summary.briefing.fullText.contains("2 gün için tahmin henüz yayımlanmadı"))
    }

    func testDifferentTimeZone() {
        let london = Place(name: "Londra", coordinate: Coordinate(latitude: 51.5, longitude: -0.12),
                           timeZoneIdentifier: "Europe/London", source: .manual)
        // 01:00 in Istanbul is still the previous day in London.
        let early = TestClock.date(hour: 1, day: 15)
        let days = TravelWeatherSummaryEngine.travelDays(departure: early, returnDate: nil, timeZone: london.timeZone)
        XCTAssertEqual(days.first?.day, 14)
        var dest = MockWeatherData.snapshot(.cloudy, now: early, place: london)
        dest.source = .openMeteo
        let summary = engine.summarize(destination: dest, origin: snapshot(istanbul, scenario: .cloudy), days: days, now: early)
        XCTAssertTrue(summary.briefing.fullText.contains("Londra saati İstanbul saatinden 3 saat geride"), summary.briefing.fullText)
    }

    func testAblative() {
        XCTAssertEqual(TurkishGrammar.ablative("İstanbul"), "İstanbul'dan")
        XCTAssertEqual(TurkishGrammar.ablative("İzmir"), "İzmir'den")
        XCTAssertEqual(TurkishGrammar.ablative("Kars"), "Kars'tan")
    }
}
