import Foundation

/// Listens on HerdrBar's own unix socket for messages pushed in from outside
/// the app: forwarded herdr hook events, and open-project requests from Finder
/// or the `herdrbar-open` CLI.
///
/// Runs its accept loop on a dedicated thread and hands every decoded message
/// to the main queue, since all consumers touch AppKit state.
final class EventServer {

    private var listenFd: Int32 = -1
    private var running = false
    private let workers = DispatchQueue(label: "dev.herdr.topbar.events", attributes: .concurrent)

    /// (event name, event payload)
    var onEvent: ((String, [String: Any]) -> Void)?
    /// Absolute path to open in herdr.
    var onOpen: ((String) -> Void)?
    /// Show the folder picker (the `open-picker` plugin action).
    var onPicker: (() -> Void)?
    /// Current app state, answered synchronously to a `status` request.
    var statusProvider: (() -> [String: Any])?

    /// Returns false when another live instance already owns the socket, which
    /// is how a second copy of the app knows to bail out.
    func start() -> Bool {
        Paths.ensureSupportDir()
        guard let fd = UnixSocket.listen(path: Paths.barSocket) else { return false }
        listenFd = fd
        running = true

        let thread = Thread { [weak self] in self?.acceptLoop() }
        thread.name = "dev.herdr.topbar.accept"
        thread.start()
        return true
    }

    func stop() {
        // Only tear down a listener this instance actually owns. A second copy
        // of the app that lost the single-instance race still gets terminated,
        // and unlinking unconditionally here would delete the *winner's* socket
        // out from under it, leaving a running app that nothing can reach.
        guard listenFd >= 0 else { return }

        running = false
        close(listenFd)
        listenFd = -1
        try? FileManager.default.removeItem(atPath: Paths.barSocket)
    }

    private func acceptLoop() {
        while running {
            let fd = accept(listenFd, nil, nil)
            if fd < 0 {
                if running && (errno == EINTR || errno == EAGAIN) { continue }
                break
            }
            workers.async { [weak self] in self?.handle(fd) }
        }
    }

    private func handle(_ fd: Int32) {
        defer { close(fd) }
        // A writer that connects and then stalls must not pin this worker.
        UnixSocket.setTimeouts(fd, 2)

        guard let line = UnixSocket.readLine(fd),
              let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
        else { return }

        switch message["kind"] as? String {
        case "event":
            guard let name = message["event"] as? String else { return }
            let data = message["data"] as? [String: Any] ?? [:]
            DispatchQueue.main.async { [weak self] in self?.onEvent?(name, data) }

        case "open":
            guard let path = message["path"] as? String, !path.isEmpty else { return }
            DispatchQueue.main.async { [weak self] in self?.onOpen?(path) }

        case "picker":
            DispatchQueue.main.async { [weak self] in self?.onPicker?() }

        case "status":
            respondWithStatus(fd)

        default:
            return
        }
    }

    /// Answer a status query. The state lives on the main thread, so this hops
    /// over and waits — bounded, so a busy main thread degrades to an empty
    /// answer instead of pinning this worker.
    private func respondWithStatus(_ fd: Int32) {
        final class Box { var value: [String: Any] = [:] }
        let box = Box()
        let ready = DispatchSemaphore(value: 0)

        DispatchQueue.main.async { [weak self] in
            box.value = self?.statusProvider?() ?? [:]
            ready.signal()
        }
        guard ready.wait(timeout: .now() + 2) == .success else { return }

        guard var data = try? JSONSerialization.data(withJSONObject: box.value) else { return }
        data.append(0x0A)
        _ = UnixSocket.writeAll(fd, data)
    }

    deinit { stop() }
}
