import Foundation

/// Answers a resolved question from a snapshot. Every number comes from the snapshot; if the requested
/// day or hours are not covered, it says so instead of guessing.
public struct WeatherAnswerEngine: Sendable {
    public var thresholds: WeatherThresholds
    private let summary: WeatherSummaryEngine
    private let dates = ForecastDateResolver()

    public init(thresholds: WeatherThresholds = .default) {
        self.thresholds = thresholds
        self.summary = WeatherSummaryEngine(thresholds: thresholds)
    }

    public func answer(_ query: ResolvedQuery, snapshot: WeatherSnapshot, now: Date) -> Briefing {
        let tz = snapshot.place.timeZone
        let requested = dates.days(for: query.date, now: now, timeZone: tz)
        let covered = dates.covered(requested, in: snapshot)
        let theme = WeatherSummaryEngine().analyze(snapshot, now: now).theme

        guard !covered.isEmpty else {
            let maxDays = (snapshot.daily.count > 0 ? snapshot.daily.count : 1)
            return Briefing(sentences: [
                "Bu tarih için henüz bir tahminim yok.",
                "Şu an en fazla \(maxDays) günlük tahmin verebiliyorum."
            ], restingMood: .sad, theme: theme)
        }

        var sentences: [String] = []
        for day in covered {
            let ctx = DayContext(day: day, snapshot: snapshot, now: now, dayPart: query.dayPart, multiDay: covered.count > 1)
            sentences.append(contentsOf: answer(query.topic, ctx))
        }
        if covered.count < requested.count {
            sentences.append("Sonraki günler için tahmin henüz yayımlanmadı.")
        }
        if snapshot.isStale(at: now) {
            sentences.append("Bu bilgiler güncel olmayabilir.")
        }
        return Briefing(sentences: sentences, restingMood: mood(for: query.topic, theme: theme), theme: theme)
    }

    public func didNotUnderstand() -> Briefing {
        Briefing(sentences: ["Bunu tam anlayamadım.", "Örneğin \"Yarın hava nasıl?\" ya da \"Akşam yağmur var mı?\" diye sorabilirsin."],
                 restingMood: .thinking, theme: .cloudy)
    }

    // MARK: - Context

    struct DayContext {
        let day: Date
        let snapshot: WeatherSnapshot
        let now: Date
        let dayPart: DayPart?
        let multiDay: Bool
        var calendar: Calendar {
            var c = Calendar(identifier: .gregorian)
            c.timeZone = snapshot.place.timeZone
            return c
        }
        var isToday: Bool { calendar.isDate(day, inSameDayAs: now) }
        var daily: DailyForecast? { snapshot.daily.first { calendar.isDate($0.date, inSameDayAs: day) } }

        /// Hourly entries for this day/day part; for today only from the current hour on.
        var hours: [HourlyForecast] {
            let hourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
            return snapshot.hourly.filter { h in
                guard calendar.isDate(h.time, inSameDayAs: day) else { return false }
                if isToday && h.time < hourStart { return false }
                if let part = dayPart { return part.hours.contains(calendar.component(.hour, from: h.time)) }
                return true
            }
        }

        /// The asked hours start with the current hour and it is precipitating right now.
        var precipitatingNow: Bool {
            guard isToday, snapshot.current.condition.isPrecipitation, let first = hours.first else { return false }
            return calendar.isDate(first.time, equalTo: now, toGranularity: .hour)
        }

