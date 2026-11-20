import SwiftUI
import PofudukCore

/// Public entry point of the character system. It consumes only `CharacterAppearance`,
/// so this SwiftUI renderer can be replaced (e.g. by a Rive state machine) without touching features.
struct CharacterView: View {
    let appearance: CharacterAppearance
    var size: CGFloat = 220
    /// true: rain/snow/sun spill around the character (home). false: kept inside `size` (small inline uses).
    var effectsBleed = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // 30 fps is visually smooth for this soft character and halves CPU/battery cost vs 60 fps.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            // Drawn parts (incl. decorative "z" letters) are hidden; the container carries the description.
            // Reduce Motion: freeze at a moment with open eyes (t = 0 falls inside a blink).
            CharacterFigure(appearance: appearance, time: reduceMotion ? CharacterFigure.stillTime : t)
                .frame(width: 200, height: 200)
                .scaleEffect(size / 200)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
                // Vertical room for the effects stays part of the layout (unchanged spacing); only their
                // width is left out, so they can never push the page sideways (that clipped both edges on
                // 375 pt iPhones: SE, mini).
                .frame(height: size * (effectsBleed ? 1.35 : 1))
                .background {
                    WeatherEffectsView(theme: appearance.theme, time: t)
                        .frame(width: size * (effectsBleed ? 1.7 : 1), height: size * (effectsBleed ? 1.35 : 1))
                        .clipped()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
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

    /// A frozen moment with open eyes, for still renders and Reduce Motion.
    static let stillTime: TimeInterval = 1.0

    private var mood: CharacterMood { appearance.mood }
    private var theme: WeatherTheme { appearance.theme }
    private var wearsSunglasses: Bool { appearance.wearsSunglasses }

    /// Tap reaction in progress (nil when none, or frozen for Reduce Motion).
    private var reaction: (kind: TapReaction, progress: Double, laugh: String)? {
        guard let playback = appearance.tapReaction, let p = playback.progress(at: time) else { return nil }
        return (playback.reaction, p, playback.laugh)
    }

    /// Body motion; a dance (three bouncy steps side to side) replaces it during that reaction.
    private func currentMotion(dancing progress: Double?) -> Motion {
        var motion = Motion(mood: mood, theme: theme, time: time)
        if let progress {
            let beat = progress * 2 * .pi * 3
            motion.bob = CGFloat(abs(sin(beat)) * 18)
            motion.tilt = sin(beat) * 14
            motion.sway = CGFloat(sin(beat / 2) * 16)
        }
        return motion
    }

    var body: some View {
        let reaction = self.reaction
        let motion = currentMotion(dancing: reaction?.kind == .dance ? reaction?.progress : nil)
        let tossing = reaction?.kind == .tossGlasses
        ZStack {
            // Ground shadow
            Ellipse()
                .fill(Color.black.opacity(0.10))
                .frame(width: 130 - motion.bob, height: 16)
                .blur(radius: 6)
                .offset(y: 92)

            ZStack {
                if theme == .rainy {
                    UmbrellaView(time: time)
                        .modifier(UmbrellaTwirl(progress: reaction?.kind == .twirlUmbrella ? reaction?.progress : nil))
                        .position(x: 156, y: 18)
                }
                if theme == .windy, mood != .sleeping { KiteView(time: time) }

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

                FaceView(mood: mood, theme: theme, time: time, wearsSunglasses: wearsSunglasses && !tossing,
                         speechCue: appearance.speechCue)

                if theme == .snowy || theme == .windy {
                    ScarfView(time: time, windy: theme == .windy).position(x: 100, y: 167)
                }
                if wearsSunglasses {
                    SunglassesView()
                        .modifier(GlassesToss(progress: tossing ? reaction?.progress : nil))
                        .position(x: 100, y: 117)
                }

                // Worn on top, so drawn after the body.
                if theme == .stormy {
                    UmbrellaHatView(time: time)
                        .modifier(HatFlip(progress: reaction?.kind == .spinUmbrellaHat ? reaction?.progress : nil))
                        .position(x: 106, y: 6)
                }

                MoodDecorations(mood: mood, time: time)
            }
            .scaleEffect(x: motion.squashX, y: motion.squashY, anchor: .bottom)
            .rotationEffect(.degrees(motion.tilt), anchor: .bottom)
            .offset(x: motion.sway, y: -motion.bob)

            if let reaction { LaughBubble(text: reaction.laugh, progress: reaction.progress) }
        }
    }
}

// MARK: - Tap reactions (just for fun)

/// Sunglasses fly up spinning and land back on the nose.
struct GlassesToss: ViewModifier {
    let progress: Double?

    func body(content: Content) -> some View {
        let p = progress ?? 0
        let arc = sin(p * .pi)
        content
            .rotationEffect(.degrees(p * 720))
            .offset(x: CGFloat(arc * 18), y: CGFloat(-arc * 120))
    }
}

/// The held umbrella spins on its handle and hops a little.
struct UmbrellaTwirl: ViewModifier {
    let progress: Double?

    func body(content: Content) -> some View {
        let p = progress ?? 0
        // Spinning on its handle = horizontal flip; never exactly 0 (singular transform).
        let c = progress == nil ? 1 : cos(p * 4 * .pi)
        content
            .scaleEffect(x: CGFloat(c >= 0 ? max(0.05, c) : min(-0.05, c)), y: 1)
            .rotationEffect(.degrees(sin(p * 4 * .pi) * 18), anchor: .bottom)
            .offset(y: CGFloat(-sin(p * .pi) * 22))
    }
}

/// The umbrella hat is tossed up, flips once and is caught again.
struct HatFlip: ViewModifier {
    let progress: Double?

    func body(content: Content) -> some View {
        let p = progress ?? 0
        content
            .rotationEffect(.degrees(p * 360))
            .offset(y: CGFloat(-sin(p * .pi) * 60))
    }
}

/// "Hihi!" in a little bubble that floats up and fades out.
struct LaughBubble: View {
    let text: String
    let progress: Double

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .heavy, design: .rounded))
            .foregroundStyle(PofudukColor.accent)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(.white.opacity(0.92)))
            .scaleEffect(CGFloat(0.6 + 0.4 * min(1, progress * 5)))
            .opacity(progress > 0.75 ? (1 - progress) * 4 : 1)
            .position(x: 138, y: CGFloat(14 - progress * 18))
    }
}

/// All procedural motion in one place (pure function of time).
struct Motion {
    var bob: CGFloat
    var squashX: CGFloat
    var squashY: CGFloat
    var tilt: Double
    /// Sideways offset (dance only).
    var sway: CGFloat = 0

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
        // Boolean union → one clean outline (no inner circle edges when stroked).
        var p = Path(roundedRect: CGRect(x: 18 * sx, y: 82 * sy, width: 164 * sx, height: 94 * sy),
                     cornerSize: CGSize(width: 46 * sx, height: 46 * sy))
        for c in [(62.0, 98.0, 46.0), (108, 76, 56), (152, 100, 42), (36, 132, 32), (168, 134, 30)] {
            p = p.union(circle(c.0, c.1, c.2))
        }
        return p
    }
}
