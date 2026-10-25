import Foundation
import SwiftUI
import AVFoundation
import Speech
import UniformTypeIdentifiers

// MARK: - Attachments

/// A file sent to the assistant: PDFs and images go to Claude as they are, other documents as their text.
struct ChatAttachment: Identifiable, Equatable {
    enum Kind: Equatable { case pdf, image, text }
    let id = UUID()
    let name: String
    let kind: Kind
    /// Base64 for PDFs and images; plain text for everything else.
    let payload: String
    let mediaType: String

    var symbol: String {
        switch kind {
        case .pdf: "doc.richtext"
        case .image: "photo"
        case .text: "doc.text"
        }
    }

    /// The content block for the Messages API.
    var block: [String: Any] {
        switch kind {
        case .pdf:
            ["type": "document", "title": name, "source": ["type": "base64", "media_type": "application/pdf", "data": payload]]
        case .image:
            ["type": "image", "source": ["type": "base64", "media_type": mediaType, "data": payload]]
        case .text:
            ["type": "document", "title": name, "source": ["type": "text", "media_type": "text/plain", "data": payload]]
        }
    }

    static let allowedTypes: [UTType] = [.pdf, .image, .plainText, .commaSeparatedText, .json, .html, .rtf, .rtfd, .xml,
                                         UTType("org.openxmlformats.wordprocessingml.document") ?? .data,
                                         UTType("com.microsoft.word.doc") ?? .data, UTType("net.daringfireball.markdown") ?? .plainText,
                                         UTType("org.oasis-open.opendocument.text") ?? .data]

    static func load(_ url: URL) throws -> ChatAttachment {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        let type = UTType(filenameExtension: ext)

        if type?.conforms(to: .pdf) == true {
            let data = try Data(contentsOf: url)
            guard data.count < 30_000_000 else { throw CloudError("“\(name)” is over 30 MB. Try a smaller PDF.") }
            return ChatAttachment(name: name, kind: .pdf, payload: data.base64EncodedString(), mediaType: "application/pdf")
        }
        if type?.conforms(to: .image) == true {
            // Shrink big photos (and convert HEIC and friends) to a JPEG Claude reads well.
            guard let image = PlatformImage.load(url), let jpeg = image.jpeg(maxSide: 1800) else {
                throw CloudError("Couldn't open the image “\(name)”.")
            }
            return ChatAttachment(name: name, kind: .image, payload: jpeg.base64EncodedString(), mediaType: "image/jpeg")
        }
        var text: String?
        #if os(macOS)
        let rich = ["docx", "doc", "rtf", "rtfd", "odt", "html", "htm", "webarchive"]
        #else
        let rich = ["rtf", "rtfd", "html", "htm"]
        if ["docx", "doc", "odt"].contains(ext) { throw CloudError("Word files can be read on the Mac. On iPhone, share it as a PDF instead.") }
        #endif
        if rich.contains(ext) {
            text = (try? NSAttributedString(url: url, options: [:], documentAttributes: nil))?.string
        }
        if text == nil { text = try? String(contentsOf: url, encoding: .utf8) }
        if text == nil { text = try? String(contentsOf: url, encoding: .isoLatin1) }
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else {
            throw CloudError("Couldn't read “\(name)”. PDFs, images, Word and text files work.")
        }
        return ChatAttachment(name: name, kind: .text, payload: String(t.prefix(150_000)), mediaType: "text/plain")
    }
}

// MARK: - Dictation

/// Speech to text for the chat boxes. Stops by itself after a pause once you've said something.
@MainActor
final class Dictation: ObservableObject {
    static let shared = Dictation()

    @Published private(set) var listening = false
    @Published private(set) var text = ""
    @Published private(set) var level: Float = 0
    @Published var error: String?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var lastChange = Date.now
    private var watcher: Task<Void, Never>?
    private var onFinish: ((String) -> Void)?

