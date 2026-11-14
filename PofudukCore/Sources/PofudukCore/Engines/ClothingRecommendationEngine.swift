import Foundation

/// Tunable clothing rules (feels-like bands in °C). Advice only; never a safety or medical guarantee.
public struct ClothingRules: Equatable, Sendable {
    public var hot: Double = 26
    public var warm: Double = 20
    public var mild: Double = 15
    public var cool: Double = 10
    public var cold: Double = 3
    /// Feels-like spread across the day that suggests layers.
    public var layeringSpread: Double = 8
    /// Temperature minus feels-like worth explaining (wind chill).
    public var noticeableChill: Double = 3
    /// Waking hours considered (local).
    public var activeHours: ClosedRange<Int> = 7...22

    public init() {}
    public static let `default` = ClothingRules()
}

public struct ClothingItem: Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// Emoji used as the visual (always available, no asset dependency).
    public var symbol: String

    static let thickCoat = ClothingItem(id: "thickCoat", name: "Kalın mont", symbol: "🧥")
    static let coat = ClothingItem(id: "coat", name: "Mont", symbol: "🧥")
    static let lightJacket = ClothingItem(id: "lightJacket", name: "İnce mont veya ceket", symbol: "🧥")
    static let sweatshirt = ClothingItem(id: "sweatshirt", name: "Sweatshirt veya hırka", symbol: "🧶")
    static let sweater = ClothingItem(id: "sweater", name: "Kazak", symbol: "🧶")
    static let longSleeve = ClothingItem(id: "longSleeve", name: "Uzun kollu üst", symbol: "👔")
    static let tshirt = ClothingItem(id: "tshirt", name: "Tişört", symbol: "👕")
    static let lightClothes = ClothingItem(id: "lightClothes", name: "Hafif, açık renkli kıyafetler", symbol: "🩳")
    static let scarf = ClothingItem(id: "scarf", name: "Atkı", symbol: "🧣")
    static let gloves = ClothingItem(id: "gloves", name: "Eldiven", symbol: "🧤")
    static let beanie = ClothingItem(id: "beanie", name: "Bere", symbol: "🧢")
    static let umbrella = ClothingItem(id: "umbrella", name: "Şemsiye", symbol: "☂️")
    static let waterproofShoes = ClothingItem(id: "waterproofShoes", name: "Su geçirmeyen ayakkabı", symbol: "👟")
    static let boots = ClothingItem(id: "boots", name: "Su geçirmez bot", symbol: "🥾")
    static let windbreaker = ClothingItem(id: "windbreaker", name: "Rüzgâr geçirmeyen bir üst", symbol: "🧥")
    static let sunglasses = ClothingItem(id: "sunglasses", name: "Güneş gözlüğü", symbol: "🕶️")
    static let hat = ClothingItem(id: "hat", name: "Şapka", symbol: "👒")
    static let sunscreen = ClothingItem(id: "sunscreen", name: "Güneş kremi", symbol: "🧴")
}

public struct ClothingRecommendation: Equatable, Sendable {
    /// Spoken/subtitled summary (1–3 sentences), derived only from forecast data.
    public var sentences: [String]
    public var items: [ClothingItem]
    /// "Why" explanations, each tied to a data point.
    public var reasons: [String]
    public var suggestsLayers: Bool
    /// True when the advice is worth adding to the main briefing.
    public var isNoteworthy: Bool
    public var feelsLikeRange: ClosedRange<Double>
    /// Single sentence suitable for the main briefing.
    public var briefingSentence: String

    public var summary: String { sentences.joined(separator: " ") }
}

/// Deterministic clothing advice from current + upcoming hours of one local day.
public struct ClothingRecommendationEngine: Sendable {
    public var rules: ClothingRules
    public var thresholds: WeatherThresholds
    private let summary: WeatherSummaryEngine

    public init(rules: ClothingRules = .default, thresholds: WeatherThresholds = .default) {
        self.rules = rules
        self.thresholds = thresholds
        self.summary = WeatherSummaryEngine(thresholds: thresholds)
    }

    /// `day`: any time on the wanted local day (default: today). Returns nil when the forecast lacks hourly data
    /// for that day — never guesses.
    public func recommend(for snapshot: WeatherSnapshot, day: Date? = nil, now: Date) -> ClothingRecommendation? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = snapshot.place.timeZone
        let target = day ?? now
        let isToday = calendar.isDate(target, inSameDayAs: now)
        let hourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now

        let dayHours = snapshot.hourly.filter { calendar.isDate($0.time, inSameDayAs: target) && (!isToday || $0.time >= hourStart) }
        var hours = dayHours.filter { rules.activeHours.contains(calendar.component(.hour, from: $0.time)) }
        if hours.isEmpty { hours = dayHours }   // late evening: use what's left
        guard !hours.isEmpty else { return nil }

