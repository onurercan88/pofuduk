import Foundation

/// Tunable interpretation thresholds. Changing these never requires UI changes.
public struct WeatherThresholds: Equatable, Sendable {
    /// Probability (%) at or above which precipitation is "likely".
    public var likelyPrecipitationProbability: Int = 60
    /// Probability (%) at or above which precipitation is "possible" (communicated with uncertainty).
    public var possiblePrecipitationProbability: Int = 30
    /// Hourly amount (mm) at or above which an hour counts as wet when amounts are available.
    public var minimumWetHourMm: Double = 0.1
    /// Hourly rate (mm/h) boundaries: light < moderate < heavy.
    public var moderateRainMmPerHour: Double = 2.5
    public var heavyRainMmPerHour: Double = 7.6
    /// Sustained wind (km/h) considered strong.
    public var strongWindKmh: Double = 40
    /// Gust (km/h) considered strong.
    public var strongGustKmh: Double = 60
    /// UV index considered high.
    public var highUVIndex: Double = 6
    /// Feels-like difference (°C) worth mentioning.
    public var notableFeelsLikeDifference: Double = 3
    /// Daily min/max swing (°C) worth mentioning.
    public var notableTemperatureSwing: Double = 10

    public init() {}

    public static let `default` = WeatherThresholds()
}
