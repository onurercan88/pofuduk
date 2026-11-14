import SwiftUI
import UIKit
import PofudukCore

/// Pofuduk explains why location helps BEFORE the system prompt, and always offers alternatives.
struct LocationPermissionSheet: View {
    let prompt: HomeViewModel.LocationPrompt
    let isIPAvailable: Bool
    let onAllow: () -> Void
    let onChooseCity: () -> Void
    let onApproximate: () -> Void

    private var message: String {
        switch prompt {
        case .explanation:
            return "Bulunduğun yerin havasını anlatabilmem için konumuna ihtiyacım var. Konumunu yalnızca uygulama açıkken ve sadece hava durumu için kullanırım. Seni takip etmem, kimseyle paylaşmam."
        case .issue(let issue):
            return issue.turkishExplanation
        }
    }

    private var isDenied: Bool {
        if case .issue(let i) = prompt { return i == .permissionDenied || i == .servicesDisabled }
        return false
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                CharacterView(appearance: CharacterAppearance(mood: .listening, theme: .cloudy), size: 140)
                    .frame(height: 170)
                Text(prompt == .explanation ? "Neredesin?" : "Konumunu bulamadım")
                    .font(PofudukFont.title).foregroundStyle(PofudukColor.ink)
                Text(message)
                    .font(PofudukFont.body).foregroundStyle(PofudukColor.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 12) {
                    if !isDenied {
                        primaryButton(prompt == .explanation ? "Konumumu kullan" : "Tekrar dene", "location.fill", onAllow)
                    } else if let url = URL(string: UIApplication.openSettingsURLString) {
                        Link(destination: url) {
                            Label("Ayarlardan izin ver", systemImage: "gearshape.fill")
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent).tint(PofudukColor.accent)
                        .clipShape(Capsule())
                    }
                    secondaryButton("Şehir veya ilçe seç", "building.2.fill", onChooseCity)
                    if isIPAvailable {
                        VStack(spacing: 4) {
                            secondaryButton("Yaklaşık konumumu kullan", "network", onApproximate)
                            Text("İnternet bağlantına göre şehir düzeyinde tahmin edilir; GPS kadar hassas değildir.")
                                .font(PofudukFont.caption).foregroundStyle(PofudukColor.inkSecondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
            }
            .padding(24)
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(prompt == .explanation)
    }

    private func primaryButton(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(PofudukFont.headline)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent).tint(PofudukColor.accent).clipShape(Capsule())
    }

    private func secondaryButton(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(PofudukFont.headline)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
        }
        .buttonStyle(.bordered).tint(PofudukColor.accent).clipShape(Capsule())
    }
}

/// Province list (offline) + district/city search (Apple geocoding).
struct LocationPickerView: View {
    let isIPAvailable: Bool
    let onSelect: (Place) -> Void
    let onUseDevice: () -> Void
    let onApproximate: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var searchResults: [Place] = []
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { onUseDevice() } label: { Label("Konumumu kullan", systemImage: "location.fill") }
                    if isIPAvailable {
                        Button { onApproximate() } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Label("Yaklaşık konumumu kullan", systemImage: "network")
                                Text("Şehir düzeyinde, GPS kadar hassas değil").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if query.count >= 2 {
                    Section("İlçe ve şehir sonuçları") {
                        if isSearching { ProgressView() }
                        ForEach(searchResults, id: \.self) { place in
                            Button { onSelect(place) } label: {
                                VStack(alignment: .leading) {
                                    Text(place.district ?? place.name).foregroundStyle(PofudukColor.ink)
                                    if let province = place.province, province != place.district {
                                        Text(province).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        if !isSearching && searchResults.isEmpty {
                            Text("Sonuç bulunamadı").foregroundStyle(.secondary)
                        }
                    }
                }
                Section("İller") {
                    ForEach(TurkishProvinces.search(query)) { province in
                        Button { onSelect(province.place) } label: {
                            HStack {
                                Text(province.name).foregroundStyle(PofudukColor.ink)
                                Spacer()
                                Text(String(format: "%02d", province.plate)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "İl veya ilçe ara")
            .task(id: query) { await search() }
            .navigationTitle("Konum seç")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } } }
        }
    }

    private func search() async {
        guard query.count >= 2 else { searchResults = []; return }
        isSearching = true
        try? await Task.sleep(for: .milliseconds(350)) // debounce; cancelled when query changes
        guard !Task.isCancelled else { return }
        searchResults = await PlaceSearch.search(query)
        isSearching = false
    }
}
