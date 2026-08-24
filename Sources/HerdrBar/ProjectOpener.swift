import AppKit
import Foundation

/// The single path every "open this project in herdr" entry point funnels
/// through — the folder picker, a recents row, Finder, and the CLI.
enum ProjectOpener {

    /// Resolve `path` to a directory (a file opens its parent), then hand it to
    /// herdr. Socket work happens off the main thread; AppKit calls hop back.
    static func open(path: String, config: Config, completion: (() -> Void)? = nil) {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDirectory) else {
            NSSound.beep()
            completion?()
            return
        }
        let directory = isDirectory.boolValue
            ? path
            : (path as NSString).deletingLastPathComponent

        Recents.record(directory)

        DispatchQueue.global(qos: .userInitiated).async {
            let serverUp = HerdrClient.isRunning()
            var created = false
            if serverUp {
                created = HerdrClient.createWorkspace(
                    cwd: directory,
                    label: (directory as NSString).lastPathComponent)
            }

            DispatchQueue.main.async {
                if serverUp && created {
                    // The workspace exists and is focused; make sure something
                    // is actually displaying it.
                    if TerminalHost.hasVisibleClient() {
                        TerminalHost.bringToFront()
                    } else {
                        // Attaching with no cwd lands on the focused workspace.
                        TerminalHost.launchHerdr(cwd: nil, config: config)
                    }
                } else {
                    // No server (or the call failed): start herdr in the folder.
                    TerminalHost.launchHerdr(cwd: directory, config: config)
                }
                completion?()
            }
        }
    }

    /// Focus an already-open workspace and bring its terminal forward.
    static func focus(workspaceId: String, config: Config) {
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = HerdrClient.focusWorkspace(workspaceId)
            DispatchQueue.main.async {
                if TerminalHost.hasVisibleClient() {
                    TerminalHost.bringToFront()
                } else if ok {
                    TerminalHost.launchHerdr(cwd: nil, config: config)
                }
            }
        }
    }

    /// Folder picker used by the menu and the `open-picker` plugin action.
    static func chooseFolder(config: Config) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open in herdr"
        panel.message = "Choose a folder to open as a herdr workspace"

        // An accessory-mode app has no windows, so the panel needs the app
        // pulled forward or it opens behind whatever is frontmost.
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(path: url.path, config: config)
    }
}
