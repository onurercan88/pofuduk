import Foundation

/// Selects the official warnings that apply to a place right now.
/// Green means "no warning" and is never shown as one.
public struct WeatherAlertMatcher: Sendable {
    public init() {}

    public func matching(_ warnings: [OfficialWarning], place: Place, at date: Date) -> [OfficialWarning] {
        let province = TurkishProvinces.normalize(place.province ?? place.name)
        let district = place.district.map(TurkishProvinces.normalize)
        return warnings
            .filter { $0.isActive(at: date) && $0.level >= .yellow }
            .filter { w in
                guard w.provinces.map(TurkishProvinces.normalize).contains(province) else { return false }
                // A district-specific warning only matches when we know the user's district and it's listed.
                guard !w.districts.isEmpty, let district else { return true }
                return w.districts.map(TurkishProvinces.normalize).contains(district)
            }
            .sorted { $0.level > $1.level }
    }
}

/// Official MGM page shown whenever automated warnings are unavailable (verified 2026-11-14).
public enum MGMOfficialPage {
    public static let warnings = URL(string: "https://www.mgm.gov.tr/meteouyari/turkiye.aspx")!
}

/// MGM provider. MGM publishes no documented public warning API/feed (checked 2026-11-14) and its
/// legal notice forbids reuse without prior permission. So this provider stays *unavailable* unless a
/// feed URL obtained through written authorization is configured. Never scrapes pages.
public struct ConfiguredMGMWarningProvider: MGMWarningProvider {
    private let feedURL: URL?
    private let http: HTTPClient

    public init(feedURL: URL?, http: HTTPClient) {
        self.feedURL = feedURL
        self.http = http
    }

    public static let unavailableReason = "MGM resmi uyarıları için yetkili bir veri bağlantısı henüz yok."

    public func warnings() async -> WarningAvailability {
        guard let feedURL else {
            return .unavailable(reason: Self.unavailableReason, officialPage: MGMOfficialPage.warnings)
        }
        guard let response = try? await http.get(feedURL), response.statusCode == 200,
              let warnings = CAPWarningParser.parse(response.data) else {
            return .unavailable(reason: "MGM uyarılarına şu an ulaşılamadı.", officialPage: MGMOfficialPage.warnings)
        }
        return .available(warnings)
    }
}

/// Spec: IWeatherAlertRepository — provider + matching for a place.
public struct MGMAlertRepository: WeatherAlertRepository {
    private let provider: MGMWarningProvider
    private let matcher = WeatherAlertMatcher()

    public init(provider: MGMWarningProvider) {
        self.provider = provider
    }

    public func warnings(for place: Place, at date: Date) async -> WarningAvailability {
        switch await provider.warnings() {
        case .available(let all): return .available(matcher.matching(all, place: place, at: date))
        case .unavailable(let reason, let page): return .unavailable(reason: reason, officialPage: page)
        }
    }
}
