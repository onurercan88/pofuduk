import SwiftUI
import PofudukCore

/// Pofuduk design tokens. All colours adapt to light/dark mode.
enum PofudukColor {
    static let ink = Color(light: .init(red: 0.17, green: 0.19, blue: 0.33), dark: .init(red: 0.95, green: 0.95, blue: 1.0))
    static let inkSecondary = Color(light: .init(red: 0.36, green: 0.38, blue: 0.52), dark: .init(red: 0.78, green: 0.80, blue: 0.90))
    static let surface = Color(light: .white.opacity(0.62), dark: .init(red: 0.16, green: 0.17, blue: 0.27).opacity(0.72))
    static let surfaceStroke = Color(light: .white.opacity(0.9), dark: .white.opacity(0.12))
    /// Light variant ≈ 5.9:1 on white (WCAG AA for small text); found by the accessibility audit.
    static let accent = Color(light: .init(red: 0.36, green: 0.32, blue: 0.82), dark: .init(red: 0.67, green: 0.64, blue: 1.0))
    static let highlight = Color(light: .init(red: 1.0, green: 0.86, blue: 0.45), dark: .init(red: 0.98, green: 0.80, blue: 0.35))

    // Character palette
    static let cloudTop = Color(red: 1.0, green: 1.0, blue: 1.0)
    static let cloudBottom = Color(red: 0.86, green: 0.88, blue: 1.0)
    static let cloudShade = Color(red: 0.74, green: 0.76, blue: 0.96)
    static let eye = Color(red: 0.16, green: 0.17, blue: 0.32)
    static let cheek = Color(red: 1.0, green: 0.62, blue: 0.70)
    static let mouth = Color(red: 0.55, green: 0.22, blue: 0.32)

    static func warning(_ level: WarningLevel) -> Color {
        switch level {
        case .green: return .green
        case .yellow: return .yellow
        case .orange: return .orange
        case .red: return .red
        }
    }
}

enum PofudukGradient {
    static func background(for theme: WeatherTheme, scheme: ColorScheme) -> LinearGradient {
        let dark = scheme == .dark
        let colors: [Color]
        switch theme {
        case .sunny:
            colors = dark ? [rgb(0.16, 0.18, 0.38), rgb(0.36, 0.26, 0.42)] : [rgb(1.0, 0.89, 0.70), rgb(0.80, 0.88, 1.0)]
        case .rainy:
            colors = dark ? [rgb(0.10, 0.14, 0.26), rgb(0.18, 0.24, 0.38)] : [rgb(0.74, 0.82, 0.95), rgb(0.86, 0.88, 0.97)]
        case .stormy:
            colors = dark ? [rgb(0.08, 0.08, 0.16), rgb(0.22, 0.18, 0.32)] : [rgb(0.55, 0.58, 0.72), rgb(0.76, 0.74, 0.86)]
        case .snowy:
            colors = dark ? [rgb(0.14, 0.18, 0.30), rgb(0.26, 0.30, 0.44)] : [rgb(0.88, 0.94, 1.0), rgb(0.97, 0.97, 1.0)]
        case .cloudy:
            colors = dark ? [rgb(0.14, 0.15, 0.24), rgb(0.24, 0.25, 0.36)] : [rgb(0.84, 0.86, 0.94), rgb(0.94, 0.92, 0.97)]
        case .windy:
            colors = dark ? [rgb(0.10, 0.18, 0.26), rgb(0.20, 0.30, 0.38)] : [rgb(0.76, 0.92, 0.94), rgb(0.88, 0.90, 1.0)]
        case .night:
            colors = [rgb(0.06, 0.07, 0.18), rgb(0.18, 0.16, 0.36)]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }
}

enum PofudukFont {
    static let title = Font.system(.title2, design: .rounded).weight(.bold)
    static let headline = Font.system(.headline, design: .rounded)
    static let body = Font.system(.body, design: .rounded)
    static let caption = Font.system(.caption, design: .rounded).weight(.medium)
}

extension Color {
    init(light: Color, dark: Color) {
        self.init(UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
    }
}

extension String {
    /// Turkish-aware first-letter capitalisation ("ılık" → "Ilık", "iyi" → "İyi").
    var sentenceCased: String {
        guard let first else { return self }
        return String(first).uppercased(with: Locale(identifier: "tr_TR")) + dropFirst()
    }
}

extension WeatherCondition {
    func symbolName(isDay: Bool = true) -> String {
        switch self {
        case .clear: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case .partlyCloudy: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case .cloudy: return "cloud.fill"
        case .fog: return "cloud.fog.fill"
        case .drizzle: return "cloud.drizzle.fill"
        case .rain: return "cloud.rain.fill"
        case .heavyRain: return "cloud.heavyrain.fill"
        case .thunderstorm: return "cloud.bolt.rain.fill"
        case .snow: return "cloud.snow.fill"
        case .sleet: return "cloud.sleet.fill"
        case .windy: return "wind"
        }
    }
}
