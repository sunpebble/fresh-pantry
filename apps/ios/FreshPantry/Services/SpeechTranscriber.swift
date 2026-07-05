import AVFoundation
import Foundation
import Speech

/// On-device push-to-talk dictation (#13): live Chinese speech → text, used to
/// fill the AI 文本解析 editor hands-free at the stove. The transcribed text flows
/// into the SAME `AiIngredientParser.fromText` pipeline as pasted text, so only
/// the capture is new. Audio I/O can't be unit-tested — the parsing it feeds is
/// already covered, and `appendTranscript` (the pure glue) has tests.
@Observable
@MainActor
final class SpeechTranscriber {
    private(set) var isRecording = false
    private(set) var transcript = ""
    private(set) var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-Hans"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    func toggle() async {
        if isRecording { stop() } else { await start() }
    }

    func start() async {
        guard !isRecording else { return }
        errorMessage = nil
        transcript = ""
        guard await Self.requestAuthorization() else {
            errorMessage = String(localized: "error.speech.permissionDenied")
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = String(localized: "error.speech.unavailable")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            // Capture `request` (NOT self) — the tap runs on an audio thread and
            // `append` is safe to call there; touching the main-actor store isn't.
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let finished = error != nil || (result?.isFinal ?? false)
                Task { @MainActor [weak self] in
                    if let text { self?.transcript = text }
                    if finished { self?.stop() }
                }
            }
        } catch {
            errorMessage = String(localized: "error.speech.startFailed \(error.localizedDescription)")
            cleanup()
        }
    }

    func stop() {
        guard isRecording else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        cleanup()
    }

    private func cleanup() {
        isRecording = false
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static func requestAuthorization() async -> Bool {
        let speechAuthorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechAuthorized else { return false }
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Pure: append a freshly dictated `transcript` onto existing editor `text`,
    /// newline-joined, trimming both. Empty transcript leaves text unchanged.
    nonisolated static func appendTranscript(_ transcript: String, to existing: String) -> String {
        let dictated = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dictated.isEmpty else { return existing }
        let base = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        return base.isEmpty ? dictated : base + "\n" + dictated
    }
}
