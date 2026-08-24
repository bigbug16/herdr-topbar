import Foundation

/// herdrbar-open — the command-line entry point into a running HerdrBar.
///
/// Two modes:
///
///   herdrbar-open <path>...   Open paths in herdr. Starts HerdrBar if needed.
///                             Used by the Finder Quick Action.
///
///   herdrbar-open --picker    Ask HerdrBar to show its folder picker.
///
///   herdrbar-open --status    Print HerdrBar's current state as JSON.
///
///   herdrbar-open --event     Forward one herdr plugin hook event, read from
///                             HERDR_PLUGIN_EVENT / HERDR_PLUGIN_EVENT_JSON.
///                             Never starts HerdrBar, and always exits 0 — a
///                             hook must not fail or stall herdr's event loop.
///
/// This is a compiled binary rather than a `nc`/`python` shell-out on purpose:
/// hooks run on every agent state change, and shelling out to an interpreter
/// risks both latency and, on a machine without Command Line Tools, a developer
/// tools install prompt.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("herdrbar-open: \(message)\n".utf8))
    exit(1)
}

/// The enclosing .app, derived from this binary's own location inside
/// `HerdrBar.app/Contents/MacOS/`, so a relocated bundle still starts itself.
func enclosingAppBundle() -> String? {
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    let bundle = executable            // .../Contents/MacOS/herdrbar-open
        .deletingLastPathComponent()   // .../Contents/MacOS
        .deletingLastPathComponent()   // .../Contents
        .deletingLastPathComponent()   // .../HerdrBar.app
    return bundle.pathExtension == "app" ? bundle.path : nil
}

func appIsListening() -> Bool {
    guard let probe = UnixSocket.connect(path: Paths.barSocket, timeout: 0.5) else { return false }
    close(probe)
    return true
}

/// Start HerdrBar in the background and wait for it to claim its socket.
func launchApp() -> Bool {
    guard let bundle = enclosingAppBundle() else { return false }

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    // -g: do not steal focus; the terminal herdr opens should come forward.
    task.arguments = ["-g", bundle]
    try? task.run()
    task.waitUntilExit()

    for _ in 0 ..< 30 {
        if appIsListening() { return true }
        usleep(100_000)
    }
    return false
}

// MARK: - Event forwarding

func forwardEvent() -> Never {
    let environment = ProcessInfo.processInfo.environment
    guard let name = environment["HERDR_PLUGIN_EVENT"], !name.isEmpty else { exit(0) }

    // herdr wraps the payload in an envelope:
    //   {"event":"pane_agent_status_changed","data":{"pane_id":…,"agent_status":…}}
    // Unwrap `data` when present, but still accept a bare event object — the
    // envelope is not part of any documented contract, so do not depend on it.
    var payload: [String: Any] = [:]
    if let raw = environment["HERDR_PLUGIN_EVENT_JSON"],
       let data = raw.data(using: .utf8),
       let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        payload = (parsed["data"] as? [String: Any]) ?? parsed
    }

    // Deliberately no launch: if the user quit HerdrBar, a background event
    // should not bring it back.
    UnixSocket.send(path: Paths.barSocket,
                    json: ["kind": "event", "event": name, "data": payload],
                    timeout: 1)
    exit(0)
}

// MARK: - Entry

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.first == "--event" {
    forwardEvent()
}

if arguments.first == "--status" {
    guard appIsListening() else { fail("HerdrBar is not running") }
    guard let fd = UnixSocket.connect(path: Paths.barSocket, timeout: 3) else {
        fail("could not connect to HerdrBar")
    }
    defer { close(fd) }
    var request = try! JSONSerialization.data(withJSONObject: ["kind": "status"])
    request.append(0x0A)
    guard UnixSocket.writeAll(fd, request), let reply = UnixSocket.readLine(fd) else {
        fail("no answer from HerdrBar")
    }
    FileHandle.standardOutput.write(reply)
    FileHandle.standardOutput.write(Data("\n".utf8))
    exit(0)
}

if arguments.first == "--picker" {
    guard appIsListening() || launchApp() else {
        fail("HerdrBar is not running and could not be started")
    }
    exit(UnixSocket.send(path: Paths.barSocket, json: ["kind": "picker"]) ? 0 : 1)
}

let paths = arguments.filter { !$0.isEmpty && !$0.hasPrefix("--") }
guard !paths.isEmpty else {
    fail("usage: herdrbar-open <path> [path...]  |  herdrbar-open --event")
}

guard appIsListening() || launchApp() else {
    fail("HerdrBar is not running and could not be started")
}

var failures = 0
for path in paths {
    let absolute = URL(fileURLWithPath: path).standardizedFileURL.path
    if !UnixSocket.send(path: Paths.barSocket, json: ["kind": "open", "path": absolute]) {
        FileHandle.standardError.write(Data("herdrbar-open: could not send \(absolute)\n".utf8))
        failures += 1
    }
}

exit(failures == 0 ? 0 : 1)
