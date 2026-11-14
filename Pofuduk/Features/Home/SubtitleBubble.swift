import SwiftUI
import PofudukCore

/// Speech bubble showing exactly the sentence being spoken, with the current word highlighted.
struct SubtitleBubble: View {
    let track: SubtitleTrack
    let onShowTranscript: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if let sentence = track.currentSentence {
                    Text(highlighted(sentence))
                        .id(track.currentIndex)
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .offset(y: 10).combined(with: .opacity),
                            removal: .opacity))
                } else {
                    Text("Pofuduk konuşmaya hazırlanıyor…")
                        .foregroundStyle(PofudukColor.inkSecondary)
                }
            }
            .font(.system(.title3, design: .rounded).weight(.semibold))
            .foregroundStyle(PofudukColor.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.85), value: track.currentIndex)

            HStack {
                progressDots
                Spacer()
                Button(action: onShowTranscript) {
                    Label("Tüm metin", systemImage: "text.alignleft")
                        .font(PofudukFont.caption)
                }
                .foregroundStyle(PofudukColor.accent)
                .disabled(track.sentences.isEmpty)
            }
        }
        .padding(18)
        .background(alignment: .top) {
            BubbleShape()
                .fill(.regularMaterial)
                .overlay(BubbleShape().stroke(PofudukColor.surfaceStroke, lineWidth: 1))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(track.currentSentence ?? "Altyazı")
        .accessibilityHint("Konuşmanın tamamını görmek için Tüm metin düğmesini kullan.")
    }

    private var progressDots: some View {
        HStack(spacing: 5) {
            ForEach(track.sentences.indices, id: \.self) { i in
                Capsule()
                    .fill(i <= (track.currentIndex ?? -1) ? PofudukColor.accent : PofudukColor.inkSecondary.opacity(0.25))
                    .frame(width: i == track.currentIndex ? 16 : 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }

    private func highlighted(_ sentence: String) -> AttributedString {
        var attributed = AttributedString(sentence)
        guard track.status == .speaking, let range = track.wordRange,
              range.location + range.length <= sentence.utf16.count else { return attributed }
        let lower = String.Index(utf16Offset: range.location, in: sentence)
        let upper = String.Index(utf16Offset: range.location + range.length, in: sentence)
        guard let a = AttributedString.Index(lower, within: attributed),
              let b = AttributedString.Index(upper, within: attributed), a < b else { return attributed }
        attributed[a..<b].backgroundColor = PofudukColor.highlight.opacity(0.55)
        return attributed
    }
}

/// Rounded bubble with a small tail pointing up at the character.
struct BubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path(roundedRect: rect, cornerRadius: 26, style: .continuous)
        let tipX = rect.midX
        p.move(to: CGPoint(x: tipX - 14, y: rect.minY + 1))
        p.addQuadCurve(to: CGPoint(x: tipX, y: rect.minY - 14), control: CGPoint(x: tipX - 4, y: rect.minY - 4))
        p.addQuadCurve(to: CGPoint(x: tipX + 14, y: rect.minY + 1), control: CGPoint(x: tipX + 4, y: rect.minY - 4))
        p.closeSubpath()
        return p
    }
}

struct TranscriptSheet: View {
    let sentences: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(sentences.joined(separator: " "))
                    .font(PofudukFont.body)
                    .foregroundStyle(PofudukColor.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding()
            }
            .navigationTitle("Pofuduk'un söyledikleri")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Kapat") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
