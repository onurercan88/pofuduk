import Foundation

/// Merges a parsed intent with conversation context (spec: WeatherIntentResolver).
/// "Yarın hava nasıl?" → "Peki yağmur var mı?" keeps "yarın"; a new date or city replaces context.
public struct WeatherIntentResolver: Sendable {
    public init() {}

    public func resolve(_ intent: WeatherIntent, context: ResolvedQuery?) -> ResolvedQuery {
        let inherit = intent.isFollowUp && context != nil
        let date = intent.date ?? (inherit ? context!.date : .today)
        let dayPart = intent.dayPart ?? (inherit && intent.date == nil ? context!.dayPart : nil)
        let province = intent.province ?? (inherit ? context!.province : nil)
        return ResolvedQuery(topic: intent.topic, date: date, dayPart: dayPart, province: province)
    }
}

/// Holds the short-term conversation context. Context expires after `contextLifetime`.
public struct ConversationManager: Sendable {
    public private(set) var context: ResolvedQuery?
    private var contextTime: Date?
    private let parser = WeatherQueryParser()
    private let resolver = WeatherIntentResolver()
    public var contextLifetime: TimeInterval = 10 * 60

    public init() {}

    public mutating func interpret(_ text: String, now: Date) -> ResolvedQuery {
        if let t = contextTime, now.timeIntervalSince(t) > contextLifetime { context = nil }
        let query = resolver.resolve(parser.parse(text), context: context)
        context = query
        contextTime = now
        return query
    }

    public mutating func reset() {
        context = nil
        contextTime = nil
    }
}
