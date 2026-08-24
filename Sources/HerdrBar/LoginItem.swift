import Foundation

/// "Start at Login", implemented as a per-user LaunchAgent.
///
/// This is what keeps the menu bar icon present while herdr is not running —
/// the plugin's `[[startup]]` hook only fires when a herdr server starts, which
/// is exactly the case the icon needs to cover.
///
/// A LaunchAgent plist is used rather than `SMAppService` because this app is
/// built and ad-hoc signed locally; the launchd path behaves predictably for an
/// unsigned local build and is easy to inspect with `launchctl print`.
enum LoginItem {

    static let label = "dev.herdr.topbar"

    static var plistPath: String {
        NSHomeDirectory() + "/Library/LaunchAgents/\(label).plist"
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistPath)
    }

    /// Path of the running executable, so the agent always points at the copy
    /// that installed it.
    private static var executablePath: String {
        Bundle.main.executablePath ?? CommandLine.arguments[0]
    }

    @discardableResult
    static func install() -> Bool {
        let dir = NSHomeDirectory() + "/Library/LaunchAgents"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            // Not a daemon: if the user quits from the menu, stay quit.
            "KeepAlive": false,
        ]
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0) else { return false }
        guard (try? data.write(to: URL(fileURLWithPath: plistPath))) != nil else { return false }

        // Load it now so it is active without waiting for the next login.
        launchctl(["bootstrap", "gui/\(getuid())", plistPath])
        return true
    }

    @discardableResult
    static func remove() -> Bool {
        launchctl(["bootout", "gui/\(getuid())/\(label)"])
        try? FileManager.default.removeItem(atPath: plistPath)
        return true
    }

    static func toggle() {
        if isInstalled { remove() } else { install() }
    }

    /// launchctl exits non-zero for benign cases (already loaded, not loaded),
    /// so failures are ignored — `isInstalled` reflects the plist, which is the
    /// state that survives a reboot.
    private static func launchctl(_ arguments: [String]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }
}
