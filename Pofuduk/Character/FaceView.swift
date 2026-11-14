import SwiftUI
import PofudukCore

/// Facial expression, drawn in the 200×200 character space.
struct FaceView: View {
    let mood: CharacterMood
    let theme: WeatherTheme
    let time: TimeInterval
    let wearsSunglasses: Bool

    enum EyeStyle { case open, wide, closed, happy }
    enum BrowStyle { case none, worried, serious }
    enum MouthStyle { case smile, bigSmile, oh, flat, frown, speaking }

    private var eyeStyle: EyeStyle {
        switch mood {
        case .sleeping: return .closed
        case .happy, .celebrating: return .happy
        case .surprised, .listening: return .wide
        default: return .open
        }
    }

    private var browStyle: BrowStyle {
        if mood == .warning || theme == .stormy { return .serious }
        if mood == .sad || mood == .error { return .worried }
        if theme == .rainy, mood == .idle || mood == .speaking { return .worried }
        return .none
    }

    private var mouthStyle: MouthStyle {
        switch mood {
        case .speaking: return .speaking
        case .happy, .celebrating: return .bigSmile
        case .surprised, .sleeping: return .oh
        case .warning, .thinking: return .flat
        case .sad, .error: return .frown
        default: return theme == .stormy ? .flat : .smile
        }
    }

    /// Natural blink every ~4 s (not while eyes are already closed/happy).
    private var blink: CGFloat {
        let phase = time.truncatingRemainder(dividingBy: 4.2)
        return phase < 0.14 ? 0.12 : 1
    }

    private var look: CGSize {
        switch mood {
        case .thinking: return CGSize(width: 4, height: -5)
        case .listening: return CGSize(width: -3, height: 0)
        default: return CGSize(width: sin(time * 0.5) * 1.5, height: 0)
        }
    }

    private var mouthOpenness: CGFloat {
        guard mood == .speaking else { return 0 }
        let v = abs(sin(time * 11)) * (0.6 + 0.4 * sin(time * 3.7))
        return CGFloat(0.25 + 0.75 * max(0, v))
    }

    var body: some View {
        ZStack {
            // Cheeks
            ForEach([54.0, 146.0], id: \.self) { x in
                Ellipse().fill(PofudukColor.cheek.opacity(0.55))
                    .frame(width: 24, height: 13).blur(radius: 2.5)
                    .position(x: x, y: 138)
            }

            if !wearsSunglasses {
                ForEach([75.0, 125.0], id: \.self) { x in
                    EyeView(style: eyeStyle, blink: blink, look: look).position(x: x, y: 116)
                }
                BrowsView(style: browStyle)
            }

            MouthView(style: mouthStyle, openness: mouthOpenness).position(x: 100, y: 145)
        }
        .frame(width: 200, height: 200)
    }
}

struct EyeView: View {
    let style: FaceView.EyeStyle
    let blink: CGFloat
    let look: CGSize

    var body: some View {
        switch style {
        case .open, .wide:
            let k: CGFloat = style == .wide ? 1.18 : 1
            ZStack {
                Capsule().fill(PofudukColor.eye).frame(width: 22 * k, height: 30 * k)
                Circle().fill(.white).frame(width: 9, height: 9).offset(x: -4 + look.width, y: -7 + look.height)
                Circle().fill(.white.opacity(0.8)).frame(width: 4, height: 4).offset(x: 4 + look.width, y: 6 + look.height)
            }
            .scaleEffect(x: 1, y: blink)
        case .closed:
            ArcShape(bulgeUp: false).stroke(PofudukColor.eye, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 22, height: 8)
        case .happy:
            ArcShape(bulgeUp: true).stroke(PofudukColor.eye, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                .frame(width: 24, height: 11)
        }
    }
}

struct BrowsView: View {
    let style: FaceView.BrowStyle

    var body: some View {
        Path { p in
            switch style {
            case .none: break
            case .worried:
                p.move(to: CGPoint(x: 62, y: 94)); p.addLine(to: CGPoint(x: 84, y: 88))
                p.move(to: CGPoint(x: 138, y: 94)); p.addLine(to: CGPoint(x: 116, y: 88))
            case .serious:
                p.move(to: CGPoint(x: 62, y: 88)); p.addLine(to: CGPoint(x: 85, y: 95))
                p.move(to: CGPoint(x: 138, y: 88)); p.addLine(to: CGPoint(x: 115, y: 95))
            }
        }
        .stroke(PofudukColor.eye, style: StrokeStyle(lineWidth: 4, lineCap: .round))
        .frame(width: 200, height: 200)
    }
}

struct MouthView: View {
    let style: FaceView.MouthStyle
    let openness: CGFloat

    var body: some View {
        switch style {
        case .smile:
            ArcShape(bulgeUp: false).stroke(PofudukColor.mouth, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 26, height: 10)
        case .bigSmile:
            SmileShape().fill(PofudukColor.mouth)
                .overlay(Ellipse().fill(PofudukColor.cheek).frame(width: 14, height: 6).offset(y: 5))
                .clipShape(SmileShape())
                .frame(width: 30, height: 16)
        case .oh:
            Ellipse().fill(PofudukColor.mouth).frame(width: 11, height: 13)
        case .flat:
            Capsule().fill(PofudukColor.mouth).frame(width: 20, height: 4)
        case .frown:
            ArcShape(bulgeUp: true).stroke(PofudukColor.mouth, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 22, height: 8)
        case .speaking:
            ZStack {
                Ellipse().fill(PofudukColor.mouth)
                Ellipse().fill(PofudukColor.cheek).frame(width: 12, height: max(2, 6 * openness)).offset(y: 5 * openness)
            }
            .clipShape(Ellipse())
            .frame(width: 22, height: 4 + 16 * openness)
        }
    }
}

/// Simple arc: bulgeUp = ∩ (happy eyes, frown), otherwise ∪ (smile, closed eyes).
struct ArcShape: Shape {
    var bulgeUp: Bool
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let y = bulgeUp ? rect.maxY : rect.minY
        p.move(to: CGPoint(x: rect.minX, y: y))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: y),
                       control: CGPoint(x: rect.midX, y: bulgeUp ? rect.minY - rect.height : rect.maxY + rect.height))
        return p
    }
}

/// "D" shaped open smile.
struct SmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.9))
        p.closeSubpath()
        return p
    }
}