    /// Starts listening; `onFinish` gets the transcript when you stop talking (or tap stop).
    func start(onFinish: @escaping (String) -> Void) async {
        guard !listening else { return }
        error = nil
        guard await permissions() else { return }
        let recognizer = SFSpeechRecognizer() ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.isAvailable else { error = "Speech recognition isn't available right now."; return }
        self.onFinish = onFinish
        text = ""
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req
        #if os(iOS)
        // The phone needs the microphone switched on (and other audio ducked) before listening.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker, .allowBluetoothHFP])
        try? session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak self] buffer, _ in
            req.append(buffer)
            let data = buffer.floatChannelData?[0]
            let n = Int(buffer.frameLength)
            var sum: Float = 0
            if let data { for i in 0..<n { sum += data[i] * data[i] } }
            let rms = n > 0 ? sqrt(sum / Float(n)) : 0
            Task { @MainActor in self?.setLevel(min(1, rms * 12)) }
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            self.error = "Couldn't use the microphone: \(error.localizedDescription)"
            return
        }
        recognition = recognizer.recognitionTask(with: req) { [weak self] result, _ in
            guard let t = result?.bestTranscription.formattedString else { return }
            Task { @MainActor in
                guard let self, t != self.text else { return }
                self.text = t
                self.lastChange = .now
            }
        }
        listening = true
        lastChange = .now
        watcher = Task { [weak self] in
            // Finish after 1.6 s of quiet once something was said, or 12 s of silence from the start.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, self.listening else { return }
                let quiet = Date.now.timeIntervalSince(self.lastChange)
                if (!self.text.isEmpty && quiet > 1.6) || (self.text.isEmpty && quiet > 12) { self.stop(); return }
            }
        }
    }

    private var levelAt = Date.distantPast
    /// At most 15 updates a second, so the chat doesn't redraw for every bit of sound.
    private func setLevel(_ v: Float) {
        guard Date.now.timeIntervalSince(levelAt) > 0.066, abs(v - level) > 0.04 else { return }
        levelAt = .now
        level = v
    }

    /// Stops and hands over what was heard.
    func stop() {
        guard listening else { return }
        listening = false
        watcher?.cancel()
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        recognition?.finish()
        recognition = nil
        request = nil
        level = 0
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        let heard = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let done = onFinish
        onFinish = nil
        done?(heard)
    }

    /// Stops without sending anything.
    func cancel() {
        onFinish = nil
        stop()
        text = ""
    }

    private func permissions() async -> Bool {
        let speech = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard speech == .authorized else { error = "Allow Speech Recognition for Orbit in System Settings › Privacy & Security."; return false }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            error = "Allow the microphone for Orbit in System Settings › Privacy & Security."; return false
        }
        return true
    }
}

// MARK: - Spoken replies

