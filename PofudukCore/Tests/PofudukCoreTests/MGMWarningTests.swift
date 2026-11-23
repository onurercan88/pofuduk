import XCTest
@testable import PofudukCore

final class MGMWarningTests: XCTestCase {
    let matcher = WeatherAlertMatcher()
    let now = TestClock.date(hour: 12)
    let istanbul = TurkishProvinces.search("İstanbul")[0].place

    private func warning(_ level: WarningLevel, provinces: [String] = ["İstanbul"], districts: [String] = [],
                         from: TimeInterval = -3600, until: TimeInterval = 3600) -> OfficialWarning {
        OfficialWarning(id: "\(level)-\(provinces)", level: level, hazard: "Kuvvetli yağış", description: "Sel ve su baskınlarına dikkat.",
                        provinces: provinces, districts: districts, validFrom: now.addingTimeInterval(from),
                        validUntil: now.addingTimeInterval(until), sourceURL: MGMOfficialPage.warnings)
    }

    func testNoWarning() {
        XCTAssertTrue(matcher.matching([], place: istanbul, at: now).isEmpty)
        XCTAssertTrue(matcher.matching([warning(.green)], place: istanbul, at: now).isEmpty, "Green is not a warning")
    }

    func testYellowOrangeRedAreMatchedAndSortedBySeverity() {
        let m = matcher.matching([warning(.yellow), warning(.red), warning(.orange)], place: istanbul, at: now)
        XCTAssertEqual(m.map(\.level), [.red, .orange, .yellow])
    }

    func testExpiredWarningIgnored() {
        XCTAssertTrue(matcher.matching([warning(.orange, from: -7200, until: -60)], place: istanbul, at: now).isEmpty)
        XCTAssertTrue(matcher.matching([warning(.orange, from: 600, until: 3600)], place: istanbul, at: now).isEmpty, "Not yet valid")
    }

    func testWarningForAnotherProvinceIgnored() {
        XCTAssertTrue(matcher.matching([warning(.red, provinces: ["Ankara"])], place: istanbul, at: now).isEmpty)
    }

    func testProvinceMatchIsDiacriticInsensitiveAndDistrictAware() {
        var kadikoy = istanbul
        kadikoy.district = "Kadıköy"
        XCTAssertEqual(matcher.matching([warning(.yellow, provinces: ["ISTANBUL"])], place: kadikoy, at: now).count, 1)
        XCTAssertEqual(matcher.matching([warning(.yellow, districts: ["Kadıköy"])], place: kadikoy, at: now).count, 1)
        XCTAssertTrue(matcher.matching([warning(.yellow, districts: ["Şile"])], place: kadikoy, at: now).isEmpty)
    }

    func testSourceUnavailableWithoutAuthorizedFeed() async {
        let repo = MGMAlertRepository(provider: ConfiguredMGMWarningProvider(feedURL: nil, http: StubHTTPClient()))
        guard case .unavailable(let reason, let page) = await repo.warnings(for: istanbul, at: now) else { return XCTFail() }
        XCTAssertEqual(page.absoluteString, "https://www.mgm.gov.tr/meteouyari/turkiye.aspx")
        // Must not read like a broken connection, and must point to MGM's page.
        XCTAssertFalse(reason.contains("bağlantı"), reason)
        XCTAssertTrue(reason.contains("MGM'nin sayfasından"), reason)
    }

    func testFeedFailureIsUnavailableNotEmpty() async {
        let provider = ConfiguredMGMWarningProvider(feedURL: URL(string: "https://example.invalid/cap")!, http: StubHTTPClient(status: 503))
        guard case .unavailable = await provider.warnings() else { return XCTFail("A failed feed must not look like 'no warnings'") }
    }

    func testCAPParsingAndRepositoryMatching() async throws {
        let cap = """
        <?xml version="1.0" encoding="UTF-8"?>
        <alerts>
        <alert xmlns="urn:oasis:names:tc:emergency:cap:1.2">
          <identifier>TR-2026-001</identifier><sent>2026-11-14T08:00:00+03:00</sent>
          <info><language>en-GB</language><event>Heavy rain</event><severity>Severe</severity>
            <expires>2026-11-14T23:00:00+03:00</expires><area><areaDesc>Istanbul</areaDesc></area></info>
          <info><language>tr-TR</language><event>Kuvvetli yağış</event><severity>Severe</severity>
            <onset>2026-11-14T09:00:00+03:00</onset><expires>2026-11-14T23:00:00+03:00</expires>
            <description>Sel ve su baskınlarına karşı dikkatli olunmalı.</description>
            <web>https://www.mgm.gov.tr/meteouyari/turkiye.aspx</web>
            <parameter><valueName>awareness_level</valueName><value>3; orange; Severe</value></parameter>
            <area><areaDesc>İstanbul, Kocaeli</areaDesc></area></info>
        </alert>
        <alert xmlns="urn:oasis:names:tc:emergency:cap:1.2">
          <identifier>TR-2026-002</identifier><sent>2026-11-14T08:00:00+03:00</sent>
          <info><language>tr-TR</language><event>Fırtına</event><severity>Extreme</severity>
            <onset>2026-11-14T09:00:00+03:00</onset><expires>2026-11-14T23:00:00+03:00</expires>
            <area><areaDesc>Ankara</areaDesc></area></info>
        </alert>
        </alerts>
        """
        let parsed = try XCTUnwrap(CAPWarningParser.parse(Data(cap.utf8)))
        XCTAssertEqual(parsed.count, 2)
        let first = parsed[0]
        XCTAssertEqual(first.level, .orange)
        XCTAssertEqual(first.hazard, "Kuvvetli yağış", "Turkish info preferred")
        XCTAssertEqual(first.provinces, ["İstanbul", "Kocaeli"])
        XCTAssertEqual(first.validFrom, TestClock.date(hour: 9))
        XCTAssertEqual(parsed[1].level, .red, "Severity fallback when no awareness level")

        let provider = ConfiguredMGMWarningProvider(feedURL: URL(string: "https://example.invalid/cap")!, http: StubHTTPClient(json: cap))
        guard case .available(let matched) = await MGMAlertRepository(provider: provider).warnings(for: istanbul, at: now) else { return XCTFail() }
        XCTAssertEqual(matched.map(\.id), ["TR-2026-001"])
    }

    func testOrangeWarningDrivesSeriousBriefing() {
        let snap = MockWeatherData.snapshot(.sunny, now: now)
        let a = WeatherSummaryEngine().analyze(snap, now: now)
        let b = CharacterPersonalityEngine(style: .playful).briefing(for: a, warnings: [warning(.orange)])
        XCTAssertEqual(b.restingMood, .warning)
        XCTAssertTrue(b.fullText.contains("MGM tarafından turuncu seviyede"))
        XCTAssertFalse(b.fullText.contains("Güneş bizimle"), "No jokes during a serious warning")
    }
}
