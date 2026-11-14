import SwiftUI
import PofudukCore

/// The app icon, drawn from the same character renderer (single source of truth).
/// Rendered to a 1024×1024 opaque PNG by `AppIconRenderTests` in CI.
struct AppIconView: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 1.0, green: 0.88, blue: 0.68), Color(red: 0.70, green: 0.80, blue: 1.0)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(RadialGradient(colors: [Color(red: 1.0, green: 0.93, blue: 0.6), Color(red: 1.0, green: 0.74, blue: 0.35)],
                                     center: .center, startRadius: 4, endRadius: 150))
                .frame(width: 300, height: 300)
                .offset(x: 250, y: -250)
            CharacterFigure(appearance: CharacterAppearance(mood: .happy, theme: .cloudy), time: 0)
                .frame(width: 200, height: 200)
                .scaleEffect(4.1)
                .offset(y: 60)
        }
        .frame(width: 1024, height: 1024)
        .clipped()
    }
}

#Preview { AppIconView().scaleEffect(0.3) }
