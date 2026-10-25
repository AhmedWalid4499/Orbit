import Foundation
import AVFoundation
import Speech
import SwiftData

/// Hands-free voice mode. While Orbit is open it listens (on this device, nothing is sent anywhere) for
/// "Hey <assistant name>". Then the big orb takes the middle of the screen and you just talk: it answers out loud,
/// listens again, and keeps the conversation going until you say "stop" / "bye", tap the orb's ✕, or go quiet for
/// a while. The chat isn't opened; the conversation is still saved in your past chats. Settings › AI › Voice.
@MainActor
final class WakeListener: ObservableObject {
    static let shared = WakeListener()

    /// Whether "Hey <name>" is listened for (per device).
    @Published var enabled = UserDefaults.standard.bool(forKey: "wake.enabled") {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "wake.enabled")
            if enabled { error = nil; Task { await permissions() } } else if !inConversation { stop() }
        }
    }
    /// The app is in front (iPhone) or running (Mac).
    var appActive = true { didSet { if !appActive { endConversation(); stop() } } }
    /// Calendar and reminders for the assistant (set by the window).
    var apple: AppleSync?

    @Published private(set) var listening = false
    /// A voice conversation is going on: the orb is in the middle of the screen.
    @Published private(set) var inConversation = false { didSet { meter?.on = inConversation } }
    /// What you're saying right now.
    @Published private(set) var heard = ""
    /// Your last question, shown under the orb while it thinks and answers.
    @Published private(set) var lastQuestion = ""
    @Published private(set) var awake = false
    /// How loud you are (0…1), for the orb's pulse.
    @Published private(set) var level: Float = 0
    @Published var error: String?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var transcript = ""
    private var lastChange = Date.now
    private var startedAt = Date.now
    private var allowed = false
    private var loop: Task<Void, Never>?

    private init() {
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                await self?.tick()
            }
        }
    }

    /// Something else is using the microphone or the speaker, so wait.
    private var busy: Bool {
        Dictation.shared.listening || Speaker.shared.speaking || AssistantStore.shared.busy
    }

    // MARK: Conversation

    /// Starts talking without the wake word (the voice button in the chat).
    func startConversation() {
        Task {
            if !allowed { guard await permissions() else { return } }
            inConversation = true
            if listening { awake = true; transcript = ""; heard = "" }
        }
    }

    /// Demo only (`-voice` launch option): shows voice mode with a sample question, no microphone.
    func preview() {
        guard Snapshot.isDemo else { return }
        inConversation = true
        awake = true
        heard = "Where can I get a good coffee near me?"
    }

    /// Ends voice mode: stops speaking, and goes back to waiting for "Hey <name>" (if that's on).
    func endConversation() {
        guard inConversation else { return }
        inConversation = false
        awake = false
        heard = ""
        lastQuestion = ""
        Speaker.shared.stop()
        if listening { restart() }
    }

    /// Tapping the orb while it talks: stop and listen.
    func interrupt() {
        if Speaker.shared.speaking { Speaker.shared.stop() }
    }

    private func tick() async {
        guard (enabled || inConversation), appActive, !Snapshot.isActive else { if listening { stop() }; return }
        if busy {
            if listening { stop() }
            return
        }
        if !listening {
            if !allowed { guard await permissions() else { return } }
            start()
            return
        }
        let quiet = Date.now.timeIntervalSince(lastChange)
        if awake {
            // You stopped talking: send it.
            if !heard.isEmpty && quiet > 1.3 { fire(heard); return }
            // Nothing said for a long while: the conversation is over.
            if heard.isEmpty && quiet > (inConversation ? 45 : 8) { endConversation(); return }
            if heard.isEmpty && Date.now.timeIntervalSince(startedAt) > 50 { restart() }
        } else if Date.now.timeIntervalSince(startedAt) > 50 && quiet > 2 {
            // Keep each listening session short so the recogniser stays quick and accurate.
            restart()
        }
    }

    private func start() {
        let recognizer = SFSpeechRecognizer() ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.isAvailable else { error = "Speech recognition isn't available right now."; return }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        // Punctuation only matters for a question you're asking; listening for the wake word stays light.
        req.addsPunctuation = inConversation
        req.taskHint = inConversation ? .dictation : .search
        req.contextualStrings = ["Hey \(AssistantName.current)", AssistantName.current]
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothHFP])
        try? session.setActive(true)
        #endif
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { error = "No microphone found."; return }
        // Bigger pieces of audio (~0.1 s) mean far less work; the loudness for the orb is only measured while it shows.
        let meter = Meter(on: inConversation)
        self.meter = meter
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            req.append(buffer)
            guard meter.on, let v = meter.level(buffer) else { return }
            Task { @MainActor in self?.setLevel(v) }
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            self.error = "Couldn't use the microphone: \(error.localizedDescription)"
            input.removeTap(onBus: 0)
            return
        }
        transcript = ""
        heard = ""
        // In a conversation every listen is a question; otherwise wait for the wake word.
        awake = inConversation
        startedAt = .now
        lastChange = .now
        listening = true
        recognition = recognizer.recognitionTask(with: req) { [weak self] result, err in
            let text = result?.bestTranscription.formattedString
            let ended = err != nil || result?.isFinal == true
            Task { @MainActor in
                guard let self else { return }
                if let text, text != self.transcript { self.transcript = text; self.lastChange = .now; self.update() }
                if ended, self.listening, self.heard.isEmpty { self.restart() }
            }
        }
    }

    private var meter: Meter?
    private var levelAt = Date.distantPast
    /// The orb's pulse: only while it's showing, at most 15 times a second, and only when it really changes.
    private func setLevel(_ v: Float) {
        guard inConversation, Date.now.timeIntervalSince(levelAt) > 0.066, abs(v - level) > 0.04 else { return }
        levelAt = .now
        level = v
    }

    /// Looks for the wake word; once heard, voice mode starts and everything after it is the question.
    private func update() {
        if let r = Self.wakeRange(in: transcript) {
            awake = true
            inConversation = true
            let h = String(transcript[r.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?"))
            if h != heard { heard = h }
        } else if awake {
            let h = transcript.trimmingCharacters(in: .whitespaces)
            if h != heard { heard = h }
        }
    }

    private func fire(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        stop()
        awake = false
        heard = ""
        guard !question.isEmpty else { return }
        if Self.isGoodbye(question) { endConversation(); return }
        lastQuestion = question
        guard let context = OrbitStore.container?.mainContext else { return }
        let store = AssistantStore.shared
        store.speakNextReply = true
        let apple = apple ?? AppleSync()
        Task { await store.send(question, context: context, apple: apple) }
    }

    /// "Stop", "that's all", "bye", "thank you, that's it"…
    static func isGoodbye(_ text: String) -> Bool {
        let t = text.lowercased().replacingOccurrences(of: #"[^\p{L}' ]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        let exact = ["stop", "stop it", "stop talking", "be quiet", "cancel", "never mind", "nevermind", "that's all", "thats all",
                     "that's it", "thats it", "bye", "goodbye", "good bye", "bye bye", "we're done", "were done", "i'm done", "im done",
                     "thank you that's all", "thanks that's all", "thank you that's it", "thanks that's it", "thanks bye", "thank you bye",
                     "okay bye", "ok bye", "end", "exit", "quit"]
        if exact.contains(t) { return true }
        let words = t.split(separator: " ")
        return words.count <= 4 && (words.contains("bye") || words.contains("goodbye") || t.hasPrefix("stop"))
    }

    private func restart() {
        stop()
        start()
    }

    func stop() {
        guard listening || request != nil else { return }
        listening = false
        level = 0
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        recognition?.cancel()
        recognition = nil
        request = nil
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    @discardableResult
    private func permissions() async -> Bool {
        let speech = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard speech == .authorized else { error = "Allow Speech Recognition for Orbit in Settings › Privacy & Security."; enabledOff(); return false }
        guard await AVCaptureDevice.requestAccess(for: .audio) else { error = "Allow the microphone for Orbit in Settings › Privacy & Security."; enabledOff(); return false }
        allowed = true
        return true
    }

    private func enabledOff() {
        UserDefaults.standard.set(false, forKey: "wake.enabled")
        enabled = false
        inConversation = false
    }

    // MARK: Matching

    /// Where "hey <name>" ends in what was heard, allowing for how the recogniser spells names ("Yuki", "you key").
    static func wakeRange(in text: String, name: String = AssistantName.current) -> Range<String.Index>? {
        let want = letters(name)
        guard want.count >= 2 else { return nil }
        let lower = text
        let pattern = #"\b(hey|hi|hay|okay|ok)\b[\s,]+"#
        var search = lower.startIndex..<lower.endIndex
        while let greet = lower.range(of: pattern, options: [.regularExpression, .caseInsensitive], range: search) {
            // Compare the next one or two words, squashed together, with the name.
            let rest = lower[greet.upperBound...]
            let words = rest.split(whereSeparator: { $0 == " " || $0 == "," }).prefix(2)
            var end = greet.upperBound
            var joined = ""
            for w in words {
                joined += letters(String(w))
                if let r = rest.range(of: w) { end = r.upperBound }
                if close(joined, want) { return greet.lowerBound..<end }
                if joined.count >= want.count + 2 { break }
            }
            search = greet.upperBound..<lower.endIndex
        }
        return nil
    }

    /// Letters only, spelled the way they sound, so "you key", "Yuuki" and "Yuki" compare alike.
    private static func letters(_ s: String) -> String {
        var t = s.lowercased().folding(options: .diacriticInsensitive, locale: nil).filter(\.isLetter)
        for (a, b) in [("ou", "u"), ("oo", "u"), ("uu", "u"), ("ee", "i"), ("ey", "i"), ("ie", "i"), ("ck", "k"), ("ph", "f")] {
            t = t.replacingOccurrences(of: a, with: b)
        }
        if t.count > 2, t.hasSuffix("y") { t = String(t.dropLast()) + "i" }
        return t
    }

    private static func close(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let allowed = b.count <= 4 ? 1 : 2
        guard abs(a.count - b.count) <= allowed else { return false }
        let x = Array(a), y = Array(b)
        var row = Array(0...y.count)
        for i in 1...x.count {
            var prev = row[0]
            row[0] = i
            for j in 1...y.count {
                let cur = row[j]
                row[j] = x[i - 1] == y[j - 1] ? prev : min(prev, row[j], row[j - 1]) + 1
                prev = cur
            }
        }
        return row[y.count] <= allowed
    }
}

/// Measures how loud the microphone is, on the audio thread, at most 15 times a second, only when switched on.
final class Meter: @unchecked Sendable {
    var on: Bool
    private var last = Date.distantPast
    init(on: Bool) { self.on = on }

    func level(_ buffer: AVAudioPCMBuffer) -> Float? {
        guard Date.now.timeIntervalSince(last) > 0.066, let data = buffer.floatChannelData?[0] else { return nil }
        last = .now
        let n = Int(buffer.frameLength)
        guard n >= 4 else { return nil }
        var sum: Float = 0
        // Every fourth sample is plenty for a loudness reading.
        for i in stride(from: 0, to: n, by: 4) { sum += data[i] * data[i] }
        return min(1, sqrt(sum / Float(n / 4)) * 14)
    }
}
