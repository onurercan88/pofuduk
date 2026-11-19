import Foundation

public struct Coordinate: Equatable, Hashable, Codable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// How a place was determined. IP-based locations are always approximate.
public enum LocationSource: String, Codable, Sendable {
    case gps, ipApproximate, manual, demo
}

public struct Place: Equatable, Hashable, Codable, Sendable {
    public var name: String
    public var district: String?
    public var province: String?
    public var coordinate: Coordinate
    public var timeZoneIdentifier: String
    public var source: LocationSource

    public init(name: String, district: String? = nil, province: String? = nil,
                coordinate: Coordinate, timeZoneIdentifier: String, source: LocationSource) {
        self.name = name
        self.district = district
        self.province = province
        self.coordinate = coordinate
        self.timeZoneIdentifier = timeZoneIdentifier
        self.source = source
    }

    public var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .current }

    public var displayName: String {
        if let district, district != name { return "\(district), \(name)" }
        return name
    }
}

/// Provider-independent weather condition.
public enum WeatherCondition: String, Codable, Sendable, CaseIterable {
    case clear, partlyCloudy, cloudy, fog
    case drizzle, rain, heavyRain, thunderstorm
    case snow, sleet
    case windy

    public var isPrecipitation: Bool {
        switch self {
        case .drizzle, .rain, .heavyRain, .thunderstorm, .snow, .sleet: return true
        default: return false
        }
    }
}

public struct CurrentWeather: Equatable, Codable, Sendable {
    public var time: Date
    public var temperature: Double
    public var feelsLike: Double
    public var condition: WeatherCondition
    public var humidity: Int
    public var windSpeedKmh: Double
    public var windGustKmh: Double?
    public var windDirectionDegrees: Int?
    public var uvIndex: Double?
    public var isDay: Bool

    public init(time: Date, temperature: Double, feelsLike: Double, condition: WeatherCondition,
                humidity: Int, windSpeedKmh: Double, windGustKmh: Double? = nil,
                windDirectionDegrees: Int? = nil, uvIndex: Double? = nil, isDay: Bool = true) {
        self.time = time
        self.temperature = temperature
        self.feelsLike = feelsLike
        self.condition = condition
        self.humidity = humidity
        self.windSpeedKmh = windSpeedKmh
        self.windGustKmh = windGustKmh
        self.windDirectionDegrees = windDirectionDegrees
        self.uvIndex = uvIndex
        self.isDay = isDay
    }
}

public struct HourlyForecast: Equatable, Codable, Sendable, Identifiable {
    public var id: Date { time }
    public var time: Date
    public var temperature: Double
    public var feelsLike: Double?
    public var condition: WeatherCondition
    /// 0...100
    public var precipitationProbability: Int?
    /// Millimetres expected within this hour.
    public var precipitationMm: Double?
    public var windSpeedKmh: Double?
    public var windGustKmh: Double?
    public var uvIndex: Double?

    public init(time: Date, temperature: Double, feelsLike: Double? = nil, condition: WeatherCondition,
                precipitationProbability: Int? = nil, precipitationMm: Double? = nil,
                windSpeedKmh: Double? = nil, windGustKmh: Double? = nil, uvIndex: Double? = nil) {
        self.time = time
        self.temperature = temperature
        self.feelsLike = feelsLike
        self.condition = condition
        self.precipitationProbability = precipitationProbability
        self.precipitationMm = precipitationMm
        self.windSpeedKmh = windSpeedKmh
        self.windGustKmh = windGustKmh
        self.uvIndex = uvIndex
    }
}

public struct DailyForecast: Equatable, Codable, Sendable, Identifiable {
    public var id: Date { date }
    /// Start of the day in the place's time zone.
    public var date: Date
    public var minTemperature: Double
    public var maxTemperature: Double
    public var condition: WeatherCondition
    public var precipitationProbability: Int?
    public var precipitationSumMm: Double?
    public var maxWindKmh: Double?
    public var uvIndexMax: Double?
    public var sunrise: Date?
    public var sunset: Date?

    public init(date: Date, minTemperature: Double, maxTemperature: Double, condition: WeatherCondition,
                precipitationProbability: Int? = nil, precipitationSumMm: Double? = nil,
                maxWindKmh: Double? = nil, uvIndexMax: Double? = nil,
                sunrise: Date? = nil, sunset: Date? = nil) {
        self.date = date
        self.minTemperature = minTemperature
        self.maxTemperature = maxTemperature
        self.condition = condition
        self.precipitationProbability = precipitationProbability
        self.precipitationSumMm = precipitationSumMm
        self.maxWindKmh = maxWindKmh
        self.uvIndexMax = uvIndexMax
        self.sunrise = sunrise
        self.sunset = sunset
    }
}

public enum WeatherDataSource: String, Codable, Sendable {
    case weatherAPI, openMeteo
    /// Apple Weather (WeatherKit). Only cross-checks current conditions; never the forecast source.
    case appleWeather
    /// Built-in sample data. Must always be labelled as such in the UI.
    case demo

    public var attribution: String {
        switch self {
        case .weatherAPI: return "WeatherAPI.com"
        case .openMeteo: return "Open-Meteo.com"
        case .appleWeather: return "Apple Weather"
        case .demo: return "Örnek veri"
        }
    }
}

/// A forecast plus provenance. Never present an expired snapshot as live.
public struct WeatherSnapshot: Equatable, Codable, Sendable {
    public var place: Place
    public var current: CurrentWeather
    public var hourly: [HourlyForecast]
    public var daily: [DailyForecast]
    public var source: WeatherDataSource
    public var retrievedAt: Date
    public var expiresAt: Date
    /// Set when `current` was cross-checked against a second source (needs its own attribution in the UI).
    public var crossCheckSource: WeatherDataSource?

    public init(place: Place, current: CurrentWeather, hourly: [HourlyForecast], daily: [DailyForecast],
                source: WeatherDataSource, retrievedAt: Date, expiresAt: Date,
                crossCheckSource: WeatherDataSource? = nil) {
        self.place = place
        self.current = current
        self.hourly = hourly.sorted { $0.time < $1.time }
        self.daily = daily.sorted { $0.date < $1.date }
        self.source = source
        self.retrievedAt = retrievedAt
        self.expiresAt = expiresAt
        self.crossCheckSource = crossCheckSource
    }

    public func isStale(at now: Date) -> Bool { now >= expiresAt }
}
