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
    func start(onResult: @escaping (String, Bool) -> Void) throws
    func stop()
}

@MainActor
final class SpeechRecognitionService: SpeechRecognizing {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "tr-TR"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    enum RecognitionError: Error { case unavailable }

    var isOnDeviceSupported: Bool { recognizer?.supportsOnDeviceRecognition ?? false }

    func requestAuthorization() async -> Bool {
        let speechStatus = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard speechStatus == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    func start(onResult: @escaping (String, Bool) -> Void) throws {
        guard let recognizer, recognizer.isAvailable else { throw RecognitionError.unavailable }
        stop()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request

        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0), block: Self.tap(appendingTo: request))
        engine.prepare()
        try engine.start()
        task = recognizer.recognitionTask(with: request, resultHandler: Self.handler(onResult))
    }

    func stop() {
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        request = nil
        task?.finish()
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
