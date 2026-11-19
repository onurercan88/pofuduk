import XCTest
@testable import PofudukCore

final class TapReactionTests: XCTestCase {
    func testReactionFollowsWhatPofudukWears() {
        XCTAssertEqual(TapReaction.choose(for: .sunny, mood: .idle), .tossGlasses)
        XCTAssertEqual(TapReaction.choose(for: .rainy, mood: .idle), .twirlUmbrella)
        XCTAssertEqual(TapReaction.choose(for: .stormy, mood: .warning), .spinUmbrellaHat)
        for theme in [WeatherTheme.cloudy, .windy, .snowy, .night] {
            XCTAssertEqual(TapReaction.choose(for: theme, mood: .idle), .dance, "\(theme)")
        }
    }

    func testNoGlassesToTossWhileAsleepOrInError() {
        XCTAssertEqual(TapReaction.choose(for: .sunny, mood: .sleeping), .dance)
        XCTAssertEqual(TapReaction.choose(for: .sunny, mood: .error), .dance)
    }

    func testLaughVariesPerTapAndWraps() {
        let n = TapReaction.laughs.count
        XCTAssertNotEqual(TapReaction.laugh(forTap: 0), TapReaction.laugh(forTap: 1))
        XCTAssertEqual(TapReaction.laugh(forTap: 0), TapReaction.laugh(forTap: n))
        XCTAssertEqual(TapReaction.laugh(forTap: -1), TapReaction.laughs[n - 1])
    }

    func testProgressOnlyWhilePlaying() {
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        let playback = TapReactionPlayback(reaction: .dance, laugh: "Hihi!", startedAt: start)
        XCTAssertNil(playback.progress(at: 999))
        XCTAssertEqual(playback.progress(at: 1000), 0)
        XCTAssertEqual(playback.progress(at: 1000 + TapReaction.duration / 2)!, 0.5, accuracy: 1e-9)
        XCTAssertNil(playback.progress(at: 1000 + TapReaction.duration + 0.01))
    }
}
