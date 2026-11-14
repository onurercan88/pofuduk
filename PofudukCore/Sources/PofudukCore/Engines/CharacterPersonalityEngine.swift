import Foundation

/// Turns factual analysis into Pofuduk's voice. Every number and event comes from `WeatherAnalysis`
/// or verified `OfficialWarning`s; style only changes greeting/closing tone, never facts.
public struct CharacterPersonalityEngine: Sendable {
    public var style: PersonalityStyle
    public var length: BriefingLength

    public init(style: PersonalityStyle = .friendly, length: BriefingLength = .detailed) {
        self.style = style
        self.length = length
    }

    // MARK: - Briefing

    public func briefing(for analysis: WeatherAnalysis, warnings: [OfficialWarning] = [],
                         clothing: ClothingRecommendation? = nil) -> Briefing {
        let tz = analysis.place.timeZone
        let activeWarnings = warnings
            .filter { $0.isActive(at: analysis.analyzedAt) }
            .sorted { $0.level > $1.level }
        let serious = (activeWarnings.first?.level ?? .green) >= .orange || analysis.theme == .stormy
        var s: [String] = []

        s.append(greeting(at: analysis.analyzedAt, timeZone: tz, serious: serious))

        if analysis.source == .demo {
            s.append("Şu an örnek verilerle konuşuyorum, bu gerçek bir tahmin değil.")
        }
        if analysis.isStale {
            let t = TurkishFormatting.clockTime(analysis.retrievedAt, timeZone: tz)
            s.append("Bu bilgiler saat \(t) itibarıyla alındı, güncel olmayabilir.")
        }

        // Official warnings always come first and are never softened.
        for warning in activeWarnings.prefix(2) where warning.level > .green {
            s.append("Dikkat! Bulunduğun bölge için MGM tarafından \(warning.level.turkishName) seviyede meteorolojik uyarı yayımlanmış.")
            s.append("\(warning.hazard) bekleniyor. Lütfen resmi uyarının detaylarını incelemeyi unutma.")
        }

        s.append(currentSentence(analysis))

        if length == .detailed, analysis.feelsLikeIsNotable {
            s.append("Hissedilen sıcaklık ise \(TurkishFormatting.temperature(analysis.current.feelsLike)).")
        }
        if let rangeSentence = rangeSentence(analysis) {
            s.append(rangeSentence)
        }
        s.append(contentsOf: precipitationSentences(analysis))

        if let wind = analysis.wind, wind.isStrong {
            s.append(windSentence(wind))
        }
        if length == .detailed, analysis.isHighUV, let uv = analysis.uvMax {
            s.append("UV indeksi \(Int(uv.rounded())) seviyesine kadar çıkıyor, güneşten korunmayı unutma.")
        }

        if length == .detailed, let clothing, clothing.isNoteworthy {
            s.append(clothing.briefingSentence)
        }

        s.append(closing(theme: analysis.theme, serious: serious, precipitation: analysis.precipitation))

        let mood: CharacterMood = serious ? .warning : restingMood(for: analysis.theme)
        return Briefing(sentences: s, restingMood: mood, theme: analysis.theme, advice: advice(for: analysis))
    }

    /// Shown while no location is available. Contains no weather claims.
    public func locationNeededBriefing() -> Briefing {
        Briefing(
            sentences: ["Merhaba! Ben Pofuduk.", "Havayı anlatabilmem için önce nerede olduğunu bilmem gerekiyor."],
            restingMood: .idle,
            theme: .cloudy
        )
    }

    /// Spoken when no data could be obtained. Never invents values.
    public func unavailableBriefing(reason: String) -> Briefing {
        Briefing(
            sentences: ["Üzgünüm, şu an hava durumu bilgisine ulaşamadım.", reason, "Biraz sonra tekrar deneyelim mi?"],
            restingMood: .error,
            theme: .cloudy
        )
    }

    // MARK: - Pieces

