import SwiftUI
import PofudukCore

/// "Pofuduk Günaydın" settings.
struct MorningBriefingSettingsView: View {
    let coordinator: NotificationCoordinator
    let placeName: String?
    let onChangeLocation: () -> Void

    private var settings: MorningBriefingSettings { coordinator.morning }

    var body: some View {
        Form {
            Section {
                Toggle("Pofuduk Günaydın", isOn: binding(\.isEnabled))
            } footer: {
                Text("Seçtiğin saatten öğlene kadar uygulamayı ilk açtığında Pofuduk günün havasını anlatır.")
            }

            if settings.isEnabled {
                Section("Saat") {
                    Picker("Günaydın saati", selection: presetBinding) {
                        ForEach(MorningBriefingSettings.presets, id: \.self) { Text(Self.format($0)).tag(Optional($0)) }
                        Text("Özel").tag(Optional<Int>.none)
                    }
                    if !MorningBriefingSettings.presets.contains(settings.minuteOfDay) {
                        DatePicker("Özel saat", selection: timeBinding, displayedComponents: .hourAndMinute)
                    }
                }

                Section {
                    Toggle("Otomatik konuşsun", isOn: binding(\.speaksAutomatically))
                    Toggle("Bildirim olarak da gönder", isOn: Binding(
                        get: { settings.sendsNotification },
                        set: { on in Task { await coordinator.setMorningNotification(on) } }))
                    if coordinator.permission == .denied {
                        Text("Bildirim izni kapalı; bildirim gönderilemez.").font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Nasıl anlatsın?")
                } footer: {
                    Text("Otomatik konuşma kapalıysa ya da ses kapalıysa günaydın mesajı yazı olarak gösterilir. Bildirim, seçtiğin saatte gelir ve sessiz saatlerden etkilenmez; o anki en son tahmine göre hazırlanır.")
                }

                Section("Konum") {
                    HStack {
                        Text(placeName ?? "Henüz seçilmedi")
                        Spacer()
                        Button("Değiştir", action: onChangeLocation)
                    }
                }
            }
        }
        .navigationTitle("Pofuduk Günaydın")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func binding(_ keyPath: WritableKeyPath<MorningBriefingSettings, Bool>) -> Binding<Bool> {
        Binding(get: { settings[keyPath: keyPath] },
                set: { v in Task { await coordinator.updateMorning { $0[keyPath: keyPath] = v } } })
    }

    /// nil = custom time.
    private var presetBinding: Binding<Int?> {
        Binding(
            get: { MorningBriefingSettings.presets.contains(settings.minuteOfDay) ? settings.minuteOfDay : nil },
            set: { v in
                // Choosing "Özel" keeps the time but nudges it off the presets so the picker appears.
                let minute = v ?? (settings.minuteOfDay + 5)
                Task { await coordinator.updateMorning { $0.minuteOfDay = minute } }
            })
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: settings.minuteOfDay / 60, minute: settings.minuteOfDay % 60, second: 0, of: Date()) ?? Date() },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                let m = (c.hour ?? 7) * 60 + (c.minute ?? 0)
                Task { await coordinator.updateMorning { $0.minuteOfDay = m } }
            })
    }

    static func format(_ minute: Int) -> String { String(format: "%02d.%02d", minute / 60, minute % 60) }
}
