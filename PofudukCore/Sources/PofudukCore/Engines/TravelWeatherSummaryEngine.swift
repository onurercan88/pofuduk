import Foundation

public struct TravelDayForecast: Equatable, Sendable, Identifiable {
    public var id: Date { date }
    /// Local midnight in the destination's time zone.
    public var date: Date
    public var minTemperature: Double
    public var maxTemperature: Double
    public var condition: WeatherCondition
    public var precipitationProbability: Int?
    /// Same calendar day at the origin, when available.
    public var originMaxTemperature: Double?
}

public struct TravelSummary: Equatable, Sendable {
    public var destination: Place
    public var origin: Place?
    public var days: [TravelDayForecast]
    /// Requested days the provider doesn't cover yet (y/m/d).
    public var unavailableDays: [DateComponents]
    public var packing: [ClothingItem]
    public var briefing: Briefing
}

/// "Seyahat Hava Durumu": destination forecast for the travel days, compared with the origin.
/// Uses forecast data only; never claims road or route conditions.
public struct TravelWeatherSummaryEngine: Sendable {
    public var thresholds: WeatherThresholds
    /// Days ahead from which forecasts are flagged as less certain.
    public var uncertainFromDayOffset = 3
    public static let maxTravelDays = 7

    public init(thresholds: WeatherThresholds = .default) {
        self.thresholds = thresholds
    }

