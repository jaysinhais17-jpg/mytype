import AppKit

/// Words and speaking time for one calendar day.
struct DayStat: Codable {
    var words = 0
    var timedWords = 0   // words whose audio length was recorded
    var secs = 0.0       // audio seconds for those words
}

/// Local productivity numbers behind the Home page: speaking speed, typing speed, time saved, money saved.
enum Stats {
    /// Speaking pace assumed for words dictated before audio lengths were recorded.
    static let assumedSpeakingWPM = 150.0
    static let defaultTypingWPM = 40.0

    private static let dayFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f }()
    static func key(_ d: Date) -> String { dayFmt.string(from: d) }

    static var days: [String: DayStat] {
        get {
            if let d = UserDefaults.standard.data(forKey: "dailyStats"), let m = try? JSONDecoder().decode([String: DayStat].self, from: d) { return m }
            // First run of this feature: rebuild what we can from the saved history.
            var m: [String: DayStat] = [:]
            for e in History.items {
                var s = m[key(e.date)] ?? DayStat()
                let w = History.words(e.text)
                s.words += w
                if let t = e.secs, t > 0 { s.timedWords += w; s.secs += t }
                m[key(e.date)] = s
            }
            days = m
            return m
        }
        set { if let d = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(d, forKey: "dailyStats") } }
    }

    static func record(words: Int, secs: Double?) {
        var m = days
        var s = m[key(Date())] ?? DayStat()
        s.words += words
        if let t = secs, t > 0 { s.timedWords += words; s.secs += t }
        m[key(Date())] = s
        days = m
    }

    // MARK: typing speed

    static var typingWPM: Double? {
        get { UserDefaults.standard.object(forKey: "typingWPM") as? Double }
        set { UserDefaults.standard.set(newValue, forKey: "typingWPM") }
    }
    static var typingBest: Double? {
        get { UserDefaults.standard.object(forKey: "typingBest") as? Double }
        set { UserDefaults.standard.set(newValue, forKey: "typingBest") }
    }
    /// What time saved is measured against: your measured typing speed, or an average until you take the test.
    static var typingForMath: Double { typingWPM ?? defaultTypingWPM }

    // MARK: time

    /// Seconds saved by speaking `s` instead of typing it.
    static func savedSeconds(_ s: DayStat) -> Double {
        let untimed = Double(s.words - s.timedWords)
        let spoken = s.secs + untimed / assumedSpeakingWPM * 60
        return max(0, Double(s.words) / typingForMath * 60 - spoken)
    }

    /// Lifetime words spoken. Older than the daily log, so the difference is treated as untimed.
    static var totalWords: Int { max(History.totalWords, days.values.reduce(0) { $0 + $1.words }) }

    static var totalSavedSeconds: Double {
        let m = days
        let tracked = m.values.reduce(0) { $0 + $1.words }
        var t = m.values.reduce(0) { $0 + savedSeconds($1) }
        let older = totalWords - tracked
        if older > 0 { t += savedSeconds(DayStat(words: older)) }
        return t
    }

    /// Average speaking speed over dictations with a recorded length.
    static var speakingWPM: Double? {
        let timed = days.values.reduce(0) { $0 + $1.timedWords }
        let secs = days.values.reduce(0) { $0 + $1.secs }
        return secs >= 10 ? Double(timed) / (secs / 60) : nil
    }

    /// Minutes saved per day for the last `n` days, oldest first.
    static func dailySaved(_ n: Int) -> [(date: Date, minutes: Double)] {
        let cal = Calendar.current, m = days
        let today = cal.startOfDay(for: Date())
        return (0..<n).reversed().map { back in
            let d = cal.date(byAdding: .day, value: -back, to: today)!
            return (d, savedSeconds(m[key(d)] ?? DayStat()) / 60)
        }
    }

    static func streak() -> Int {
        let cal = Calendar.current
        var active = Set(days.filter { $0.value.words > 0 }.keys)
        for e in Usage.events() where e.audioSeconds > 0 { active.insert(key(e.date)) }
        var d = cal.startOfDay(for: Date()), n = 0
        if !active.contains(key(d)) { d = cal.date(byAdding: .day, value: -1, to: d)! }
        while active.contains(key(d)) { n += 1; d = cal.date(byAdding: .day, value: -1, to: d)! }
        return n
    }

    static func duration(_ secs: Double) -> String {
        let m = Int((secs / 60).rounded())
        if m < 1 { return secs >= 10 ? "\(Int(secs.rounded())) s" : "0 min" }
        if m < 60 { return "\(m) min" }
        return String(format: "%dh %02dm", m / 60, m % 60)
    }

    // MARK: money

    /// Monthly price (in US dollars, as such plans are billed) of a paid dictation subscription you'd otherwise have. Editable.
    /// Converted to rand at the daily exchange rate.
    static var planPriceUSD: Double {
        get { UserDefaults.standard.object(forKey: "planPriceUSD") as? Double ?? 15 }
        set { UserDefaults.standard.set(newValue, forKey: "planPriceUSD") }
    }
    static var planPriceZAR: Double { Currency.zar(planPriceUSD) }

    /// Whole months of use so far (a subscription bills per month started).
    static var monthsUsed: Int {
        var first = Usage.events().map(\.date).min() ?? Date()
        if let k = days.keys.sorted().first, let d = dayFmt.date(from: k), d < first { first = d }
        let d = Calendar.current.dateComponents([.day], from: first, to: Date()).day ?? 0
        return max(1, Int((Double(d) / 30).rounded(.up)))
    }

    static var subscriptionCost: Double { Double(monthsUsed) * planPriceZAR }
    /// What MyType has actually cost you, in rand: API spend beyond free credit and free tiers.
    static var myTypeCost: Double { Currency.zar(Usage.totals(Usage.events(), since: nil).youPay) }
    static var moneySaved: Double { max(0, subscriptionCost - myTypeCost) }
}

