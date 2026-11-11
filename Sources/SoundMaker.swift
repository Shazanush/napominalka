import Foundation
import AVFoundation

/// Делает звуковой файл: сигнал + твой текст, прочитанный голосом.
/// Файл кладётся в Library/Sounds — оттуда iOS берёт звуки для уведомлений,
/// поэтому текст читается даже на заблокированном телефоне.
@MainActor
final class SoundMaker {
    static let shared = SoundMaker()
    private let maxSeconds: Double = 29

    static var soundsDir: URL {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func fileName(for r: Reminder) -> String { "r-\(r.id.uuidString)-\(r.soundRev).caf" }
    static func url(for r: Reminder) -> URL { soundsDir.appendingPathComponent(fileName(for: r)) }

    static func removeSounds(for id: UUID, except keep: String? = nil) {
        let fm = FileManager.default
        let prefix = "r-\(id.uuidString)-"
        let files = (try? fm.contentsOfDirectory(atPath: soundsDir.path)) ?? []
        for f in files where f.hasPrefix(prefix) && f != keep {
            try? fm.removeItem(at: soundsDir.appendingPathComponent(f))
        }
    }

    /// Возвращает имя файла звука или nil (тогда стандартный звук).
    func ensureSound(for r: Reminder) async -> String? {
        if r.kind == .notification && !r.speak { return nil }
        let name = SoundMaker.fileName(for: r)
        let url = SoundMaker.url(for: r)
        if FileManager.default.fileExists(atPath: url.path) { return name }
        SoundMaker.removeSounds(for: r.id, except: name)

        var rate: Double = 22050
        var speech: [Float] = []
        if r.speak {
            let res = await SpeechRenderer.render(r.spokenText)
            speech = res.samples
            if res.rate > 0 { rate = res.rate }
            normalize(&speech)
        }

        let maxCount = Int(rate * maxSeconds)
        var out: [Float] = []
        if r.kind == .alarm {
            repeat {
                out += alarmBeeps(rate)
                if !speech.isEmpty {
                    out += silence(0.25, rate)
                    out += speech
                }
                out += silence(0.6, rate)
            } while out.count < maxCount
        } else {
            out = chime(rate) + silence(0.2, rate) + speech
        }
        if out.count > maxCount { out = Array(out.prefix(maxCount)) }
        fadeOut(&out, rate)

        do {
            try write(out, rate: rate, to: url)
            return name
        } catch {
            return nil
        }
    }

    // MARK: генерация звука

    private func tone(_ freq: Double, _ dur: Double, _ rate: Double, amp: Float = 0.6) -> [Float] {
        let n = Int(dur * rate)
        let fade = max(1, Int(0.008 * rate))
        var s = [Float](repeating: 0, count: n)
        for i in 0..<n {
            var env: Float = 1
            if i < fade { env = Float(i) / Float(fade) }
            if i > n - fade { env = Float(n - i) / Float(fade) }
            let v = sin(2 * Double.pi * freq * Double(i) / rate)
            s[i] = Float(v) * amp * env
        }
        return s
    }

    private func silence(_ dur: Double, _ rate: Double) -> [Float] {
        [Float](repeating: 0, count: Int(dur * rate))
    }

    private func alarmBeeps(_ rate: Double) -> [Float] {
        var s: [Float] = []
        for _ in 0..<2 {
            for _ in 0..<4 {
                s += tone(1046, 0.12, rate, amp: 0.75)
                s += silence(0.07, rate)
            }
            s += silence(0.35, rate)
        }
        return s
    }

    private func chime(_ rate: Double) -> [Float] {
        tone(880, 0.15, rate, amp: 0.5) + tone(1318, 0.25, rate, amp: 0.5)
    }

    private func normalize(_ s: inout [Float]) {
        let peak = s.reduce(Float(0)) { max($0, abs($1)) }
        guard peak > 0.0001 else { return }
        let gain = min(Float(0.95) / peak, 4)
        for i in s.indices { s[i] *= gain }
    }

    private func fadeOut(_ s: inout [Float], _ rate: Double) {
        let n = min(s.count, Int(0.05 * rate))
        guard n > 0 else { return }
        for k in 0..<n {
            s[s.count - 1 - k] *= Float(k) / Float(n)
        }
    }

    private func write(_ samples: [Float], rate: Double, to url: URL) throws {
        guard let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false),
              let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(max(samples.count, 1))),
              let ch = buf.floatChannelData else {
            throw NSError(domain: "SoundMaker", code: 1)
        }
        buf.frameLength = AVAudioFrameCount(samples.count)
        for i in 0..<samples.count { ch[0][i] = samples[i] }

        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buf)
    }
}

/// Озвучивает текст в массив сэмплов (русский голос).
final class SpeechRenderer {
    private let synth = AVSpeechSynthesizer()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var rate: Double = 0
    private var done = false
    private var converter: AVAudioConverter?
    private var continuation: CheckedContinuation<(samples: [Float], rate: Double), Never>?

    static func render(_ text: String) async -> (samples: [Float], rate: Double) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return ([], 0) }
        let r = SpeechRenderer()
        return await r.run(trimmed)
    }

    private func run(_ text: String) async -> (samples: [Float], rate: Double) {
        await withCheckedContinuation { cont in
            self.continuation = cont
            let u = AVSpeechUtterance(string: text)
            u.voice = AVSpeechSynthesisVoice(language: "ru-RU")
            u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
            u.volume = 1
            synth.write(u) { [self] buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 { finish(); return }
                append(pcm)
            }
            // страховка, если синтезатор не прислал завершение
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [self] in finish() }
        }
    }

    private func append(_ pcm: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        if done { return }
        let fmt = pcm.format
        if rate == 0 { rate = fmt.sampleRate }
        let n = Int(pcm.frameLength)
        if fmt.commonFormat == .pcmFormatFloat32, let ch = pcm.floatChannelData {
            samples.append(contentsOf: UnsafeBufferPointer(start: ch[0], count: n))
        } else if fmt.commonFormat == .pcmFormatInt16, let ch = pcm.int16ChannelData {
            let stride = fmt.isInterleaved ? Int(fmt.channelCount) : 1
            for i in 0..<n { samples.append(Float(ch[0][i * stride]) / 32768) }
        } else if fmt.commonFormat == .pcmFormatInt32, let ch = pcm.int32ChannelData {
            let stride = fmt.isInterleaved ? Int(fmt.channelCount) : 1
            for i in 0..<n { samples.append(Float(ch[0][i * stride]) / 2147483648) }
        } else {
            // запасной путь через конвертер
            guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: fmt.sampleRate, channels: 1, interleaved: false) else { return }
            if converter == nil { converter = AVAudioConverter(from: fmt, to: target) }
            guard let conv = converter,
                  let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: pcm.frameLength + 1024) else { return }
            var given = false
            var err: NSError?
            conv.convert(to: out, error: &err) { _, status in
                if given { status.pointee = .noDataNow; return nil }
                given = true
                status.pointee = .haveData
                return pcm
            }
            if let ch = out.floatChannelData {
                samples.append(contentsOf: UnsafeBufferPointer(start: ch[0], count: Int(out.frameLength)))
            }
        }
    }

    private func finish() {
        lock.lock()
        if done { lock.unlock(); return }
        done = true
        let result = (samples, rate)
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(returning: result)
    }
}
