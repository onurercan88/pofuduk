import XCTest
@testable import PofudukCore

/// End-to-end pipelines with deterministic fixtures (no live network).
final class IntegrationTests: XCTestCase {
    let now = TestClock.date(hour: 9, minute: 20)
    let place = TurkishProvinces.search("İstanbul")[0].place

    func testProviderToSpokenBriefingWithMatchingSubtitles() async throws {
        let repo = CachedWeatherRepository(
            engine: WeatherProviderFallbackEngine(providers: [
                WeatherAPIProvider(http: StubHTTPClient(error: WeatherError.network), apiKey: { "K" }),
                OpenMeteoProvider(http: StubHTTPClient(json: Fixtures.openMeteo), now: { [now] in now })
            ]),
            cache: InMemoryWeatherCacheStore(), now: { [now] in now })
        let snapshot = try await repo.snapshot(for: place, forceRefresh: false)
        XCTAssertEqual(snapshot.source, .openMeteo, "Fell back to the second provider")

        let analysis = WeatherSummaryEngine().analyze(snapshot, now: now)
        let clothing = ClothingRecommendationEngine().recommend(for: snapshot, now: now)
        let briefing = CharacterPersonalityEngine().briefing(for: analysis, clothing: clothing)
        XCTAssertTrue(briefing.fullText.contains("İstanbul'da şu an 18 derece"), briefing.fullText)
        XCTAssertTrue(briefing.fullText.contains("Saat 14.00 civarında yağmur"), briefing.fullText)

        var track = SubtitleTrack()
        track.load(briefing.sentences)
        for i in briefing.sentences.indices { track.didStart(sentenceAt: i); track.didFinish(sentenceAt: i) }
        XCTAssertEqual(track.spokenSentences, briefing.sentences, "Subtitles equal spoken text")
        XCTAssertEqual(track.status, .finished)
    }

    func testConversationOverWeatherAPIFixture() async throws {
        let provider = WeatherAPIProvider(http: StubHTTPClient(json: Fixtures.weatherAPI), apiKey: { "K" }, now: { [now] in now })
        let snapshot = try await provider.fetchSnapshot(for: place)
        var manager = ConversationManager()
        let answer = WeatherAnswerEngine().answer(manager.interpret("Bugün şemsiye gerekir mi?", now: now), snapshot: snapshot, now: now)
        XCTAssertTrue(answer.fullText.hasPrefix("Evet, şemsiye almanı öneririm."), answer.fullText)
        XCTAssertTrue(answer.fullText.contains("Yer yer kuvvetli"), "8.4 mm/h → heavy from amounts")
    }

    func testForecastToNotificationsToMorningBriefing() async throws {
        let snapshot = try await OpenMeteoProvider(http: StubHTTPClient(json: Fixtures.openMeteo), now: { [now] in now }).fetchSnapshot(for: place)
        var prefs = NotificationPreferences()
        prefs.isEnabled = true
        prefs.quietHours.enabled = false
        let plan = RainNotificationEngine().plan(snapshot: snapshot, preferences: prefs, log: InMemoryNotificationLog(), now: now)
        XCTAssertEqual(plan.first?.category, .rainSoon)
        XCTAssertEqual(plan.first?.fireDate, TestClock.date(hour: 13, minute: 30))

        let morning = MorningBriefingEngine().briefing(snapshot: snapshot, analysis: WeatherSummaryEngine().analyze(snapshot, now: now),
                                                       clothing: nil, now: now)
        XCTAssertEqual(morning.sentences.first, "Günaydın!")
    }

    /// Opt-in live check of real providers: run with POFUDUK_LIVE_TESTS=1. Skipped in normal runs.
    func testLiveOpenMeteo() async throws {
        guard ProcessInfo.processInfo.environment["POFUDUK_LIVE_TESTS"] == "1" else {
            throw XCTSkip("Live network tests are opt-in (POFUDUK_LIVE_TESTS=1).")
        }
        let snapshot = try await OpenMeteoProvider(http: URLSessionHTTPClient()).fetchSnapshot(for: place)
        XCTAssertGreaterThanOrEqual(snapshot.hourly.count, 72)
        XCTAssertGreaterThanOrEqual(snapshot.daily.count, 3)
    }
}
