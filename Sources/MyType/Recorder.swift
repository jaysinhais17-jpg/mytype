import AVFoundation

/// Captures mic audio as 16 kHz mono Float32 while recording.
final class Recorder {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Config.sampleRate, channels: 1, interleaved: false)!
    private var samples: [Float] = []
    private let lock = NSLock()
    var onLevel: ((Float) -> Void)?

    func start() throws {
        samples.removeAll(keepingCapacity: true)
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: inFormat, to: target)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
            self?.append(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let ch = out.floatChannelData?[0] else { return }
        lock.lock()
        samples.append(contentsOf: UnsafeBufferPointer(start: ch, count: Int(out.frameLength)))
        lock.unlock()
        let n = Int(out.frameLength)
        if n > 0 {
            var sum: Float = 0
            for i in 0..<n { sum += ch[i] * ch[i] }
            let r = (sum / Float(n)).squareRoot()
            DispatchQueue.main.async { [weak self] in self?.onLevel?(r) }
        }
    }

    /// Samples recorded so far from `index` onward (safe to call while recording).
    func snapshot(from index: Int) -> [Float] {
        lock.lock(); defer { lock.unlock() }
        return index < samples.count ? Array(samples[index...]) : []
    }

    /// The most recent `count` samples (safe to call while recording).
    func tail(_ count: Int) -> [Float] {
        lock.lock(); defer { lock.unlock() }
        return Array(samples.suffix(count))
    }

    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.lock(); defer { lock.unlock() }
        return samples
    }
}

enum Audio {
    static func rms(_ s: [Float]) -> Float {
        guard !s.isEmpty else { return 0 }
        var sum: Float = 0
        for v in s { sum += v * v }
        return (sum / Float(s.count)).squareRoot()
    }

    /// Trim leading/trailing silence so whisper gets less to chew on (and hallucinates less).
    static func trimSilence(_ s: [Float], threshold: Float = 0.01) -> [Float] {
        let pad = Int(Config.sampleRate * 0.15)
        guard let first = s.firstIndex(where: { abs($0) > threshold }),
              let last = s.lastIndex(where: { abs($0) > threshold }) else { return s }
        return Array(s[max(0, first - pad)...min(s.count - 1, last + pad)])
    }

    static func wav(_ s: [Float]) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let bytes = UInt32(s.count * 2)
        d.append("RIFF".data(using: .ascii)!); u32(36 + bytes)
        d.append("WAVEfmt ".data(using: .ascii)!); u32(16); u16(1); u16(1)
        u32(UInt32(Config.sampleRate)); u32(UInt32(Config.sampleRate) * 2); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(bytes)
        for v in s {
            let i = Int16(max(-1, min(1, v)) * 32767)
            u16(UInt16(bitPattern: i))
        }
        return d
    }
}
