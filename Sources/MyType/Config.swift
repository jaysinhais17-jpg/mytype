import AppKit

enum Config {
    static let supportDir = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MyType", isDirectory: true)
    static let modelPath = supportDir.appendingPathComponent("models/ggml-large-v3-turbo-q5_0.bin").path
    static let serverPort = 8178
    static let llmPort = 8179
    static let llmModelPath = supportDir.appendingPathComponent("models/qwen2.5-3b-instruct-q4_k_m.gguf").path
    static var llamaBinary: String? {
        ["/opt/homebrew/bin/llama-server", "/usr/local/bin/llama-server"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    static let sampleRate = 16_000.0
    /// A press shorter than this is a "tap" (toggle hands-free); longer is push-to-talk.
    static let tapSeconds = 0.25       // shorter than this = a tap, not a hold
    static let doubleTapSeconds = 0.4  // second tap within this = hands-free
    static let minSeconds = 0.35
    static let silenceRMS: Float = 0.004

    static var serverBinary: String? {
        ["/opt/homebrew/bin/whisper-server", "/usr/local/bin/whisper-server"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Dictations shorter than this skip cloud cleanup; Deepgram's own punctuation is good enough and it saves ~0.4 s.
    static let cloudCleanupMinWords = 10
    static let defaultDictionary = "OSCE, urology, uroradiology, nephrolithiasis, hydronephrosis, cystoscopy, paediatrics, obstetrics, gynaecology, MyType, Wispr Flow, Typeless, Deepgram, Groq, Qwen, Claude, Claude Code, Anthropic, ChatGPT, OpenAI, Gemini, Vertex AI, Cursor, GitHub, API, LLM, SwiftUI, TypeScript, JavaScript, prompt, hands-free, push-to-talk"
    static var dictionary: String {
        get { UserDefaults.standard.string(forKey: "dictionary") ?? defaultDictionary }
        set { UserDefaults.standard.set(newValue, forKey: "dictionary") }
    }

    /// Spoken shortcuts, one "trigger = text" per line.
    static var snippets: String {
        get { UserDefaults.standard.string(forKey: "snippets") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "snippets") }
    }
}


/// What MyType calls the user in greetings. Free text (a nickname is fine); defaults to the macOS first name.
enum Profile {
    static var systemFirstName: String { NSFullUserName().split(separator: " ").first.map(String.init) ?? "" }
    static var name: String {
        get { (UserDefaults.standard.string(forKey: "callName") ?? systemFirstName).trimmingCharacters(in: .whitespacesAndNewlines) }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "callName") }
    }
}

/// Light / Dark / follow the Mac. "System" leaves NSApp.appearance nil, so macOS Auto (day/night) switching carries through.
enum AppearanceMode: Int, CaseIterable {
    case system, light, dark
    var title: String { ["Match my Mac", "Light", "Dark"][rawValue] }
    static var current: AppearanceMode {
        get { AppearanceMode(rawValue: UserDefaults.standard.integer(forKey: "appearanceMode")) ?? .system }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "appearanceMode"); newValue.apply() }
    }
    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

/// What a modifier key does. Every mode except Off keeps hold-to-talk; they differ in how hands-free starts.
enum KeyMode: Int, CaseIterable {
    case holdTap, holdDoubleTap, holdOnly, off
    var title: String {
        ["Hold to talk, tap for hands-free", "Hold to talk, double-tap for hands-free", "Hold to talk only", "Off"][rawValue]
    }
}

/// Dictation shortcuts. Defaults: Fn = hold, or double-tap for hands-free; Right Option = hold, or a single tap for hands-free
/// (a double-tap of Option collides with other tools, so it is never required).
enum Shortcuts {
    private static func load(_ key: String, _ fallback: KeyMode) -> KeyMode {
        (UserDefaults.standard.object(forKey: key) as? Int).flatMap(KeyMode.init(rawValue:)) ?? fallback
    }
    static var fn: KeyMode {
        get { load("fnMode", .holdDoubleTap) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "fnMode") }
    }
    static var option: KeyMode {
        get { load("optionMode", .holdTap) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "optionMode") }
    }

    private static func how(_ m: KeyMode) -> String {
        switch m {
        case .holdTap: return "hold to talk, or tap once for hands-free"
        case .holdDoubleTap: return "hold to talk, or double-tap for hands-free"
        case .holdOnly: return "hold to talk"
        case .off: return ""
        }
    }
    /// Home-page heading and body text for the current bindings.
    static var homeText: (title: String, body: String) {
        var parts: [String] = []
        if fn != .off { parts.append("fn: \(how(fn))") }
        if option != .off { parts.append("Right Option: \(how(option))") }
        if parts.isEmpty { return ("Shortcuts are off", "Turn a key on in Settings to start dictating.") }
        let title = fn != .off ? "Hold fn to talk" : "Hold Right Option to talk"
        let hands = [fn, option].contains { $0 == .holdTap || $0 == .holdDoubleTap }
        return (title, "Release to paste at your cursor. " + parts.joined(separator: ". ").prefix(1).uppercased() + parts.joined(separator: ". ").dropFirst()
                + "." + (hands ? " Tap once more to stop hands-free." : ""))
    }
}
