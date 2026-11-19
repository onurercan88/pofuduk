import XCTest
@testable import PofudukCore

final class LipSyncTests: XCTestCase {
    let start = Date(timeIntervalSinceReferenceDate: 1000)

    private func pose(_ word: String, atLetter position: Double, rate: Double = 1) -> MouthPose {
        let cue = SpokenWordCue(word: word, startedAt: start, rateMultiplier: rate)
        return LipSync.pose(for: cue, at: start.addingTimeInterval(position * cue.secondsPerLetter))
    }

    func testVowelsOpenAndLipConsonantsClose() {
        // "mama": m a m a
        XCTAssertEqual(pose("mama", atLetter: 0.1).open, 0)
        XCTAssertEqual(pose("mama", atLetter: 1.1).open, 1)
        XCTAssertEqual(pose("mama", atLetter: 2.1).open, 0)
    }

    func testRoundVowels() {
        XCTAssertEqual(pose("o", atLetter: 0.1).round, 1)
        XCTAssertEqual(pose("i", atLetter: 0.1).round, 0)
        // Turkish lowercasing: "I" is "ı", "İ" is "i" — both spread.
        XCTAssertEqual(pose("UZUN", atLetter: 0.1).round, 1)
        XCTAssertEqual(pose("İZMİR", atLetter: 0.1), LipSync.pose(for: Character("i")))
    }

    func testMouthClosesAfterTheWord() {
        XCTAssertEqual(pose("a", atLetter: 5), .rest)
        XCTAssertGreaterThan(pose("a", atLetter: 1.5).open, MouthPose.rest.open)
    }

    func testBlendsTowardsNextLetter() {
        // Second half of "a" moves towards "m" (closed).
        let mid = pose("am", atLetter: 0.75).open
        XCTAssertLessThan(mid, 1)
        XCTAssertGreaterThan(mid, 0)
    }

    func testFasterSpeechMovesFaster() {
        let slow = SpokenWordCue(word: "merhaba", startedAt: start, rateMultiplier: 1)
        let fast = SpokenWordCue(word: "merhaba", startedAt: start, rateMultiplier: 1.25)
        XCTAssertLessThan(fast.secondsPerLetter, slow.secondsPerLetter)
    }

    func testDigitsAndPunctuationAreIgnored() {
        XCTAssertEqual(pose("12,", atLetter: 0), .rest)
        XCTAssertEqual(pose("a!", atLetter: 0.1).open, 1)
    }
}
