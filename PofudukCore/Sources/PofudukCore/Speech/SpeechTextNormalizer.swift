import Foundation

/// Text sent to the speech synthesizer, derived from a subtitle sentence. Subtitles stay exactly as
/// written; only the spoken form changes (clock times, abbreviations). `subtitleRange(for:)` maps the
/// synthesizer's word ranges back so the highlighted subtitle word stays right.
/// Ranges are UTF-16 offsets (`NSRange`), like `AVSpeechSynthesizer` reports them.
public struct SpokenText: Equatable, Sendable {
    public let subtitle: String
    public let text: String
    /// Replaced pieces, in order: range in the subtitle and range in the spoken text.
    let replacements: [(subtitle: TextRange, spoken: TextRange)]

    public static func == (lhs: SpokenText, rhs: SpokenText) -> Bool {
        lhs.subtitle == rhs.subtitle && lhs.text == rhs.text
    }

    /// A word inside a replacement maps to the whole replaced subtitle piece; text between
    /// replacements is shifted by the length difference so far.
    public func subtitleRange(for spoken: TextRange) -> TextRange {
        var delta = 0
        for r in replacements {
            let spokenEnd = r.spoken.location + r.spoken.length
            if spoken.location < r.spoken.location { break }
            if spoken.location < spokenEnd { return r.subtitle }
            delta = (r.subtitle.location + r.subtitle.length) - spokenEnd
        }
        let location = max(0, spoken.location + delta)
        let maxLength = max(0, (subtitle as NSString).length - location)
        return TextRange(location: location, length: min(spoken.length, maxLength))
    }
}

/// Turkish speech fixes for words the system voice reads badly. Only touches forms the app itself writes.
public enum SpeechTextNormalizer {
    private struct Rule {
        let regex: NSRegularExpression
        let replace: (NSTextCheckingResult, NSString) -> String
    }

    private static let rules: [Rule] = [
        // Clock times written as "14.00" / "09.30" (TurkishFormatting.clockTime) were read like decimals.
        // "14.00" → "14", "09.30" → "9 30", keeping a suffix such as "'te" attached.
        Rule(regex: try! NSRegularExpression(pattern: #"\b([01]?\d|2[0-3])\.([0-5]\d)\b"#)) { m, s in
            let hour = Int(s.substring(with: m.range(at: 1))) ?? 0
            let minute = Int(s.substring(with: m.range(at: 2))) ?? 0
            return minute == 0 ? "\(hour)" : "\(hour) \(minute)"
        },
        Rule(regex: try! NSRegularExpression(pattern: #"\bUV\b"#)) { _, _ in "ultraviyole" },
        Rule(regex: try! NSRegularExpression(pattern: #"\bMGM\b"#)) { _, _ in "Meteoroloji" },
    ]

    public static func spoken(_ sentence: String) -> SpokenText {
        let ns = sentence as NSString
        var matches: [(range: NSRange, replacement: String)] = []
        for rule in rules {
            for m in rule.regex.matches(in: sentence, range: NSRange(location: 0, length: ns.length)) {
                // Rules never overlap in practice; skip any overlap rather than produce garbled text.
                guard !matches.contains(where: { NSIntersectionRange($0.range, m.range).length > 0 }) else { continue }
                matches.append((m.range, rule.replace(m, ns)))
            }
        }
        matches.sort { $0.range.location < $1.range.location }

        var text = ""
        var replacements: [(subtitle: TextRange, spoken: TextRange)] = []
        var cursor = 0
        var spokenLength = 0
        for (range, replacement) in matches {
            let before = ns.substring(with: NSRange(location: cursor, length: range.location - cursor))
            text += before
            spokenLength += (before as NSString).length
            let replacementLength = (replacement as NSString).length
            replacements.append((TextRange(location: range.location, length: range.length),
                                 TextRange(location: spokenLength, length: replacementLength)))
            text += replacement
            spokenLength += replacementLength
            cursor = range.location + range.length
        }
        text += ns.substring(from: cursor)
        return SpokenText(subtitle: sentence, text: text, replacements: replacements)
    }
}
