import Foundation

public enum SubtitleSize: String, Codable, Sendable, CaseIterable {
    case standard, large, extraLarge, huge

    public var turkishName: String {
        switch self {
        case .standard: return "Normal"
        case .large: return "Büyük"
        case .extraLarge: return "Çok büyük"
        case .huge: return "En büyük"
        }
    }
}

/// Pitch of Pofuduk's voice. Raising the system voice's pitch can sound more synthetic, so users can pick.
public enum VoiceTone: String, Codable, Sendable, CaseIterable {
    /// A little higher, the character's original voice.
    case pofuduk
    /// The system voice's own pitch.
    case natural

    public var turkishName: String { self == .pofuduk ? "Pofuduk (ince)" : "Doğal" }
    public var pitchMultiplier: Float { self == .pofuduk ? 1.12 : 1.0 }
}

/// Personalization stored on device only (no sync, no inferred personal attributes).
public struct UserPreferences: Codable, Equatable, Sendable {
    public var style: PersonalityStyle = .friendly
    public var briefingLength: BriefingLength = .detailed
    /// Multiplier on the natural speech rate (0.8 = slower, 1.25 = faster).
    public var speechRateMultiplier: Double = 1.0
    /// AVSpeechSynthesisVoice identifier; nil = best installed Turkish voice.
    public var voiceIdentifier: String?
    public var subtitleSize: SubtitleSize = .standard
    public var voiceTone: VoiceTone = .pofuduk

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case style, briefingLength, speechRateMultiplier, voiceIdentifier, subtitleSize, voiceTone
    }

    /// Missing keys keep their defaults, so preferences saved by an older version (without newer
    /// settings such as `voiceTone`) still load instead of resetting everything.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = UserPreferences()
        style = try c.decodeIfPresent(PersonalityStyle.self, forKey: .style) ?? d.style
        briefingLength = try c.decodeIfPresent(BriefingLength.self, forKey: .briefingLength) ?? d.briefingLength
        speechRateMultiplier = try c.decodeIfPresent(Double.self, forKey: .speechRateMultiplier) ?? d.speechRateMultiplier
        voiceIdentifier = try c.decodeIfPresent(String.self, forKey: .voiceIdentifier)
        subtitleSize = (try? c.decodeIfPresent(SubtitleSize.self, forKey: .subtitleSize)) ?? d.subtitleSize
        voiceTone = (try? c.decodeIfPresent(VoiceTone.self, forKey: .voiceTone)) ?? d.voiceTone
    }

    public static let speechRateRange: ClosedRange<Double> = 0.8...1.25

    public var clampedSpeechRate: Double { min(max(speechRateMultiplier, Self.speechRateRange.lowerBound), Self.speechRateRange.upperBound) }
}

public extension PersonalityStyle {
    var turkishName: String {
        switch self {
        case .friendly: return "Samimi"
        case .playful: return "Şakacı"
        case .calm: return "Sakin"
        }
    }
}

public extension BriefingLength {
    var turkishName: String { self == .short ? "Kısa" : "Ayrıntılı" }
}

public final class UserPreferencesStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "pofuduk.userPreferences"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> UserPreferences {
        guard let data = defaults.data(forKey: key),
              let p = try? JSONDecoder().decode(UserPreferences.self, from: data) else { return UserPreferences() }
        return p
    }
    public func save(_ p: UserPreferences) {
        if let data = try? JSONEncoder().encode(p) { defaults.set(data, forKey: key) }
    }
    public func clear() { defaults.removeObject(forKey: key) }
}
