import Foundation

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
    static let tapSeconds = 0.35
    static let minSeconds = 0.35
    static let silenceRMS: Float = 0.004

    static var serverBinary: String? {
        ["/opt/homebrew/bin/whisper-server", "/usr/local/bin/whisper-server"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static let defaultDictionary = "OSCE, urology, uroradiology, nephrolithiasis, hydronephrosis, cystoscopy, paediatrics, obstetrics, gynaecology"
    static var dictionary: String {
        get { UserDefaults.standard.string(forKey: "dictionary") ?? defaultDictionary }
        set { UserDefaults.standard.set(newValue, forKey: "dictionary") }
    }
}
