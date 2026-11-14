import Foundation
import PofudukCore

// Pofuduk console demo: the same engines as the iOS app, with live Open-Meteo data.
// Usage: PofudukDemo [il] [--stil samimi|sakaci|sakin] [--kisa] [--ses] [--soru "metin"]

// MARK: - Options

struct Options {
    var placeText = "İstanbul"
    var style: PersonalityStyle = .friendly
    var length: BriefingLength = .detailed
    var speak = false
    var question: String?
}

func parseOptions() -> Options {
    var o = Options()
    var words: [String] = []
    var args = Array(CommandLine.arguments.dropFirst())
    while !args.isEmpty {
        let a = args.removeFirst()
        switch a {
        case "--stil":
            let v = TurkishProvinces.normalize(args.isEmpty ? "" : args.removeFirst())
            o.style = v.hasPrefix("sak") && v.contains("ac") ? .playful : (v.hasPrefix("sakin") ? .calm : .friendly)
        case "--kisa": o.length = .short
        case "--ses": o.speak = true
        case "--soru": o.question = args.isEmpty ? nil : args.removeFirst()
        default: words.append(a)
        }
    }
    if !words.isEmpty { o.placeText = words.joined(separator: " ") }
    return o
}

// MARK: - Output helpers

func line(_ s: String = "") { print(s) }
func section(_ title: String) { line(); line("── \(title) " + String(repeating: "─", count: max(4, 44 - title.count))) }

func say(_ sentences: [String], enabled: Bool) {
    for s in sentences { line("  › \(s)") }
    guard enabled else { return }
    let text = sentences.joined(separator: " ")
    #if os(Windows)
    guard let script = ProcessInfo.processInfo.environment["POFUDUK_SPEAK_SCRIPT"] else { return }
    run("C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe",
        ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script, "-Text", text])
    #elseif os(macOS)
    run("/usr/bin/say", ["-v", "Yelda", text])
    #endif
}

func run(_ executable: String, _ arguments: [String]) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: executable)
    p.arguments = arguments
    do { try p.run(); p.waitUntilExit() } catch { line("  (Seslendirme başlatılamadı.)") }
}

func resolvePlace(_ text: String) -> Place? {
    WeatherQueryParser().province(in: text)?.place ?? TurkishProvinces.search(text).first?.place
}

// MARK: - Main

let options = parseOptions()
guard let origin = resolvePlace(options.placeText) else {
    line("'\(options.placeText)' için il bulunamadı. Örnek: Ankara, İzmir, Bursa")
    exit(1)
}

let repository = CachedWeatherRepository(
    engine: WeatherProviderFallbackEngine(providers: [OpenMeteoProvider(http: URLSessionHTTPClient())]),
    cache: InMemoryWeatherCacheStore())

func fetch(_ place: Place) async -> WeatherSnapshot? {
    do { return try await repository.snapshot(for: place, forceRefresh: false) } catch {
        line("Hava durumu alınamadı: \((error as? WeatherError)?.turkishExplanation ?? "\(error)")")
        return nil
    }
}

guard let snapshot = await fetch(origin) else { exit(2) }
let now = Date()
let tz = origin.timeZone
let analysis = WeatherSummaryEngine().analyze(snapshot, now: now)
let clothing = ClothingRecommendationEngine().recommend(for: snapshot, now: now)
let personality = CharacterPersonalityEngine(style: options.style, length: options.length)

line("═══ Pofuduk · \(origin.name) " + String(repeating: "═", count: 30))
let c = snapshot.current
line("Şu an \(TurkishFormatting.shortTemperature(c.temperature)) · \(TurkishFormatting.conditionName(c.condition, isDay: c.isDay)) · Hissedilen \(TurkishFormatting.shortTemperature(c.feelsLike))")
line("\(TurkishFormatting.longDate(now, timeZone: tz)) \(TurkishFormatting.clockTime(now, timeZone: tz)) · Kaynak: Open-Meteo.com (CC BY 4.0), \(TurkishFormatting.clockTime(snapshot.retrievedAt, timeZone: tz)) itibarıyla")
line("Tarz: \(options.style.turkishName) · \(options.length.turkishName) anlatım · Pofuduk'un modu: \(analysis.theme.accessibilityDescription)")

