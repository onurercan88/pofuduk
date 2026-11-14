import Foundation

public enum NotificationCategory: String, Codable, Sendable, CaseIterable {
    case rainSoon, heavyRain, strongWind, severeWeather, mgmWarning, morningBriefing, temperatureChange, destinationUpdate

    public var turkishName: String {
        switch self {
        case .rainSoon: return "Yağmur başlamadan haber ver"
        case .heavyRain: return "Kuvvetli yağış"
        case .strongWind: return "Kuvvetli rüzgâr"
        case .severeWeather: return "Gök gürültülü sağanak"
        case .mgmWarning: return "Resmi MGM uyarıları"
        case .morningBriefing: return "Pofuduk Günaydın"
        case .temperatureChange: return "Belirgin sıcaklık değişimi"
        case .destinationUpdate: return "Seyahat hava güncellemeleri"
        }
    }

    /// Ordering priority (lower first). Verified official warnings always come first.
    var priority: Int {
        switch self {
        case .mgmWarning: return 0
        case .severeWeather: return 1
        case .heavyRain: return 2
        case .strongWind: return 3
        case .rainSoon: return 4
        case .temperatureChange: return 5
        case .morningBriefing: return 6
        case .destinationUpdate: return 7
        }
    }
}

/// Local time-of-day window, may wrap midnight (e.g. 22:00–07:00).
public struct QuietHours: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var startMinute: Int
    public var endMinute: Int

    public init(enabled: Bool = true, startMinute: Int = 22 * 60, endMinute: Int = 7 * 60) {
        self.enabled = enabled
        self.startMinute = startMinute
        self.endMinute = endMinute
    }

    public func contains(_ date: Date, timeZone: TimeZone) -> Bool {
        guard enabled, startMinute != endMinute else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        return startMinute < endMinute ? (m >= startMinute && m < endMinute) : (m >= startMinute || m < endMinute)
    }
}

public struct NotificationPreferences: Codable, Equatable, Sendable {
    /// Master switch. Off by default: the user opts in.
    public var isEnabled: Bool = false
    public var enabledCategories: Set<NotificationCategory> = [.rainSoon, .heavyRain, .strongWind, .severeWeather, .mgmWarning]
    /// Minutes before expected rain.
    public var rainLeadMinutes: Int = 30
    /// Minimum precipitation probability (%) for "rain soon".
    public var rainProbabilityThreshold: Int = 60
    public var quietHours = QuietHours()

    public init() {}

    public func allows(_ category: NotificationCategory) -> Bool { isEnabled && enabledCategories.contains(category) }
}

public struct PlannedNotification: Equatable, Sendable, Identifiable {
    /// Stable dedup key (category + place + event hour).
    public var id: String
    public var category: NotificationCategory
    public var fireDate: Date
    public var title: String
    public var body: String
    /// Official warnings may break through quiet hours / focus (time-sensitive).
    public var isTimeSensitive: Bool
}

/// Remembers which notifications were scheduled and when they fire, so a delivered one is never re-sent.
public protocol NotificationDeliveryLog: Sendable {
    func fireDate(for key: String) -> Date?
    func record(_ key: String, fireDate: Date)
    func prune(before date: Date)
}

public final class UserDefaultsNotificationLog: NotificationDeliveryLog, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "pofuduk.notificationLog"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private var entries: [String: Double] {
        get { defaults.dictionary(forKey: key) as? [String: Double] ?? [:] }
        set { defaults.set(newValue, forKey: key) }
    }
    public func fireDate(for key: String) -> Date? { entries[key].map(Date.init(timeIntervalSince1970:)) }
    public func record(_ key: String, fireDate: Date) { entries[key] = fireDate.timeIntervalSince1970 }
    public func prune(before date: Date) { entries = entries.filter { $0.value >= date.timeIntervalSince1970 } }
}

public final class InMemoryNotificationLog: NotificationDeliveryLog, @unchecked Sendable {
    private var entries: [String: Date] = [:]
    public init() {}
    public func fireDate(for key: String) -> Date? { entries[key] }
    public func record(_ key: String, fireDate: Date) { entries[key] = fireDate }
    public func prune(before date: Date) { entries = entries.filter { $0.value >= date } }
}

/// Persists notification preferences on device.
public final class NotificationPreferenceStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "pofuduk.notificationPreferences"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> NotificationPreferences {
        guard let data = defaults.data(forKey: key),
              let p = try? JSONDecoder().decode(NotificationPreferences.self, from: data) else { return NotificationPreferences() }
        return p
    }
    public func save(_ p: NotificationPreferences) {
        if let data = try? JSONEncoder().encode(p) { defaults.set(data, forKey: key) }
    }
}
