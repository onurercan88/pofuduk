import XCTest
@testable import PofudukCore

final class PersonalizationTests: XCTestCase {
    let now = TestClock.date(hour: 15)

    private func briefing(_ scenario: MockWeatherData.Scenario, style: PersonalityStyle, length: BriefingLength) -> Briefing {
        var snap = MockWeatherData.snapshot(scenario, now: now)
        snap.source = .openMeteo
        let a = WeatherSummaryEngine().analyze(snap, now: now)
        return CharacterPersonalityEngine(style: style, length: length).briefing(for: a)
    }

    func testShortBriefingIsShorterButKeepsFacts() {
        let short = briefing(.windy, style: .friendly, length: .short)
        let detailed = briefing(.windy, style: .friendly, length: .detailed)
        XCTAssertLessThan(short.sentences.count, detailed.sentences.count)
        XCTAssertTrue(short.fullText.contains("şu an"), "Current conditions always included")
        XCTAssertTrue(short.fullText.contains("kilometre"), "Strong wind is never dropped")
        XCTAssertFalse(short.fullText.contains("Hissedilen"))
    }

    func testStylesChangeToneNotFacts() {
        let facts = { (b: Briefing) in b.sentences.dropFirst().dropLast().joined(separator: " ") }
        let friendly = briefing(.rainyAfternoon, style: .friendly, length: .detailed)
        let playful = briefing(.rainyAfternoon, style: .playful, length: .detailed)
        let calm = briefing(.rainyAfternoon, style: .calm, length: .detailed)
        XCTAssertEqual(facts(friendly), facts(playful))
        XCTAssertEqual(facts(friendly), facts(calm))
        XCTAssertNotEqual(friendly.sentences.last, playful.sentences.last)
        XCTAssertTrue(playful.fullText.contains("suçlama"))
        XCTAssertFalse(calm.sentences.last!.contains("!"), "Calm style avoids exclamations")
    }

    func testPlayfulIsNeverPlayfulInStorms() {
        let b = briefing(.stormy, style: .playful, length: .short)
        XCTAssertEqual(b.restingMood, .warning)
        XCTAssertTrue(b.sentences.last!.hasPrefix("Şakayı bir kenara bırakalım"))
    }

    func testPreferencesStoreRoundTripAndClamp() {
        let suite = "PersonalizationTests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = UserPreferencesStore(defaults: defaults)
        XCTAssertEqual(store.load(), UserPreferences())
        var p = UserPreferences()
        p.style = .calm
        p.briefingLength = .short
        p.subtitleSize = .huge
        p.speechRateMultiplier = 3
        store.save(p)
        XCTAssertEqual(store.load().style, .calm)
        XCTAssertEqual(store.load().clampedSpeechRate, 1.25)
        store.clear()
        XCTAssertEqual(store.load(), UserPreferences())
    }
}