// Briefing (morning greeting between 07:30 and noon, like the app).
section("Pofuduk anlatıyor")
let morning = MorningBriefingEngine()
let briefing = morning.shouldGreet(now: now, settings: MorningBriefingSettings(), timeZone: tz)
    ? morning.briefing(snapshot: snapshot, analysis: analysis, clothing: clothing, now: now)
    : personality.briefing(for: analysis, clothing: clothing)
say(briefing.sentences, enabled: options.speak)

section("Saatlik (12 saat)")
let hourStart = now.addingTimeInterval(-3600)
let hours = snapshot.hourly.filter { $0.time > hourStart }.prefix(12)
for row in stride(from: 0, to: hours.count, by: 4) {
    let chunk = hours.dropFirst(row).prefix(4).map { h -> String in
        let p = (h.precipitationProbability ?? 0) >= 20 ? " %\(h.precipitationProbability!)" : ""
        return "\(TurkishFormatting.clockTime(h.time, timeZone: tz)) \(TurkishFormatting.shortTemperature(h.temperature))\(p)"
    }
    line("  " + chunk.joined(separator: "   "))
}

section("Bugün Ne Giysem?")
if let clothing {
    say(clothing.sentences, enabled: false)
    line("  Yanına: " + clothing.items.map(\.name).joined(separator: ", "))
    line("  Neden: " + clothing.reasons.joined(separator: " "))
} else {
    line("  Bugün için saatlik veri yok, öneri verilemiyor.")
}

section("Bildirimler (açık olsaydı planlanacaklar)")
var notificationPrefs = NotificationPreferences()
notificationPrefs.isEnabled = true
notificationPrefs.enabledCategories.insert(.temperatureChange)
let planned = RainNotificationEngine().plan(snapshot: snapshot, preferences: notificationPrefs, log: InMemoryNotificationLog(), now: now)
if planned.isEmpty { line("  Şu an planlanacak bildirim yok (önümüzdeki 6 saatte yağış/rüzgâr beklenmiyor ya da sessiz saatler).") }
for n in planned { line("  \(TurkishFormatting.clockTime(n.fireDate, timeZone: tz))  \(n.title) — \(n.body)") }

section("Resmi MGM uyarıları")
line("  Yetkili veri bağlantısı yok; resmi sayfa: \(MGMOfficialPage.warnings.absoluteString)")

// MARK: - Questions

var manager = ConversationManager()

func answer(_ text: String) async {
    let query = manager.interpret(text, now: Date())
    if query.topic == .travel {
        guard let destination = query.province?.place else {
            say(["Nereye gideceğini anlayamadım.", "Örneğin \"Yarın Bursa'ya gideceğim\" diyebilirsin."], enabled: options.speak)
            return
        }
        guard let destinationSnapshot = await fetch(destination) else { return }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = destination.timeZone
        let days = ForecastDateResolver().days(for: query.date, now: Date(), timeZone: destination.timeZone)
            .map { cal.dateComponents([.year, .month, .day], from: $0) }
        let summary = TravelWeatherSummaryEngine().summarize(destination: destinationSnapshot, origin: snapshot, days: days, now: Date())
        say(summary.briefing.sentences, enabled: options.speak)
        return
    }
    let place = query.province?.place ?? origin
    guard let snap = place == origin ? snapshot : await fetch(place) else { return }
    say(WeatherAnswerEngine().answer(query, snapshot: snap, now: Date()).sentences, enabled: options.speak)
}

if let q = options.question {
    section("Soru: \(q)")
    await answer(q)
    exit(0)
}

section("Soru sor")
line("  Örnek: Yarın hava nasıl? · Peki yağmur var mı? · Akşam dışarı çıkabilir miyim? · Yarın Bursa'ya gideceğim")
line("  Türkçe harf yazamazsan sorun değil: 'yarin hava nasil' da anlaşılır. Çıkmak için: çık")
while true {
    print("\nSen › ", terminator: "")
    guard let input = readLine()?.trimmingCharacters(in: .whitespaces) else { break }
    if input.isEmpty { continue }
    if ["cik", "q", "exit", "quit"].contains(TurkishProvinces.normalize(input)) { break }
    line("Pofuduk ›")
    await answer(input)
}
line("Görüşürüz! ☁️")
