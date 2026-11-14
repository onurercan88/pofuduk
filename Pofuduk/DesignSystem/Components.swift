import SwiftUI

/// Soft frosted card used across the app.
struct SoftCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PofudukColor.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(PofudukColor.surfaceStroke, lineWidth: 1))
    }
}

/// Round icon button with a mandatory accessibility label.
struct RoundIconButton: View {
    let systemImage: String
    let label: String
    var prominent = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: prominent ? 22 : 18, weight: .semibold))
                .foregroundStyle(prominent ? Color.white : PofudukColor.ink)
                .frame(width: prominent ? 60 : 48, height: prominent ? 60 : 48)
                .background {
                    if prominent {
                        Circle().fill(PofudukColor.accent.gradient)
                            .shadow(color: PofudukColor.accent.opacity(0.4), radius: 10, y: 4)
                    } else {
                        Circle().fill(PofudukColor.surface)
                            .overlay(Circle().strokeBorder(PofudukColor.surfaceStroke, lineWidth: 1))
                    }
                }
        }
        .buttonStyle(SquishButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel(label)
    }
}

struct SquishButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Small text badge; carries text so meaning never depends on colour alone.
/// Solid ink pill → high contrast on every weather background (accessibility audit).
struct Badge: View {
    let text: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(PofudukFont.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(PofudukColor.ink.opacity(0.88), in: Capsule())
        .foregroundStyle(PofudukColor.inkInverse)
    }
}