/// Reads replies aloud with the best voice installed for the language.
@MainActor
final class Speaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = Speaker()

    @Published private(set) var speaking = false
    private let synth = AVSpeechSynthesizer()
    private var onDone: (() -> Void)?

    override private init() {
        super.init()
        synth.delegate = self
    }

    private var pending = 0

    /// Set for speech you didn't ask for (the welcome): on iPhone it stays silent when the ring/silent switch is on silent.
    private(set) var quiet = false

    func speak(_ text: String, quiet: Bool = false, then: (() -> Void)? = nil) {
        stop()
        self.quiet = quiet
        if NaturalVoice.isOn {
            onDone = then
            speaking = true
            let token = UUID()
            natural = token
            Task {
                let ok = await NaturalVoice.shared.speak(Self.plain(text)) { [weak self] in self?.natural == token }
                guard self.natural == token else { return }
                self.natural = nil
                if ok { self.finished() } else { self.speakWithApple(text) }
            }
            return
        }
        onDone = then
        speakWithApple(text)
    }

    /// Set while a natural (online) reply is playing; cleared by stop().
    private var natural: UUID?

    private func finished() {
        speaking = false
        let done = onDone
        onDone = nil
        done?()
    }

    /// Text without links, markdown or bullets, for reading aloud.
    static func plain(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[*_`#>]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "•", with: "\n")
    }

    private func speakWithApple(_ text: String) {
        let then = onDone
        let clean = text
            .replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression) // links → their text
            .replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[*_`#>]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "•", with: "\n")
        let sentences = Self.sentences(clean)
        guard !sentences.isEmpty else { finished(); return }
        let voice = Self.voice(for: clean)
        onDone = then
        speaking = true
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(Speaker.shared.quiet ? .ambient : .playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        // One utterance per sentence, with a breath in between and a little variation, so it sounds like someone talking
        // rather than a block of text being read out.
        pending = sentences.count
        for (i, sentence) in sentences.enumerated() {
            let u = AVSpeechUtterance(string: sentence)
            u.voice = voice
            let question = sentence.hasSuffix("?")
            u.rate = AVSpeechUtteranceDefaultSpeechRate * (sentence.count < 40 ? 0.98 : 1.03)
            u.pitchMultiplier = question ? 1.04 : (i == 0 ? 1.02 : 1.0)
            u.preUtteranceDelay = i == 0 ? 0.05 : 0
            u.postUtteranceDelay = sentence.hasSuffix(",") || sentence.hasSuffix(":") ? 0.08 : 0.22
            synth.speak(u)
        }
    }

    func stop() {
        onDone = nil
        pending = 0
        natural = nil
        liveToken = UUID()
        liveQueue = []
        appleWaiter?.resume()
        appleWaiter = nil
        NaturalVoice.shared.stop()
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        speaking = false
    }

    /// Runs `then` once nothing is being read aloud (right away if it's quiet).
    func whenDone(_ then: @escaping () -> Void) {
        if speaking { onDone = then } else { then() }
    }

    // MARK: Speaking while the reply is written

    /// Sentences waiting to be read, in order; the reader works through them as the reply streams in.
    private var liveQueue: [String] = []
    private var liveEnded = true
    private var liveToken = UUID()
    /// How much of the current part of the reply has been queued already.
    private var liveQueued = 0
    private var appleWaiter: CheckedContinuation<Void, Never>?

    /// Starts reading a reply that's still being written: feed it with `liveFeed` and close with `liveEnd`.
    func liveBegin() {
        stop()
        quiet = false
        let token = UUID()
        liveToken = token
        liveQueue = []
        liveQueued = 0
        liveEnded = false
        speaking = true
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(Speaker.shared.quiet ? .ambient : .playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        Task { await readLive(token) }
    }

    /// The reply so far (of the current part). Whole sentences are queued as soon as they're complete;
    /// `final` queues the rest and makes the next call start a new part.
    func liveFeed(_ text: String, final: Bool = false) {
        guard !liveEnded else { return }
        let chars = Array(text)
        guard liveQueued <= chars.count else { liveQueued = 0; return }
        var cut = liveQueued
        if final {
            cut = chars.count
        } else {
            // The end of the last finished sentence: . ! ? or a line break, followed by a space.
            var i = chars.count - 2
            while i >= liveQueued {
                if ".!?\n".contains(chars[i]) && (chars[i + 1] == " " || chars[i + 1] == "\n") { cut = i + 1; break }
                if chars[i] == "\n" { cut = i + 1; break }
                i -= 1
            }
        }
        if cut > liveQueued {
            let piece = String(chars[liveQueued..<cut])
            liveQueue += Self.sentences(Self.plain(piece))
            liveQueued = cut
        }
        if final { liveQueued = 0 }
    }

    /// No more text is coming; reading finishes with what's queued.
    func liveEnd() { liveEnded = true }

    private func readLive(_ token: UUID) async {
        var index = 0
        var useNatural = NaturalVoice.isOn
        let key = Keychain.read("openai-key") ?? ""
        var clips: [Int: Task<Data?, Never>] = [:]
        while liveToken == token {
            if index < liveQueue.count {
                let sentence = liveQueue[index]
                if useNatural && !key.isEmpty {
                    // Ask for the next few sentences' audio ahead, so there are no gaps between them.
                    for k in index..<min(index + 3, liveQueue.count) where clips[k] == nil {
                        let s = liveQueue[k]
                        clips[k] = Task { try? await NaturalVoice.audio(s, key: key) }
                    }
                    if let data = await clips[index]?.value {
                        guard liveToken == token else { break }
                        await NaturalVoice.shared.playClip(data)
                    } else {
                        useNatural = false
                        await sayApple(sentence)
                    }
                } else {
                    await sayApple(sentence)
                }
                clips[index] = nil
                index += 1
            } else if liveEnded {
                break
            } else {
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
        clips.values.forEach { $0.cancel() }
        guard liveToken == token else { return }
        liveEnded = true
        finished()
    }

    /// One sentence with the Apple voice, returning when it's been said.
    private func sayApple(_ sentence: String) async {
        let u = AVSpeechUtterance(string: sentence)
        u.voice = Self.voice(for: sentence)
        u.rate = AVSpeechUtteranceDefaultSpeechRate * (sentence.count < 40 ? 0.98 : 1.03)
        u.pitchMultiplier = sentence.hasSuffix("?") ? 1.04 : 1.0
        u.postUtteranceDelay = sentence.hasSuffix(",") || sentence.hasSuffix(":") ? 0.08 : 0.2
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            appleWaiter = c
            synth.speak(u)
        }
    }

    /// Splits text into sentences (and list lines), keeping the punctuation.
    static func sentences(_ text: String) -> [String] {
        var out: [String] = []
        for line in text.components(separatedBy: .newlines) {
            let l = line.trimmingCharacters(in: .whitespaces)
            guard !l.isEmpty else { continue }
            var parts: [String] = []
            l.enumerateSubstrings(in: l.startIndex..., options: .bySentences) { sub, _, _, _ in
                if let s = sub?.trimmingCharacters(in: .whitespaces), !s.isEmpty { parts.append(s) }
            }
            out += parts.isEmpty ? [l] : parts
        }
        return out
    }

    /// The voice picked in Settings › AI, or the most natural one installed.
    static func voice(for text: String) -> AVSpeechSynthesisVoice? {
        let arabic = text.unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) }
        if !arabic, let id = UserDefaults.standard.string(forKey: "assistantVoice"), let v = AVSpeechSynthesisVoice(identifier: id) { return v }
        return bestVoice(for: text)
    }

    /// Voices that sound like a person: premium first, then enhanced; the robotic Eloquence and novelty voices are left out.
    static func naturalVoices(language: String) -> [AVSpeechSynthesisVoice] {
        let region = Locale.current.region?.identifier ?? ""
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language) && !$0.identifier.contains("eloquence") && !$0.identifier.contains("speech.synthesis.voice")
                && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .sorted {
                if $0.quality != $1.quality { return $0.quality.rawValue > $1.quality.rawValue }
                let r0 = $0.language.hasSuffix(region), r1 = $1.language.hasSuffix(region)
                if r0 != r1 { return r0 }
                let us0 = $0.language == "en-US", us1 = $1.language == "en-US"
                if us0 != us1 { return us0 }
                return $0.name < $1.name
            }
    }

    static func bestVoice(for text: String) -> AVSpeechSynthesisVoice? {
        let arabic = text.unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) }
        let lang = arabic ? "ar" : (Locale.current.language.languageCode?.identifier ?? "en")
        return naturalVoices(language: lang).first ?? AVSpeechSynthesisVoice(language: arabic ? "ar-SA" : nil)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if let w = self.appleWaiter { self.appleWaiter = nil; w.resume(); return }
            self.pending -= 1
            guard self.pending <= 0 else { return }
            self.speaking = false
            let done = self.onDone
            self.onDone = nil
            done?()
        }
    }
}

