import Foundation

/// Open-Meteo adapter. Free API is NON-COMMERCIAL only (see API_INTEGRATIONS.md); attribution CC BY 4.0.
public struct OpenMeteoProvider: WeatherProvider {
    public let source = WeatherDataSource.openMeteo
    public let maxForecastDays = 7
    public var cacheLifetime: TimeInterval = 30 * 60

    private let http: HTTPClient
    private let now: @Sendable () -> Date
    private let baseURL: URL

    public init(http: HTTPClient, now: @escaping @Sendable () -> Date = { Date() },
                baseURL: URL = URL(string: "https://api.open-meteo.com/v1/forecast")!) {
        self.http = http
        self.now = now
        self.baseURL = baseURL
    }

    func url(for place: Place) -> URL {
        var c = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        c.queryItems = [
            .init(name: "latitude", value: String(format: "%.4f", place.coordinate.latitude)),
            .init(name: "longitude", value: String(format: "%.4f", place.coordinate.longitude)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,is_day,weather_code,wind_speed_10m,wind_gusts_10m,wind_direction_10m"),
            .init(name: "hourly", value: "temperature_2m,apparent_temperature,precipitation_probability,precipitation,weather_code,wind_speed_10m,wind_gusts_10m,uv_index"),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max,wind_speed_10m_max,uv_index_max,sunrise,sunset"),
            .init(name: "timezone", value: place.timeZoneIdentifier),
            .init(name: "forecast_days", value: "5"),
            .init(name: "wind_speed_unit", value: "kmh")
        ]
        return c.url!
    }

    public func fetchSnapshot(for place: Place) async throws -> WeatherSnapshot {
        let response = try await http.get(url(for: place))
        switch response.statusCode {
        case 200: break
        case 429: throw WeatherError.rateLimited
        default: throw WeatherError.invalidResponse
        }
        let dto: OpenMeteoResponse
        do { dto = try JSONDecoder().decode(OpenMeteoResponse.self, from: response.data) } catch {
            throw WeatherError.invalidResponse
        }
        return try Self.map(dto, place: place, retrievedAt: now(), lifetime: cacheLifetime)
    }

    static func map(_ dto: OpenMeteoResponse, place: Place, retrievedAt: Date, lifetime: TimeInterval) throws -> WeatherSnapshot {
        let tz = place.timeZone
        guard let cur = dto.current, let curTime = LocalTimeParser.dateTime(cur.time, timeZone: tz),
              let temp = cur.temperature_2m else { throw WeatherError.noData }

        var hourly: [HourlyForecast] = []
        if let h = dto.hourly {
            for (i, t) in h.time.enumerated() {
                guard let time = LocalTimeParser.dateTime(t, timeZone: tz), let temp = h.temperature_2m.at(i) else { continue }
                hourly.append(HourlyForecast(
                    time: time, temperature: temp, feelsLike: h.apparent_temperature?.at(i),
                    condition: condition(wmo: h.weather_code?.at(i)),
                    precipitationProbability: h.precipitation_probability?.at(i).map { Int($0.rounded()) },
                    precipitationMm: h.precipitation?.at(i),
                    windSpeedKmh: h.wind_speed_10m?.at(i), windGustKmh: h.wind_gusts_10m?.at(i),
                    uvIndex: h.uv_index?.at(i)))
            }
        }

        var daily: [DailyForecast] = []
        if let d = dto.daily {
            for (i, t) in d.time.enumerated() {
                guard let date = LocalTimeParser.day(t, timeZone: tz),
                      let lo = d.temperature_2m_min?.at(i), let hi = d.temperature_2m_max?.at(i) else { continue }
                daily.append(DailyForecast(
                    date: date, minTemperature: lo, maxTemperature: hi,
                    condition: condition(wmo: d.weather_code?.at(i)),
                    precipitationProbability: d.precipitation_probability_max?.at(i).map { Int($0.rounded()) },
                    precipitationSumMm: d.precipitation_sum?.at(i), maxWindKmh: d.wind_speed_10m_max?.at(i),
                    uvIndexMax: d.uv_index_max?.at(i),
                    sunrise: d.sunrise?.at(i).flatMap { LocalTimeParser.dateTime($0, timeZone: tz) },
                    sunset: d.sunset?.at(i).flatMap { LocalTimeParser.dateTime($0, timeZone: tz) }))
            }
        }

        // `current` has no UV index → use the current hour's hourly value.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        let hourStart = calendar.dateInterval(of: .hour, for: curTime)?.start ?? curTime
        let currentUV = hourly.first { abs($0.time.timeIntervalSince(hourStart)) < 1 }?.uvIndex

        let current = CurrentWeather(
            time: curTime, temperature: temp, feelsLike: cur.apparent_temperature ?? temp,
            condition: condition(wmo: cur.weather_code), humidity: Int((cur.relative_humidity_2m ?? 0).rounded()),
            windSpeedKmh: cur.wind_speed_10m ?? 0, windGustKmh: cur.wind_gusts_10m,
            windDirectionDegrees: cur.wind_direction_10m.map { Int($0.rounded()) },
            uvIndex: currentUV, isDay: (cur.is_day ?? 1) == 1)

        return WeatherSnapshot(place: place, current: current, hourly: hourly, daily: daily, source: .openMeteo,
                               retrievedAt: retrievedAt, expiresAt: retrievedAt.addingTimeInterval(lifetime))
    }

    /// WMO weather interpretation codes.
    static func condition(wmo code: Int?) -> WeatherCondition {
        switch code ?? -1 {
        case 0, 1: return .clear
        case 2: return .partlyCloudy
        case 3: return .cloudy
        case 45, 48: return .fog
        case 51, 53, 55: return .drizzle
        case 56, 57, 66, 67: return .sleet
        case 61, 63, 80, 81: return .rain
        case 65, 82: return .heavyRain
        case 71, 73, 75, 77, 85, 86: return .snow
        case 95, 96, 99: return .thunderstorm
        default: return .cloudy
        }
    }
}

// MARK: - DTOs

struct OpenMeteoResponse: Decodable {
    struct Current: Decodable {
        var time: String
        var temperature_2m: Double?
        var apparent_temperature: Double?
        var relative_humidity_2m: Double?
        var is_day: Int?
        var weather_code: Int?
        var wind_speed_10m: Double?
        var wind_gusts_10m: Double?
        var wind_direction_10m: Double?
    }
    struct Hourly: Decodable {
        var time: [String]
        var temperature_2m: [Double?]
        var apparent_temperature: [Double?]?
        var precipitation_probability: [Double?]?
        var precipitation: [Double?]?
        var weather_code: [Int?]?
        var wind_speed_10m: [Double?]?
        var wind_gusts_10m: [Double?]?
        var uv_index: [Double?]?
    }
    struct Daily: Decodable {
        var time: [String]
        var weather_code: [Int?]?
        var temperature_2m_max: [Double?]?
        var temperature_2m_min: [Double?]?
        var precipitation_sum: [Double?]?
        var precipitation_probability_max: [Double?]?
        var wind_speed_10m_max: [Double?]?
        var uv_index_max: [Double?]?
        var sunrise: [String?]?
        var sunset: [String?]?
    }
    var utc_offset_seconds: Int?
    var current: Current?
    var hourly: Hourly?
    var daily: Daily?
}

extension Array {
    /// Safe element access that flattens optional elements.
    func at<T>(_ index: Int) -> T? where Element == T? {
        indices.contains(index) ? self[index] : nil
    }
}
