import AVFoundation
import Speech

/// Turkish speech-to-text. Permissions are requested only when the user taps the microphone.
/// On-device recognition is required whenever the device supports it; otherwise the UI discloses
/// that audio is processed by Apple's servers.
@MainActor
protocol SpeechRecognizing: AnyObject {
    var isOnDeviceSupported: Bool { get }
    func requestAuthorization() async -> Bool
    /// `onResult(text, isFinal)` is delivered on the main actor.
    func start(onResult: @escaping (String, Bool) -> Void) async throws
    func stop()
}

@MainActor
final class SpeechRecognitionService: SpeechRecognizing {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "tr-TR"))
    /// A fresh engine per session: its input format is read after the record session is active, so a
    /// route or category change since the last session (Bluetooth, the voice playing) can't leave it stale.
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var observers: [NSObjectProtocol] = []

    enum RecognitionError: Error { case unavailable, noInput }

    var isOnDeviceSupported: Bool { recognizer?.supportsOnDeviceRecognition ?? false }

    func requestAuthorization() async -> Bool {
        let speechStatus = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard speechStatus == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    func start(onResult: @escaping (String, Bool) -> Void) async throws {
        guard let recognizer, recognizer.isAvailable else { throw RecognitionError.unavailable }
        stop()
        do {
            try begin(with: recognizer, onResult: onResult)
        } catch {
            // Usually the voice that was just stopped is still releasing the audio session: retry once.
            stop()
            try await Task.sleep(for: .milliseconds(300))
            try begin(with: recognizer, onResult: onResult)
        }
    }

    private func begin(with recognizer: SFSpeechRecognizer, onResult: @escaping (String, Bool) -> Void) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // Installing a tap with an invalid format raises an exception (a crash), so fail softly instead.
        guard format.sampleRate > 0, format.channelCount > 0 else { throw RecognitionError.noInput }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        // Stored before the tap exists so `stop()` always removes it, even if starting fails below.
        self.engine = engine
        self.request = request

        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.tap(appendingTo: request))
        engine.prepare()
        try engine.start()
        task = recognizer.recognitionTask(with: request, resultHandler: Self.handler(onResult))
        observeInterruptions(of: engine)
    }

    func stop() {
        removeObservers()
        if let engine {
            if engine.isRunning { engine.stop() }
            // Also when the system already stopped the engine: a leftover tap makes the next
            // `installTap` raise an exception.
            engine.inputNode.removeTap(onBus: 0)
        }
        engine = nil
        request?.endAudio()
        request = nil
        task?.finish()
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// A call, Siri or a route change (e.g. headphones) stops the engine; ending the audio then makes the
    /// recognizer deliver its final result with what was heard so far instead of waiting for the timeout.
    private func observeInterruptions(of engine: AVAudioEngine) {
        let center = NotificationCenter.default
        let endAudio: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.endAudioEarly() }
        }
        observers = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main, using: endAudio),
            center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main, using: endAudio),
        ]
    }

    private func endAudioEarly() {
        removeObservers()
        if let engine {
            if engine.isRunning { engine.stop() }
            engine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
    }

    private func removeObservers() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
    }

    // Built outside the main actor: these closures run on audio / recognition threads.
    private nonisolated static func tap(appendingTo request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        { buffer, _ in request.append(buffer) }
    }

    private nonisolated static func handler(_ onResult: @escaping (String, Bool) -> Void) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            let text = result?.bestTranscription.formattedString ?? ""
            let isFinal = (result?.isFinal ?? false) || error != nil
            DispatchQueue.main.async { onResult(text, isFinal) }
        }
    }
}
