import Foundation

/// Behavioural state of the character. Independent from rendering technology.
public enum CharacterMood: String, Codable, Sendable, CaseIterable {
    case idle, speaking, listening, thinking, happy, surprised, warning, sad, sleeping, celebrating, error
}

/// Weather-driven look (accessories + ambient effects).
public enum WeatherTheme: String, Codable, Sendable, CaseIterable {
    case sunny, rainy, stormy, snowy, cloudy, windy, night

    public var accessibilityDescription: String {
        switch self {
        case .sunny: return "Güneş gözlüklü, mutlu Pofuduk"
        case .rainy: return "Küçük şemsiyesiyle Pofuduk"
        case .stormy: return "Başında minik şemsiyesiyle, biraz ürkek Pofuduk"
        case .snowy: return "Atkı takmış Pofuduk"
        case .cloudy: return "Sakin Pofuduk"
        case .windy: return "Rüzgârda uçurtma uçuran Pofuduk"
        case .night: return "Gece modunda Pofuduk"
        }
    }
}

/// Everything a renderer needs. Rendering (SwiftUI today, Rive later) consumes only this value.
public struct CharacterAppearance: Equatable, Sendable {
    public var mood: CharacterMood
    public var theme: WeatherTheme
    public var isMorningGreeting: Bool
    /// Word being spoken right now (drives the mouth while speaking; nil = generic talking motion).
    public var speechCue: SpokenWordCue?

    public init(mood: CharacterMood, theme: WeatherTheme, isMorningGreeting: Bool = false,
                speechCue: SpokenWordCue? = nil) {
        self.mood = mood
        self.theme = theme
        self.isMorningGreeting = isMorningGreeting
        self.speechCue = speechCue
    }
}

public enum PersonalityStyle: String, Codable, Sendable, CaseIterable {
    case friendly, playful, calm
}

public enum BriefingLength: String, Codable, Sendable, CaseIterable {
    case short, detailed
}

/// A spoken message. `sentences` are exactly what is spoken and exactly what subtitles show.
public struct Briefing: Equatable, Sendable {
    public var sentences: [String]
    /// Mood the character should show when not actively speaking.
    public var restingMood: CharacterMood
    public var theme: WeatherTheme
    /// Short advice bullets for the advice section (all derived from data).
    public var advice: [String]

    public init(sentences: [String], restingMood: CharacterMood, theme: WeatherTheme, advice: [String] = []) {
        self.sentences = sentences
        self.restingMood = restingMood
        self.theme = theme
        self.advice = advice
    }

    public var fullText: String { sentences.joined(separator: " ") }
}