// MARK: - Shared composer controls

/// Mic button: tap to talk, tap again to stop. Pulses with your voice.
struct MicButton: View {
    @ObservedObject private var dictation = Dictation.shared
    let onText: (String) -> Void

    var body: some View {
        Button {
            if dictation.listening { dictation.stop() } else { Task { await dictation.start(onFinish: onText) } }
        } label: {
            Image(systemName: dictation.listening ? "stop.fill" : "mic.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(dictation.listening ? Theme.stickerInk : Theme.inkSecondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(dictation.listening ? Theme.pink : Theme.canvas))
                .scaleEffect(dictation.listening ? 1 + CGFloat(dictation.level) * 0.25 : 1)
                .animation(.easeOut(duration: 0.12), value: dictation.level)
        }
        .buttonStyle(.plain)
        .help(dictation.listening ? "Stop listening" : "Talk instead of typing")
    }
}

// MARK: - Natural voice (OpenAI)

/// Replies read by OpenAI's text-to-speech, the same kind of voice ChatGPT talks with. Needs an OpenAI API key
/// (Settings › AI › Voice, kept in the Keychain). Falls back to the Apple voice when there's no key or no connection.
@MainActor
final class NaturalVoice: NSObject, AVAudioPlayerDelegate {
    static let shared = NaturalVoice()
    static let voices = ["coral", "nova", "shimmer", "sage", "alloy", "ash", "ballad", "echo", "fable", "onyx", "verse"]

