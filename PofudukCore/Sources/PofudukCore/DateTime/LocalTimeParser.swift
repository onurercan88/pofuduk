import Foundation

/// Parses provider local-time strings in the location's time zone (DST-correct, locale-independent).
public enum LocalTimeParser {
    /// "2026-11-14T09:00" or "2026-11-14 09:00" (anything after minutes is ignored).
    public static func dateTime(_ string: String, timeZone: TimeZone) -> Date? {
        let parts = string.split(whereSeparator: { "-T :".contains($0) }).prefix(5).compactMap { Int($0) }
        guard parts.count == 5 else { return nil }
        return make(parts[0], parts[1], parts[2], parts[3], parts[4], timeZone)
    }

    /// "2026-11-14" → local midnight.
    public static func day(_ string: String, timeZone: TimeZone) -> Date? {
        let parts = string.split(separator: "-").prefix(3).compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return make(parts[0], parts[1], parts[2], 0, 0, timeZone)
    }

    /// "07:02 AM" on the given local day.
    public static func clock12h(_ string: String, on day: Date, timeZone: TimeZone) -> Date? {
        let tokens = string.uppercased().split(separator: " ")
        guard tokens.count == 2 else { return nil }
        let hm = tokens[0].split(separator: ":").compactMap { Int($0) }
        guard hm.count == 2, (1...12).contains(hm[0]) else { return nil }
        var hour = hm[0] % 12
        if tokens[1] == "PM" { hour += 12 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        return make(c.year ?? 0, c.month ?? 0, c.day ?? 0, hour, hm[1], timeZone)
    }

    private static func make(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ tz: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        return calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))
    }
}
