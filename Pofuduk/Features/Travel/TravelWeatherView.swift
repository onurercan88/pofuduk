import SwiftUI
import PofudukCore

/// Home entry card.
struct TravelCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SoftCard {
                HStack(spacing: 12) {
                    Text("🧳").font(.title).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Seyahat Hava Durumu").font(PofudukFont.headline).foregroundStyle(PofudukColor.ink)
                        Text("Gideceğin yerin havasını öğren").font(PofudukFont.caption).foregroundStyle(PofudukColor.inkSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(PofudukColor.inkSecondary)
                }
            }
        }
        .buttonStyle(SquishButtonStyle())
    }
}

/// "Seyahat Hava Durumu": destination search, dates, comparison and summary.
struct TravelWeatherView: View {
    @Bindable var viewModel: TravelWeatherViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Nereye?") {
                    TextField("Şehir veya ilçe", text: $viewModel.query)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                    if viewModel.isSearching { ProgressView() }
                    ForEach(viewModel.candidates, id: \.self) { place in
                        Button { viewModel.select(place) } label: {
                            VStack(alignment: .leading) {
                                Text(place.district ?? place.name).foregroundStyle(PofudukColor.ink)
                                if let p = place.province, p != place.district { Text(p).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                .task(id: viewModel.query) { await viewModel.search() }

                Section("Ne zaman?") {
                    DatePicker("Gidiş", selection: $viewModel.departure, in: viewModel.minimumDate..., displayedComponents: .date)
                    Toggle("Dönüş tarihi", isOn: $viewModel.hasReturn)
                    if viewModel.hasReturn {
                        DatePicker("Dönüş", selection: $viewModel.returnDate, in: viewModel.departure..., displayedComponents: .date)
                    }
                }

                Section {
                    Button {
                        Task { await viewModel.show() }
                    } label: {
                        HStack {
                            Spacer()
                            if viewModel.isLoading { ProgressView() } else { Text("Hava durumunu göster").bold() }
                            Spacer()
                        }
                    }
                    .disabled(!viewModel.canShow)
                }

                if let error = viewModel.errorMessage {
                    Section { Text(error).foregroundStyle(.secondary) }
                }

                if let summary = viewModel.summary {
                    Section {
                        HStack(alignment: .top, spacing: 12) {
                            CharacterView(appearance: CharacterAppearance(mood: .happy, theme: summary.briefing.theme), size: 70)
                                .frame(width: 84, height: 84)
                            Text(summary.briefing.fullText).font(PofudukFont.body).foregroundStyle(PofudukColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button { viewModel.speak(); dismiss() } label: {
                            Label("Pofuduk anlatsın", systemImage: "speaker.wave.2.fill")
                        }
                    }

                    if !summary.days.isEmpty {
                        Section("Günlük") {
                            ForEach(summary.days) { day in
                                TravelDayRow(day: day, timeZone: summary.destination.timeZone, originName: summary.origin?.name)
                            }
                        }
                    }
                    if !summary.packing.isEmpty {
                        Section("Yanına al") {
                            ForEach(summary.packing) { item in
                                Label { Text(item.name) } icon: { Text(item.symbol) }
                            }
                        }
                    }
                }

                Section {
                    Text("Yol ve trafik durumu bilgisi verilmez; yalnızca hava tahmini gösterilir. Tahminler yerel saate göredir.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Seyahat Hava Durumu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Kapat") { dismiss() } } }
        }
    }
}

struct TravelDayRow: View {
    let day: TravelDayForecast
    let timeZone: TimeZone
    let originName: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: day.condition.symbolName()).symbolRenderingMode(.multicolor).font(.title3).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(TurkishFormatting.longDate(day.date, timeZone: timeZone)).font(.subheadline.weight(.semibold))
                if let originMax = day.originMaxTemperature, let originName {
                    Text("\(originName): en yüksek \(TurkishFormatting.shortTemperature(originMax))").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(TurkishFormatting.shortTemperature(day.maxTemperature)) / \(TurkishFormatting.shortTemperature(day.minTemperature))")
                if let p = day.precipitationProbability, p >= 20 {
                    Label("%\(p)", systemImage: "drop.fill").font(.caption).foregroundStyle(PofudukColor.accent)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
