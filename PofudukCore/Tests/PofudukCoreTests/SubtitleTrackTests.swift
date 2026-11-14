import XCTest
@testable import PofudukCore

final class SubtitleTrackTests: XCTestCase {
    func testSegmenterKeepsClockTimesAndDecimals() {
        let s = SentenceSegmenter.split("Saat 14.00 civarında yağmur var. 2.5 mm bekleniyor! Hazır mısın?")
        XCTAssertEqual(s, ["Saat 14.00 civarında yağmur var.", "2.5 mm bekleniyor!", "Hazır mısın?"])
    }

    func testProgressionFollowsCallbacks() {
        var t = SubtitleTrack(sentences: ["Merhaba.", "Bugün güneşli."])
        XCTAssertEqual(t.status, .idle)
        t.didStart(sentenceAt: 0)
        XCTAssertEqual(t.status, .speaking)
        XCTAssertEqual(t.currentSentence, "Merhaba.")
        t.willSpeak(TextRange(location: 0, length: 7), sentenceAt: 0)
        XCTAssertEqual(t.wordRange, TextRange(location: 0, length: 7))
        t.didFinish(sentenceAt: 0)
        XCTAssertEqual(t.status, .speaking)
        t.didStart(sentenceAt: 1)
        XCTAssertEqual(t.spokenSentences.count, 2)
        t.didFinish(sentenceAt: 1)
        XCTAssertEqual(t.status, .finished)
        XCTAssertEqual(t.currentSentence, "Bugün güneşli.", "Last sentence stays visible")
    }

    func testPauseResumeStop() {
        var t = SubtitleTrack(sentences: ["Bir.", "İki."])
        t.didStart(sentenceAt: 0)
        t.didPause()
        XCTAssertEqual(t.status, .paused)
        t.didResume()
        XCTAssertEqual(t.status, .speaking)
        t.didStop()
        XCTAssertEqual(t.status, .stopped)
        XCTAssertEqual(t.currentSentence, "Bir.")
        XCTAssertEqual(t.transcript, "Bir.\nİki.")
    }

    func testInvalidRangeIsIgnored() {
        var t = SubtitleTrack(sentences: ["Kısa."])
        t.didStart(sentenceAt: 0)
        t.willSpeak(TextRange(location: 3, length: 50), sentenceAt: 0)
        XCTAssertNil(t.wordRange)
    }

    func testSoundDisabledShowsEverything() {
        var t = SubtitleTrack(sentences: ["Bir.", "İki."])
        t.showAllWithoutAudio()
        XCTAssertEqual(t.status, .finished)
        XCTAssertEqual(t.spokenSentences, ["Bir.", "İki."])
    }
}
