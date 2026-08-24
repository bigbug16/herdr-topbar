import AppKit

/// An NSMenuItem that carries its own handler, so the menu can be rebuilt
/// declaratively without a switch over tags or selectors.
final class BlockMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, keyEquivalent: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: keyEquivalent)
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("not supported") }

    @objc private func fire() { handler() }
}

/// Everything the menu can do, supplied by the app delegate.
struct MenuActions {
    var startHerdr: () -> Void
    var bringToFront: () -> Void
    var focusWorkspace: (String) -> Void
    var openFolder: () -> Void
    var openRecent: (String) -> Void
    var removeRecent: (String) -> Void
    var clearRecents: () -> Void
    var toggleLoginItem: () -> Void
    var installFinderIntegration: () -> Void
    var setBlinkTimeout: (Int) -> Void
    var quit: () -> Void
}

enum MenuBuilder {

    /// Build the full right-click menu for the current state.
    static func build(waiting: [WaitingAgent],
                      recents: [RecentProject],
                      snapshot: Snapshot?,
                      serverRunning: Bool,
                      hasClient: Bool,
                      blinkTimeout: Int,
                      actions: MenuActions) -> NSMenu {

        let menu = NSMenu()
        menu.autoenablesItems = false

        // MARK: Front / start
        if hasClient {
            menu.addItem(BlockMenuItem(title: "Bring herdr to Front",
                                       handler: actions.bringToFront))
        } else {
            menu.addItem(BlockMenuItem(title: "Start herdr", handler: actions.startHerdr))
        }

        // MARK: Waiting agents
        if !waiting.isEmpty {
            menu.addItem(.separator())
            menu.addItem(header("Waiting for Input"))

            for agent in waiting {
                let item = BlockMenuItem(title: agent.menuTitle) {
                    actions.focusWorkspace(agent.workspaceId)
                }
                if let label = agent.workspaceLabel, !label.isEmpty {
                    // Project name as a dimmed trailing line, so a glance
                    // answers "which agent, in which project".
                    item.attributedTitle = twoPart(agent.menuTitle, label)
                }
                item.indentationLevel = 1
                menu.addItem(item)
            }
        }

        // MARK: Opening projects
        menu.addItem(.separator())

        let open = BlockMenuItem(title: "Open Folder…", keyEquivalent: "o",
                                 handler: actions.openFolder)
        open.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(open)

        let recentsItem = NSMenuItem(title: "Recent Projects", action: nil, keyEquivalent: "")
        recentsItem.submenu = recentsMenu(recents, actions: actions)
        recentsItem.isEnabled = !recents.isEmpty
        menu.addItem(recentsItem)

        // MARK: Settings
        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settings.submenu = settingsMenu(blinkTimeout: blinkTimeout, actions: actions)
        menu.addItem(settings)

        menu.addItem(header(statusLine(snapshot: snapshot, serverRunning: serverRunning)))

        menu.addItem(.separator())
        menu.addItem(BlockMenuItem(title: "Quit HerdrBar", keyEquivalent: "q",
                                   handler: actions.quit))
        return menu
    }

    // MARK: - Sections

    private static func recentsMenu(_ recents: [RecentProject],
                                    actions: MenuActions) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if recents.isEmpty {
            menu.addItem(header("No recent projects"))
            return menu
        }

        for project in recents {
            if project.exists {
                let item = BlockMenuItem(title: project.label) {
                    actions.openRecent(project.path)
                }
                item.attributedTitle = twoPart(project.label, project.displayPath)
                item.toolTip = project.path
                menu.addItem(item)
            } else {
                // Keep it visible but obviously dead; clicking clears it.
                let item = BlockMenuItem(title: project.label) {
                    actions.removeRecent(project.path)
                }
                item.attributedTitle = twoPart(project.label, "missing — click to remove",
                                               strikethrough: true)
                item.toolTip = project.path
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        menu.addItem(BlockMenuItem(title: "Clear Menu", handler: actions.clearRecents))
        return menu
    }

    private static func settingsMenu(blinkTimeout: Int, actions: MenuActions) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // How long the icon blinks for a waiting agent before it goes quiet.
        let blink = NSMenuItem(title: "Blink Duration", action: nil, keyEquivalent: "")
        blink.submenu = blinkMenu(selected: blinkTimeout, actions: actions)
        menu.addItem(blink)

        menu.addItem(.separator())

        let login = BlockMenuItem(title: "Start at Login", handler: actions.toggleLoginItem)
        login.state = LoginItem.isInstalled ? .on : .off
        menu.addItem(login)

        menu.addItem(BlockMenuItem(title: "Install Finder Integration…",
                                   handler: actions.installFinderIntegration))
        return menu
    }

    private static func blinkMenu(selected: Int, actions: MenuActions) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        for choice in Config.blinkTimeoutChoices {
            let item = BlockMenuItem(title: choice.title) {
                actions.setBlinkTimeout(choice.seconds)
            }
            item.state = choice.seconds == selected ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    // MARK: - Presentation helpers

    private static func statusLine(snapshot: Snapshot?, serverRunning: Bool) -> String {
        guard serverRunning else { return "herdr: not running" }
        let count = snapshot?.workspaces.count ?? 0
        let noun = count == 1 ? "workspace" : "workspaces"
        return "herdr: running · \(count) \(noun)"
    }

    /// A non-interactive caption row.
    private static func header(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        return item
    }

    /// "Primary   secondary" on one row, the secondary dimmed and smaller.
    private static func twoPart(_ primary: String, _ secondary: String,
                                strikethrough: Bool = false) -> NSAttributedString {
        let result = NSMutableAttributedString(string: primary, attributes: [
            .font: NSFont.menuFont(ofSize: 0),
            .foregroundColor: NSColor.labelColor,
        ])
        var trailing: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        if strikethrough {
            trailing[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        result.append(NSAttributedString(string: "   " + secondary, attributes: trailing))
        return result
    }
}
