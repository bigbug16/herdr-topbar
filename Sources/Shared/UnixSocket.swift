import Foundation

/// Shared POSIX unix-domain-socket helpers.
///
/// Both endpoints this tool talks to speak the same shape — newline-delimited
/// JSON, one JSON object per line:
///   * herdr's own API socket (`~/.config/herdr/herdr.sock`), verified against
///     herdr 0.8.0: `{"id":..,"method":..,"params":{..}}\n` in, one response
///     line out.
///   * HerdrBar's own event socket, which the plugin hooks and `herdrbar-open`
///     write to.
///
/// Everything here is blocking with an explicit timeout: callers run it off the
/// main thread, and a hung herdr server must never freeze the menu bar.
enum UnixSocket {

    /// `sun_path` is a fixed 104-byte buffer on Darwin; longer paths cannot be
    /// represented at all, so reject them instead of silently truncating into a
    /// wrong path.
    static let maxPathLength = 103

    /// Connect to `path`, returning a socket fd with send/recv timeouts armed.
    static func connect(path: String, timeout: TimeInterval) -> Int32? {
        let bytes = Array(path.utf8)
        guard bytes.count <= maxPathLength else { return nil }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }

        setTimeouts(fd, timeout)

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let ok = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, size) == 0 }
        }
        guard ok else { close(fd); return nil }
        return fd
    }

    /// Bind + listen on `path`, replacing a stale socket file left behind by a
    /// crashed process. Returns nil when another *live* process already owns it,
    /// which is how HerdrBar enforces a single instance.
    static func listen(path: String, backlog: Int32 = 16) -> Int32? {
        let bytes = Array(path.utf8)
        guard bytes.count <= maxPathLength else { return nil }

        // A socket file that still accepts connections means a live owner.
        if FileManager.default.fileExists(atPath: path) {
            if let probe = connect(path: path, timeout: 0.5) {
                close(probe)
                return nil
            }
            try? FileManager.default.removeItem(atPath: path)
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, size) == 0 }
        }
        guard bound, Darwin.listen(fd, backlog) == 0 else { close(fd); return nil }

        // Owner-only: these sockets accept commands that spawn terminals.
        chmod(path, 0o600)
        return fd
    }

    static func setTimeouts(_ fd: Int32, _ timeout: TimeInterval) {
        var tv = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - floor(timeout)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        let buf = [UInt8](data)
        var off = 0
        while off < buf.count {
            let n = buf.withUnsafeBytes { raw -> Int in
                Darwin.send(fd, raw.baseAddress!.advanced(by: off), buf.count - off, 0)
            }
            if n <= 0 { return false }
            off += n
        }
        return true
    }

    /// Read bytes up to and including the next `\n`. Returns nil on timeout or
    /// a peer that closed before sending a full line.
    static func readLine(_ fd: Int32, limit: Int = 8 * 1024 * 1024) -> Data? {
        var out = Data()
        var byte: UInt8 = 0
        while out.count < limit {
            let n = Darwin.recv(fd, &byte, 1, 0)
            if n <= 0 { return out.isEmpty ? nil : out }
            if byte == 0x0A { return out }
            out.append(byte)
        }
        return out
    }

    /// One request, one response, one connection — the pattern herdr's API uses.
    static func request(path: String, json: [String: Any], timeout: TimeInterval = 3) -> [String: Any]? {
        guard let fd = connect(path: path, timeout: timeout) else { return nil }
        defer { close(fd) }
        guard var payload = try? JSONSerialization.data(withJSONObject: json) else { return nil }
        payload.append(0x0A)
        guard writeAll(fd, payload), let line = readLine(fd) else { return nil }
        return try? JSONSerialization.jsonObject(with: line) as? [String: Any]
    }

    /// Fire-and-forget: used by hooks, which must not block herdr's event loop.
    @discardableResult
    static func send(path: String, json: [String: Any], timeout: TimeInterval = 1) -> Bool {
        guard let fd = connect(path: path, timeout: timeout) else { return false }
        defer { close(fd) }
        guard var payload = try? JSONSerialization.data(withJSONObject: json) else { return false }
        payload.append(0x0A)
        return writeAll(fd, payload)
    }
}

/// Filesystem locations shared by the app, the CLI, and the hook scripts.
enum Paths {
    static var supportDir: String {
        NSHomeDirectory() + "/Library/Application Support/dev.herdr.topbar"
    }
    static var barSocket: String { supportDir + "/bar.sock" }
    static var recentsFile: String { supportDir + "/recents.json" }
    static var configFile: String { supportDir + "/config.json" }
    static var launchScript: String { supportDir + "/launch.command" }

    static var herdrSocket: String {
        if let p = ProcessInfo.processInfo.environment["HERDR_SOCKET_PATH"], !p.isEmpty { return p }
        return NSHomeDirectory() + "/.config/herdr/herdr.sock"
    }
    static var herdrSessionFile: String { NSHomeDirectory() + "/.config/herdr/session.json" }

    static func ensureSupportDir() {
        try? FileManager.default.createDirectory(
            atPath: supportDir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
    }
}
