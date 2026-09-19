import Foundation

/// One billable API call: audio streamed to Deepgram, or tokens used by the cleanup model.
struct UsageEvent: Codable {
    let date: Date
    var audioSeconds: Double = 0
    var promptTokens: Int = 0
    var completionTokens: Int = 0
}

/// Local, on-device log of API usage (kept in Application Support as JSON lines) plus editable price estimates.
enum Usage {
    private static let queue = DispatchQueue(label: "mytype.usage")
    private static let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MyType")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("usage.jsonl")
    }()

    static func add(_ e: UsageEvent) {
        queue.async {
            let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
            guard var line = try? enc.encode(e) else { return }
            line.append(10)
            if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(line); try? h.close() }
            else { try? line.write(to: url) }
        }
    }

    static func events() -> [UsageEvent] {
        queue.sync {
            guard let s = try? String(contentsOf: url, encoding: .utf8) else { return [] }
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            return s.split(separator: "\n").compactMap { try? dec.decode(UsageEvent.self, from: Data($0.utf8)) }
        }
    }

    // Price estimates (USD). Editable in the Usage tab, because providers change prices; check their pricing pages.
    private static func rate(_ k: String, _ d: Double) -> Double { UserDefaults.standard.object(forKey: k) as? Double ?? d }
    static var deepgramPerMinute: Double { get { rate("rateDG", 0.0077) } set { UserDefaults.standard.set(newValue, forKey: "rateDG") } }
    static var llmInPerMillion: Double { get { rate("rateIn", 0.29) } set { UserDefaults.standard.set(newValue, forKey: "rateIn") } }
    static var llmOutPerMillion: Double { get { rate("rateOut", 0.59) } set { UserDefaults.standard.set(newValue, forKey: "rateOut") } }

    struct Totals {
        var dictations = 0, calls = 0, promptTokens = 0, completionTokens = 0
        var audioSeconds = 0.0
        var speechCost: Double { audioSeconds / 60 * Usage.deepgramPerMinute }
        var cleanupCost: Double {
            Double(promptTokens) / 1e6 * Usage.llmInPerMillion + Double(completionTokens) / 1e6 * Usage.llmOutPerMillion
        }
        var total: Double { speechCost + cleanupCost }
    }

    static func totals(_ evs: [UsageEvent], since: Date?) -> Totals {
        var t = Totals()
        for e in evs where since == nil || e.date >= since! {
            if e.audioSeconds > 0 { t.dictations += 1; t.audioSeconds += e.audioSeconds }
            if e.promptTokens + e.completionTokens > 0 { t.calls += 1; t.promptTokens += e.promptTokens; t.completionTokens += e.completionTokens }
        }
        return t
    }
}
