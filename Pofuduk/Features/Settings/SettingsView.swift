import SwiftUI
import PofudukCore

/// Central settings (spec §21). Everything is stored on this device only.
struct SettingsView: View {
    @Bindable var viewModel: HomeViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    private var prefs: UserPreferences { viewModel.preferences }

    var body: some View {
        NavigationStack {
            Form {
                Section("Pofuduk") {
                    Picker("Konuşma tarzı", selection: Binding(get: { prefs.style }, set: { v in viewModel.updatePreferences { $0.style = v } })) {
                        ForEach(PersonalityStyle.allCases, id: \.self) { Text($0.turkishName).tag($0) }
                    }
                    Picker("Anlatım", selection: Binding(get: { prefs.briefingLength }, set: { v in viewModel.updatePreferences { $0.briefingLength = v } })) {
                        ForEach(BriefingLength.allCases, id: \.self) { Text($0.turkishName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    NavigationLink("Pofuduk Günaydın") {
                        MorningBriefingSettingsView(coordinator: viewModel.notifications,
                                                    placeName: viewModel.snapshot?.place.displayName,
                                                    onChangeLocation: changeLocation)
                    }
                }

                Section {
                    Toggle("Ses", isOn: Binding(get: { viewModel.isSoundOn }, set: { _ in viewModel.toggleSound() }))
                    if viewModel.availableVoices.isEmpty {
                        Text("Türkçe ses yüklü değil. iOS Ayarları › Erişilebilirlik › Seslendirilen İçerik › Sesler › Türkçe bölümünden yükleyebilirsin. O zamana kadar altyazılar gösterilir.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Picker("Türkçe ses", selection: Binding(get: { prefs.voiceIdentifier }, set: { v in viewModel.updatePreferences { $0.voiceIdentifier = v } })) {
                            Text("Otomatik (en iyi kalite)").tag(String?.none)
                            ForEach(viewModel.availableVoices) { v in Text("\(v.name) · \(v.qualityName)").tag(Optional(v.id)) }
                        }
                    }
                    VStack(alignment: .leading) {
                        Text("Konuşma hızı")
                        Slider(value: Binding(get: { prefs.speechRateMultiplier }, set: { v in viewModel.updatePreferences { $0.speechRateMultiplier = v } }),
                               in: UserPreferences.speechRateRange, step: 0.05) {
                            Text("Konuşma hızı")
                        } minimumValueLabel: { Image(systemName: "tortoise") } maximumValueLabel: { Image(systemName: "hare") }
                    }
                    Button("Sesi dene") { viewModel.previewVoice() }
                        .disabled(!viewModel.isSoundOn || viewModel.availableVoices.isEmpty)
                } header: { Text("Ses") }

                Section {
                    Picker("Altyazı boyutu", selection: Binding(get: { prefs.subtitleSize }, set: { v in viewModel.updatePreferences { $0.subtitleSize = v } })) {
                        ForEach(SubtitleSize.allCases, id: \.self) { Text($0.turkishName).tag($0) }
                    }
                    Text("Pofuduk böyle konuşur.")
                        .font(SubtitleBubble.font(for: prefs.subtitleSize))
                        .foregroundStyle(PofudukColor.ink)
                } header: { Text("Altyazılar") } footer: {
                    Text("Altyazılar her zaman açıktır ve iOS yazı boyutu ayarıyla birlikte büyür.")
                }

                Section("Konum") {
                    HStack {
                        Text(viewModel.snapshot?.place.displayName ?? "Seçilmedi")
                        if viewModel.isApproximateLocation { Text("(yaklaşık)").foregroundStyle(.secondary) }
                        Spacer()
                        Button("Değiştir", action: changeLocation)
                    }
                }

                Section {
                    NavigationLink("Bildirimler") {
                        NotificationSettingsView(coordinator: viewModel.notifications,
                                                 placeName: viewModel.snapshot?.place.displayName,
                                                 onChangeLocation: changeLocation)
                    }
                }

                Section("Birimler ve dil") {
                    LabeledContent("Sıcaklık", value: "Santigrat (°C)")
                    LabeledContent("Rüzgâr", value: "km/sa")
                    LabeledContent("Dil", value: "Türkçe")
                }

                Section("Veri kaynakları") {
                    Link("Hava verisi: Open-Meteo.com (CC BY 4.0)", destination: URL(string: "https://open-meteo.com/")!)
                    Link("Hava verisi: WeatherAPI.com (anahtar yapılandırıldığında)", destination: URL(string: "https://www.weatherapi.com/")!)
                    Link("Anlık durum doğrulaması: Apple Weather", destination: AppleWeatherAttributionView.legalPage)
                    Link("Resmi uyarılar: MGM (mgm.gov.tr)", destination: MGMOfficialPage.warnings)
                    Text("Pofuduk'un hava tahminleri resmi uyarı değildir.").font(.footnote).foregroundStyle(.secondary)
                }

                Section {
                    Text("Konumun yalnızca uygulama açıkken ve sadece hava durumu için kullanılır; takip edilmez, satılmaz, paylaşılmaz. Mikrofon yalnızca sen düğmeye bastığında açılır. Tüm tercihler bu cihazda saklanır; hesap gerekmez.")
                        .font(.footnote)
                    Button("Verilerimi sil", role: .destructive) { confirmDelete = true }
                } header: { Text("Gizlilik") }

                Section("Hakkında") {
                    LabeledContent("Sürüm", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")
                    Text("Pofuduk, hava durumunu Türkçe anlatan sevimli bir bulut arkadaş.").font(.footnote)
                }
            }
            .navigationTitle("Ayarlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
            .confirmationDialog("Tüm verilerin silinsin mi?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Verilerimi sil", role: .destructive) { Task { await viewModel.deleteAllData() } }
            } message: {
                Text("Kayıtlı konum, önbellekteki tahminler, bildirim ve günaydın ayarları, kişiselleştirme ve sohbet geçmişi silinir. Bekleyen bildirimler iptal edilir.")
            }
        }
    }

    private func changeLocation() {
        viewModel.showSettings = false
        viewModel.chooseCityInstead()
    }
}
