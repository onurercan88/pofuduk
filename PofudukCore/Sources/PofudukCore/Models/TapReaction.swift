import Foundation

/// Just-for-fun reaction when Pofuduk is tapped while not speaking.
/// Depends on what Pofuduk is wearing: glasses get tossed, an umbrella gets played with, otherwise a dance.
public enum TapReaction: String, Sendable, CaseIterable {
    case tossGlasses, twirlUmbrella, spinUmbrellaHat, dance

    public static func choose(for theme: WeatherTheme, mood: CharacterMood) -> TapReaction {
        if CharacterAppearance.wearsSunglasses(theme: theme, mood: mood) { return .tossGlasses }
        switch theme {
        case .rainy: return .twirlUmbrella
        case .stormy: return .spinUmbrellaHat
        default: return .dance
        }
    }

    /// Giggle shown in a little bubble (and spoken when sound is on); varies with each tap.
    public static let laughs = ["Hihi!", "Ha ha ha!", "Gıdıklanıyorum!", "Hi hi hi, bir daha!", "Vay, ne eğlenceli!"]

    public static func laugh(forTap count: Int) -> String {
        laughs[((count % laughs.count) + laughs.count) % laughs.count]
    }

    public static let duration: TimeInterval = 1.8
}

/// A reaction in progress. `startedAt` is wall-clock time, matched against the character's animation clock.
public struct TapReactionPlayback: Equatable, Sendable {
    public var reaction: TapReaction
    public var laugh: String
    public var startedAt: Date

    public init(reaction: TapReaction, laugh: String, startedAt: Date) {
        self.reaction = reaction
        self.laugh = laugh
        self.startedAt = startedAt
    }

    /// 0...1 while playing, nil before/after.
    public func progress(at time: TimeInterval) -> Double? {
        let p = (time - startedAt.timeIntervalSinceReferenceDate) / TapReaction.duration
        return (0...1).contains(p) ? p : nil
    }
}
