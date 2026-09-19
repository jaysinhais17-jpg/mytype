import Foundation

/// Optional cloud speech + cleanup. Keys live in UserDefaults on this Mac only (no Keychain prompts).
enum Cloud {
    private static func get(_ k: String, _ d: String = "") -> String { UserDefaults.standard.string(forKey: k) ?? d }
    private static func set(_ k: String, _ v: String) { UserDefaults.standard.set(v.trimmingCharacters(in: .whitespacesAndNewlines), forKey: k) }

    static var deepgramKey: String { get { get("deepgramKey") } set { set("deepgramKey", newValue) } }
    static var llmKey: String { get { get("llmKey") } set { set("llmKey", newValue) } }
    /// Any OpenAI-compatible chat endpoint: Gemini, DeepSeek, OpenAI, Groq…
    static var llmBaseURL: String {
        get { get("llmBaseURL", "https://generativelanguage.googleapis.com/v1beta/openai") }
        set { set("llmBaseURL", newValue) }
    }
    static var llmModel: String { get { get("llmModel", "gemini-flash-lite-latest") } set { set("llmModel", newValue) } }

    static var useDeepgram: Bool { !deepgramKey.isEmpty }
    static var useLLM: Bool { !llmKey.isEmpty }
}

/// Live speech-to-text over Deepgram's WebSocket: audio streams up while you talk, so only the last
/// fraction of a second is left to process when you let go.
final class DeepgramSession {
    private let recorder: Recorder
    private var task: URLSessionWebSocketTask?
    private var receiver: Task<Void, Never>?
    private var timer: Timer?
    private var finals: [String] = []
    private var sent = 0

    init(recorder: Recorder) { self.recorder = recorder }

    func start(language: String) {
        var c = URLComponents(string: "wss://api.deepgram.com/v1/listen")!
        var q: [URLQueryItem] = [
            .init(name: "model", value: "nova-3"), .init(name: "language", value: language),
            .init(name: "smart_format", value: "true"), .init(name: "punctuate", value: "true"),
            .init(name: "encoding", value: "linear16"), .init(name: "sample_rate", value: String(Int(Config.sampleRate))),
            .init(name: "channels", value: "1"),
        ]
        let terms = Config.dictionary.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for t in terms.prefix(80) { q.append(.init(name: "keyterm", value: t)) }
        c.queryItems = q
        var req = URLRequest(url: c.url!)
        req.setValue("Token \(Cloud.deepgramKey)", forHTTPHeaderField: "Authorization")
        let t = URLSession.shared.webSocketTask(with: req)
        task = t
        t.resume()
        receiver = Task { [weak self] in await self?.receiveLoop(t) }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.pump() }
    }

    private func receiveLoop(_ t: URLSessionWebSocketTask) async {
        while let msg = try? await t.receive() {
            guard case .string(let s) = msg, let d = s.data(using: .utf8),
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  j["type"] as? String == "Results", j["is_final"] as? Bool == true,
                  let alt = ((j["channel"] as? [String: Any])?["alternatives"] as? [[String: Any]])?.first,
                  let text = alt["transcript"] as? String, !text.isEmpty else { continue }
            finals.append(text)
        }
    }

    private func pump() { sendNew(recorder.snapshot(from: sent)) }

    private func sendNew(_ chunk: [Float]) {
        guard !chunk.isEmpty else { return }
        sent += chunk.count
        var d = Data(capacity: chunk.count * 2)
        for v in chunk {
            let i = Int16(max(-1, min(1, v)) * 32767)
            withUnsafeBytes(of: i.littleEndian) { d.append(contentsOf: $0) }
        }
        task?.send(.data(d)) { _ in }
    }

    func cancel() {
        timer?.invalidate(); timer = nil
        receiver?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    /// The final transcript, or nil if Deepgram gave nothing (bad key, offline…) so the caller can fall back.
    func finish(allSamples: [Float]) async -> String? {
        timer?.invalidate(); timer = nil
        if sent < allSamples.count { sendNew(Array(allSamples[sent...])) }
        task?.send(.string(#"{"type":"Finalize"}"#)) { _ in }
        task?.send(.string(#"{"type":"CloseStream"}"#)) { _ in }
        let t = task
        let guardTask = Task { try? await Task.sleep(nanoseconds: 3_000_000_000); t?.cancel(with: .goingAway, reason: nil) }
        await receiver?.value
        guardTask.cancel()
        task = nil
        return finals.isEmpty ? nil : finals.joined(separator: " ")
    }
}

/// Fast hosted-LLM cleanup. Same contract as the local Polisher: on any failure the input comes back unchanged.
final class CloudPolisher {
    func polish(_ text: String) async -> String {
        guard text.split(separator: " ").count >= 5 else { return text }
        let base = Cloud.llmBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: base + "/chat/completions") else { return text }
        let words = max(1, text.split(separator: " ").count)
        let glossary = Config.dictionary.trimmingCharacters(in: .whitespacesAndNewlines)
        let system = Polisher.system
            + " Exception to (5): if a word was clearly misheard and the context makes the intended word obvious "
            + "(for example 'suing' for 'using'), fix it."
            + " Formatting: only when the speaker clearly enumerates items (says 'bullet points', 'list', 'number one', "
            + "'first… second… third…') or says 'new line' or 'new paragraph', format that part as a list with one item per line "
            + "using '- ' bullets (or '1. 2. 3.' when they count), or insert the line break. Keep every item's wording. "
            + "Otherwise write normal prose and never add lists, headings or markdown on your own."
            + (glossary.isEmpty ? "" : " Correct spellings of terms the speaker uses: \(glossary).")
        let listShot: [[String: String]] = [
            ["role": "user", "content": "<t>things to buy bullet points milk eggs and sourdough bread</t>"],
            ["role": "assistant", "content": "Things to buy:\n- Milk\n- Eggs\n- Sourdough bread"],
        ]
        let body: [String: Any] = [
            "model": Cloud.llmModel,
            "messages": [["role": "system", "content": system]] + Polisher.shots + listShot + [["role": "user", "content": "<t>\(text)</t>"]],
            "temperature": 0,
            "max_tokens": min(2048, words * 4 + 96),
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 4
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(Cloud.llmKey)", forHTTPHeaderField: "Authorization")
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return text }
        req.httpBody = payload
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let m = (j["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any],
              let out = m["content"] as? String else { return text }
        return Polisher.accept(out, for: text)
    }
}
