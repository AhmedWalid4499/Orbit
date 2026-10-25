import Foundation
import AVFoundation

/// The natural (OpenAI) voice, streamed: audio starts playing a moment after each sentence is sent, instead of
/// waiting for the whole clip to be made, and sentences follow each other without gaps.
@MainActor
final class VoiceStream {
    static let shared = VoiceStream()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    /// OpenAI's raw audio: 24 kHz, 16-bit, mono.
    private let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000, channels: 1, interleaved: false)!
    private var queued = 0
    private var started = false
    private var drained: CheckedContinuation<Void, Never>?

    private init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    /// Streams `text` and queues its audio as it arrives; returns once it's all downloaded (it keeps playing).
    /// False if OpenAI couldn't be reached, so the caller can use the Apple voice instead.
    func say(_ text: String, key: String, still: () -> Bool) async -> Bool {
        guard startEngine() else { return false }
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": "gpt-4o-mini-tts", "voice": NaturalVoice.voice, "input": text, "response_format": "pcm",
            "instructions": "Speak like a warm, relaxed friend having a real conversation: natural pace, light expression, small pauses, never like an announcer.",
        ])
        // Downloaded off the main thread, in ~0.1 s pieces (small enough to start quickly, big enough to play smoothly).
        enum Piece { case audio(Data), failed }
        let request = req
        let pieces = AsyncStream<Piece> { cont in
            let job = Task.detached {
                guard let (bytes, response) = try? await URLSession.shared.bytes(for: request),
                      (response as? HTTPURLResponse)?.statusCode == 200 else { cont.yield(.failed); cont.finish(); return }
                var pending = Data()
                pending.reserveCapacity(9600)
                do {
                    for try await byte in bytes {
                        if Task.isCancelled { break }
                        pending.append(byte)
                        if pending.count >= 9600 { cont.yield(.audio(pending)); pending.removeAll(keepingCapacity: true) }
                    }
                } catch {}
                if pending.count > 1 { cont.yield(.audio(pending.count % 2 == 0 ? pending : pending.dropLast())) }
                cont.finish()
            }
            cont.onTermination = { _ in job.cancel() }
        }
        var gotAudio = false
        for await piece in pieces {
            guard still() else { return true }
            switch piece {
            case .failed: return gotAudio
            case .audio(let d): schedule(d); gotAudio = true
            }
        }
        return gotAudio
    }

    /// Waits until everything queued has been heard.
    func finish() async {
        guard queued > 0 else { return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in drained = c }
    }

    func stop() {
        player.stop()
        queued = 0
        drained?.resume()
        drained = nil
        if engine.isRunning { engine.stop() }
        started = false
    }

    private func startEngine() -> Bool {
        if started && engine.isRunning { return true }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        do { try engine.start() } catch { return false }
        player.play()
        started = true
        return true
    }

    private func schedule(_ data: Data) {
        let frames = AVAudioFrameCount(data.count / 2)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames), let out = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = frames
        data.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            for i in 0..<Int(frames) { out[i] = Float(Int16(littleEndian: samples[i])) / 32768 }
        }
        queued += 1
        player.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.queued = max(0, self.queued - 1)
                if self.queued == 0 { self.drained?.resume(); self.drained = nil }
            }
        }
    }
}
