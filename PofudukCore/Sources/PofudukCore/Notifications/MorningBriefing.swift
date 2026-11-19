import Foundation

/// "Pofuduk Günaydın" settings, stored on device.
public struct MorningBriefingSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool = true
    /// Local minute of day (default 07:30).
    public var minuteOfDay: Int = 7 * 60 + 30
    /// Speak automatically when the app is opened in the morning (otherwise text only).
    public var speaksAutomatically: Bool = true
    /// Also send a text notification at the chosen time (needs notification permission).
    public var sendsNotification: Bool = false
    /// "yyyy-MM-dd" of the last morning greeting shown, so it happens once per day.
    public var lastGreetedDay: String?

    public init() {}

    public static let presets = [7 * 60, 7 * 60 + 30, 8 * 60, 8 * 60 + 30]
}

public final class MorningBriefingStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "pofuduk.morningBriefing"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> MorningBriefingSettings {
        guard let data = defaults.data(forKey: key),
              let s = try? JSONDecoder().decode(MorningBriefingSettings.self, from: data) else { return MorningBriefingSettings() }
        return s
    }
    public func save(_ s: MorningBriefingSettings) {
        if let data = try? JSONEncoder().encode(s) { defaults.set(data, forKey: key) }
    }
}

/// Builds the morning greeting/briefing and its optional notification. All facts come from the snapshot.
public struct MorningBriefingEngine: Sendable {
    public var thresholds: WeatherThresholds
    /// Morning greeting window ends at this local hour.
    public var morningEndsHour = 12
    /// A briefing notification is only scheduled if the forecast is at most this old at delivery time.
    public var maxForecastAgeAtDelivery: TimeInterval = 18 * 3600

    public init(thresholds: WeatherThresholds = .default) {
        self.thresholds = thresholds
    }

    // MARK: - When to greet

    public static func dayKey(_ date: Date, timeZone: TimeZone) -> String {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        let x = c.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", x.year ?? 0, x.month ?? 0, x.day ?? 0)
    }

    /// True between the chosen time and noon, once per day.
    public func shouldGreet(now: Date, settings: MorningBriefingSettings, timeZone: TimeZone) -> Bool {
        guard settings.isEnabled, settings.lastGreetedDay != Self.dayKey(now, timeZone: timeZone) else { return false }
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        let x = c.dateComponents([.hour, .minute], from: now)
        let minute = (x.hour ?? 0) * 60 + (x.minute ?? 0)
        return minute >= settings.minuteOfDay && minute < morningEndsHour * 60
    }

    // MARK: - Spoken briefing

