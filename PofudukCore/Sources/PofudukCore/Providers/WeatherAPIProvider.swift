import Foundation

/// WeatherAPI.com adapter. Free plan: commercial use allowed, 3 forecast days, credit "WeatherAPI.com" required.
/// The key comes from `apiKey` at call time and is never logged; production should go through a backend proxy.
public struct WeatherAPIProvider: WeatherProvider {
    public let source = WeatherDataSource.weatherAPI
    public var maxForecastDays: Int
    public var cacheLifetime: TimeInterval = 30 * 60

    private let http: HTTPClient
    private let apiKey: @Sendable () -> String?
    private let now: @Sendable () -> Date
    private let baseURL: URL

    public init(http: HTTPClient, apiKey: @escaping @Sendable () -> String?, maxForecastDays: Int = 3,
                now: @escaping @Sendable () -> Date = { Date() },
                baseURL: URL = URL(string: "https://api.weatherapi.com/v1/forecast.json")!) {
        self.http = http
        self.apiKey = apiKey
        self.maxForecastDays = maxForecastDays
        self.now = now
        self.baseURL = baseURL
    }

    func url(for place: Place, key: String) -> URL {
        var c = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        c.queryItems = [
            .init(name: "key", value: key),
            .init(name: "q", value: String(format: "%.4f,%.4f", place.coordinate.latitude, place.coordinate.longitude)),
            .init(name: "days", value: String(maxForecastDays)),
            .init(name: "aqi", value: "no"),
            .init(name: "alerts", value: "no"),
            .init(name: "lang", value: "tr")
        ]
        return c.url!
    }

    public func fetchSnapshot(for place: Place) async throws -> WeatherSnapshot {
        guard let key = apiKey(), !key.isEmpty else { throw WeatherError.missingAPIKey }
        let response = try await http.get(url(for: place, key: key))
        switch response.statusCode {
        case 200: break
        case 401, 403: throw WeatherError.missingAPIKey
        case 429: throw WeatherError.rateLimited
        case 400: throw WeatherError.noData
        default: throw WeatherError.invalidResponse
        }
        let dto: WeatherAPIResponse
        do { dto = try JSONDecoder().decode(WeatherAPIResponse.self, from: response.data) } catch {
            throw WeatherError.invalidResponse
        }
        return try Self.map(dto, place: place, retrievedAt: now(), lifetime: cacheLifetime)
    }

    static func map(_ dto: WeatherAPIResponse, place: Place, retrievedAt: Date, lifetime: TimeInterval) throws -> WeatherSnapshot {
        guard let cur = dto.current else { throw WeatherError.noData }
        // Prefer the provider's resolved zone if ours is unknown to it; keep ours otherwise (location layer owns it).
        let tz = place.timeZone

        var hourly: [HourlyForecast] = []
        var daily: [DailyForecast] = []
        for day in dto.forecast?.forecastday ?? [] {
            for h in day.hour ?? [] {
                hourly.append(HourlyForecast(
                    time: Date(timeIntervalSince1970: TimeInterval(h.time_epoch)),
                    temperature: h.temp_c, feelsLike: h.feelslike_c,
                    condition: condition(code: h.condition?.code),
                    precipitationProbability: probability(rain: h.chance_of_rain, snow: h.chance_of_snow),
                    precipitationMm: h.precip_mm, windSpeedKmh: h.wind_kph, windGustKmh: h.gust_kph, uvIndex: h.uv))
            }
            guard let date = LocalTimeParser.day(day.date, timeZone: tz), let d = day.day else { continue }
            daily.append(DailyForecast(
                date: date, minTemperature: d.mintemp_c, maxTemperature: d.maxtemp_c,
                condition: condition(code: d.condition?.code),
                precipitationProbability: probability(rain: d.daily_chance_of_rain, snow: d.daily_chance_of_snow),
                precipitationSumMm: d.totalprecip_mm, maxWindKmh: d.maxwind_kph, uvIndexMax: d.uv,
                sunrise: day.astro?.sunrise.flatMap { LocalTimeParser.clock12h($0, on: date, timeZone: tz) },
                sunset: day.astro?.sunset.flatMap { LocalTimeParser.clock12h($0, on: date, timeZone: tz) }))
        }

        let current = CurrentWeather(
            time: cur.last_updated_epoch.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? retrievedAt,
            temperature: cur.temp_c, feelsLike: cur.feelslike_c ?? cur.temp_c,
            condition: condition(code: cur.condition?.code), humidity: cur.humidity ?? 0,
            windSpeedKmh: cur.wind_kph ?? 0, windGustKmh: cur.gust_kph, windDirectionDegrees: cur.wind_degree,
            uvIndex: cur.uv, isDay: (cur.is_day ?? 1) == 1)

        return WeatherSnapshot(place: place, current: current, hourly: hourly, daily: daily, source: .weatherAPI,
                               retrievedAt: retrievedAt, expiresAt: retrievedAt.addingTimeInterval(lifetime))
    }

    static func probability(rain: Int?, snow: Int?) -> Int? {
        switch (rain, snow) {
        case (nil, nil): return nil
        default: return max(rain ?? 0, snow ?? 0)
        }
    }

    /// https://www.weatherapi.com/docs/weather_conditions.json
    static func condition(code: Int?) -> WeatherCondition {
        switch code ?? -1 {
        case 1000: return .clear
        case 1003: return .partlyCloudy
        case 1006, 1009: return .cloudy
        case 1030, 1135, 1147: return .fog
        case 1072, 1150, 1153: return .drizzle
        case 1063, 1180, 1183, 1186, 1189, 1240: return .rain
        case 1192, 1195, 1243, 1246: return .heavyRain
        case 1069, 1168, 1171, 1198, 1201, 1204, 1207, 1237, 1249, 1252, 1261, 1264: return .sleet
        case 1066, 1114, 1117, 1210, 1213, 1216, 1219, 1222, 1225, 1255, 1258: return .snow
        case 1087, 1273, 1276, 1279, 1282: return .thunderstorm
        default: return .cloudy
        }
    }
}

// MARK: - DTOs

struct WeatherAPIResponse: Decodable {
    struct Condition: Decodable { var code: Int? }
    struct Current: Decodable {
        var last_updated_epoch: Int?
        var temp_c: Double
        var feelslike_c: Double?
        var condition: Condition?
        var humidity: Int?
        var wind_kph: Double?
        var gust_kph: Double?
        var wind_degree: Int?
        var uv: Double?
        var is_day: Int?
    }
    struct Hour: Decodable {
        var time_epoch: Int
        var temp_c: Double
        var feelslike_c: Double?
        var condition: Condition?
        var chance_of_rain: Int?
        var chance_of_snow: Int?
        var precip_mm: Double?
        var wind_kph: Double?
        var gust_kph: Double?
        var uv: Double?
    }
    struct Day: Decodable {
        var maxtemp_c: Double
        var mintemp_c: Double
        var totalprecip_mm: Double?
        var daily_chance_of_rain: Int?
        var daily_chance_of_snow: Int?
        var maxwind_kph: Double?
        var uv: Double?
        var condition: Condition?
    }
    struct Astro: Decodable {
        var sunrise: String?
        var sunset: String?
    }
    struct ForecastDay: Decodable {
        var date: String
        var day: Day?
        var astro: Astro?
        var hour: [Hour]?
    }
    struct Forecast: Decodable { var forecastday: [ForecastDay]? }
    var current: Current?
    var forecast: Forecast?
}
