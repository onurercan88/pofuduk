import Foundation

/// Deterministic Turkish weather-question parser (no LLM). Keyword based on normalized text
/// ("ı→i, ş→s, ğ→g, ü→u, ö→o, ç→c", apostrophes removed).
public struct WeatherQueryParser: Sendable {
    public init() {}

    public func parse(_ text: String) -> WeatherIntent {
        let normalized = TurkishProvinces.normalize(text)
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
        let tokens = normalized.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let joined = " " + tokens.joined(separator: " ") + " "
        func has(_ phrases: String...) -> Bool { phrases.contains { joined.contains(" \($0)") } }

        let date = parseDate(tokens: tokens, has: has)
        let dayPart = parseDayPart(tokens: tokens, has: has)
        let province = parseProvince(tokens: tokens)
        let topic = parseTopic(has: has)
        let followUpMarker = tokens.first.map { ["peki", "ya", "o", "bir", "ayrica"].contains($0) } ?? false
        let isFollowUp = followUpMarker || (date == nil && province == nil)
        return WeatherIntent(topic: topic, date: date, dayPart: dayPart, province: province, isFollowUp: isFollowUp)
    }

    // MARK: - Date

    private func parseDate(tokens: [String], has: (String...) -> Bool) -> DateReference? {
        if has("yarindan sonra", "obur gun", "obur gun", "ertesi gun") { return .inDays(2) }
        if has("hafta sonu", "haftasonu", "hafta sonunda", "haftasonunda") { return .weekend }
        if has("yarin") { return .tomorrow }
        if has("bugun", "bu aksam", "bu sabah", "bu gece", "simdi", "su an", "bu ogle") { return .today }
        let weekdays = ["pazar": 1, "pazartesi": 2, "sali": 3, "carsamba": 4, "persembe": 5, "cuma": 6, "cumartesi": 7]
        for token in tokens {
            // Longest match first so "pazartesi" isn't read as "pazar", "cumartesi" not as "cuma".
            for (name, day) in weekdays.sorted(by: { $0.key.count > $1.key.count }) where token.hasPrefix(name) {
                return .weekday(day)
            }
        }
        if let i = tokens.firstIndex(where: { $0 == "gun" || $0.hasPrefix("gun") }), i > 0, let n = Int(tokens[i - 1]),
           (1...14).contains(n), tokens.contains(where: { $0.hasPrefix("sonra") }) {
            return .inDays(n)
        }
        return nil
    }

    // MARK: - Time of day

    private func parseDayPart(tokens: [String], has: (String...) -> Bool) -> DayPart? {
        if let hour = parseHour(tokens: tokens, morning: has("sabah"), night: has("gece")) { return .hour(hour) }
        if has("ogleden sonra") { return .afternoon }
        if has("ogle", "oglen") { return .noon }
        if has("sabah") { return .morning }
        if has("aksam") { return .evening }
        if has("gece") { return .night }
        return nil
    }

    /// "saat 17", "17.00", "17:30", "saat 5te" (1–6 without "sabah"/"gece" means afternoon).
    private func parseHour(tokens: [String], morning: Bool, night: Bool) -> Int? {
        for (i, token) in tokens.enumerated() {
            let digits = token.prefix { $0.isNumber }
            guard !digits.isEmpty, let value = Int(digits), (0...24).contains(value) else { continue }
            let afterSaat = i > 0 && tokens[i - 1] == "saat"
            let clockStyle = i + 1 < tokens.count && ["00", "30", "15", "45"].contains(tokens[i + 1])
            guard afterSaat || clockStyle else { continue }
            if (1...6).contains(value) && !morning && !night { return value + 12 }
            return value % 24
        }
        return nil
    }

    // MARK: - Location

    static let caseSuffixes: Set<String> = ["", "da", "de", "ta", "te", "a", "e", "ya", "ye", "dan", "den", "tan",
                                            "ten", "nin", "in", "un", "nun", "daki", "deki"]
    static let dativeSuffixes: Set<String> = ["a", "e", "ya", "ye"]

    /// DestinationResolver (offline part): the destination province named in free text, if any.
    public func province(in text: String) -> TurkishProvinces.Province? {
        parse(text).province
    }

    private func parseProvince(tokens: [String]) -> TurkishProvinces.Province? {
        var matches: [(TurkishProvinces.Province, suffix: String)] = []
        for token in tokens {
            for province in TurkishProvinces.all {
                let name = TurkishProvinces.normalize(province.name)
                guard token.hasPrefix(name) else { continue }
                let suffix = String(token.dropFirst(name.count))
                if Self.caseSuffixes.contains(suffix) { matches.append((province, suffix)) }
            }
        }
        // "İstanbul'dan Ankara'ya" → the destination (dative) wins; otherwise the last mentioned.
        return matches.last { Self.dativeSuffixes.contains($0.suffix) }?.0 ?? matches.last?.0
    }

    // MARK: - Topic

    private func parseTopic(has: (String...) -> Bool) -> WeatherTopic {
        let rainWords = has("yagmur", "yagis", "yagacak", "yagar", "islan", "saganak", "kar ", "kar yag")
        if rainWords && has("kacta", "ne zaman", "saat kac", "ne vakit", "baslayacak", "baslar") { return .rainTiming }
        if has("semsiye") { return .umbrella }
        if has("giy", "kiyafet", "mont", "ceket", "kazak", "sweatshirt", "hirka", "mont yeter") { return .clothing }
        if has("gunes kremi", "krem", "uv") { return .uv }
        if has("disari", "cikabilir", "yuruyus", "piknik") { return .goingOut }
        if rainWords { return .rain }
        if has("ruzgar", "firtina", "esinti") { return .wind }
        if has("derece", "sicaklik", "soguk", "sicak", "serin", "isi") { return .temperature }
        if has("gidece", "gidiyor", "gitmek", "gitcem", "yolculuk", "seyahat", "tatil", "ziyaret") { return .travel }
        return .overview
    }
}
