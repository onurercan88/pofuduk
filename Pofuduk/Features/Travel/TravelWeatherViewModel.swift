import Foundation
import Observation
import PofudukCore

@MainActor
@Observable
final class TravelWeatherViewModel {
    var query = ""
    private(set) var candidates: [Place] = []
    private(set) var isSearching = false
    var destination: Place?
    var departure: Date
    var hasReturn = false
    var returnDate: Date
    private(set) var summary: TravelSummary?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    @ObservationIgnored var origin: () -> Place? = { nil }
    @ObservationIgnored var demoScenario: () -> MockWeatherData.Scenario? = { nil }
    @ObservationIgnored var onSpeak: (Briefing) -> Void = { _ in }
    @ObservationIgnored private let service: TravelWeatherService
    @ObservationIgnored private let now: () -> Date

    init(service: TravelWeatherService, now: @escaping () -> Date) {
        self.service = service
        self.now = now
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now()) ?? now()
        self.departure = tomorrow
        self.returnDate = Calendar.current.date(byAdding: .day, value: 2, to: now()) ?? tomorrow
    }

    var canShow: Bool { destination != nil && !isLoading }
    var minimumDate: Date { Calendar.current.startOfDay(for: now()) }

    @ObservationIgnored private var selectedLabel: String?

    func search() async {
        if query == selectedLabel { return }        // text was set by selecting a candidate
        if destination != nil { destination = nil; summary = nil }   // user is typing a new destination
        guard query.trimmingCharacters(in: .whitespaces).count >= 2 else { candidates = []; return }
        isSearching = true
        try? await Task.sleep(for: .milliseconds(350))   // debounce; cancelled when query changes
        guard !Task.isCancelled else { return }
        candidates = await DestinationResolver.candidates(for: query)
        isSearching = false
    }

    func select(_ place: Place) {
        destination = place
        query = place.district.map { $0 == place.name ? place.name : "\($0), \(place.name)" } ?? place.name
        selectedLabel = query
        candidates = []
        summary = nil
    }

    func show() async {
        guard let destination else { return }
        isLoading = true
        errorMessage = nil
        let result = await service.summary(destination: destination, departure: departure,
                                           returnDate: hasReturn ? max(returnDate, departure) : nil,
                                           origin: origin(), demoScenario: demoScenario())
        isLoading = false
        switch result {
        case .success(let s): summary = s
        case .failure(let e): summary = nil; errorMessage = e.turkishExplanation
        }
    }

    func speak() {
        if let summary { onSpeak(summary.briefing) }
    }
}
