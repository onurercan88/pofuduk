import Foundation

/// Resolves date references to local days in the place's time zone (DST- and midnight-safe).
public struct ForecastDateResolver: Sendable {
    public init() {}

    /// Start-of-day dates for the reference, in `timeZone`.
    public func days(for reference: DateReference, now: Date, timeZone: TimeZone) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: now)
        func plus(_ n: Int) -> Date { calendar.date(byAdding: .day, value: n, to: today) ?? today }

        switch reference {
        case .today: return [today]
        case .tomorrow: return [plus(1)]
        case .inDays(let n): return [plus(max(0, n))]
        case .weekday(let target):
            let current = calendar.component(.weekday, from: today)
            return [plus((target - current + 7) % 7)]
        case .weekend:
            switch calendar.component(.weekday, from: today) {
            case 7: return [today, plus(1)]        // Saturday
            case 1: return [today]                 // Sunday
            case let w: return [plus(7 - w), plus(8 - w)]
            }
        }
    }

    /// The subset of `days` the snapshot actually covers (daily entry or at least one hourly entry).
    public func covered(_ days: [Date], in snapshot: WeatherSnapshot) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = snapshot.place.timeZone
        return days.filter { day in
            snapshot.daily.contains { calendar.isDate($0.date, inSameDayAs: day) }
                || snapshot.hourly.contains { calendar.isDate($0.time, inSameDayAs: day) }
        }
    }
}
