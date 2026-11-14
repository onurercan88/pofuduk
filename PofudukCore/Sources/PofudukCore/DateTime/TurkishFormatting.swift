import Foundation

/// Locale-independent Turkish formatting (output is identical on iOS, macOS and Windows).
public enum TurkishFormatting {
    /// "14.00" style clock time in the given time zone.
    public static func clockTime(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d.%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// Rounded temperature as spoken text, e.g. "24 derece", "eksi 3 derece".
    public static func temperature(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        return rounded < 0 ? "eksi \(-rounded) derece" : "\(rounded) derece"
    }

    /// Compact temperature for UI, e.g. "24°".
    public static func shortTemperature(_ value: Double) -> String {
        "\(Int(value.rounded()))°"
    }

    public static let weekdayNames = ["Pazar", "Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi"]
    public static let monthNames = ["Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran",
                                    "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık"]

    /// "14 Kasım Cumartesi"
    public static func longDate(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.day, .month, .weekday], from: date)
        let month = monthNames[(c.month ?? 1) - 1]
        let weekday = weekdayNames[(c.weekday ?? 1) - 1]
        return "\(c.day ?? 1) \(month) \(weekday)"
    }

    public static func conditionName(_ condition: WeatherCondition, isDay: Bool = true) -> String {
        switch condition {
        case .clear: return isDay ? "güneşli" : "açık"
        case .partlyCloudy: return "parçalı bulutlu"
        case .cloudy: return "bulutlu"
        case .fog: return "sisli"
        case .drizzle: return "çisentili"
        case .rain: return "yağmurlu"
        case .heavyRain: return "kuvvetli yağışlı"
        case .thunderstorm: return "gök gürültülü sağanaklı"
        case .snow: return "karlı"
        case .sleet: return "karla karışık yağmurlu"
        case .windy: return "rüzgârlı"
        }
    }
}

/// Minimal Turkish suffix helper for proper nouns (vowel harmony + consonant hardening).
public enum TurkishGrammar {
    private static let backVowels: Set<Character> = ["a", "ı", "o", "u"]
    private static let frontVowels: Set<Character> = ["e", "i", "ö", "ü"]
    private static let hardConsonants: Set<Character> = ["f", "s", "t", "k", "ç", "ş", "h", "p"]

    /// "İstanbul" → "İstanbul'da", "İzmir" → "İzmir'de", "Kars" → "Kars'ta", "Rize" → "Rize'de".
    public static func locative(_ word: String) -> String {
        "\(word)'\(consonant(word))\(vowel(word))"
    }

    /// "İstanbul" → "İstanbul'dan", "İzmir" → "İzmir'den", "Kars" → "Kars'tan".
    public static func ablative(_ word: String) -> String {
        "\(word)'\(consonant(word))\(vowel(word))n"
    }

    private static func vowel(_ word: String) -> String {
        let lower = word.lowercased(with: Locale(identifier: "tr_TR"))
        let lastVowel = lower.last { backVowels.contains($0) || frontVowels.contains($0) }
        return (lastVowel.map { backVowels.contains($0) } ?? true) ? "a" : "e"
    }

    private static func consonant(_ word: String) -> String {
        word.lowercased(with: Locale(identifier: "tr_TR")).last.map { hardConsonants.contains($0) } == true ? "t" : "d"
    }
}
