import AppKit
import Foundation

/// Finds the terminal window hosting herdr and brings it forward, and launches
/// a new one when there is none.
///
/// This deliberately avoids AppleScript: driving Terminal through Apple Events
/// triggers a TCC "wants to control" prompt, and the automation permission can
/// be revoked later, silently breaking the icon's main job. Walking the process
/// tree and calling `NSRunningApplication.activate()` needs no permission at
/// all, and it resolves whatever terminal actually hosts herdr — so it keeps
/// working if the user switches from Terminal.app to something else.
enum TerminalHost {

    // MARK: - Process table

    private struct Proc {
        let pid: pid_t
        let ppid: pid_t
        /// `p_comm`, truncated by the kernel to 16 bytes. Cheap to read, so it
        /// serves as a prefilter before the far costlier per-pid argv lookup.
        let comm: String
    }

    private static func allProcesses() -> [Proc] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }

        let stride = MemoryLayout<kinfo_proc>.stride
        var buffer = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 8)
        var actual = buffer.count * stride
        guard sysctl(&mib, 4, &buffer, &actual, nil, 0) == 0 else { return [] }

        return (0 ..< actual / stride).map { index in
            let proc = buffer[index]
            // Copy the fixed-size tuple out before taking a pointer to it, so
            // reading its size does not overlap the pointer access.
            var name = proc.kp_proc.p_comm
            let capacity = MemoryLayout.size(ofValue: name)
            let comm = withUnsafeMutablePointer(to: &name) {
                $0.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
            }
            return Proc(pid: proc.kp_proc.p_pid, ppid: proc.kp_eproc.e_ppid, comm: comm)
        }
    }

    /// Full argv for a pid via KERN_PROCARGS2, whose layout is:
    /// `int32 argc | exec_path\0 | \0 padding | argc × arg\0 | env...`
    ///
    /// `p_comm` alone is not enough here: it is truncated to 16 bytes and is
    /// identical ("herdr") for the client and the server, which we must tell
    /// apart — the server is a daemon with no terminal to focus.
    private static func arguments(pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 else { return [] }

        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > 4 else { return [] }

        let argc = buffer.withUnsafeBytes { Int($0.load(as: Int32.self)) }
        guard argc > 0 else { return [] }

        // Split the region after argc into NUL-terminated tokens. The first is
        // the exec path; the padding between it and argv[0] yields empty tokens.
        var tokens: [String] = []
        var current = [UInt8]()
        for byte in buffer[4 ..< size] {
            if byte == 0 {
                if !current.isEmpty {
                    tokens.append(String(decoding: current, as: UTF8.self))
                    current.removeAll(keepingCapacity: true)
                }
            } else {
                current.append(byte)
            }
        }
        guard !tokens.isEmpty else { return [] }

        // tokens[0] is the exec path; the next argc entries are argv.
        let argv = Array(tokens.dropFirst().prefix(argc))
        return argv.isEmpty ? [tokens[0]] : [tokens[0]] + argv
    }

    // MARK: - herdr client discovery

    /// pids of attached herdr *clients* (the TUI), excluding `herdr server`.
    ///
    /// Reading argv means one `sysctl` per process, so the cheap `p_comm` field
    /// narrows the field first. A client started by absolute path has its comm
    /// truncated to the path rather than the basename, so a miss falls back to
    /// scanning everything.
    private static func clientPids(in processes: [Proc]? = nil) -> [pid_t] {
        let all = processes ?? allProcesses()
        let quick = all.filter { $0.comm.contains("herdr") }
        let found = scanForClients(quick)
        return found.isEmpty ? scanForClients(all) : found
    }

    private static func scanForClients(_ candidates: [Proc]) -> [pid_t] {
        let selfPid = ProcessInfo.processInfo.processIdentifier
        var found: [pid_t] = []

        for proc in candidates where proc.pid != selfPid {
            let argv = arguments(pid: proc.pid)
            guard let execPath = argv.first,
                  (execPath as NSString).lastPathComponent == "herdr" else { continue }
            // argv[0] is the exec path, argv[1] the real argv[0]; a server is
            // `herdr server`, so the subcommand sits past both.
            if argv.dropFirst(2).first == "server" { continue }
            found.append(proc.pid)
        }
        return found
    }

    /// Cached host lookup. App-activation notifications and menu openings both
    /// ask repeatedly within a moment; a short TTL keeps that from re-scanning
    /// the process table each time, while staying fresh enough to notice a
    /// terminal that just quit.
    private static var cachedHost: (app: NSRunningApplication?, at: Date)?
    private static let hostCacheTTL: TimeInterval = 2

    static func hostApplication(useCache: Bool = true) -> NSRunningApplication? {
        if useCache, let cached = cachedHost,
           Date().timeIntervalSince(cached.at) < hostCacheTTL {
            // A cached app that has since terminated is worse than no answer.
            if cached.app == nil || cached.app?.isTerminated == false { return cached.app }
        }
        let resolved = resolveHostApplication()
        cachedHost = (resolved, Date())
        return resolved
    }

    /// Drop the cache after an action that is expected to change the answer.
    static func invalidateHostCache() { cachedHost = nil }

    private static func resolveHostApplication() -> NSRunningApplication? {
        let guiApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular
        }
        guard !guiApps.isEmpty else { return nil }
        var byPid = [pid_t: NSRunningApplication]()
        for app in guiApps { byPid[app.processIdentifier] = app }

        let processes = allProcesses()
        var parents = [pid_t: pid_t]()
        for proc in processes { parents[proc.pid] = proc.ppid }

        for clientPid in clientPids(in: processes) {
            var pid = clientPid
            // Depth guard: herdr → shell → login → Terminal is 3 hops; allow
            // slack for wrappers, but never risk a cycle.
            for _ in 0 ..< 10 {
                guard let parent = parents[pid], parent > 1 else { break }
                if let app = byPid[parent] { return app }
                pid = parent
            }
        }
        return nil
    }

    /// True when herdr is attached to a terminal we can actually bring forward.
    static func hasVisibleClient() -> Bool { hostApplication() != nil }

    /// Is that terminal the frontmost app right now?
    static func isHostFrontmost() -> Bool {
        guard let host = hostApplication() else { return false }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == host.processIdentifier
    }

    // MARK: - Actions

    @discardableResult
    static func bringToFront() -> Bool {
        guard let host = hostApplication() else { return false }
        return host.activate(options: [.activateAllWindows])
    }

    /// Open a new terminal window running herdr, optionally starting in `cwd`.
    ///
    /// Goes through LaunchServices (same as double-clicking a `.command` file)
    /// rather than `tell application "Terminal" to do script`, so it needs no
    /// automation consent. The script is written to a unique filename because
    /// Terminal reads the file when it opens it and two rapid launches would
    /// otherwise race on one path.
    static func launchHerdr(cwd: String?, config: Config) {
        Paths.ensureSupportDir()
        pruneOldLaunchScripts()

        let script = Paths.supportDir + "/launch-\(UUID().uuidString.prefix(8)).command"
        var body = "#!/bin/bash\n"
        if let cwd {
            body += "cd \(shellQuote(cwd)) || exit 1\n"
        }
        body += "exec \(shellQuote(config.herdrBinary))\n"

        guard (try? body.write(toFile: script, atomically: true, encoding: .utf8)) != nil else { return }
        chmod(script, 0o700)

        guard let terminal = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: config.terminalBundleId)
        else { return }

        let options = NSWorkspace.OpenConfiguration()
        options.activates = true
        NSWorkspace.shared.open([URL(fileURLWithPath: script)],
                                withApplicationAt: terminal,
                                configuration: options)
    }

    /// Launch scripts are single-use; drop anything older than an hour so the
    /// support directory does not accumulate them.
    private static func pruneOldLaunchScripts() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: Paths.supportDir) else { return }
        let cutoff = Date().addingTimeInterval(-3600)
        for name in entries where name.hasPrefix("launch-") && name.hasSuffix(".command") {
            let path = Paths.supportDir + "/" + name
            let modified = (try? fm.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? nil
            if let modified, modified > cutoff { continue }
            try? fm.removeItem(atPath: path)
        }
    }

    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