    public func briefing(snapshot: WeatherSnapshot, analysis: WeatherAnalysis, warnings: [OfficialWarning] = [],
                         clothing: ClothingRecommendation?, now: Date) -> Briefing {
        let tz = snapshot.place.timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        let active = warnings.filter { $0.isActive(at: now) && $0.level > .green }.sorted { $0.level > $1.level }
        let serious = (active.first?.level ?? .green) >= .orange || analysis.outlookTheme == .stormy
        let p = analysis.precipitation
        var s: [String] = []

        s.append(serious ? "Günaydın." : "Günaydın!")
        if !serious, p == nil, analysis.outlookTheme == .sunny || analysis.outlookTheme == .cloudy, analysis.wind?.isStrong != true {
            s.append("Bugün senin için güzel bir gün olabilir.")
        }
        if snapshot.source == .demo { s.append("Şu an örnek verilerle konuşuyorum, bu gerçek bir tahmin değil.") }
        if analysis.isStale {
            s.append("Bu bilgiler saat \(TurkishFormatting.clockTime(analysis.retrievedAt, timeZone: tz)) itibarıyla alındı, güncel olmayabilir.")
        }
        for w in active.prefix(2) {
            s.append("Dikkat! Bulunduğun bölge için MGM tarafından \(w.level.turkishName) seviyede meteorolojik uyarı yayımlanmış.")
            s.append("\(w.hazard) bekleniyor. Lütfen resmi uyarının detaylarını incelemeyi unutma.")
        }

        // Temperature arc: morning start → afternoon peak.
        let today = snapshot.hourly.filter { calendar.isDate($0.time, inSameDayAs: now) }
        func hour(_ h: HourlyForecast) -> Int { calendar.component(.hour, from: h.time) }
        let nowHour = calendar.component(.hour, from: now)
        let morning = today.filter { hour($0) >= max(nowHour, 7) && hour($0) <= 9 }.map(\.temperature)
        let afternoon = today.filter { (12...17).contains(hour($0)) }.map(\.temperature)
        let place = TurkishGrammar.locative(snapshot.place.name)
        if nowHour < 10, let start = morning.first {
            s.append("\(place) sabah \(TurkishFormatting.temperature(start))yle başlıyoruz.")
        } else {
            s.append("\(place) şu an \(TurkishFormatting.temperature(analysis.current.temperature)).")
        }
        if let peak = afternoon.max(), let start = morning.first ?? Optional(analysis.current.temperature) {
            if peak - start >= 2 {
                s.append("Öğleden sonra sıcaklık \(TurkishFormatting.temperature(peak))ye çıkıyor.")
            } else {
                s.append("Gün boyunca sıcaklık \(TurkishFormatting.temperature(peak)) civarında.")
            }
        }

        // Rain.
        if let p {
            let part = Self.dayPartPhrase(calendar.component(.hour, from: p.start))
            let noun = p.kind == .snow ? "kar" : (p.kind == .thunderstorm ? "gök gürültülü sağanak" : "yağmur")
            if p.isLikely {
                s.append("Ancak \(part) \(noun) bekleniyor.")
                if p.intensity == .heavy { s.append("Yağışın yer yer kuvvetli olması bekleniyor.") }
            } else {
                s.append("\(part.prefix(1).uppercased(with: Locale(identifier: "tr_TR")) + part.dropFirst()) \(noun) ihtimali var, ama kesin değil.")
            }
        } else if analysis.hasHourlyCoverage {
            s.append("Gün boyu yağış beklenmiyor.")
        }

        if let wind = analysis.wind, wind.isStrong {
            s.append(CharacterPersonalityEngine().windSentence(wind))
        }
        if analysis.isHighUV, let uv = analysis.uvMax {
            s.append("Öğle saatlerinde UV indeksi \(Int(uv.rounded())) seviyesine çıkıyor, güneş kremini unutma.")
        }
        if let clothing, clothing.isNoteworthy { s.append(clothing.briefingSentence) }

        if serious {
            s.append("Lütfen dikkatli ol ve gereksiz yere dışarı çıkma.")
        } else if p?.isLikely == true {
            s.append(p?.kind == .snow ? "Dışarı çıkacaksan sıkı giyin!" : "Dışarı çıkacaksan şemsiyeni hazırla!")
        } else {
            s.append("Güzel bir gün geçirmeni dilerim!")
        }

        let mood: CharacterMood = serious ? .warning : .happy
        return Briefing(sentences: s, restingMood: mood, theme: analysis.theme)
    }

    static func dayPartPhrase(_ hour: Int) -> String {
        switch hour {
        case 5..<11: return "sabah saatlerinde"
        case 11..<14: return "öğle saatlerinde"
        case 14..<18: return "öğleden sonra"
        case 18..<22: return "akşam"
        default: return "gece"
        }
    }

    // MARK: - Notification

    /// Next morning-briefing notification (today if the time hasn't passed, else tomorrow), from daily data.
    public func notification(snapshot: WeatherSnapshot, settings: MorningBriefingSettings, now: Date) -> PlannedNotification? {
        guard settings.isEnabled, settings.sendsNotification else { return nil }
        let tz = snapshot.place.timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        let todayStart = calendar.startOfDay(for: now)
        guard var fire = calendar.date(byAdding: .minute, value: settings.minuteOfDay, to: todayStart) else { return nil }
        if fire <= now { fire = calendar.date(byAdding: .day, value: 1, to: fire) ?? fire }
        // Too old by delivery time → don't promise anything.
        guard fire.timeIntervalSince(snapshot.retrievedAt) <= maxForecastAgeAtDelivery,
              let day = snapshot.daily.first(where: { calendar.isDate($0.date, inSameDayAs: fire) }) else { return nil }

        var body = "Bugün \(TurkishFormatting.temperature(day.minTemperature).replacingOccurrences(of: " derece", with: "")) ile \(TurkishFormatting.temperature(day.maxTemperature)) arası, \(TurkishFormatting.conditionName(day.condition))."
        if let prob = day.precipitationProbability, prob >= thresholds.possiblePrecipitationProbability {
            body += " Yağış ihtimali %\(prob)."
        }
        body += " Ayrıntılar için Pofuduk'u aç. Kaynak: \(snapshot.source.attribution) tahmini, \(TurkishFormatting.clockTime(snapshot.retrievedAt, timeZone: tz)) itibarıyla."
        return PlannedNotification(id: "morningBriefing-\(Self.dayKey(fire, timeZone: tz))", category: .morningBriefing,
                                   fireDate: fire, title: "Günaydın! ☀️", body: body, isTimeSensitive: false)
    }
}
