import Foundation

/// Splits free text into sentences without breaking clock times ("14.00") or decimals ("2.5").
public enum SentenceSegmenter {
    public static func split(_ text: String) -> [String] {
        let chars = Array(text)
        var sentences: [String] = []
        var current = ""
        for (i, ch) in chars.enumerated() {
            current.append(ch)
            guard ch == "." || ch == "!" || ch == "?" else { continue }
            let prev = i > 0 ? chars[i - 1] : " "
            let next = i + 1 < chars.count ? chars[i + 1] : " "
            if ch == ".", prev.isNumber, next.isNumber { continue }
            if next.isWhitespace || i + 1 == chars.count {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { sentences.append(trimmed) }
                current = ""
            }
        }
        let rest = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rest.isEmpty { sentences.append(rest) }
        return sentences
    }
}

/// UTF-16 based range, matching `NSRange` from AVSpeechSynthesizer callbacks.
public struct TextRange: Equatable, Sendable {
    public var location: Int
    public var length: Int
    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }
}

public enum PlaybackStatus: Equatable, Sendable {
    case idle, speaking, paused, finished, stopped
}

/// Subtitle state driven only by real speech callbacks (no timing estimates).
/// Sentences are exactly the utterance strings, so subtitles always match speech.
public struct SubtitleTrack: Equatable, Sendable {
    public private(set) var sentences: [String]
    public private(set) var status: PlaybackStatus = .idle
    /// Sentence currently (or most recently) spoken. Stays visible after finishing so text never vanishes abruptly.
    public private(set) var currentIndex: Int?
    /// Word being spoken inside the current sentence.
    public private(set) var wordRange: TextRange?

    public init(sentences: [String] = []) {
        self.sentences = sentences
    }

    public var currentSentence: String? { currentIndex.map { sentences[$0] } }
    public var transcript: String { sentences.joined(separator: "\n") }
    public var isActive: Bool { status == .speaking || status == .paused }

    /// Sentences already spoken, including the current one.
    public var spokenSentences: [String] {
        guard let currentIndex else { return [] }
        return Array(sentences[...currentIndex])
    }

    public mutating func load(_ sentences: [String]) {
        self = SubtitleTrack(sentences: sentences)
    }

    public mutating func didStart(sentenceAt index: Int) {
        guard sentences.indices.contains(index) else { return }
        currentIndex = index
        wordRange = nil
        status = .speaking
    }

    public mutating func willSpeak(_ range: TextRange, sentenceAt index: Int) {
        guard sentences.indices.contains(index) else { return }
        let length = sentences[index].utf16.count
        guard range.location >= 0, range.location + range.length <= length else { return }
        currentIndex = index
        wordRange = range
    }

    public mutating func didFinish(sentenceAt index: Int) {
        guard index == currentIndex else { return }
        wordRange = nil
        if index == sentences.count - 1 { status = .finished }
    }

    public mutating func didPause() {
        if status == .speaking { status = .paused }
    }

    public mutating func didResume() {
        if status == .paused { status = .speaking }
    }

    /// Stopping keeps the last sentence visible; the full transcript stays available.
    public mutating func didStop() {
        wordRange = nil
        if status != .finished { status = .stopped }
    }

    /// Without sound, the whole message is shown at once.
    public mutating func showAllWithoutAudio() {
        guard !sentences.isEmpty else { return }
        currentIndex = sentences.count - 1
        wordRange = nil
        status = .finished
    }
}