        let feels = hours.map { $0.feelsLike ?? $0.temperature }
        let temps = hours.map(\.temperature)
        let coldFL = feels.min()!, warmFL = feels.max()!
        let label = isToday ? "Bugün" : (calendar.isDate(target, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: now)!) ? "Yarın" : "O gün")

        var items: [ClothingItem] = []
        var reasons: [String] = []

        // Outer layer from the coldest felt temperature.
        switch coldFL {
        case ..<rules.cold: items += [.thickCoat, .scarf, .gloves, .beanie]
        case ..<rules.cool: items += [.coat, .scarf]
        case ..<rules.mild: items += [.lightJacket]
        case ..<rules.warm: items += [.sweatshirt]
        default: break
        }
        // Base layer from the warmest felt temperature.
        switch warmFL {
        case rules.hot...: items += [.lightClothes]
        case rules.warm...: items += [.tshirt]
        case rules.cool...: items += [.longSleeve]
        default: items += [.sweater]
        }
        reasons.append("\(label) hissedilen sıcaklık \(Int(coldFL.rounded())) ile \(Int(warmFL.rounded())) derece arasında.")

        let layers = warmFL - coldFL >= rules.layeringSpread
        if layers {
            let coldHour = hours[feels.firstIndex(of: coldFL)!].time
            let warmHour = hours[feels.firstIndex(of: warmFL)!].time
            let tz = snapshot.place.timeZone
            reasons.append("Saat \(TurkishFormatting.clockTime(coldHour, timeZone: tz)) civarında \(Int(coldFL.rounded())), saat \(TurkishFormatting.clockTime(warmHour, timeZone: tz)) civarında \(Int(warmFL.rounded())) derece hissedilecek; gün içinde fark büyük.")
        }

        // Wind chill: actual vs felt at the coldest-felt hour.
        let chillIndex = feels.firstIndex(of: coldFL)!
        let chill = temps[chillIndex] - coldFL
        let maxWind = hours.compactMap(\.windSpeedKmh).max() ?? 0
        let maxGust = hours.compactMap(\.windGustKmh).max() ?? 0
        let windy = maxWind >= thresholds.strongWindKmh || maxGust >= thresholds.strongGustKmh
        if windy {
            items.append(.windbreaker)
            reasons.append("Rüzgâr saatte \(Int(maxWind.rounded())) kilometreye kadar çıkabilir.")
        }
        let chillNotable = chill >= rules.noticeableChill

        // Precipitation (same rules as the briefing: heavy only from amounts).
        let precipitation = summary.precipitationOutlook(in: dayHours)
        if let p = precipitation {
            let start = TurkishFormatting.clockTime(p.start, timeZone: snapshot.place.timeZone)
            if p.kind == .snow {
                items += [.boots]
                reasons.append("Saat \(start) civarında kar bekleniyor.")
            } else if p.isLikely {
                items += [.umbrella, .waterproofShoes]
                reasons.append("Saat \(start) civarında yağış bekleniyor.")
            } else {
                items += [.umbrella]
                let prob = p.maxProbability.map { "yüzde \($0)" } ?? "düşük"
                reasons.append("Yağış ihtimali \(prob) civarında; kesin değil.")
            }
        }

        // UV during the remaining daylight.
        let uv = hours.compactMap(\.uvIndex).max() ?? 0
        if uv >= thresholds.highUVIndex {
            items += [.sunglasses, .hat, .sunscreen]
            reasons.append("UV indeksi \(Int(uv.rounded())) seviyesine çıkıyor.")
        }

        // Spoken summary.
        var sentences: [String] = []
        let tempText = TurkishFormatting.temperature(temps.max()!)
        if chillNotable {
            sentences.append("\(label) hava \(tempText) civarında ama rüzgâr nedeniyle daha serin, \(TurkishFormatting.temperature(coldFL)) gibi hissedilebilir.")
        } else if layers {
            sentences.append("\(label) sabahla gün ortası arasında belirgin bir sıcaklık farkı var.")
        }
        sentences.append(mainAdvice(coldFL: coldFL, warmFL: warmFL, layers: layers, label: label, hasLeadIn: !sentences.isEmpty))
        if let p = precipitation {
            if p.kind == .snow { sentences.append("Kar beklendiği için su geçirmez bir bot iyi olur.") }
            else if p.isLikely { sentences.append("Yağış beklendiği için şemsiye ve su geçirmeyen ayakkabı iyi fikir olabilir.") }
            else { sentences.append("Yağış ihtimali olduğu için yanına bir şemsiye alabilirsin.") }
        }
        if uv >= thresholds.highUVIndex { sentences.append("UV değeri yüksek; güneşten korunmayı da unutma.") }

        let noteworthy = layers || chillNotable || windy || (precipitation?.isLikely ?? false)
            || coldFL < rules.cool || warmFL >= rules.hot
        return ClothingRecommendation(sentences: sentences, items: unique(items), reasons: reasons,
                                      suggestsLayers: layers, isNoteworthy: noteworthy,
                                      feelsLikeRange: coldFL...warmFL,
                                      briefingSentence: briefingSentence(coldFL: coldFL, layers: layers, label: label))
    }

    private func mainAdvice(coldFL: Double, warmFL: Double, layers: Bool, label: String, hasLeadIn: Bool) -> String {
        let core = coreAdvice(coldFL)
        let text: String
        if layers { text = "Katmanlı giyinmek iyi olur; \(core)." }
        else { text = hasLeadIn ? "\(core)." : "\(label) \(core)." }
        return text.prefix(1).uppercased(with: Locale(identifier: "tr_TR")) + text.dropFirst()
    }

    /// One self-contained sentence for the main briefing (no umbrella/UV repetition).
    func briefingSentence(coldFL: Double, layers: Bool, label: String) -> String {
        layers ? "\(label) katmanlı giyinmek iyi olur; \(coreAdvice(coldFL))." : "\(label) \(coreAdvice(coldFL))."
    }

    private func coreAdvice(_ coldFL: Double) -> String {
        let core: String
        switch coldFL {
        case ..<rules.cold: core = "kalın bir mont, atkı, eldiven ve bere iyi olur"
        case ..<rules.cool: core = "bir mont ve atkı almanı öneririm"
        case ..<rules.mild: core = "ince bir mont veya ceket tercih edebilirsin"
        case ..<rules.warm: core = "ince bir mont veya sweatshirt tercih edebilirsin"
        case ..<rules.hot: core = "tişört gibi hafif bir üst yeterli olur"
        default: core = "hafif ve açık renkli kıyafetler tercih edebilirsin"
        }
        return core
    }

    private func unique(_ items: [ClothingItem]) -> [ClothingItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }
}
