import Foundation

/// User-editable settings at `~/Library/Application Support/dev.herdr.topbar/config.json`.
/// Written on first launch so the file is discoverable and self-documenting.
struct Config {
    var terminalBundleId: String = "com.apple.Terminal"
    /// Absolute path to the herdr binary. Empty means "let the login shell
    /// resolve it" — a GUI app inherits a minimal PATH, so we resolve eagerly.
    var herdrBinary: String = ""

    /// How long the icon keeps blinking for a waiting agent before it settles
    /// to the static badge. `0` means "keep blinking until clicked".
    var blinkTimeoutSeconds: Int = Config.defaultBlinkTimeout

    static let defaultBlinkTimeout = 180

    /// The choices offered in the menu, in order.
    static let blinkTimeoutChoices: [(title: String, seconds: Int)] = [
        ("1 minute", 60),
        ("3 minutes", 180),
        ("10 minutes", 600),
        ("Until clicked", 0),
    ]

    static func load() -> Config {
        var config = Config()
        if let data = FileManager.default.contents(atPath: Paths.configFile),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let t = json["terminalBundleId"] as? String, !t.isEmpty { config.terminalBundleId = t }
            if let b = json["herdrBinary"] as? String { config.herdrBinary = b }
            if let t = json["blinkTimeoutSeconds"] as? Int, t >= 0 {
                config.blinkTimeoutSeconds = t
            }
        }
        if config.herdrBinary.isEmpty { config.herdrBinary = Config.locateHerdr() }
        return config
    }

    func save() {
        Paths.ensureSupportDir()
        let json: [String: Any] = [
            "terminalBundleId": terminalBundleId,
            "herdrBinary": herdrBinary,
            "blinkTimeoutSeconds": blinkTimeoutSeconds,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: json,
                                                     options: [.prettyPrinted, .sortedKeys])
        else { return }
        try? data.write(to: URL(fileURLWithPath: Paths.configFile))
    }

    /// A GUI process gets PATH=/usr/bin:/bin:/usr/sbin:/sbin, which never
    /// contains herdr. Check the usual install roots, then the env var herdr
    /// injects into plugin hooks (set when the startup hook launches us).
    private static func locateHerdr() -> String {
        if let injected = ProcessInfo.processInfo.environment["HERDR_BIN_PATH"],
           FileManager.default.isExecutableFile(atPath: injected) {
            return injected
        }
        let candidates = [
            "/opt/homebrew/bin/herdr",
            "/usr/local/bin/herdr",
            NSHomeDirectory() + "/.local/bin/herdr",
            "/usr/bin/herdr",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        // Last resort: the login shell that runs launch.command will resolve it.
        return "herdr"
    }
}
