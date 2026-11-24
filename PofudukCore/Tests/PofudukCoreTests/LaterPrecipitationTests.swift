import XCTest
@testable import PofudukCore

/// Seen on a device: raining at 07.00, briefing said "Saat 09.00 civarında yağmur başlaması bekleniyor."
final class LaterPrecipitationTests: XCTestCase {
    let summary = WeatherSummaryEngine()
    let at = TestClock.date(hour: 7)

    /// Sunny mock, made wet (probability 80 %, `mm` per hour) from `wetFrom` to 12.00; `now` = current condition.
    private func snapshot(now condition: WeatherCondition, wetFrom: Int, mm: Double = 1.0,
                          wetCondition: WeatherCondition = .rain) -> WeatherSnapshot {
        var snap = MockWeatherData.snapshot(.sunny, now: at)
        snap.current.condition = condition
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = snap.place.timeZone
        snap.hourly = snap.hourly.map { h in
            var h = h
            let hour = calendar.component(.hour, from: h.time)
            let wet = calendar.isDate(h.time, inSameDayAs: at) && (wetFrom..<12).contains(hour)
            h.precipitationProbability = wet ? 80 : 0
            h.precipitationMm = wet ? mm : 0
            h.condition = wet ? wetCondition : .partlyCloudy
            return h
        }
        return snap
    }

    private func analysis(_ snap: WeatherSnapshot) -> WeatherAnalysis { summary.analyze(snap, now: at) }
    private func text(_ snap: WeatherSnapshot) -> String {
        CharacterPersonalityEngine().briefing(for: analysis(snap)).fullText
    }

    func testSameRainWithoutRealBreakIsToldAsContinuing() {
        // Raining now (forecast missed it); 08.00 dry, wet from 09.00: one dry hour is not a break.
        let snap = snapshot(now: .rain, wetFrom: 9)
        XCTAssertEqual(analysis(snap).laterPrecipitation, .continues)
        let t = text(snap)
        XCTAssertTrue(t.contains("Şu sıralar yağmur var ve yaklaşık 5 saat daha sürebilir."), t)
        XCTAssertFalse(t.contains("başlaması bekleniyor"), t)
    }

    func testTwoDryHoursMeanItMayStopAndStartAgain() {
        let snap = snapshot(now: .rain, wetFrom: 10)
        XCTAssertEqual(analysis(snap).laterPrecipitation, .resumes)
        let t = text(snap)
        XCTAssertTrue(t.contains("Şu anki yağmur ara verebilir; saat 10.00 civarında yeniden başlaması bekleniyor"), t)
    }

    func testHeavierLaterIsToldAsIntensifying() {
        let heavy = snapshot(now: .drizzle, wetFrom: 9, mm: 9)
        XCTAssertEqual(analysis(heavy).laterPrecipitation, .intensifies)
        XCTAssertTrue(text(heavy).contains("Şu sıralar çisenti var; saat 09.00 civarında kuvvetlenmesi bekleniyor"), text(heavy))

        let storm = snapshot(now: .rain, wetFrom: 9, wetCondition: .thunderstorm)
        XCTAssertTrue(text(storm).contains("saat 09.00 civarında gök gürültülü sağanağa dönmesi bekleniyor"), text(storm))
    }

    func testDryNowKeepsTheStartTime() {
        let snap = snapshot(now: .cloudy, wetFrom: 9)
        XCTAssertNil(analysis(snap).laterPrecipitation)
        XCTAssertTrue(text(snap).contains("Saat 09.00 civarında yağmur başlaması bekleniyor"), text(snap))
    }

    func testRainInTheCurrentHourIsUnchanged() {
        // The forecast has rain now too: the existing "Şu sıralar … var" wording applies.
        let snap = snapshot(now: .rain, wetFrom: 7)
        XCTAssertNil(analysis(snap).laterPrecipitation)
        XCTAssertTrue(text(snap).contains("Şu sıralar yağmur var"), text(snap))
    }

    func testAnswerToRainQuestionWhileRaining() {
        var m = ConversationManager()
        let answer = WeatherAnswerEngine().answer(m.interpret("Bugün yağmur var mı?", now: at),
                                                  snapshot: snapshot(now: .rain, wetFrom: 10), now: at).fullText
        XCTAssertTrue(answer.contains("Şu an yağmur var; ara verip saat 10.00 civarında yeniden başlaması bekleniyor."), answer)
    }

    func testMorningBriefingWhileRaining() {
        let snap = snapshot(now: .rain, wetFrom: 9)
        let b = MorningBriefingEngine().briefing(snapshot: snap, analysis: analysis(snap), clothing: nil, now: at).fullText
        XCTAssertTrue(b.contains("Şu sıralar yağmur var ve bir süre daha sürmesi bekleniyor."), b)
        XCTAssertFalse(b.contains("Ancak sabah saatlerinde yağmur bekleniyor"), b)
    }
}
