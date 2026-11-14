import SwiftUI

/// Bottom input: suggestions, text field, microphone and send. Fully usable without voice.
struct AskBar: View {
    @Bindable var conversation: ConversationViewModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            if let message = conversation.microphoneMessage {
                Text(message)
                    .font(PofudukFont.caption)
                    .foregroundStyle(PofudukColor.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if focused && conversation.inputText.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(ConversationViewModel.suggestions, id: \.self) { s in
                            Button(s) { conversation.inputText = s; Task { await conversation.send() } }
                                .font(PofudukFont.caption.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(.ultraThinMaterial, in: Capsule())
                                .foregroundStyle(PofudukColor.ink)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            HStack(spacing: 10) {
                TextField(conversation.isListening ? "Dinliyorum…" : "Pofuduk'a sor…", text: $conversation.inputText)
                    .font(PofudukFont.body)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit { Task { await conversation.send() } }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(conversation.isListening ? PofudukColor.accent : PofudukColor.surfaceStroke,
                                                    lineWidth: conversation.isListening ? 2 : 1))
                    .accessibilityLabel("Soru")

                RoundIconButton(systemImage: conversation.isListening ? "stop.fill" : "mic.fill",
                                label: conversation.isListening ? "Dinlemeyi bitir" : "Sesli sor",
                                prominent: conversation.isListening) {
                    focused = false
                    Task { await conversation.toggleListening() }
                }
                if conversation.canSend && !conversation.isListening {
                    RoundIconButton(systemImage: "arrow.up", label: "Gönder", prominent: true) {
                        focused = false
                        Task { await conversation.send() }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(.bar)
    }
}
