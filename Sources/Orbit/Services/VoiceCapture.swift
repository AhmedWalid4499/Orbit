import Foundation
import SwiftUI
import SwiftData
import AVFoundation
import Speech
import AppKit

/// Hold ⌥Space and talk. Speech is transcribed on the Mac, then Ask files it (task, event, expense, note…),
/// or, if it sounds like a question, opens Ask with it. A quick tap still opens the typed quick-capture box.
@MainActor
final class VoiceCapture: ObservableObject {
    static let shared = VoiceCapture()

    enum Phase: Equatable { case idle, listening, thinking, done(String), failed(String) }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var level: Float = 0

    private var holdTimer: Task<Void, Never>?
    private var isHolding = false
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var panel: NSPanel?
    private static let holdDelay: Duration = .milliseconds(350)

    // MARK: Key handling (tap vs hold)

    private var keyIsDown = false

    func keyDown() {
        guard !keyIsDown else { return } // ignore key repeat while held
        keyIsDown = true
        holdTimer?.cancel()
        isHolding = false
        holdTimer = Task {
            try? await Task.sleep(for: Self.holdDelay)
            guard !Task.isCancelled else { return }
            isHolding = true
            await start()
        }
    }

    func keyUp() {
        keyIsDown = false
        holdTimer?.cancel()
        if isHolding {
            isHolding = false
            Task { await finish() }
        } else {
            CapturePanel.shared.toggle()
        }
    }

    // MARK: Recording

    private func start() async {
        guard await permissions(), isHolding else { return }   // the key may have come up during the permission prompt
        let recognizer = SFSpeechRecognizer() ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.isAvailable else { show(.failed("Speech recognition isn't available right now.")); return }

        transcript = ""
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            req.append(buffer)
            let data = buffer.floatChannelData?[0]
            let n = Int(buffer.frameLength)
            var sum: Float = 0
            if let data { for i in 0..<n { sum += data[i] * data[i] } }
            let rms = n > 0 ? sqrt(sum / Float(n)) : 0
            Task { @MainActor in self?.level = min(1, rms * 12) }
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            show(.failed("Couldn't use the microphone: \(error.localizedDescription)"))
            return
        }
        recognition = recognizer.recognitionTask(with: req) { [weak self] result, _ in
            guard let text = result?.bestTranscription.formattedString else { return }
            Task { @MainActor in self?.transcript = text }
        }
        show(.listening)
    }

    private func finish() async {
        guard phase == .listening else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        show(.thinking)
        try? await Task.sleep(for: .milliseconds(700)) // let the last words come in
        recognition?.finish()
        recognition = nil
        request = nil
        level = 0

        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { show(.failed("Didn't catch that. Hold ⌥Space a little longer while you talk.")); return }
        if Self.isQuestion(text) {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
            AppState.current?.openAssistant(with: text)
            show(.done("Asked \(AssistantName.current)"))
        } else if let container = OrbitStore.container {
            let summary = await CaptureEngine.capture(text, context: container.mainContext)
            show(summary.isEmpty ? .failed("Nothing to save in “\(text)”.") : .done(summary))
        }
        try? await Task.sleep(for: .seconds(2.5))
        if case .listening = phase { return }
        hide()
    }

    static func isQuestion(_ text: String) -> Bool {
        let t = text.lowercased()
        if t.hasSuffix("?") { return true }
        let starts = ["what", "how", "why", "when should", "should i", "can you", "could you", "help me", "recommend", "suggest",
                      "tell me", "ask ", "which", "who", "is it", "do i"]
        return starts.contains { t.hasPrefix($0) }
    }

    private func permissions() async -> Bool {
        let speech = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard speech == .authorized else { show(.failed("Allow Speech Recognition for Joshu in System Settings › Privacy & Security.")); return false }
        let mic = await AVCaptureDevice.requestAccess(for: .audio)
        guard mic else { show(.failed("Allow the microphone for Joshu in System Settings › Privacy & Security.")); return false }
        return true
    }

    // MARK: HUD

    private func show(_ p: Phase) {
        phase = p
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 120), styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let host = NSHostingView(rootView: VoiceHUD())
            host.sizingOptions = [.preferredContentSize]
            panel.contentView = host
            self.panel = panel
        }
        if let panel, let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: f.minY + 120))
            panel.orderFrontRegardless()
        }
        if case .failed = p {
            Task { try? await Task.sleep(for: .seconds(3.5)); if case .failed = phase { hide() } }
        }
    }

    private func hide() {
        panel?.orderOut(nil)
        phase = .idle
        transcript = ""
    }
}

private struct VoiceHUD: View {
    @ObservedObject private var voice = VoiceCapture.shared

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(color).frame(width: 44, height: 44)
                    .scaleEffect(voice.phase == .listening ? 1 + CGFloat(voice.level) * 0.35 : 1)
                    .animation(.easeOut(duration: 0.12), value: voice.level)
                Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.stickerInk)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.ui(12, weight: .semibold)).foregroundStyle(Color.white.opacity(0.7))
                Text(detail).font(Theme.ui(15, weight: .medium)).foregroundStyle(.white).lineLimit(3)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(width: 460)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(hex: 0x141416)))
    }

    private var color: Color {
        switch voice.phase {
        case .listening: Theme.pink
        case .done: Theme.lime
        case .failed: Theme.orange
        default: Theme.cyan
        }
    }
    private var symbol: String {
        switch voice.phase {
        case .listening: "mic.fill"
        case .thinking: "sparkles"
        case .done: "checkmark"
        case .failed: "exclamationmark"
        case .idle: "mic"
        }
    }
    private var title: String {
        switch voice.phase {
        case .listening: "Listening… let go of ⌥Space when you're done"
        case .thinking: "\(AssistantName.current) is filing it…"
        case .done: "Done"
        case .failed: "Couldn't do that"
        case .idle: ""
        }
    }
    private var detail: String {
        switch voice.phase {
        case .listening, .thinking: voice.transcript.isEmpty ? "Say something like “Dentist Thursday at 3”" : voice.transcript
        case .done(let s), .failed(let s): s
        case .idle: ""
        }
    }
}