    func greeting(at date: Date, timeZone: TimeZone, serious: Bool) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let hour = calendar.component(.hour, from: date)
        let base: String
        switch hour {
        case 5..<11: base = "Günaydın"
        case 11..<17: base = "İyi günler"
        case 17..<22: base = "İyi akşamlar"
        default: base = "Merhaba"
        }
        if serious { return "\(base)." }
        switch style {
        case .friendly: return "\(base)! Ben Pofuduk, havayı senin için kontrol ettim."
        case .playful: return "\(base)! Pofuduk bildiriyor, bulutlarla konuştum bile."
        case .calm: return "\(base). Bugünün havasına birlikte bakalım."
        }
    }

    func currentSentence(_ a: WeatherAnalysis) -> String {
        let place = TurkishGrammar.locative(a.place.name)
        let temp = TurkishFormatting.temperature(a.current.temperature)
        let condition = TurkishFormatting.conditionName(a.current.condition, isDay: a.current.isDay)
        return "\(place) şu an \(temp), hava \(condition)."
    }

    func rangeSentence(_ a: WeatherAnalysis) -> String? {
        guard let minT = a.minTemperature, let maxT = a.maxTemperature else { return nil }
        let lo = Int(minT.rounded()), hi = Int(maxT.rounded())
        if lo == hi { return "Gün boyunca sıcaklık \(TurkishFormatting.temperature(maxT)) civarında." }
        var sentence = "Bugün sıcaklık \(TurkishFormatting.temperature(minT).replacingOccurrences(of: " derece", with: "")) ile \(TurkishFormatting.temperature(maxT)) arasında olacak."
        if a.temperatureSwingIsNotable {
            sentence += " Sabahla akşam arasındaki farka dikkat."
        }
        return sentence
    }

    func precipitationSentences(_ a: WeatherAnalysis) -> [String] {
        let tz = a.place.timeZone
        guard let p = a.precipitation else {
            return a.hasHourlyCoverage ? ["Bugün için yağış beklenmiyor."] : []
        }
        let start = TurkishFormatting.clockTime(p.start, timeZone: tz)
        let startsNow = p.start <= a.analyzedAt
        let noun: String
        switch p.kind {
        case .rain: noun = "yağmur"
        case .snow: noun = "kar"
        case .sleet: noun = "karla karışık yağmur"
        case .thunderstorm: noun = "gök gürültülü sağanak"
        }

        guard p.isLikely else {
            let probabilityText = p.maxProbability.map { " yüzde \($0) civarında" } ?? ""
            let when = startsNow ? "Önümüzdeki saatlerde" : "Saat \(start) sonrasında"
            return ["\(when) \(noun) ihtimali\(probabilityText). Kesin değil ama hazırlıklı olmakta fayda var."]
        }

        var result: [String] = []
        let duration = p.durationHours
        let durationText: String
        if p.lastsUntilEndOfDay {
            durationText = " ve gün sonuna kadar sürebilir"
        } else {
            durationText = duration >= 2 ? " ve yaklaşık \(duration) saat sürebilir" : ""
        }
        if startsNow {
            result.append("Şu sıralar \(noun) var\(durationText).")
        } else {
            result.append("Saat \(start) civarında \(noun) başlaması bekleniyor\(durationText).")
        }

        switch (p.kind, p.intensity) {
        case (.thunderstorm, _): result.append("Gök gürültüsü sırasında açık alanlarda bulunmamaya özen göster.")
        case (_, .heavy): result.append("Yağışın yer yer kuvvetli olması bekleniyor.")
        case (_, .moderate): result.append("Orta şiddette bir yağış bekleniyor.")
        case (_, .light): result.append("Hafif bir yağış bekleniyor.")
        case (_, .unknown): break
        }
        return result
    }

    func windSentence(_ wind: WindOutlook) -> String {
        let speed = Int(wind.maxSpeedKmh.rounded())
        var sentence = "Rüzgâr saatte \(speed) kilometreye kadar çıkabilir"
        if let gust = wind.maxGustKmh, gust > wind.maxSpeedKmh + 5 {
            sentence += ", ani esintiler \(Int(gust.rounded())) kilometreyi bulabilir"
        }
        return sentence + ". Açık alanlarda dikkatli ol."
    }

    func closing(theme: WeatherTheme, serious: Bool, precipitation: PrecipitationOutlook?) -> String {
        if serious {
            return "Şakayı bir kenara bırakalım; lütfen dikkatli ol ve gereksiz yere dışarı çıkma."
        }
        switch (theme, style) {
        case (.rainy, .playful): return "Şemsiyeni unutma, sonra ıslanıp beni suçlama!"
        case (.rainy, .calm): return "Dışarı çıkacaksan yanına bir şemsiye almanı öneririm."
        case (.rainy, _): return "Şemsiyeni unutma! Islanmanı hiç istemem."
        case (.snowy, .calm): return "Atkını ve montunu hazırlamanı öneririm."
        case (.snowy, _): return "Ortalık beyaza bürünebilir. Atkını ve montunu hazırlamayı unutma!"
        case (.windy, .playful): return "Saçlarımız biraz dağılabilir, rüzgâr bugün oldukça hareketli!"
        case (.windy, .calm): return "Dışarıdayken rüzgârı hesaba katmanı öneririm."
        case (.windy, _): return "Bugün biraz rüzgârımız var, sıkı giyinmeyi unutma!"
        case (.sunny, .playful): return "Güneş bizimle! Bence güzel bir yürüyüş için harika bir gün."
        case (.sunny, .calm): return "Dışarıda vakit geçirmek için uygun bir gün."
        case (.sunny, _): return "Harika bir gün! Dışarı çıkmak için güzel bir fırsat."
        case (.night, _): return "İyi dinlenmeler, yarın yine buradayım."
        case (.cloudy, .playful): return "Bulutlar bugün bana benziyor, ama güzel bir gün geçirmek senin elinde!"
        case (.cloudy, _): return precipitation == nil
            ? "Sakin ve bulutlu bir gün. Güzel bir gün geçirmek yine de senin elinde!"
            : "Gün içinde gökyüzüne bir göz atmayı unutma."
        case (.stormy, _): return "Lütfen dikkatli ol."
        }
    }

    func restingMood(for theme: WeatherTheme) -> CharacterMood {
        switch theme {
        case .sunny: return .happy
        case .snowy: return .celebrating
        case .stormy: return .warning
        case .night: return .sleeping
        case .rainy, .cloudy, .windy: return .idle
        }
    }

    func advice(for a: WeatherAnalysis) -> [String] {
        var items: [String] = []
        if let p = a.precipitation {
            items.append(p.isLikely ? "Şemsiye al" : "Şemsiye yanında olsun, yağış ihtimali var")
        }
        if a.wind?.isStrong == true { items.append("Rüzgâra karşı dikkatli ol") }
        if a.isHighUV { items.append("Güneş kremi ve şapka iyi fikir") }
        if a.temperatureSwingIsNotable { items.append("Katmanlı giyin, gün içinde sıcaklık çok değişiyor") }
        if a.feelsLikeIsNotable, a.current.feelsLike < a.current.temperature {
            items.append("Olduğundan serin hissedilebilir")
        }
        return items
    }
}
