import SwiftUI
import PofudukCore

/// Ambient weather effects behind the character, drawn procedurally with Canvas.
struct WeatherEffectsView: View {
    let theme: WeatherTheme
    let time: TimeInterval

    var body: some View {
        Canvas { ctx, size in
            switch theme {
            case .sunny: drawSun(&ctx, size)
            case .rainy: drawRain(&ctx, size, count: 34, speed: 260)
            case .stormy:
                drawRain(&ctx, size, count: 50, speed: 380)
                drawLightning(&ctx, size)
            case .snowy: drawSnow(&ctx, size)
            case .windy: drawWind(&ctx, size)
            case .night: drawNight(&ctx, size)
            case .cloudy: drawBackgroundClouds(&ctx, size)
            }
        }
    }

    /// Deterministic pseudo-random in 0..<1 for particle `i`.
    private func rand(_ i: Int, _ salt: Int = 0) -> Double {
        let v = sin(Double(i * 127 + salt * 311) * 12.9898) * 43758.5453
        return v - floor(v)
    }

    private func drawSun(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let center = CGPoint(x: size.width * 0.78, y: size.height * 0.16)
        let angle = time * 0.25
        var rays = ctx
        rays.translateBy(x: center.x, y: center.y)
        rays.rotate(by: .radians(angle))
        for i in 0..<12 {
            var r = rays
            r.rotate(by: .degrees(Double(i) * 30))
            let pulse = 1 + 0.08 * sin(time * 2 + Double(i))
            r.fill(Path(roundedRect: CGRect(x: 44, y: -4, width: 22 * pulse, height: 8), cornerRadius: 4),
                   with: .color(Color(red: 1.0, green: 0.78, blue: 0.35).opacity(0.75)))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: center.x - 36, y: center.y - 36, width: 72, height: 72)),
                 with: .radialGradient(Gradient(colors: [Color(red: 1.0, green: 0.92, blue: 0.55), Color(red: 1.0, green: 0.72, blue: 0.32)]),
                                       center: center, startRadius: 4, endRadius: 40))
    }

    private func drawRain(_ ctx: inout GraphicsContext, _ size: CGSize, count: Int, speed: Double) {
        for i in 0..<count {
            let x = rand(i) * size.width
            let offset = rand(i, 1) * size.height
            let y = (time * speed * (0.8 + rand(i, 2) * 0.4) + offset).truncatingRemainder(dividingBy: size.height + 30) - 15
            var p = Path()
            p.move(to: CGPoint(x: x, y: y))
            p.addLine(to: CGPoint(x: x - 3, y: y + 14))
            ctx.stroke(p, with: .color(Color(red: 0.45, green: 0.6, blue: 0.95).opacity(0.55)),
                       style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        }
    }

    private func drawLightning(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let phase = time.truncatingRemainder(dividingBy: 5.5)
        guard phase < 0.22 else { return }
        let flicker = phase < 0.08 || (phase > 0.14 && phase < 0.2)
        guard flicker else { return }
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(0.25)))
        let x = size.width * 0.18
        var bolt = Path()
        bolt.move(to: CGPoint(x: x + 14, y: 10))
        bolt.addLine(to: CGPoint(x: x, y: 52))
        bolt.addLine(to: CGPoint(x: x + 12, y: 52))
        bolt.addLine(to: CGPoint(x: x - 2, y: 96))
        bolt.addLine(to: CGPoint(x: x + 24, y: 42))
        bolt.addLine(to: CGPoint(x: x + 12, y: 42))
        bolt.addLine(to: CGPoint(x: x + 26, y: 10))
        bolt.closeSubpath()
        ctx.fill(bolt, with: .color(Color(red: 1.0, green: 0.88, blue: 0.4)))
    }

    private func drawSnow(_ ctx: inout GraphicsContext, _ size: CGSize) {
        for i in 0..<40 {
            let r = 2 + rand(i, 3) * 3.5
            let baseX = rand(i) * size.width
            let y = (time * (22 + rand(i, 2) * 26) + rand(i, 1) * size.height).truncatingRemainder(dividingBy: size.height + 10) - 5
            let x = baseX + sin(time * 1.2 + Double(i)) * 10
            ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.9)))
        }
    }

    private func drawWind(_ ctx: inout GraphicsContext, _ size: CGSize) {
        for i in 0..<7 {
            let y = size.height * (0.15 + rand(i) * 0.7)
            let length = 50 + rand(i, 1) * 60
            let x = (time * (140 + rand(i, 2) * 80) + rand(i, 3) * size.width).truncatingRemainder(dividingBy: size.width + length * 2) - length
            var p = Path()
            p.move(to: CGPoint(x: x, y: y))
            p.addCurve(to: CGPoint(x: x + length, y: y),
                       control1: CGPoint(x: x + length * 0.35, y: y - 8), control2: CGPoint(x: x + length * 0.65, y: y + 8))
            ctx.stroke(p, with: .color(.white.opacity(0.65)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
    }

    private func drawNight(_ ctx: inout GraphicsContext, _ size: CGSize) {
        for i in 0..<24 {
            let x = rand(i) * size.width, y = rand(i, 1) * size.height * 0.6
            let twinkle = 0.3 + 0.7 * abs(sin(time * (0.8 + rand(i, 2)) + Double(i)))
            ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 3, height: 3)), with: .color(.white.opacity(twinkle)))
        }
        let c = CGPoint(x: size.width * 0.8, y: size.height * 0.15)
        var moon = Path(ellipseIn: CGRect(x: c.x - 22, y: c.y - 22, width: 44, height: 44))
        moon = moon.subtracting(Path(ellipseIn: CGRect(x: c.x - 10, y: c.y - 30, width: 44, height: 44)))
        ctx.fill(moon, with: .color(Color(red: 1.0, green: 0.93, blue: 0.7)))
    }

    private func drawBackgroundClouds(_ ctx: inout GraphicsContext, _ size: CGSize) {
        for i in 0..<3 {
            let w = 90 + rand(i) * 50
            let x = (time * (8 + Double(i) * 4) + rand(i, 1) * size.width).truncatingRemainder(dividingBy: size.width + w) - w / 2
            let y = size.height * (0.08 + Double(i) * 0.12)
            var p = Path()
            p.addEllipse(in: CGRect(x: x, y: y + 10, width: w, height: w * 0.3))
            p.addEllipse(in: CGRect(x: x + w * 0.2, y: y, width: w * 0.45, height: w * 0.35))
            p.addEllipse(in: CGRect(x: x + w * 0.45, y: y + 4, width: w * 0.4, height: w * 0.3))
            ctx.fill(p, with: .color(.white.opacity(0.35)))
        }
    }
}
