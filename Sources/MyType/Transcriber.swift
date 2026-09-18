import Foundation

/// Owns a long-lived whisper-server child process so the model stays warm in memory.
final class Transcriber {
    private var process: Process?
    private let base = URL(string: "http://127.0.0.1:\(Config.serverPort)")!
    private(set) var ready = false

    var language: String {
        UserDefaults.standard.string(forKey: "language") ?? "en"
    }

    func startServer(onReady: @escaping (Bool) -> Void) {
        guard let bin = Config.serverBinary else { onReady(false); return }
        guard FileManager.default.fileExists(atPath: Config.modelPath) else { onReady(false); return }
        killStrays()

        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = [
            "-m", Config.modelPath,
            "--host", "127.0.0.1", "--port", String(Config.serverPort),
            "-t", "4", "-nt", "-sns", "-l", language,
            "-ac", "768", // ~15s audio context: ~40% faster on short dictation; long audio is chunked below
            "--prompt", "Hello. This is a clear, punctuated sentence.",
        ]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { onReady(false); return }
        process = p

        // Poll until the server answers (first launch compiles Metal shaders, ~20s).
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            for _ in 0..<180 {
                if self.ping() { self.ready = true; DispatchQueue.main.async { onReady(true) }; return }
                Thread.sleep(forTimeInterval: 0.5)
            }
            DispatchQueue.main.async { onReady(false) }
        }
    }

    func stopServer() {
        process?.terminate()
        process = nil
        ready = false
    }

    private func killStrays() {
        let k = Process()
        k.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        k.arguments = ["-f", "whisper-server.*--port \(Config.serverPort)"]
        try? k.run(); k.waitUntilExit()
    }

    private func ping() -> Bool {
        var req = URLRequest(url: base); req.timeoutInterval = 1
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        URLSession.shared.dataTask(with: req) { _, resp, _ in ok = resp != nil; sem.signal() }.resume()
        _ = sem.wait(timeout: .now() + 1.5)
        return ok
    }

    /// Splits long audio at the quietest point near 10-14s so each piece fits the 15s audio context.
    private func chunks(_ s: [Float]) -> [[Float]] {
        let sr = Int(Config.sampleRate)
        var out: [[Float]] = []
        var rest = s[...]
        while rest.count > 14 * sr {
            let lo = rest.startIndex + 10 * sr, hi = rest.startIndex + 14 * sr
            let win = sr / 20 // 50ms energy windows
            var best = lo, bestE = Float.greatestFiniteMagnitude
            var i = lo
            while i + win < hi {
                var e: Float = 0
                for j in i..<(i + win) { e += rest[j] * rest[j] }
                if e < bestE { bestE = e; best = i + win / 2 }
                i += win
            }
            out.append(Array(rest[rest.startIndex..<best]))
            rest = rest[best...]
        }
        out.append(Array(rest))
        return out
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        var parts: [String] = []
        for c in chunks(samples) {
            let t = try await transcribeChunk(c).trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { parts.append(t) }
        }
        return parts.joined(separator: " ")
    }

    private func transcribeChunk(_ samples: [Float]) async throws -> String {
        let boundary = "MyType-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        field("response_format", "json")
        field("temperature", "0.0")
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(Audio.wav(samples))
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var req = URLRequest(url: base.appendingPathComponent("inference"))
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let (data, _) = try await URLSession.shared.data(for: req)
        struct R: Decodable { let text: String }
        return try JSONDecoder().decode(R.self, from: data).text
    }
}

enum TextCleaner {
    private static let hallucinations: Set<String> = [
        "thank you.", "thanks for watching.", "thanks for watching!", "you", "bye.", "thank you for watching.",
        "[blank_audio]", "(silence)", "[silence]", ".",
    ]

    static func clean(_ raw: String) -> String {
        var t = raw.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if hallucinations.contains(t.lowercased()) { return "" }
        // Bracketed non-speech tags like [MUSIC], (coughs)
        t = t.replacingOccurrences(of: #"\s*[\[\(][^\]\)]{1,30}[\]\)]\s*"#, with: " ", options: .regularExpression)
        // Filler words
        t = t.replacingOccurrences(of: #"(?i)\b(u+m+|u+h+|er+m*|hmm+|mhm)\b[,.]?\s*"#, with: "", options: .regularExpression)
        // Collapse stutter repeats: "the the" -> "the"
        t = t.replacingOccurrences(of: #"(?i)\b(\w+)(\s+\1\b)+"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        // Spoken emails: "john at gmail dot com" -> john@gmail.com
        t = t.replacingOccurrences(
            of: #"(?i)\b([a-z0-9._-]+) at ([a-z0-9-]+) dot (com|org|net|io|edu|co|ai|dev|app)\b"#,
            with: "$1@$2.$3", options: .regularExpression)
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        if let f = t.first, f.isLowercase { t = f.uppercased() + t.dropFirst() }
        return t
    }
}
