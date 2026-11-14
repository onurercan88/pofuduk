import SwiftUI
import PofudukCore

struct HomeHeader: View {
    let viewModel: HomeViewModel

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                if let place = viewModel.snapshot?.place {
                    Button { viewModel.openLocationPicker() } label: {
                        Label(place.displayName, systemImage: place.source == .gps ? "location.fill" : "mappin.and.ellipse")
                            .font(PofudukFont.title)
                            .foregroundStyle(PofudukColor.ink)
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(viewModel.isDemoMode ? "" : "Konumu değiştir")
                    TimelineView(.everyMinute) { context in
                        Text("\(TurkishFormatting.longDate(context.date, timeZone: place.timeZone)) · \(TurkishFormatting.clockTime(context.date, timeZone: place.timeZone))")
                            .font(PofudukFont.caption)
                            .foregroundStyle(PofudukColor.inkSecondary)
                    }
                } else {
                    Text("Pofuduk").font(PofudukFont.title).foregroundStyle(PofudukColor.ink)
                }
                if viewModel.isDemo {
                    Badge(text: "Örnek veri — gerçek tahmin değil", systemImage: "info.circle")
                        .padding(.top, 4)
                }
                if viewModel.isApproximateLocation {
                    Badge(text: "Yaklaşık konum (IP)", systemImage: "network")
                        .padding(.top, 4)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                RoundIconButton(systemImage: "gearshape.fill", label: "Ayarlar") {
                    viewModel.showSettings = true
                }
                RoundIconButton(systemImage: viewModel.isSoundOn ? "speaker.wave.2.fill" : "speaker.slash.fill",
                                label: viewModel.isSoundOn ? "Sesi kapat" : "Sesi aç") {
                    viewModel.toggleSound()
                }
            }
        }
        .padding(.top, 8)
    }
}

struct PlaybackControls: View {
    let viewModel: HomeViewModel

    var body: some View {
        let status = viewModel.track.status
        HStack(spacing: 18) {
            RoundIconButton(systemImage: "stop.fill", label: "Durdur", isEnabled: viewModel.track.isActive) {
                viewModel.stop()
            }
            RoundIconButton(systemImage: status == .speaking ? "pause.fill" : (status == .paused ? "play.fill" : "arrow.counterclockwise"),
                            label: status == .speaking ? "Duraklat" : (status == .paused ? "Devam et" : "Tekrar dinle"),
                            prominent: true, isEnabled: viewModel.briefing != nil) {
                viewModel.togglePause()
            }
            RoundIconButton(systemImage: "text.bubble.fill", label: "Tüm metni göster",
                            isEnabled: !viewModel.track.sentences.isEmpty) {
                viewModel.showTranscript = true
            }
        }
        .overlay(alignment: .bottom) {
            if viewModel.voiceMissing {
                Text("Türkçe ses bulunamadı; altyazılar gösteriliyor.")
                    .font(PofudukFont.caption)
                    .foregroundStyle(PofudukColor.inkSecondary)
                    .fixedSize()
                    .offset(y: 26)
            }
        }
        .padding(.bottom, viewModel.voiceMissing ? 20 : 0)
    }
}

struct HourlyTimeline: View {
    let hours: [HourlyForecast]
    let timeZone: TimeZone

