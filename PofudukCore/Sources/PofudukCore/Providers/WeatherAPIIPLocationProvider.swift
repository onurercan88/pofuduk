import Foundation

/// Approximate, IP-based city lookup via WeatherAPI `ip.json`. Used ONLY after the user explicitly
/// chooses "Yaklaşık konum". City-level accuracy at best — never presented as GPS.
public struct WeatherAPIIPLocationProvider: LocationProvider {
    private let http: HTTPClient
    private let apiKey: @Sendable () -> String?
    private let baseURL: URL

    public init(http: HTTPClient, apiKey: @escaping @Sendable () -> String?,
                baseURL: URL = URL(string: "https://api.weatherapi.com/v1/ip.json")!) {
        self.http = http
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    public func currentPlace() async throws -> Place {
        guard let key = apiKey(), !key.isEmpty else { throw LocationError.unavailable }
        var c = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        c.queryItems = [.init(name: "key", value: key), .init(name: "q", value: "auto:ip")]
        let response: HTTPResponse
        do { response = try await http.get(c.url!) } catch { throw LocationError.unavailable }
        guard response.statusCode == 200,
              let dto = try? JSONDecoder().decode(DTO.self, from: response.data),
              let lat = dto.lat, let lon = dto.lon, let city = dto.city, !city.isEmpty else {
            throw LocationError.notFound
        }
        return Place(name: city, province: dto.region, coordinate: Coordinate(latitude: lat, longitude: lon),
                     timeZoneIdentifier: dto.tz_id ?? "Europe/Istanbul", source: .ipApproximate)
    }

    struct DTO: Decodable {
        var city: String?
        var region: String?
        var lat: Double?
        var lon: Double?
        var tz_id: String?
    }
}
