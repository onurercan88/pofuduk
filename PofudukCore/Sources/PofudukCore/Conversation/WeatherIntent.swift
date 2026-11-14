import Foundation

public enum DateReference: Equatable, Sendable {
    case today, tomorrow
    case inDays(Int)
    case weekend
    /// Calendar weekday (1 = Sunday … 7 = Saturday); the next occurrence, today included.
    case weekday(Int)
}

public enum DayPart: Equatable, Sendable {
    case morning, noon, afternoon, evening, night
    case hour(Int)

    /// Local hours covered (inclusive).
    public var hours: ClosedRange<Int> {
        switch self {
        case .morning: return 6...11
        case .noon: return 11...14
        case .afternoon: return 12...17
        case .evening: return 18...22
        case .night: return 21...23
        case .hour(let h): return h...h
        }
    }
}

public enum WeatherTopic: String, Equatable, Sendable {
    case overview, rain, rainTiming, umbrella, temperature, wind, uv, clothing, goingOut, travel
}

/// Parsed from one utterance. `nil` fields mean "not mentioned" (may be inherited from context).
public struct WeatherIntent: Equatable, Sendable {
    public var topic: WeatherTopic
    public var date: DateReference?
    public var dayPart: DayPart?
    /// Province mentioned in the query (resolved against the offline province list).
    public var province: TurkishProvinces.Province?
    public var isFollowUp: Bool

    public init(topic: WeatherTopic, date: DateReference? = nil, dayPart: DayPart? = nil,
                province: TurkishProvinces.Province? = nil, isFollowUp: Bool = false) {
        self.topic = topic
        self.date = date
        self.dayPart = dayPart
        self.province = province
        self.isFollowUp = isFollowUp
    }
}

/// Intent after merging with conversation context; ready to be answered.
public struct ResolvedQuery: Equatable, Sendable {
    public var topic: WeatherTopic
    public var date: DateReference
    public var dayPart: DayPart?
    /// nil = the user's current place.
    public var province: TurkishProvinces.Province?
}
