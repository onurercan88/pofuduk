import XCTest
@testable import PofudukCore

final class SpeechTextNormalizerTests: XCTestCase {
    private func range(of word: String, in text: String) -> TextRange {
        let r = (text as NSString).range(of: word)
        return TextRange(location: r.location, length: r.length)
    }

    func testClockTimesAreSpokenAsHours() {
        XCTAssertEqual(SpeechTextNormalizer.spoken("Saat 14.00 civarında yağmur başlaması bekleniyor.").text,
                       "Saat 14 civarında yağmur başlaması bekleniyor.")
        XCTAssertEqual(SpeechTextNormalizer.spoken("Saat 09.30 sonrasında kar ihtimali.").text,
                       "Saat 9 30 sonrasında kar ihtimali.")
        XCTAssertEqual(SpeechTextNormalizer.spoken("Yarın saat 07.00'ye kadar").text, "Yarın saat 7'ye kadar")
    }

    func testAbbreviations() {
        XCTAssertEqual(SpeechTextNormalizer.spoken("UV indeksi 7 seviyesine çıkıyor.").text,
                       "ultraviyole indeksi 7 seviyesine çıkıyor.")
        XCTAssertEqual(SpeechTextNormalizer.spoken("Bölgen için MGM tarafından uyarı yayımlanmış.").text,
                       "Bölgen için Meteoroloji tarafından uyarı yayımlanmış.")
        // Only whole words.
        XCTAssertEqual(SpeechTextNormalizer.spoken("UVA ve MGMX").text, "UVA ve MGMX")
    }

    func testTextWithoutRulesIsUnchanged() {
        let s = "İstanbul'da şu an 15 derece, hava parçalı bulutlu."
        let spoken = SpeechTextNormalizer.spoken(s)
        XCTAssertEqual(spoken.text, s)
        XCTAssertEqual(spoken.subtitleRange(for: range(of: "derece", in: s)), range(of: "derece", in: s))
    }

    func testSpokenWordRangesMapBackToSubtitle() {
        let subtitle = "Saat 14.00 civarında UV indeksi yükseliyor."
        let spoken = SpeechTextNormalizer.spoken(subtitle)
        XCTAssertEqual(spoken.text, "Saat 14 civarında ultraviyole indeksi yükseliyor.")
        // Words before, inside and after replacements land on the right subtitle words.
        XCTAssertEqual(spoken.subtitleRange(for: range(of: "Saat", in: spoken.text)), range(of: "Saat", in: subtitle))
        XCTAssertEqual(spoken.subtitleRange(for: range(of: "14", in: spoken.text)), range(of: "14.00", in: subtitle))
        XCTAssertEqual(spoken.subtitleRange(for: range(of: "civarında", in: spoken.text)), range(of: "civarında", in: subtitle))
        XCTAssertEqual(spoken.subtitleRange(for: range(of: "ultraviyole", in: spoken.text)), range(of: "UV", in: subtitle))
        XCTAssertEqual(spoken.subtitleRange(for: range(of: "yükseliyor", in: spoken.text)), range(of: "yükseliyor", in: subtitle))
    }

    func testPreferencesFromOlderVersionKeepTheirValues() throws {
        // Saved before `voiceTone` existed.
        let old = #"{"style":"playful","briefingLength":"short","speechRateMultiplier":1.1,"subtitleSize":"large"}"#
        let p = try JSONDecoder().decode(UserPreferences.self, from: Data(old.utf8))
        XCTAssertEqual(p.style, .playful)
        XCTAssertEqual(p.briefingLength, .short)
        XCTAssertEqual(p.speechRateMultiplier, 1.1)
        XCTAssertEqual(p.subtitleSize, .large)
        XCTAssertEqual(p.voiceTone, .pofuduk)

        var changed = p
        changed.voiceTone = .natural
        let roundTrip = try JSONDecoder().decode(UserPreferences.self, from: JSONEncoder().encode(changed))
        XCTAssertEqual(roundTrip, changed)
        XCTAssertEqual(VoiceTone.natural.pitchMultiplier, 1.0)
    }
}