    /// Calendar days (y/m/d) from departure through return, in `timeZone`, capped at `maxTravelDays`.
    public static func travelDays(departure: Date, returnDate: Date?, timeZone: TimeZone) -> [DateComponents] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: departure)
        let end = calendar.startOfDay(for: max(returnDate ?? departure, departure))
        var days: [DateComponents] = []
        var d = start
        while d <= end && days.count < maxTravelDays {
            days.append(calendar.dateComponents([.year, .month, .day], from: d))
            d = calendar.date(byAdding: .day, value: 1, to: d) ?? end.addingTimeInterval(1)
        }
        return days
    }

    public func summarize(destination: WeatherSnapshot, origin: WeatherSnapshot?, days: [DateComponents], now: Date) -> TravelSummary {
        let dest = destination.place
        let tz = dest.timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        var originCalendar = Calendar(identifier: .gregorian)
        originCalendar.timeZone = origin?.place.timeZone ?? tz

        var rows: [TravelDayForecast] = []
        var missing: [DateComponents] = []
        for c in days {
            guard let date = calendar.date(from: DateComponents(year: c.year, month: c.month, day: c.day)),
                  let daily = destination.daily.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) else {
                missing.append(c); continue
            }
            let originMax = origin?.daily.first { d in
                let x = originCalendar.dateComponents([.year, .month, .day], from: d.date)
                return x.year == c.year && x.month == c.month && x.day == c.day
            }?.maxTemperature
            rows.append(TravelDayForecast(date: date, minTemperature: daily.minTemperature, maxTemperature: daily.maxTemperature,
                                          condition: daily.condition, precipitationProbability: daily.precipitationProbability,
                                          originMaxTemperature: dest == origin?.place ? nil : originMax))
        }

        var s: [String] = []
        var packing: [ClothingItem] = []
        let destLoc = TurkishGrammar.locative(dest.name)

        guard let first = rows.first else {
            let maxDays = max(destination.daily.count, 1)
            s.append("Bu tarihler için \(destLoc) henüz tahmin yok.")
            s.append("Şu an en fazla \(maxDays) gün ileriyi görebiliyorum; yolculuğa yaklaştıkça tekrar sor.")
            return TravelSummary(destination: dest, origin: origin?.place, days: [], unavailableDays: missing, packing: [],
                                 briefing: Briefing(sentences: s, restingMood: .sad, theme: .cloudy))
        }

        // First day: conditions + comparison with origin.
        let label = dayLabel(first.date, now: now, calendar: calendar)
        let range = "\(Int(first.minTemperature.rounded())) ile \(TurkishFormatting.temperature(first.maxTemperature))"
        if let o = origin?.place, let originMax = first.originMaxTemperature {
            let diff = first.maxTemperature - originMax
            let comparison: String
            switch diff {
            case ..<(-5): comparison = "\(TurkishGrammar.ablative(o.name)) belirgin şekilde daha serin"
            case ..<(-1.5): comparison = "\(TurkishGrammar.ablative(o.name)) biraz daha serin"
            case 1.5..<5: comparison = "\(TurkishGrammar.ablative(o.name)) biraz daha sıcak"
            case 5...: comparison = "\(TurkishGrammar.ablative(o.name)) belirgin şekilde daha sıcak"
            default: comparison = "\(o.name) ile benzer"
            }
            s.append("\(label) \(destLoc) hava \(comparison) olacak; sıcaklık \(range) arasında, hava \(TurkishFormatting.conditionName(first.condition)).")
        } else {
            s.append("\(label) \(destLoc) hava \(TurkishFormatting.conditionName(first.condition)); sıcaklık \(range) arasında olacak.")
        }

        // Precipitation on the first day (hourly if available, else daily probability).
        let firstHours = destination.hourly.filter { calendar.isDate($0.time, inSameDayAs: first.date) && $0.time >= calendar.dateInterval(of: .hour, for: now)?.start ?? now }
        if let p = WeatherSummaryEngine(thresholds: thresholds).precipitationOutlook(in: firstHours) {
            let part = MorningBriefingEngine.dayPartPhrase(calendar.component(.hour, from: p.start))
            let partCap = part.prefix(1).uppercased(with: Locale(identifier: "tr_TR")) + part.dropFirst()
            let noun = p.kind == .snow ? "kar" : (p.kind == .thunderstorm ? "gök gürültülü sağanak" : "yağış")
            s.append(p.isLikely ? "\(partCap) \(noun) bekleniyor." : "\(partCap) \(noun) ihtimali var.")
        } else if !firstHours.isEmpty {
            s.append("Yağış beklenmiyor.")
        } else if let prob = first.precipitationProbability, prob >= thresholds.possiblePrecipitationProbability {
            s.append("Yağış ihtimali yüzde \(prob).")
        }
        if let wind = firstHours.compactMap(\.windSpeedKmh).max(), wind >= thresholds.strongWindKmh {
            s.append("Rüzgâr saatte \(Int(wind.rounded())) kilometreye kadar çıkabilir.")
        }

        // Further days, one short sentence each.
        for row in rows.dropFirst() {
            var t = "\(dayLabel(row.date, now: now, calendar: calendar)) \(Int(row.minTemperature.rounded())) ile \(TurkishFormatting.temperature(row.maxTemperature)) arası, \(TurkishFormatting.conditionName(row.condition))"
            if let p = row.precipitationProbability, p >= thresholds.possiblePrecipitationProbability { t += ", yağış ihtimali yüzde \(p)" }
            s.append(t + ".")
        }

        // Packing advice from the clothing engine across all travel days.
        let clothing = ClothingRecommendationEngine(thresholds: thresholds)
        for row in rows {
            if let rec = clothing.recommend(for: destination, day: row.date.addingTimeInterval(12 * 3600), now: now) {
                packing += rec.items
            } else if row.maxTemperature < 15 {
                packing.append(row.minTemperature < 10 ? .coat : .lightJacket)
            }
            if (row.precipitationProbability ?? 0) >= thresholds.likelyPrecipitationProbability { packing.append(.umbrella) }
        }
        var seen = Set<String>()
        packing = packing.filter { seen.insert($0.id).inserted }
        if let packSentence = Self.packingSentence(packing) { s.append(packSentence) }

        if !missing.isEmpty {
            s.append("\(missing.count) gün için tahmin henüz yayımlanmadı.")
        }
        let maxOffset = rows.map { calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: $0.date).day ?? 0 }.max() ?? 0
        if maxOffset >= uncertainFromDayOffset {
            s.append("Birkaç gün sonrası için tahminler daha belirsiz; yola çıkmadan önce tekrar bakmanı öneririm.")
        }
        if let o = origin?.place {
            let hours = (tz.secondsFromGMT(for: now) - o.timeZone.secondsFromGMT(for: now)) / 3600
            if hours != 0 {
                s.append("\(dest.name) saati \(o.name) saatinden \(abs(hours)) saat \(hours > 0 ? "ileride" : "geride"); saatler yerel saate göre.")
            }
        }

        let theme = WeatherSummaryEngine.theme(
            current: CurrentWeather(time: first.date, temperature: first.maxTemperature, feelsLike: first.maxTemperature,
                                    condition: first.condition, humidity: 0, windSpeedKmh: 0),
            precipitation: nil, wind: nil, now: first.date)
        return TravelSummary(destination: dest, origin: origin?.place, days: rows, unavailableDays: missing, packing: packing,
                             briefing: Briefing(sentences: s, restingMood: .happy, theme: theme))
    }

    static func packingSentence(_ items: [ClothingItem]) -> String? {
        let outer = items.first { ["thickCoat", "coat", "lightJacket", "sweatshirt", "windbreaker"].contains($0.id) }
        let rain = items.first { ["umbrella", "boots"].contains($0.id) }
        let sun = items.first { $0.id == "sunscreen" }
        let spoken: [String: String] = ["thickCoat": "kalın bir mont", "coat": "bir mont", "lightJacket": "ince bir mont",
                                        "sweatshirt": "bir sweatshirt", "windbreaker": "rüzgâr geçirmeyen bir üst",
                                        "umbrella": "şemsiye", "boots": "su geçirmez bot", "sunscreen": "güneş kremi"]
        let names = [outer, rain, sun].compactMap { $0.flatMap { spoken[$0.id] } }
        guard !names.isEmpty else { return nil }
        let list = names.count == 1 ? names[0] : names.dropLast().joined(separator: ", ") + " ve " + names.last!
        return "Yanına \(list) almanı öneririm."
    }

    private func dayLabel(_ date: Date, now: Date, calendar: Calendar) -> String {
        let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: date).day ?? 0
        switch offset {
        case 0: return "Bugün"
        case 1: return "Yarın"
        default: return TurkishFormatting.weekdayNames[calendar.component(.weekday, from: date) - 1]
        }
    }
}
