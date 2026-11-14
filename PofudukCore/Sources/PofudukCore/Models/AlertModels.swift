import Foundation

/// MGM warning levels. Each level has a text label so severity is never shown by colour alone.
public enum WarningLevel: Int, Codable, Sendable, Comparable, CaseIterable {
    case green = 0, yellow, orange, red

    public static func < (lhs: WarningLevel, rhs: WarningLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    public var turkishName: String {
        switch self {
        case .green: return "yeşil"
        case .yellow: return "sarı"
        case .orange: return "turuncu"
        case .red: return "kırmızı"
        }
    }
}

/// An official warning. Only an authorized official source may create one; it is never derived from a forecast.
public struct OfficialWarning: Equatable, Codable, Sendable, Identifiable {
    public var id: String
    public var level: WarningLevel
    public var hazard: String
    public var description: String
    public var provinces: [String]
    public var districts: [String]
    public var validFrom: Date
    public var validUntil: Date
    public var sourceURL: URL

    public init(id: String, level: WarningLevel, hazard: String, description: String,
                provinces: [String], districts: [String] = [], validFrom: Date, validUntil: Date, sourceURL: URL) {
        self.id = id
        self.level = level
        self.hazard = hazard
        self.description = description
        self.provinces = provinces
        self.districts = districts
        self.validFrom = validFrom
        self.validUntil = validUntil
        self.sourceURL = sourceURL
    }

    public func isActive(at date: Date) -> Bool { date >= validFrom && date < validUntil }
}

/// Result of an MGM warning lookup. `.unavailable` means automated data could not be obtained,
/// which is different from "there are no warnings".
public enum WarningAvailability: Equatable, Sendable {
    case available([OfficialWarning])
    case unavailable(reason: String, officialPage: URL)
}
