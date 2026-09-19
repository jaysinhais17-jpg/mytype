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

    /// Deepgram credit balance in USD (a sign-up grant); speech is free until list-price spend passes it.
    static var deepgramCredit: Double { get { rate("creditDG", 200) } set { UserDefaults.standard.set(newValue, forKey: "creditDG") } }
    /// Groq's free tier covers cleanup while on; turn off if you move to a paid plan.
    static var cleanupFree: Bool {
        get { UserDefaults.standard.object(forKey: "cleanupFree") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "cleanupFree") }
    }

    struct Totals {
        var dictations = 0, calls = 0, promptTokens = 0, completionTokens = 0
        var audioSeconds = 0.0
        var speechPaid = 0.0 // speech list price beyond the credit
        var speechCost: Double { audioSeconds / 60 * Usage.deepgramPerMinute }
        var cleanupCost: Double {
            Double(promptTokens) / 1e6 * Usage.llmInPerMillion + Double(completionTokens) / 1e6 * Usage.llmOutPerMillion
        }
        /// What it would cost at list price.
        var total: Double { speechCost + cleanupCost }
        /// What actually leaves your pocket: speech beyond the credit, cleanup unless the free tier covers it.
        var youPay: Double { speechPaid + (Usage.cleanupFree ? 0 : cleanupCost) }
    }

    static func totals(_ evs: [UsageEvent], since: Date?) -> Totals {
        var t = Totals()
        var spent = 0.0 // running list-price speech spend, oldest first, so the credit is used up in order
        for e in evs.sorted(by: { $0.date < $1.date }) {
            let cost = e.audioSeconds / 60 * deepgramPerMinute
            let inPeriod = since == nil || e.date >= since!
            if inPeriod {
                t.speechPaid += max(0, spent + cost - deepgramCredit) - max(0, spent - deepgramCredit)
                if e.audioSeconds > 0 { t.dictations += 1; t.audioSeconds += e.audioSeconds }
                if e.promptTokens + e.completionTokens > 0 { t.calls += 1; t.promptTokens += e.promptTokens; t.completionTokens += e.completionTokens }
            }
            spent += cost
        }
        return t
    }

    /// Lifetime list-price speech spend, and the projected month at the current pace.
    static func creditStatus(_ evs: [UsageEvent]) -> (used: Double, monthly: Double) {
        let all = totals(evs, since: nil)
        guard let first = evs.map(\.date).min() else { return (0, 0) }
        let days = max(1, Date().timeIntervalSince(first) / 86_400)
        return (all.speechCost, all.total / days * 30)
    }
}