/// Provider prices are in US dollars; everything you see is shown in rand.
enum Currency {
    static let fallbackRate = 18.0

    /// Rand per US dollar. Refreshed about once a day from a free rate feed; editable in Usage.
    static var rate: Double {
        get { UserDefaults.standard.object(forKey: "zarRate") as? Double ?? fallbackRate }
        set { UserDefaults.standard.set(newValue, forKey: "zarRate") }
    }
    /// True once the rate was set by hand: we stop overwriting it.
    static var manual: Bool {
        get { UserDefaults.standard.bool(forKey: "zarRateManual") }
        set { UserDefaults.standard.set(newValue, forKey: "zarRateManual") }
    }
    static var updated: Date? { UserDefaults.standard.object(forKey: "zarRateDate") as? Date }

    static func zar(_ usd: Double) -> Double { usd * rate }

    static func refresh(force: Bool = false, done: @escaping () -> Void = {}) {
        if manual && !force { return }
        if !force, let u = updated, Date().timeIntervalSince(u) < 86_400 { return }
        guard let url = URL(string: "https://open.er-api.com/v6/latest/USD") else { return }
        URLSession.shared.dataTask(with: URLRequest(url: url, timeoutInterval: 8)) { data, _, _ in
            guard let data, let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let r = (j["rates"] as? [String: Any])?["ZAR"] as? Double, r > 1 else { return }
            DispatchQueue.main.async {
                rate = r; manual = false
                UserDefaults.standard.set(Date(), forKey: "zarRateDate")
                done()
            }
        }.resume()
    }

    /// "R1 234.50". Small amounts get more decimals so cents-worth of API spend doesn't read as zero.
    static func format(rand v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal; f.groupingSeparator = " "; f.usesGroupingSeparator = true; f.locale = Locale(identifier: "en_ZA")
        f.groupingSeparator = " "; f.decimalSeparator = "."
        let digits = v != 0 && abs(v) < 1 ? 3 : 2
        f.minimumFractionDigits = digits; f.maximumFractionDigits = digits
        return "R" + (f.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v))
    }
    /// A dollar price (as the provider bills it) shown in rand.
    static func format(usd v: Double) -> String { format(rand: zar(v)) }
}

/// Minimal bar chart: one bar per day, today highlighted.
final class BarChart: NSView {
    var values: [(label: String, value: Double)] = [] { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 120) }

    override func draw(_ dirtyRect: NSRect) {
        guard !values.isEmpty else { return }
        let labelH: CGFloat = 16, top: CGFloat = 4
        let plot = NSRect(x: 0, y: top, width: bounds.width, height: bounds.height - labelH - top)
        let peak = max(values.map(\.value).max() ?? 0, 1)
        let slot = plot.width / CGFloat(values.count)
        let barW = min(22, slot * 0.6)
        // faint baseline
        Theme.line.setFill(); NSRect(x: 0, y: plot.maxY, width: plot.width, height: 1).fill()
        for (i, v) in values.enumerated() {
            let h = v.value <= 0 ? 3 : max(4, CGFloat(v.value / peak) * (plot.height - 4))
            let r = NSRect(x: CGFloat(i) * slot + (slot - barW) / 2, y: plot.maxY - h, width: barW, height: h)
            let today = i == values.count - 1
            (v.value <= 0 ? Theme.line : (today ? Theme.purple : Theme.purple.withAlphaComponent(0.42))).setFill()
            NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4).fill()
            if i == values.count - 1 || (i % 3 == 0 && i < values.count - 2) {
                let s = NSAttributedString(string: v.label, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular), .foregroundColor: NSColor.tertiaryLabelColor])
                s.draw(at: NSPoint(x: r.midX - s.size().width / 2, y: plot.maxY + 3))
            }
        }
    }
}
