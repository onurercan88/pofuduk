import SwiftUI
import UIKit
import PofudukCore

/// "Yağmur Başlamadan Haber Ver" and other notification preferences. Honest about iOS limits.
struct NotificationSettingsView: View {
    let coordinator: NotificationCoordinator
    var placeName: String?
    var onChangeLocation: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    private let configurable: [NotificationCategory] = [.rainSoon, .heavyRain, .severeWeather, .strongWind, .temperatureChange, .mgmWarning]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        MorningBriefingSettingsView(coordinator: coordinator, placeName: placeName, onChangeLocation: onChangeLocation)
                    } label: {
                        HStack {
                            Label("Pofuduk Günaydın", systemImage: "sun.horizon.fill")
                            Spacer()
                            Text(coordinator.morning.isEnabled ? MorningBriefingSettingsView.format(coordinator.morning.minuteOfDay) : "Kapalı")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Toggle("Hava bildirimleri", isOn: Binding(
                        get: { coordinator.preferences.isEnabled },
                        set: { value in Task { await coordinator.setEnabled(value) } }))
                    if coordinator.permission == .denied {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Bildirim izni kapalı. Açmak için iOS Ayarları'nı kullanabilirsin.")
                                .font(.footnote).foregroundStyle(.secondary)
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                Link("Ayarları aç", destination: url).font(.footnote.weight(.semibold))
                            }
                        }
                    }
                } footer: {
                    Text("Pofuduk yalnızca senin açtığın bildirim türlerini gönderir.")
                }

                if coordinator.preferences.isEnabled {
                    Section("Bildirim türleri") {
                        ForEach(configurable, id: \.self) { category in
                            Toggle(category.turkishName, isOn: Binding(
                                get: { coordinator.preferences.enabledCategories.contains(category) },
                                set: { on in Task { await coordinator.update { if on { $0.enabledCategories.insert(category) } else { $0.enabledCategories.remove(category) } } } }))
                        }
                    }

                    Section("Yağmur başlamadan haber ver") {
                        Picker("Ne kadar önce", selection: Binding(
                            get: { coordinator.preferences.rainLeadMinutes },
                            set: { v in Task { await coordinator.update { $0.rainLeadMinutes = v } } })) {
                            ForEach([15, 30, 45, 60], id: \.self) { Text("\($0) dakika").tag($0) }
                        }
                        Stepper("Yağış olasılığı en az %\(coordinator.preferences.rainProbabilityThreshold)",
                                value: Binding(
                                    get: { coordinator.preferences.rainProbabilityThreshold },
                                    set: { v in Task { await coordinator.update { $0.rainProbabilityThreshold = v } } }),
                                in: 40...90, step: 10)
                    }

                    Section {
                        Toggle("Sessiz saatler", isOn: Binding(
                            get: { coordinator.preferences.quietHours.enabled },
                            set: { v in Task { await coordinator.update { $0.quietHours.enabled = v } } }))
                        if coordinator.preferences.quietHours.enabled {
                            DatePicker("Başlangıç", selection: minuteBinding(\.startMinute), displayedComponents: .hourAndMinute)
                            DatePicker("Bitiş", selection: minuteBinding(\.endMinute), displayedComponents: .hourAndMinute)
                        }
                    } footer: {
                        Text("Sessiz saatlerde yalnızca turuncu ve kırmızı seviyedeki resmi MGM uyarıları gönderilir.")
                    }

                    if !coordinator.lastPlanned.isEmpty {
                        Section("Planlanan bildirimler") {
                            ForEach(coordinator.lastPlanned) { n in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(n.title).font(.subheadline.weight(.semibold))
                                    Text(n.fireDate, style: .time).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("Nasıl çalışır?") {
                    Text("Bildirimler cihazındaki en son hava tahminine göre planlanır. iOS, uygulamanın arka planda ne zaman güncelleneceğine kendisi karar verir; bu yüzden bildirim zamanı garanti değildir. Tahmin eskiyse bildirim gönderilmez.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Bildirimler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
            .task { await coordinator.refreshPermission() }
        }
    }

    /// Binds a minute-of-day preference to a DatePicker (today's date, local time).
    private func minuteBinding(_ keyPath: WritableKeyPath<QuietHours, Int>) -> Binding<Date> {
        Binding(
            get: {
                let m = coordinator.preferences.quietHours[keyPath: keyPath]
                return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                let minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
                Task { await coordinator.update { $0.quietHours[keyPath: keyPath] = minutes } }
            })
    }
}
