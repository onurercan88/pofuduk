import SwiftUI
import PofudukCore

struct HomeHeader: View {
    let viewModel: HomeViewModel

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                if let place = viewModel.snapshot?.place {
                    Label(place.displayName, systemImage: "location.fill")
                        .font(PofudukFont.title)
                        .foregroundStyle(PofudukColor.ink)
                        .labelStyle(.titleAndIcon)
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
            }
            Spacer()
            RoundIconButton(systemImage: viewModel.isSoundOn ? "speaker.wave.2.fill" : "speaker.slash.fill",
                            label: viewModel.isSoundOn ? "Sesi kapat" : "Sesi aç") {
                viewModel.toggleSound()
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

struct OfficialWarningBanner: View {
    let warning: OfficialWarning

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("MGM \(warning.level.turkishName.uppercased(with: Locale(identifier: "tr_TR"))) UYARI", systemImage: "exclamationmark.triangle.fill")
                .font(PofudukFont.headline)
            Text(warning.hazard).font(PofudukFont.body.weight(.semibold))
            if !warning.description.isEmpty { Text(warning.description).font(PofudukFont.caption) }
            Link("Resmi kaynağı aç", destination: warning.sourceURL).font(PofudukFont.caption.weight(.semibold))
        }
        .foregroundStyle(PofudukColor.ink)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PofudukColor.warning(warning.level).opacity(0.25), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(PofudukColor.warning(warning.level), lineWidth: 2))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
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

struct SourceFooter: View {
    let snapshot: WeatherSnapshot?
    let isStale: Bool

    var body: some View {
        if let snapshot {
            VStack(spacing: 4) {
                Text("Kaynak: \(snapshot.source.attribution) · Güncelleme \(TurkishFormatting.clockTime(snapshot.retrievedAt, timeZone: snapshot.place.timeZone))")
                if isStale {
                    Label("Veriler güncel olmayabilir", systemImage: "clock.badge.exclamationmark")
                }
            }
            .font(PofudukFont.caption)
            .foregroundStyle(PofudukColor.inkSecondary)
            .multilineTextAlignment(.center)
        }
    }
}
