import Foundation

/// Transcribes finished phrases *while you're still talking*: whenever a pause is detected the audio so far is sent
/// to whisper in the background, so at key-up only the last short phrase is left to process.
final class Streamer {
    private let recorder: Recorder
    private let transcriber: Transcriber
    private var committed = 0
    private var pieces: [Task<String, Never>] = []
    private var timer: Timer?
    private var prompt = ""

    private let sr = Int(Config.sampleRate)
    private let minChunk = 2.5, maxChunk = 8.5, pause = 0.6
    private let pauseRMS: Float = 0.006

    init(recorder: Recorder, transcriber: Transcriber) {
        self.recorder = recorder
        self.transcriber = transcriber
    }

    private static func makePrompt() -> String {
        let words = Config.dictionary.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = "Hello. This is a clear, punctuated sentence."
        return words.isEmpty ? base : "\(base) Glossary: \(words)."
    }

    func start() {
        committed = 0
        pieces = []
        prompt = Streamer.makePrompt()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        let pending = recorder.snapshot(from: committed)
        guard Double(pending.count) / Double(sr) >= minChunk else { return }
        let tail = pending.suffix(Int(pause * Double(sr)))
        if Audio.rms(Array(tail)) < pauseRMS {
            commit(pending.count, of: pending)
        } else if Double(pending.count) / Double(sr) > maxChunk {
            commit(quietestCut(pending), of: pending)
        }
    }

    /// Quietest 50 ms window between 6 s and the end of the buffer.
    private func quietestCut(_ s: [Float]) -> Int {
        let lo = 6 * sr, hi = min(s.count, Int(maxChunk * Double(sr)))
        let win = sr / 20
        var best = hi, bestE = Float.greatestFiniteMagnitude
        var i = lo
        while i + win < hi {
            var e: Float = 0
            for j in i..<(i + win) { e += s[j] * s[j] }
            if e < bestE { bestE = e; best = i + win / 2 }
            i += win
        }
        return best
    }

    private func commit(_ count: Int, of pending: [Float]) {
        committed += count
        send(Array(pending[0..<count]))
    }

    private func send(_ audio: [Float]) {
        guard Audio.rms(audio) > Config.silenceRMS else { return }
        let trimmed = Audio.trimSilence(audio)
        let prompt = self.prompt
        let t = transcriber
        pieces.append(Task {
            let raw = (try? await t.transcribeChunk(trimmed, prompt: prompt)) ?? ""
            return TextCleaner.clean(raw)
        })
    }

    /// Offline path for a finished recording (used when the cloud is unreachable): split under 8.5 s and transcribe.
    func transcribeAll(_ all: [Float]) async -> String {
        prompt = Streamer.makePrompt()
        committed = 0
        pieces = []
        while Double(all.count - committed) / Double(sr) > maxChunk {
            let pending = Array(all[committed...])
            commit(quietestCut(pending), of: pending)
        }
        return await finish(allSamples: all)
    }

    func cancel() {
        timer?.invalidate(); timer = nil
        pieces.forEach { $0.cancel() }
        pieces = []
    }

    /// Call after `recorder.stop()`. Returns the whole cleaned transcript.
    func finish(allSamples: [Float]) async -> String {
        timer?.invalidate(); timer = nil
        if committed < allSamples.count {
            let rest = Array(allSamples[committed...])
            if Double(rest.count) / Double(sr) >= Config.minSeconds { send(rest) }
        }
        var parts: [String] = []
        for p in pieces {
            let t = await p.value
            if !t.isEmpty { parts.append(t) }
        }
        return parts.joined(separator: " ")
    }
}