    static var hasKey: Bool { !(Keychain.read("openai-key") ?? "").isEmpty }
    /// On when there's a key, unless switched off in Settings.
    static var isOn: Bool { hasKey && UserDefaults.standard.object(forKey: "voice.natural") as? Bool ?? true }
    static var voice: String { UserDefaults.standard.string(forKey: "voice.openai") ?? "coral" }

    private var player: AVAudioPlayer?
    private var finished: CheckedContinuation<Void, Never>?

    /// Plays `text`; returns false if it couldn't (so the caller can use the Apple voice). `still` says whether
    /// the reply is still wanted (stop() was not pressed meanwhile).
    func speak(_ text: String, still: @escaping () -> Bool) async -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let key = Keychain.read("openai-key"), !key.isEmpty else { return false }
        // The first sentence goes on its own so it starts talking quickly while the rest is made.
        let sentences = Speaker.sentences(t)
        var chunks: [String] = []
        if let first = sentences.first { chunks.append(first) }
        var rest = ""
        for s in sentences.dropFirst() {
            if rest.count + s.count > 3500 { chunks.append(rest); rest = "" }
            rest += (rest.isEmpty ? "" : " ") + s
        }
        if !rest.isEmpty { chunks.append(rest) }
        let jobs = chunks.map { chunk in Task { try await Self.audio(chunk, key: key) } }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(Speaker.shared.quiet ? .ambient : .playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        for (i, job) in jobs.enumerated() {
            guard let data = try? await job.value else {
                jobs.forEach { $0.cancel() }
                return i > 0 // part of it was read; don't start over with the other voice
            }
            guard still() else { jobs.forEach { $0.cancel() }; return true }
            await play(data)
            guard still() else { jobs.forEach { $0.cancel() }; return true }
        }
        return true
    }

    func stop() {
        player?.stop()
        player = nil
        finished?.resume()
        finished = nil
    }

    /// Plays one clip made by `audio` (used when reading a reply as it's written).
    func playClip(_ data: Data) async { await play(data) }

    private func play(_ data: Data) async {
        guard let p = try? AVAudioPlayer(data: data) else { return }
        player = p
        p.delegate = self
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            finished = c
            if !p.play() { finished = nil; c.resume() }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.finished?.resume()
            self.finished = nil
        }
    }

    static func audio(_ text: String, key: String) async throws -> Data {
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "gpt-4o-mini-tts", "voice": voice, "input": text, "response_format": "mp3",
            "instructions": "Speak like a warm, relaxed friend having a real conversation: natural pace, light expression, small pauses, never like an announcer.",
        ])
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, !data.isEmpty else {
            let msg = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]).flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
            throw CloudError("OpenAI voice error \(status)\(msg.map { ": \($0)" } ?? "")")
        }
        return data
    }

    /// For Settings: checks the key by making a short clip.
    static func test(key: String) async -> String? {
        do { _ = try await audio("Hi!", key: key); return nil } catch { return error.localizedDescription }
    }
}
