import SwiftUI
import PofudukCore

/// Public entry point of the character system. It consumes only `CharacterAppearance`,
/// so this SwiftUI renderer can be replaced (e.g. by a Rive state machine) without touching features.
struct CharacterView: View {
    let appearance: CharacterAppearance
    var size: CGFloat = 220
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                WeatherEffectsView(theme: appearance.theme, time: t)
                    .frame(width: size * 1.7, height: size * 1.35)
                    .allowsHitTesting(false)
                CharacterFigure(appearance: appearance, time: reduceMotion ? 0 : t)
                    .frame(width: 200, height: 200)
                    .scaleEffect(size / 200)
                    .frame(width: size, height: size)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isImage)
    }

    private var accessibilityText: String {
        let moodText: String
        switch appearance.mood {
        case .speaking: moodText = "konuşuyor"
        case .listening: moodText = "dinliyor"
        case .thinking: moodText = "düşünüyor"
        case .warning: moodText = "uyarı modunda"
        case .sleeping: moodText = "uyuyor"
        case .error: moodText = "bilgiye ulaşamadı"
        default: moodText = ""
        }
        return [appearance.theme.accessibilityDescription, moodText].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

// MARK: - Figure

/// Draws Pofuduk in a 200×200 design space.
struct CharacterFigure: View {
    let appearance: CharacterAppearance
    let time: TimeInterval

    private var mood: CharacterMood { appearance.mood }
    private var theme: WeatherTheme { appearance.theme }
    private var wearsSunglasses: Bool { theme == .sunny && mood != .sleeping && mood != .error }

    var body: some View {
        let motion = Motion(mood: mood, theme: theme, time: time)
        ZStack {
            // Ground shadow
            Ellipse()
                .fill(Color.black.opacity(0.10))
                .frame(width: 130 - motion.bob, height: 16)
                .blur(radius: 6)
                .offset(y: 92)

            ZStack {
                if theme == .rainy { UmbrellaView(time: time).position(x: 156, y: 18) }

                CloudBody()
                    .fill(LinearGradient(colors: [PofudukColor.cloudTop, PofudukColor.cloudBottom],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(
                        CloudBody()
                            .fill(RadialGradient(colors: [.white.opacity(0.9), .clear],
                                                 center: UnitPoint(x: 0.4, y: 0.25), startRadius: 2, endRadius: 70))
                    )
                    .overlay(
                        CloudBody().stroke(PofudukColor.cloudShade.opacity(0.55), lineWidth: 1.5)
                    )
                    .shadow(color: PofudukColor.cloudShade.opacity(0.6), radius: 12, y: 6)

                FaceView(mood: mood, theme: theme, time: time, wearsSunglasses: wearsSunglasses)

                if theme == .snowy || theme == .windy {
                    ScarfView(time: time, windy: theme == .windy).position(x: 100, y: 160)
                }
                if wearsSunglasses { SunglassesView().position(x: 100, y: 117) }

                MoodDecorations(mood: mood, time: time)
            }
            .scaleEffect(x: motion.squashX, y: motion.squashY, anchor: .bottom)
            .rotationEffect(.degrees(motion.tilt), anchor: .bottom)
            .offset(y: -motion.bob)
        }
    }
}

/// All procedural motion in one place (pure function of time).
struct Motion {
    var bob: CGFloat
    var squashX: CGFloat
    var squashY: CGFloat
    var tilt: Double

    init(mood: CharacterMood, theme: WeatherTheme, time t: TimeInterval) {
        let breathe = sin(t * 2.0)
        switch mood {
        case .celebrating:
            bob = CGFloat(abs(sin(t * 4.0)) * 14)
        case .speaking:
            bob = CGFloat(4 + sin(t * 3.2) * 5)
        case .sleeping:
            bob = CGFloat(2 + sin(t * 1.0) * 2)
        case .warning:
            bob = CGFloat(3 + sin(t * 1.5) * 2)
        default:
            bob = CGFloat(5 + breathe * 5)
        }
        squashX = 1 + CGFloat(breathe) * 0.018
        squashY = 1 - CGFloat(breathe) * 0.018
        switch theme {
        case .windy: tilt = -5 + sin(t * 1.8) * 6
        default: tilt = mood == .listening ? -6 : sin(t * 0.9) * 1.5
        }
    }
}

// MARK: - Body shape

struct CloudBody: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 200, sy = rect.height / 200
        func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: (x - r) * sx, y: (y - r) * sy, width: 2 * r * sx, height: 2 * r * sy))
        }
        var p = Path()
        p.addRoundedRect(in: CGRect(x: 18 * sx, y: 82 * sy, width: 164 * sx, height: 94 * sy),
                         cornerSize: CGSize(width: 46 * sx, height: 46 * sy))
        p.addPath(circle(62, 98, 46))
        p.addPath(circle(108, 76, 56))
        p.addPath(circle(152, 100, 42))
        p.addPath(circle(36, 132, 32))
        p.addPath(circle(168, 134, 30))
        return p
    }
}