    var body: some View {
        SoftCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Saatlik").font(PofudukFont.headline).foregroundStyle(PofudukColor.ink)
                ScrollView(.horizontal) {
                    HStack(spacing: 16) {
                        ForEach(Array(hours.enumerated()), id: \.element.id) { index, hour in
                            VStack(spacing: 6) {
                                Text(index == 0 ? "Şimdi" : TurkishFormatting.clockTime(hour.time, timeZone: timeZone))
                                    .font(PofudukFont.caption)
                                    .foregroundStyle(PofudukColor.inkSecondary)
                                Image(systemName: hour.condition.symbolName())
                                    .symbolRenderingMode(.multicolor)
                                    .font(.title3)
                                    .frame(height: 26)
                                Text(TurkishFormatting.shortTemperature(hour.temperature))
                                    .font(PofudukFont.headline)
                                    .foregroundStyle(PofudukColor.ink)
                                if let p = hour.precipitationProbability, p >= 20 {
                                    Text("%\(p)").font(PofudukFont.caption).foregroundStyle(PofudukColor.accent)
                                } else {
                                    Text(" ").font(PofudukFont.caption)
                                }
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(accessibilityText(hour, isNow: index == 0))
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func accessibilityText(_ hour: HourlyForecast, isNow: Bool) -> String {
        let time = isNow ? "Şimdi" : "Saat \(TurkishFormatting.clockTime(hour.time, timeZone: timeZone))"
        var text = "\(time), \(TurkishFormatting.temperature(hour.temperature)), \(TurkishFormatting.conditionName(hour.condition))"
        if let p = hour.precipitationProbability, p >= 20 { text += ", yağış ihtimali yüzde \(p)" }
        return text
    }
}

struct TomorrowCard: View {
    let day: DailyForecast

    var body: some View {
        SoftCard {
            HStack(spacing: 14) {
                Image(systemName: day.condition.symbolName())
                    .symbolRenderingMode(.multicolor)
                    .font(.largeTitle)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Yarın").font(PofudukFont.headline).foregroundStyle(PofudukColor.ink)
                    Text(TurkishFormatting.conditionName(day.condition).sentenceCased)
                        .font(PofudukFont.caption).foregroundStyle(PofudukColor.inkSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(TurkishFormatting.shortTemperature(day.maxTemperature)) / \(TurkishFormatting.shortTemperature(day.minTemperature))")
                        .font(PofudukFont.headline).foregroundStyle(PofudukColor.ink)
                    if let p = day.precipitationProbability, p >= 20 {
                        Label("%\(p)", systemImage: "drop.fill").font(PofudukFont.caption).foregroundStyle(PofudukColor.accent)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct AdviceSection: View {
    let items: [String]

    var body: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Pofuduk'un önerileri", systemImage: "sparkles")
                    .font(PofudukFont.headline).foregroundStyle(PofudukColor.ink)
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(PofudukColor.accent).frame(width: 6, height: 6).padding(.top, 7)
                        Text(item).font(PofudukFont.body).foregroundStyle(PofudukColor.ink)
                    }
                }
            }
        }
    }
}

/// Official MGM status. Never shows a warning unless it came from an authorized official source.
struct MGMStatusCard: View {
    let availability: WarningAvailability?

    var body: some View {
        SoftCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Resmi MGM uyarıları", systemImage: "checkmark.shield")
                    .font(PofudukFont.headline).foregroundStyle(PofudukColor.ink)
                switch availability {
                case .unavailable(let reason, let page)?:
                    Text(reason).font(PofudukFont.caption).foregroundStyle(PofudukColor.inkSecondary)
                    Link(destination: page) {
                        Label("Resmi uyarıları mgm.gov.tr'de kontrol et", systemImage: "arrow.up.right.square")
                            .font(PofudukFont.caption.weight(.semibold))
                    }
                case .available(let list)? where list.isEmpty:
                    Text("Bölgen için yürürlükte resmi uyarı yok.").font(PofudukFont.caption).foregroundStyle(PofudukColor.inkSecondary)
                case .available?:
                    Text("Yürürlükte resmi uyarı var, yukarıdaki bildirime bak.").font(PofudukFont.caption).foregroundStyle(PofudukColor.ink)
                case nil:
                    Text("Kontrol ediliyor…").font(PofudukFont.caption).foregroundStyle(PofudukColor.inkSecondary)
                }
            }
        }
    }
}

extension WarningLevel {
    /// Distinct shape per level, so severity never depends on colour alone.
    var symbolName: String {
        switch self {
        case .green: return "checkmark.circle.fill"
        case .yellow: return "exclamationmark.circle.fill"
        case .orange: return "exclamationmark.triangle.fill"
        case .red: return "exclamationmark.octagon.fill"
        }
    }
    var label: String { "MGM \(turkishName.uppercased(with: Locale(identifier: "tr_TR"))) UYARI" }
}

struct OfficialWarningBanner: View {
    let warning: OfficialWarning
    var extraCount = 0
    let onDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(warning.level.label, systemImage: warning.level.symbolName)
                .font(PofudukFont.headline)
            Text(warning.hazard).font(PofudukFont.body.weight(.semibold))
            Text("Geçerlilik: \(WarningDetailView.validity(warning))").font(PofudukFont.caption)
            if extraCount > 0 { Text("+\(extraCount) uyarı daha").font(PofudukFont.caption) }
            Button("Ayrıntılar ve resmi kaynak", action: onDetails).font(PofudukFont.caption.weight(.semibold))
        }
        .foregroundStyle(PofudukColor.ink)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PofudukColor.warning(warning.level).opacity(0.25), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(PofudukColor.warning(warning.level), lineWidth: 2))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(warning.level.label). \(warning.hazard). Geçerlilik \(WarningDetailView.validity(warning)).")
        .accessibilityAddTraits(.isHeader)
    }
}

/// Full official warning details. Clearly separated from Pofuduk's own forecasts.
struct WarningDetailView: View {
    let warnings: [OfficialWarning]
    @Environment(\.dismiss) private var dismiss

