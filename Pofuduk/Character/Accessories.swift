import SwiftUI
import PofudukCore

struct SunglassesView: View {
    var body: some View {
        ZStack {
            HStack(spacing: 12) {
                lens
                lens
            }
            Capsule().fill(Color(red: 0.12, green: 0.12, blue: 0.2)).frame(width: 16, height: 4).offset(y: -6)
        }
    }

    private var lens: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.18, green: 0.16, blue: 0.32), Color(red: 0.36, green: 0.22, blue: 0.48)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(
                Capsule().fill(.white.opacity(0.45)).frame(width: 14, height: 4).rotationEffect(.degrees(-20)).offset(x: -6, y: -6)
            )
            .frame(width: 38, height: 28)
    }
}

struct UmbrellaView: View {
    let time: TimeInterval

    var body: some View {
        ZStack(alignment: .top) {
            // Handle
            Path { p in
                p.move(to: CGPoint(x: 50, y: 30))
                p.addLine(to: CGPoint(x: 50, y: 82))
                p.addQuadCurve(to: CGPoint(x: 38, y: 82), control: CGPoint(x: 44, y: 92))
            }
            .stroke(Color(red: 0.45, green: 0.32, blue: 0.28), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))

            CanopyShape()
                .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.62, blue: 0.62), Color(red: 1.0, green: 0.78, blue: 0.55)],
                                     startPoint: .leading, endPoint: .trailing))
                .overlay(CanopyShape().stroke(.white.opacity(0.7), lineWidth: 1.5))
                .frame(width: 100, height: 40)
                .offset(y: 4)
            Circle().fill(Color(red: 1.0, green: 0.62, blue: 0.62)).frame(width: 7, height: 7)
        }
        .frame(width: 100, height: 96)
        .rotationEffect(.degrees(-14 + sin(time * 2.2) * 3), anchor: .bottom)
    }
}

/// Umbrella canopy with a scalloped bottom edge.
struct CanopyShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.9))
        let scallops = 4
        let w = rect.width / CGFloat(scallops)
        for i in (0..<scallops).reversed() {
            let x0 = rect.minX + CGFloat(i) * w
            p.addQuadCurve(to: CGPoint(x: x0, y: rect.maxY), control: CGPoint(x: x0 + w / 2, y: rect.maxY - rect.height * 0.28))
        }
        p.closeSubpath()
        return p
    }
}

struct ScarfView: View {
    let time: TimeInterval
    let windy: Bool

    private let red = Color(red: 0.93, green: 0.42, blue: 0.48)
    private let stripe = Color(red: 1.0, green: 0.86, blue: 0.86)

    var body: some View {
        ZStack {
            Capsule().fill(red).frame(width: 142, height: 16)
                .overlay(HStack(spacing: 16) { ForEach(0..<6, id: \.self) { _ in Capsule().fill(stripe.opacity(0.7)).frame(width: 4, height: 11) } })
            // Tail: flutters sideways when windy, hangs when snowy
            RoundedRectangle(cornerRadius: 6).fill(red)
                .frame(width: 18, height: 36)
                .overlay(Capsule().fill(stripe.opacity(0.7)).frame(width: 14, height: 4).offset(y: 10))
                .rotationEffect(.degrees(windy ? 70 + sin(time * 7) * 14 : 8 + sin(time * 1.5) * 4), anchor: .top)
                .offset(x: 38, y: 18)
        }
    }
}

/// Small symbols that make mood readable at a glance.
struct MoodDecorations: View {
    let mood: CharacterMood
    let time: TimeInterval

    var body: some View {
        ZStack {
            switch mood {
            case .sleeping:
                ForEach(0..<3, id: \.self) { i in
                    let phase = (time * 0.6 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    Text("z").font(.system(.footnote, design: .rounded).weight(.bold))
                        .scaleEffect(1 + CGFloat(i) * 0.3)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)   // scales, but stays inside the drawing
                        .foregroundStyle(PofudukColor.accent.opacity(1 - phase))
                        .position(x: 160 + CGFloat(phase) * 16, y: 50 - CGFloat(phase) * 40)
                }
            case .thinking:
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle().fill(PofudukColor.accent)
                            .frame(width: 7, height: 7)
                            .opacity(0.35 + 0.65 * max(0, sin(time * 5 - Double(i) * 0.8)))
                    }
                }
                .padding(8)
                .background(Capsule().fill(.white.opacity(0.9)))
                .position(x: 168, y: 30)
            case .listening:
                ForEach(0..<3, id: \.self) { i in
                    ArcShape(bulgeUp: true)
                        .stroke(PofudukColor.accent.opacity(0.4 + 0.6 * max(0, sin(time * 4 - Double(i)))), lineWidth: 3)
                        .frame(width: 14 + CGFloat(i) * 9, height: 6)
                        .rotationEffect(.degrees(-90))
                        .position(x: 10 - CGFloat(i) * 6, y: 112)
                }
            case .surprised:
                Text("!").font(.system(.title, design: .rounded).weight(.heavy))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .foregroundStyle(PofudukColor.accent).position(x: 170, y: 36)
            case .warning:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.orange)
                    .position(x: 172, y: 36)
            case .celebrating:
                ForEach(0..<5, id: \.self) { i in
                    Image(systemName: "sparkle")
                        .font(.system(size: 12 + CGFloat(i % 3) * 4))
                        .foregroundStyle(PofudukColor.highlight)
                        .opacity(0.4 + 0.6 * max(0, sin(time * 3 + Double(i))))
                        .position(x: [20, 180, 30, 170, 100][i], y: [40, 50, 160, 160, 8][i])
                }
            case .error:
                Image(systemName: "questionmark")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(PofudukColor.inkSecondary)
                    .position(x: 168, y: 36)
            default:
                EmptyView()
            }
        }
        .frame(width: 200, height: 200)
    }
}
