import AppKit

/// HerdrBar — a macOS menu bar companion for herdr.
///
/// Left click brings the terminal running herdr to the front. Right click opens
/// a menu for starting herdr in a folder, jumping to a recent project, and
/// seeing which agent is waiting for input.
///
/// Note on notifications: herdr already delivers its own (`[ui.toast]`,
/// `[ui.sound]`). This app posts none and changes none of that configuration —
/// it only makes an existing "agent is waiting" state easy to spot by animating
/// the menu bar icon.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private var icon: IconController!
    private let events = EventServer()
    private let agents = AgentWatch()
    private var config = Config.load()

    /// Panes whose waiting state the user has already seen. A pane that starts
    /// waiting later is absent here, so the icon flashes again for it.
    private var acknowledged = Set<String>()

    /// Cached for menu building; refreshed just before the menu opens.
    private var snapshot: Snapshot?
    private var serverRunning = false

    /// Stops the blink once `config.blinkTimeoutSeconds` has elapsed, so an
    /// agent left waiting overnight does not blink forever.
    private var blinkDeadline: Timer?
    private var wasFlashing = false

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // One icon only. A second copy finds the socket already owned and exits
        // rather than stacking a duplicate in the menu bar.
        guard events.start() else {
            NSApp.terminate(nil)
            return
        }

        Paths.ensureSupportDir()
        config.save()
        Recents.seedIfEmpty()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = StatusIcon.normal()
            button.target = self
            button.action = #selector(iconClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "herdr"
        }
        icon = IconController(button: statusItem.button)

        events.onEvent = { [weak self] name, data in
            self?.agents.apply(event: name, data: data)
        }
        events.onOpen = { [weak self] path in
            guard let self else { return }
            ProjectOpener.open(path: path, config: self.config)
        }
        events.onPicker = { [weak self] in
            guard let self else { return }
            ProjectOpener.chooseFolder(config: self.config)
        }
        events.statusProvider = { [weak self] in self?.statusPayload() ?? [:] }
        agents.onChange = { [weak self] in self?.refreshIcon() }

        // Bringing herdr forward by any route — this icon, Cmd-Tab, clicking
        // the window — counts as having seen what is waiting.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)

        refreshState()
    }

    func applicationWillTerminate(_ notification: Notification) {
        events.stop()
    }

    /// Finder's "Open With → HerdrBar" arrives here.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.isFileURL {
            ProjectOpener.open(path: url.path, config: config)
        }
    }

    // MARK: - Icon interaction

    @objc private func iconClicked() {
        let isRightClick = NSApp.currentEvent.map {
            $0.type == .rightMouseUp || $0.modifierFlags.contains(.control)
        } ?? false

        // Left click's job is to get back to herdr, so take the fast path: a
        // cached process-tree lookup, no socket round-trip. With nothing to go
        // back to, fall through to the menu so the click still does something.
        if !isRightClick && TerminalHost.hasVisibleClient() {
            TerminalHost.bringToFront()
            acknowledgeWaiting()
            return
        }

        refreshState()
        showMenu()
    }

    private func showMenu() {
        let menu = MenuBuilder.build(
            waiting: agents.sorted,
            recents: Recents.load(),
            snapshot: snapshot,
            serverRunning: serverRunning,
            hasClient: TerminalHost.hasVisibleClient(),
            blinkTimeout: config.blinkTimeoutSeconds,
            actions: menuActions())
        menu.delegate = self

        // The status item only owns a menu while one is being shown; otherwise
        // AppKit would open it on left click too and swallow the front action.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func menuActions() -> MenuActions {
        MenuActions(
            startHerdr: { [weak self] in
                guard let self else { return }
                TerminalHost.launchHerdr(cwd: nil, config: self.config)
                TerminalHost.invalidateHostCache()
            },
            bringToFront: { [weak self] in
                TerminalHost.bringToFront()
                self?.acknowledgeWaiting()
            },
            focusWorkspace: { [weak self] workspaceId in
                guard let self else { return }
                ProjectOpener.focus(workspaceId: workspaceId, config: self.config)
                self.acknowledgeWaiting()
            },
            openFolder: { [weak self] in
                guard let self else { return }
                ProjectOpener.chooseFolder(config: self.config)
            },
            openRecent: { [weak self] path in
                guard let self else { return }
                ProjectOpener.open(path: path, config: self.config)
            },
            removeRecent: { Recents.remove($0) },
            clearRecents: { Recents.clear() },
            toggleLoginItem: { LoginItem.toggle() },
            installFinderIntegration: { [weak self] in self?.installFinderIntegration() },
            setBlinkTimeout: { [weak self] seconds in
                guard let self else { return }
                self.config.blinkTimeoutSeconds = seconds
                self.config.save()
                // Re-arm against the new limit rather than waiting out the old.
                self.wasFlashing = false
                self.refreshIcon()
            },
            quit: { NSApp.terminate(nil) })
    }

    // MARK: - State

    /// Refresh the herdr-derived state the menu and icon read from.
    private func refreshState() {
        // Short timeout: this runs on the main thread right before the menu is
        // shown, and a wedged server must not freeze the menu bar.
        snapshot = HerdrClient.snapshot(timeout: 0.6)
        serverRunning = snapshot != nil
        agents.reconcile(with: snapshot)
        Recents.merge(snapshot: snapshot)
        refreshIcon()
    }

    private func refreshIcon() {
        let waiting = Set(agents.waiting.keys)
        // Forget acknowledgements for panes that are no longer waiting, so the
        // set cannot grow without bound.
        acknowledged.formIntersection(waiting)

        // The flash means "look at herdr". If herdr is already the frontmost
        // app, that has happened — there is no activation notification coming,
        // because no activation is needed.
        if !waiting.isEmpty && TerminalHost.isHostFrontmost() {
            acknowledged.formUnion(waiting)
        }

        let flashing = !waiting.isEmpty && !waiting.isSubset(of: acknowledged)

        if waiting.isEmpty {
            icon.set(.idle)
        } else if flashing {
            icon.set(.flashing)
        } else {
            icon.set(.acknowledged)
        }

        // Arm the deadline on the transition into blinking, not on every
        // refresh, or a burst of events would keep pushing it out.
        if flashing && !wasFlashing {
            armBlinkDeadline()
        } else if !flashing {
            blinkDeadline?.invalidate()
            blinkDeadline = nil
        }
        wasFlashing = flashing

        let count = waiting.count
        statusItem?.button?.toolTip = count == 0
            ? "herdr"
            : "herdr — \(count) agent\(count == 1 ? "" : "s") waiting for input"
    }

    /// Machine-readable state, used by `herdrbar-open --status`.
    private func statusPayload() -> [String: Any] {
        let host = TerminalHost.hostApplication()
        let iconState: String
        switch icon.state {
        case .idle: iconState = "idle"
        case .flashing: iconState = "flashing"
        case .acknowledged: iconState = "acknowledged"
        }
        let frontmost = NSWorkspace.shared.frontmostApplication
        return [
            "serverRunning": serverRunning,
            "iconState": iconState,
            "frontmostApp": frontmost?.bundleIdentifier ?? "",
            "frontmostPid": frontmost?.processIdentifier ?? 0,
            "hostFrontmost": TerminalHost.isHostFrontmost(),
            "blinkTimeoutSeconds": config.blinkTimeoutSeconds,
            "hostTerminal": host?.bundleIdentifier ?? "",
            "hostPid": host?.processIdentifier ?? 0,
            "waiting": agents.sorted.map {
                [
                    "agent": $0.agent,
                    "paneId": $0.paneId,
                    "workspaceId": $0.workspaceId,
                    "workspaceLabel": $0.workspaceLabel ?? "",
                    "menuTitle": $0.menuTitle,
                ]
            },
        ]
    }

    /// Let the blink run for the configured window, then settle to the badge.
    /// A timeout of 0 means the user wants it to blink until they click.
    private func armBlinkDeadline() {
        blinkDeadline?.invalidate()
        blinkDeadline = nil

        let seconds = config.blinkTimeoutSeconds
        guard seconds > 0 else { return }

        let timer = Timer(timeInterval: TimeInterval(seconds), repeats: false) { [weak self] _ in
            self?.acknowledgeWaiting()
        }
        RunLoop.main.add(timer, forMode: .common)
        blinkDeadline = timer
    }

    /// Stop the flash: the user has looked at herdr.
    private func acknowledgeWaiting() {
        acknowledged.formUnion(agents.waiting.keys)
        refreshIcon()
    }

    @objc private func appActivated(_ notification: Notification) {
        guard !agents.isEmpty,
              let activated = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                  as? NSRunningApplication,
              let host = TerminalHost.hostApplication(),
              activated.processIdentifier == host.processIdentifier
        else { return }
        acknowledgeWaiting()
    }

    // MARK: - Menu delegate

    func menuWillOpen(_ menu: NSMenu) {
        // Nothing to do: showMenu() already refreshed. Kept so future
        // resubmissions of the menu stay in one place.
    }

    // MARK: - Finder integration

    private func installFinderIntegration() {
        guard let script = Bundle.main.path(forResource: "install-finder", ofType: "sh") else {
            presentAlert(title: "Finder integration script missing",
                         body: "install-finder.sh was not found inside the app bundle. "
                             + "Run scripts/install-finder.sh from the plugin directory instead.")
            return
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [script]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
        } catch {
            presentAlert(title: "Could not run the installer", body: error.localizedDescription)
            return
        }
        task.waitUntilExit()

        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        if task.terminationStatus == 0 {
            presentAlert(
                title: "Finder integration installed",
                body: "Right-click a file or folder to find “Open with herdr” under "
                    + "Services, and HerdrBar under Open With.\n\nServices sits near the "
                    + "bottom of the context menu — macOS reserves the Quick Actions submenu "
                    + "for app extensions and Shortcuts.\n\nIf it does not appear, enable it "
                    + "in System Settings → Keyboard → Keyboard Shortcuts… → Services, then "
                    + "relaunch Finder.")
        } else {
            presentAlert(title: "Finder integration failed",
                         body: output.isEmpty ? "The installer exited with an error." : output)
        }
    }

    private func presentAlert(title: String, body: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// `--diagnose` reports what the app can see, without touching the menu bar.
// Host detection walks the process tree, so this is the fastest way to explain
// a "clicking the icon does nothing" report.
if CommandLine.arguments.contains("--diagnose") {
    let config = Config.load()
    print("herdr binary   : \(config.herdrBinary)")
    print("terminal       : \(config.terminalBundleId)")
    print("herdr socket   : \(Paths.herdrSocket)")
    print("server running : \(HerdrClient.isRunning())")

    if let host = TerminalHost.hostApplication(useCache: false) {
        print("host terminal  : \(host.localizedName ?? "?") "
            + "(\(host.bundleIdentifier ?? "?"), pid \(host.processIdentifier))")
    } else {
        print("host terminal  : none — no attached herdr client found")
    }

    if let snapshot = HerdrClient.snapshot() {
        print("workspaces     : \(snapshot.workspaces.count)")
        for workspace in snapshot.workspaces {
            let path = snapshot.projectPath(for: workspace.workspaceId) ?? "-"
            print("  \(workspace.label)  \(path)")
        }
        let blocked = snapshot.panes.filter { $0.agentStatus == "blocked" }
        print("waiting agents : \(blocked.count)")
        for pane in blocked { print("  \(pane.agentName) in \(pane.workspaceId)") }
    }
    exit(0)
}

// An accessory app: menu bar only, no Dock tile and no menu bar menus.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