    static func validity(_ w: OfficialWarning) -> String {
        let tz = TimeZone(identifier: "Europe/Istanbul") ?? .current
        func f(_ d: Date) -> String { "\(TurkishFormatting.longDate(d, timeZone: tz)) \(TurkishFormatting.clockTime(d, timeZone: tz))" }
        return "\(f(w.validFrom)) – \(f(w.validUntil))"
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(warnings) { w in
                    Section {
                        Label(w.level.label, systemImage: w.level.symbolName)
                            .font(PofudukFont.headline)
                            .foregroundStyle(PofudukColor.ink)
                            .listRowBackground(PofudukColor.warning(w.level).opacity(0.25))
                        LabeledContent("Tehlike", value: w.hazard)
                        LabeledContent("Etkilenen bölge", value: (w.provinces + w.districts).joined(separator: ", "))
                        LabeledContent("Başlangıç", value: Self.validity(w).components(separatedBy: " – ").first ?? "")
                        LabeledContent("Bitiş", value: Self.validity(w).components(separatedBy: " – ").last ?? "")
                        if !w.description.isEmpty { Text(w.description) }
                        Link(destination: w.sourceURL) { Label("Resmi kaynak: MGM", systemImage: "arrow.up.right.square") }
                    }
                }
                Section {
                    Text("Bu uyarılar Meteoroloji Genel Müdürlüğü'nün resmi kaynağından alınır. Pofuduk'un kendi hava tahminleri resmi uyarı değildir ve hiçbir zaman uyarıya dönüştürülmez.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Resmi Uyarılar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Kapat") { dismiss() } } }
        }
    }
}

#Preview("Uyarı bandı (örnek, yalnızca önizleme)") {
    OfficialWarningBanner(warning: OfficialWarning(
        id: "preview", level: .orange, hazard: "Kuvvetli yağış", description: "Önizleme amaçlı örnek.",
        provinces: ["İstanbul"], validFrom: Date(), validUntil: Date().addingTimeInterval(6 * 3600),
        sourceURL: MGMOfficialPage.warnings)) {}
        .padding()
}

struct DemoScenarioPicker: View {
    let selected: MockWeatherData.Scenario
    let onSelect: (MockWeatherData.Scenario) -> Void

    private func title(_ s: MockWeatherData.Scenario) -> String {
        switch s {
        case .sunny: return "Güneşli"
        case .rainyAfternoon: return "Yağmurlu"
        case .stormy: return "Fırtına"
        case .snowy: return "Karlı"
        case .cloudy: return "Bulutlu"
        case .windy: return "Rüzgârlı"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Demo: hava senaryosu seç").font(PofudukFont.caption).foregroundStyle(PofudukColor.inkSecondary)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(MockWeatherData.Scenario.allCases, id: \.self) { s in
                        Button { onSelect(s) } label: {
                            Text(title(s))
                                .font(PofudukFont.caption.weight(.semibold))
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(s == selected ? AnyShapeStyle(PofudukColor.accent) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
                                .foregroundStyle(s == selected ? Color.white : PofudukColor.ink)
                        }
                        .accessibilityAddTraits(s == selected ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RetryCard: View {
    let reason: String
    let action: () -> Void

    var body: some View {
        SoftCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Hava durumu alınamadı", systemImage: "wifi.exclamationmark")
                        .font(PofudukFont.headline).foregroundStyle(PofudukColor.ink)
                    Text(reason).font(PofudukFont.caption).foregroundStyle(PofudukColor.inkSecondary)
                }
                Spacer()
                Button("Tekrar dene", action: action)
                    .font(PofudukFont.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(PofudukColor.accent)
            }
        }
    }
}

/// Provider attribution (required by WeatherAPI terms and Open-Meteo's CC BY 4.0) + freshness.
struct SourceFooter: View {
    let snapshot: WeatherSnapshot?
    let isStale: Bool

    private func sourceLink(_ source: WeatherDataSource) -> URL? {
        switch source {
        case .weatherAPI: return URL(string: "https://www.weatherapi.com/")
        case .openMeteo: return URL(string: "https://open-meteo.com/")
        case .demo: return nil
        }
    }

    var body: some View {
        if let snapshot {
            VStack(spacing: 4) {
                if let url = sourceLink(snapshot.source) {
                    Link(destination: url) {
                        Text(snapshot.source == .weatherAPI ? "Powered by WeatherAPI.com" : "Hava verisi: Open-Meteo.com (CC BY 4.0)")
                            .underline()
                    }
                } else {
                    Text("Kaynak: \(snapshot.source.attribution)")
                }
                Text("Güncelleme \(TurkishFormatting.clockTime(snapshot.retrievedAt, timeZone: snapshot.place.timeZone))")
                if isStale {
                    Label("Veriler güncel olmayabilir", systemImage: "clock.badge.exclamationmark")
                }
                if snapshot.source != .demo {
                    Text("Tahminler bilgilendirme amaçlıdır ve kesinlik garanti edilmez.")
                }
            }
            .font(PofudukFont.caption)
            .foregroundStyle(PofudukColor.inkSecondary)
            .multilineTextAlignment(.center)
        }
    }
}
