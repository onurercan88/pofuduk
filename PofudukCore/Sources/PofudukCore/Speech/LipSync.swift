import Foundation

/// The word the speech engine just started, as reported by the synthesizer's word callback.
public struct SpokenWordCue: Equatable, Sendable {
    public var word: String
    public var startedAt: Date
    /// Estimated time per letter at the current speech rate.
    public var secondsPerLetter: TimeInterval

    /// At the default rate Turkish TTS speaks roughly 14 letters per second.
    public static let defaultSecondsPerLetter: TimeInterval = 0.07

    public init(word: String, startedAt: Date, rateMultiplier: Double = 1) {
        self.word = word
        self.startedAt = startedAt
        self.secondsPerLetter = Self.defaultSecondsPerLetter / max(0.5, rateMultiplier)
    }
}

/// Mouth pose for one moment. `open` 0 = closed … 1 = wide open; `round` 0 = spread … 1 = rounded (o/u).
public struct MouthPose: Equatable, Sendable {
    public var open: Double
    public var round: Double

    public static let rest = MouthPose(open: 0.12, round: 0)

    public init(open: Double, round: Double) {
        self.open = open
        self.round = round
    }
}

/// Approximate lip sync from letters (Turkish is written close to how it is spoken).
/// The synthesizer only reports word starts, so letters inside a word are timed evenly.
public enum LipSync {
    public static func pose(for letter: Character) -> MouthPose {
        switch letter {
        case "a", "â": return MouthPose(open: 1.0, round: 0)
        case "e": return MouthPose(open: 0.75, round: 0)
        case "ı", "i", "î": return MouthPose(open: 0.45, round: 0)
        case "o": return MouthPose(open: 0.85, round: 1)
        case "ö": return MouthPose(open: 0.7, round: 0.9)
        case "u", "û": return MouthPose(open: 0.5, round: 1)
        case "ü": return MouthPose(open: 0.45, round: 1)
        case "m", "b", "p": return MouthPose(open: 0, round: 0)
        case "f", "v": return MouthPose(open: 0.12, round: 0)
        case "ş", "ç", "c", "j": return MouthPose(open: 0.25, round: 0.5)
        default: return MouthPose(open: 0.3, round: 0)
        }
    }

    /// Pose at `date`. Blends towards the next letter so the mouth moves smoothly;
    /// after the word it closes to rest within a short tail.
    public static func pose(for cue: SpokenWordCue, at date: Date) -> MouthPose {
        let letters = Array(cue.word.lowercased(with: Locale(identifier: "tr_TR")).filter(\.isLetter))
        guard !letters.isEmpty, cue.secondsPerLetter > 0 else { return .rest }
        let elapsed = date.timeIntervalSince(cue.startedAt)
        guard elapsed >= 0 else { return .rest }
        let position = elapsed / cue.secondsPerLetter
        let index = Int(position)
        if index >= letters.count {
            // Close over ~2 letters' time after the word ends.
            let tail = min(1, (position - Double(letters.count)) / 2)
            return blend(pose(for: letters[letters.count - 1]), .rest, tail)
        }
        let current = pose(for: letters[index])
        let next = index + 1 < letters.count ? pose(for: letters[index + 1]) : .rest
        // Hold each letter for the first half, then move towards the next one.
        let fraction = max(0, (position - Double(index)) - 0.5) * 2
        return blend(current, next, fraction)
    }

    static func blend(_ a: MouthPose, _ b: MouthPose, _ t: Double) -> MouthPose {
        let t = min(1, max(0, t))
        return MouthPose(open: a.open + (b.open - a.open) * t, round: a.round + (b.round - a.round) * t)
    }
}
