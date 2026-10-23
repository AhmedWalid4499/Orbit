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
            Task { @MainActor in self?.level = min(1, rms * 12) }
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

    func speak(_ text: String, then: (() -> Void)? = nil) {
        stop()
        let clean = text
            .replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression) // links → their text
            .replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[*_`#>]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "•", with: "\n")
        let sentences = Self.sentences(clean)
        guard !sentences.isEmpty else { then?(); return }
        let voice = Self.voice(for: clean)
        onDone = then
        speaking = true
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
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
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        speaking = false
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
