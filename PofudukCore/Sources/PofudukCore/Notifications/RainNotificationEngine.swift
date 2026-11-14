import Foundation

/// Plans local notifications from the latest forecast ("Yağmur Başlamadan Haber Ver").
/// Best effort by design: iOS decides when background refresh runs, so plans are only made within
/// `horizon` of the forecast's retrieval time and never from stale data.
public struct RainNotificationEngine: Sendable {
    public var thresholds: WeatherThresholds
    /// How far after the forecast retrieval we trust it enough to schedule a notification.
    public var horizon: TimeInterval = 6 * 3600
    /// Day-to-day max temperature change (°C) worth a heads-up.
    public var temperatureChangeThreshold: Double = 8
    /// Local time for the "tomorrow is different" heads-up.
    public var temperatureNoticeHour = 19

    public init(thresholds: WeatherThresholds = .default) {
        self.thresholds = thresholds
    }

    public func plan(snapshot: WeatherSnapshot, warnings: [OfficialWarning] = [], preferences: NotificationPreferences,
                     log: NotificationDeliveryLog, now: Date) -> [PlannedNotification] {
        guard preferences.isEnabled else { return [] }
        let tz = snapshot.place.timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        let placeKey = String(format: "%.2f_%.2f", snapshot.place.coordinate.latitude, snapshot.place.coordinate.longitude)
        var planned: [PlannedNotification] = []

        // Official warnings are independent of forecast freshness.
        for w in warnings where w.isActive(at: now) && w.level >= .yellow {
            planned.append(PlannedNotification(
                id: "mgmWarning-\(w.id)", category: .mgmWarning, fireDate: now.addingTimeInterval(5),
                title: "MGM \(w.level.turkishName) uyarı", body: "\(w.hazard). \(w.description) Kaynak: MGM (resmi uyarı).",
                isTimeSensitive: w.level >= .orange))
        }

        // Never notify from stale forecasts.
        if !snapshot.isStale(at: now) {
            let hourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
            let windowEnd = snapshot.retrievedAt.addingTimeInterval(horizon)
            let hours = snapshot.hourly.filter { $0.time >= hourStart && $0.time < windowEnd }
            let source = "Kaynak: \(snapshot.source.attribution) tahmini, saat \(TurkishFormatting.clockTime(snapshot.retrievedAt, timeZone: tz)) itibarıyla."
            let place = TurkishGrammar.locative(snapshot.place.name)
            let lead = TimeInterval(preferences.rainLeadMinutes * 60)

            func key(_ c: NotificationCategory, _ event: Date) -> String {
                let x = calendar.dateComponents([.year, .month, .day, .hour], from: event)
                return "\(c.rawValue)-\(placeKey)-\(x.year!)\(x.month!)\(x.day!)\(x.hour!)"
            }
            /// Fire `lead` before the event; if that moment passed but the event hasn't started, fire now.
            func fireDate(for event: Date) -> Date? {
                guard event > now else { return nil }
                return max(event.addingTimeInterval(-lead), now.addingTimeInterval(60))
            }
            func when(_ event: Date) -> String {
                let minutes = Int((event.timeIntervalSince(now) / 60).rounded())
                if minutes <= 90 { return "Yaklaşık \(max(5, (minutes + 4) / 5 * 5)) dakika içinde" }
                return "Saat \(TurkishFormatting.clockTime(event, timeZone: tz)) civarında"
            }

            // Precipitation, using the user's probability threshold.
            var t = thresholds
            t.likelyPrecipitationProbability = preferences.rainProbabilityThreshold
            if let p = WeatherSummaryEngine(thresholds: t).precipitationOutlook(in: hours), p.isLikely, let fire = fireDate(for: p.start) {
                let prob = p.maxProbability.map { " (olasılık %\($0))" } ?? ""
                let w = when(p.start)
                switch (p.kind, p.intensity) {
                case (.thunderstorm, _):
                    planned.append(PlannedNotification(id: key(.severeWeather, p.start), category: .severeWeather, fireDate: fire,
                        title: "Gök gürültülü sağanak", body: "\(w) \(place) gök gürültülü sağanak bekleniyor\(prob). Açık alanlarda dikkatli ol. \(source)",
                        isTimeSensitive: false))
                case (_, .heavy):
                    planned.append(PlannedNotification(id: key(.heavyRain, p.start), category: .heavyRain, fireDate: fire,
                        title: "Kuvvetli yağış bekleniyor", body: "\(w) \(place) kuvvetli yağış bekleniyor\(prob). Dışarı çıkarken dikkatli ol. \(source)",
                        isTimeSensitive: false))
                default:
                    let noun = p.kind == .snow ? "kar" : "yağmur"
                    planned.append(PlannedNotification(id: key(.rainSoon, p.start), category: .rainSoon, fireDate: fire,
                        title: p.kind == .snow ? "Kar geliyor ❄️" : "Şemsiyeni unutma! ☂️",
                        body: "\(w) \(place) \(noun) bekleniyor\(prob). \(source)", isTimeSensitive: false))
                }
            }

            // Strong wind.
            if let h = hours.first(where: { ($0.windSpeedKmh ?? 0) >= thresholds.strongWindKmh || ($0.windGustKmh ?? 0) >= thresholds.strongGustKmh }),
               let fire = fireDate(for: h.time) {
                let speed = Int(max(h.windSpeedKmh ?? 0, h.windGustKmh ?? 0).rounded())
                planned.append(PlannedNotification(id: key(.strongWind, h.time), category: .strongWind, fireDate: fire,
                    title: "Kuvvetli rüzgâr", body: "\(when(h.time)) \(place) rüzgâr saatte \(speed) kilometreye kadar çıkabilir. Dışarı çıkarken dikkatli ol. \(source)",
                    isTimeSensitive: false))
            }

            // Tomorrow notably warmer/colder (daily data; announced this evening).
            let today = calendar.startOfDay(for: now)
            if let tomorrowDate = calendar.date(byAdding: .day, value: 1, to: today),
               let d0 = snapshot.daily.first(where: { calendar.isDate($0.date, inSameDayAs: today) }),
               let d1 = snapshot.daily.first(where: { calendar.isDate($0.date, inSameDayAs: tomorrowDate) }),
               abs(d1.maxTemperature - d0.maxTemperature) >= temperatureChangeThreshold,
               let fire = calendar.date(bySettingHour: temperatureNoticeHour, minute: 0, second: 0, of: now), fire > now {
                let diff = Int(abs(d1.maxTemperature - d0.maxTemperature).rounded())
                let direction = d1.maxTemperature < d0.maxTemperature ? "daha serin" : "daha sıcak"
                planned.append(PlannedNotification(id: key(.temperatureChange, tomorrowDate), category: .temperatureChange, fireDate: fire,
                    title: "Yarın hava değişiyor", body: "Yarın en yüksek sıcaklık \(TurkishFormatting.temperature(d1.maxTemperature)); bugünden yaklaşık \(diff) derece \(direction). \(source)",
                    isTimeSensitive: false))
            }
        }

        var seen = Set<String>()
        return planned
            .filter { preferences.allows($0.category) }
            // Quiet hours: only time-sensitive official warnings may break through.
            .filter { $0.isTimeSensitive || !preferences.quietHours.contains($0.fireDate, timeZone: tz) }
            // Dedup: never re-send something already delivered.
            .filter { n in
                if let fired = log.fireDate(for: n.id), fired <= now { return false }
                return seen.insert(n.id).inserted
            }
            .sorted { ($0.category.priority, $0.fireDate) < ($1.category.priority, $1.fireDate) }
    }
}
