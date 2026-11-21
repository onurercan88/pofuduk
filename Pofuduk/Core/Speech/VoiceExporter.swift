#if DEBUG
import AVFoundation
import Foundation

/// Promo Reels only (reel-draft.yml). `-pofuduk.exportVoice "name=text|name!=text"` renders each line with
/// Pofuduk's own voice settings (same voice, rate and pitch as `SpeechService`; `!` = giggle style) to
/// `Documents/voice/<name>.caf`, then writes `done.txt` with the voice used and the frame counts.
enum VoiceExporter {
    static func runIfRequested(defaults: UserDefaults = .standard) {
        guard let spec = defaults.string(forKey: "pofuduk.exportVoice"), !spec.isEmpty else { return }
        Task.detached { await export(spec) }
    }

    private static func export(_ spec: String) async {
        let fm = FileManager.default
        let dir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("voice")
        try? fm.removeItem(at: dir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let voice = SpeechService.preferredTurkishVoice()
        let synthesizer = AVSpeechSynthesizer()
        var report = "voice=\(voice?.identifier ?? "none") quality=\(voice?.quality.rawValue ?? 0)\n"
        for item in spec.split(separator: "|") {
            guard let eq = item.firstIndex(of: "=") else { continue }
            var name = String(item[..<eq])
            let effect = name.hasSuffix("!")
            if effect { name.removeLast() }
            let utterance = AVSpeechUtterance(string: String(item[item.index(after: eq)...]))
            utterance.voice = voice
            utterance.rate = effect ? SpeechService.effectRate : SpeechService.defaultRate
            utterance.pitchMultiplier = effect ? SpeechService.effectPitch : SpeechService.briefingPitch
            let frames = await render(utterance, with: synthesizer, to: dir.appendingPathComponent("\(name).caf"))
            report += "\(name) frames=\(frames)\n"
        }
        try? report.write(to: dir.appendingPathComponent("done.txt"), atomically: true, encoding: .utf8)
    }

    /// Frames written, or -1 on a file error. Finishes on the empty end buffer, or 3 s after the last buffer
    /// (some simulator voices never send the end marker).
    private static func render(_ utterance: AVSpeechUtterance, with synthesizer: AVSpeechSynthesizer,
                               to url: URL) async -> Int {
        let state = RenderState()
        return await withCheckedContinuation { continuation in
            state.continuation = continuation
            synthesizer.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                state.append(pcm, to: url)
            }
            Task.detached {
                while true {
                    try? await Task.sleep(for: .milliseconds(500))
                    if state.idleTimedOut() { return }
                }
            }
        }
    }
}

private final class RenderState: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var frames = 0
    private var lastBuffer = Date()
    private var finished = false
    var continuation: CheckedContinuation<Int, Never>?

    func append(_ pcm: AVAudioPCMBuffer, to url: URL) {
        lock.lock(); defer { lock.unlock() }
        guard !finished else { return }
        lastBuffer = Date()
        guard pcm.frameLength > 0 else { return finish(frames) }
        do {
            if file == nil {
                file = try AVAudioFile(forWriting: url, settings: pcm.format.settings,
                                       commonFormat: pcm.format.commonFormat, interleaved: pcm.format.isInterleaved)
            }
            try file?.write(from: pcm)
            frames += Int(pcm.frameLength)
        } catch {
            finish(-1)
        }
    }

    /// True once finished (also when it finishes here because no buffer came for 3 s).
    func idleTimedOut() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if !finished, Date().timeIntervalSince(lastBuffer) > 3 { finish(frames) }
        return finished
    }

    private func finish(_ result: Int) {
        finished = true
        file = nil // closes the file
        continuation?.resume(returning: result)
        continuation = nil
    }
}
#endif
