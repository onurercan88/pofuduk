import SwiftUI
import PofudukCore

/// Home card: "Bugün Ne Giysem?"
struct ClothingCard: View {
    let recommendation: ClothingRecommendation
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            SoftCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Bugün Ne Giysem?").font(PofudukFont.headline).foregroundStyle(PofudukColor.ink)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(PofudukColor.inkSecondary)
                    }
                    HStack(spacing: 6) {
                        ForEach(recommendation.items.prefix(5)) { item in
                            Text(item.symbol).font(.title2).accessibilityHidden(true)
                        }
                    }
                    Text(recommendation.briefingSentence)
                        .font(PofudukFont.body).foregroundStyle(PofudukColor.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .buttonStyle(SquishButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Ayrıntılı kıyafet önerisini aç")
    }
}

/// Detailed clothing screen with today/tomorrow, items and the reasons behind them.
struct ClothingDetailView: View {
    let theme: WeatherTheme
    let recommendationFor: (Int) -> ClothingRecommendation?
    let onSpeak: (ClothingRecommendation) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var dayOffset = 0

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Picker("Gün", selection: $dayOffset) {
                        Text("Bugün").tag(0)
                        Text("Yarın").tag(1)
                    }
                    .pickerStyle(.segmented)

                    if let rec = recommendationFor(dayOffset) {
                        let layout = typeSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
                        layout {
                            CharacterView(appearance: CharacterAppearance(mood: .happy, theme: theme), size: 90,
                                          effectsBleed: false)
                                .frame(width: 110, height: 110)
                            Text(rec.summary)
                                .font(PofudukFont.body).foregroundStyle(PofudukColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                            ForEach(rec.items) { item in
                                HStack(spacing: 10) {
                                    Text(item.symbol).font(.title).accessibilityHidden(true)
                                    Text(item.name).font(PofudukFont.body).foregroundStyle(PofudukColor.ink)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(PofudukColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .accessibilityElement(children: .combine)
                            }
                        }

                        SoftCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Neden bu öneri?", systemImage: "questionmark.bubble")
                                    .font(PofudukFont.headline).foregroundStyle(PofudukColor.ink)
                                ForEach(rec.reasons, id: \.self) { reason in
                                    Text("• \(reason)").font(PofudukFont.body).foregroundStyle(PofudukColor.ink)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }

                        Button { onSpeak(rec); dismiss() } label: {
                            Label("Pofuduk anlatsın", systemImage: "speaker.wave.2.fill")
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent).tint(PofudukColor.accent).clipShape(Capsule())
                    } else {
                        Text("Bu gün için saatlik tahmin henüz yok, bu yüzden kıyafet önerisi veremiyorum.")
                            .font(PofudukFont.body).foregroundStyle(PofudukColor.inkSecondary)
                    }

                    Text("Öneriler yalnızca hava tahminine dayanır; kendi ihtiyaçlarına ve sağlık durumuna göre karar vermeyi unutma.")
                        .font(PofudukFont.caption).foregroundStyle(PofudukColor.inkSecondary)
                }
                .padding(20)
            }
            .navigationTitle("Bugün Ne Giysem?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Kapat") { dismiss() } } }
        }
    }
}