        /// "Yarın akşam", "Bugün saat 17.00 civarında", "Cumartesi"
        var label: String {
            let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: day).day ?? 0
            var base: String
            switch offset {
            case 0: base = "Bugün"
            case 1: base = "Yarın"
            default: base = TurkishFormatting.weekdayNames[calendar.component(.weekday, from: day) - 1]
            }
            if multiDay, offset > 1 { base = TurkishFormatting.weekdayNames[calendar.component(.weekday, from: day) - 1] }
            if offset == 0 {
                // Natural Turkish: "Bu sabah / Bu akşam / Bu gece" rather than "Bugün sabah".
                switch dayPart {
                case .morning?: return "Bu sabah"
                case .evening?: return "Bu akşam"
                case .night?: return "Bu gece"
                default: break
                }
            }
            switch dayPart {
            case .morning?: return base + " sabah"
            case .noon?: return base + " öğle saatlerinde"
            case .afternoon?: return base + " öğleden sonra"
            case .evening?: return base + " akşam"
            case .night?: return base + " gece"
            case .hour(let h)?: return base + " saat " + String(format: "%02d.00", h) + " civarında"
            case nil: return base
            }
        }
        var place: String { TurkishGrammar.locative(snapshot.place.name) }
    }

    // MARK: - Topics

    private func answer(_ topic: WeatherTopic, _ c: DayContext) -> [String] {
        switch topic {
        case .overview, .travel: return overview(c)
        case .temperature: return [temperature(c) ?? noData(c)]
        case .rain, .rainTiming: return rain(c, timing: topic == .rainTiming)
        case .umbrella: return umbrella(c)
        case .wind: return [wind(c) ?? noData(c)]
        case .uv: return [uv(c) ?? noData(c)]
        case .clothing: return clothing(c)
        case .goingOut: return goingOut(c)
        }
    }

    private func noData(_ c: DayContext) -> String {
        "\(c.label) için bu bilgiye ait tahmin verisi yok."
    }

    private func overview(_ c: DayContext) -> [String] {
        var out: [String] = []
        if let t = temperature(c) { out.append(t) }
        out.append(contentsOf: rain(c, timing: false, repeatLabel: out.isEmpty))
        if let w = wind(c), (maxWind(c) ?? 0) >= thresholds.strongWindKmh { out.append(w) }
        return out.isEmpty ? [noData(c)] : out
    }

    private func temperature(_ c: DayContext) -> String? {
        let hours = c.hours
        if case .hour? = c.dayPart, let h = hours.first {
            return "\(c.label) \(c.place) sıcaklık \(TurkishFormatting.temperature(h.temperature)), hava \(TurkishFormatting.conditionName(h.condition)) olacak."
        }
        if c.dayPart != nil, let lo = hours.map(\.temperature).min(), let hi = hours.map(\.temperature).max() {
            return range(prefix: "\(c.label) \(c.place) sıcaklık", lo, hi)
        }
        if c.isToday, c.dayPart == nil, !c.multiDay {
            let now = "\(c.place) şu an \(TurkishFormatting.temperature(c.snapshot.current.temperature))"
            if let d = c.daily {
                return now + "; gün içinde en düşük \(TurkishFormatting.temperature(d.minTemperature)), en yüksek \(TurkishFormatting.temperature(d.maxTemperature))."
            }
            return now + "."
        }
        if let d = c.daily {
            return "\(c.label) \(c.place) hava \(TurkishFormatting.conditionName(d.condition)); " +
                "sıcaklık \(TurkishFormatting.temperature(d.minTemperature).replacingOccurrences(of: " derece", with: "")) ile \(TurkishFormatting.temperature(d.maxTemperature)) arasında olacak."
        }
        if let lo = hours.map(\.temperature).min(), let hi = hours.map(\.temperature).max() {
            return range(prefix: "\(c.label) \(c.place) sıcaklık", lo, hi)
        }
        return nil
    }

    private func range(prefix: String, _ lo: Double, _ hi: Double) -> String {
        if Int(lo.rounded()) == Int(hi.rounded()) { return "\(prefix) \(TurkishFormatting.temperature(hi)) civarında olacak." }
        return "\(prefix) \(TurkishFormatting.temperature(lo).replacingOccurrences(of: " derece", with: "")) ile \(TurkishFormatting.temperature(hi)) arasında olacak."
    }

    /// `repeatLabel: false` is used after a sentence that already named the day (avoids "Yarın … Yarın …").
    private func rain(_ c: DayContext, timing: Bool, repeatLabel: Bool = true) -> [String] {
        let hours = c.hours
        let tz = c.snapshot.place.timeZone
        if !hours.isEmpty {
            guard let p = summary.precipitationOutlook(in: hours) else {
                if c.precipitatingNow {
                    return ["Şu an yağış var ama sonraki saatlerde başka yağış beklenmiyor."]
                }
                return [repeatLabel ? "\(c.label) yağış beklenmiyor." : "Yağış beklenmiyor."]
            }
            let noun = p.kind == .snow ? "kar" : (p.kind == .thunderstorm ? "gök gürültülü sağanak" : "yağmur")
            let start = TurkishFormatting.clockTime(p.start, timeZone: tz)
            // Precipitating now while the forecast's period starts later: don't announce a "start".
            if c.precipitatingNow, let first = hours.first,
               let relation = summary.laterPrecipitationRelation(current: c.snapshot.current, outlook: p,
                                                                 hours: hours, hourStart: first.time),
               let nowNoun = CharacterPersonalityEngine.precipitationNoun(c.snapshot.current.condition) {
                guard p.isLikely else {
                    let prob = p.maxProbability.map { " yüzde \($0) civarında" } ?? ""
                    return ["Şu an \(nowNoun) var. Saat \(start) sonrasında da \(noun) ihtimali\(prob)."]
                }
                switch relation {
                case .continues:
                    return ["Şu an \(nowNoun) var ve sonraki saatlerde de sürmesi bekleniyor."]
                case .intensifies:
                    let change = p.kind == .thunderstorm && c.snapshot.current.condition != .thunderstorm
                        ? "gök gürültülü sağanağa dönmesi" : "kuvvetlenmesi"
                    return ["Şu an \(nowNoun) var; saat \(start) civarında \(change) bekleniyor."]
                case .resumes:
                    return ["Şu an \(nowNoun) var; ara verip saat \(start) civarında yeniden başlaması bekleniyor."]
                }
            }
            if !p.isLikely {
                let prob = p.maxProbability.map { "yüzde \($0) civarında" } ?? "düşük"
                return ["\(c.label) yağış ihtimali \(prob); kesin değil. En olası zaman saat \(start) civarı."]
            }
            var isHour = false
            if case .hour? = c.dayPart { isHour = true }
            let showStart = (timing || c.dayPart == nil) && !isHour
            var s: String
            switch (repeatLabel, showStart) {
            case (true, true): s = "\(c.label) saat \(start) civarında \(noun) bekleniyor."
            case (true, false): s = "\(c.label) \(noun) bekleniyor."
            case (false, true): s = "Saat \(start) civarında \(noun) bekleniyor."
            case (false, false): s = "O saatlerde \(noun) bekleniyor."
            }
            if p.durationHours >= 2 && !p.lastsUntilEndOfDay { s.removeLast(); s += ", yaklaşık \(p.durationHours) saat sürebilir." }
            var out = [s]
            switch p.intensity {
            case .heavy: out.append("Yer yer kuvvetli olabilir.")
            case .moderate: out.append("Orta şiddette bir yağış görünüyor.")
            case .light: out.append("Hafif bir yağış görünüyor.")
            case .unknown: break
            }
            return out
        }
        if let d = c.daily, let prob = d.precipitationProbability {
            if prob < thresholds.possiblePrecipitationProbability { return ["\(c.label) yağış beklenmiyor."] }
            return ["\(c.label) yağış ihtimali yüzde \(prob). Saatlik ayrıntı henüz yok."]
        }
        return [noData(c)]
    }

    private func umbrella(_ c: DayContext) -> [String] {
        let rainInfo = rain(c, timing: true)
        guard let p = c.hours.isEmpty ? nil : summary.precipitationOutlook(in: c.hours) else {
            if let prob = c.daily?.precipitationProbability, prob >= thresholds.possiblePrecipitationProbability {
                return ["Yanına bir şemsiye almanda fayda var."] + rainInfo
            }
            return c.hours.isEmpty && c.daily == nil ? [noData(c)] : ["Şemsiyeye gerek yok gibi görünüyor."] + rainInfo
        }
        return [p.isLikely ? "Evet, şemsiye almanı öneririm." : "Kesin değil ama yanına bir şemsiye alabilirsin."] + rainInfo
    }

    private func maxWind(_ c: DayContext) -> Double? {
        (c.hours.compactMap(\.windSpeedKmh) + [c.daily?.maxWindKmh].compactMap { $0 }).max()
    }

    private func wind(_ c: DayContext) -> String? {
        guard let speed = maxWind(c) else { return nil }
        let gust = c.hours.compactMap(\.windGustKmh).max()
        var s = "\(c.label) rüzgâr saatte \(Int(speed.rounded())) kilometreye kadar çıkabilir"
        if let gust, gust > speed + 5 { s += ", ani esintiler \(Int(gust.rounded())) kilometreyi bulabilir" }
        let strong = speed >= thresholds.strongWindKmh || (gust ?? 0) >= thresholds.strongGustKmh
        return s + (strong ? ". Açık alanlarda dikkatli ol." : ".")
    }

    private func uv(_ c: DayContext) -> String? {
        guard let uv = (c.hours.compactMap(\.uvIndex) + [c.daily?.uvIndexMax].compactMap { $0 }).max() else { return nil }
        let level = Int(uv.rounded())
        if uv >= thresholds.highUVIndex { return "\(c.label) UV indeksi \(level) seviyesine çıkıyor; güneş kremi kullanmanı öneririm." }
        if uv >= 3 { return "\(c.label) UV indeksi \(level), orta seviyede. Uzun süre güneşte kalacaksan güneş kremi iyi olur." }
        return "\(c.label) UV indeksi \(level), düşük seviyede."
    }

    private func clothing(_ c: DayContext) -> [String] {
        guard let rec = ClothingRecommendationEngine(thresholds: thresholds).recommend(for: c.snapshot, day: c.day, now: c.now) else {
            return [noData(c)]
        }
        return rec.sentences
    }

    private func goingOut(_ c: DayContext) -> [String] {
        var out: [String] = []
        if let t = temperature(c) { out.append(t) }
        out.append(contentsOf: rain(c, timing: false, repeatLabel: out.isEmpty))
        if let w = wind(c), (maxWind(c) ?? 0) >= thresholds.strongWindKmh { out.append(w) }
        return out
    }

    private func mood(for topic: WeatherTopic, theme: WeatherTheme) -> CharacterMood {
        switch theme {
        case .stormy: return .warning
        case .sunny: return .happy
        default: return .idle
        }
    }
}
