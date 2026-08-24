import Foundation

struct RecentProject {
    let path: String
    var lastOpened: Date

    var label: String { (path as NSString).lastPathComponent }
    var exists: Bool { FileManager.default.fileExists(atPath: path) }

    /// `~`-relative form for the menu's secondary line.
    var displayPath: String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

/// The last projects herdr was used in, persisted across restarts.
///
/// Three sources feed this so the list stays useful no matter how a project was
/// opened: explicit opens through this app, a merge from `session.snapshot`
/// (projects opened from inside herdr), and herdr's own `session.json` as a
/// cold-start seed when the server is not running.
enum Recents {

    static let limit = 10

    static func load() -> [RecentProject] {
        guard let data = FileManager.default.contents(atPath: Paths.recentsFile),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }

        return rows.compactMap { row in
            guard let path = row["path"] as? String else { return nil }
            let stamp = row["lastOpened"] as? Double ?? 0
            return RecentProject(path: path, lastOpened: Date(timeIntervalSince1970: stamp))
        }
        .sorted { $0.lastOpened > $1.lastOpened }
    }

    static func save(_ list: [RecentProject]) {
        Paths.ensureSupportDir()
        let rows = list
            .sorted { $0.lastOpened > $1.lastOpened }
            .prefix(limit)
            .map { ["path": $0.path, "lastOpened": $0.lastOpened.timeIntervalSince1970] as [String: Any] }
        guard let data = try? JSONSerialization.data(withJSONObject: Array(rows),
                                                     options: [.prettyPrinted])
        else { return }
        try? data.write(to: URL(fileURLWithPath: Paths.recentsFile))
    }

    /// Move a project to the top of the list.
    static func record(_ path: String) {
        var list = load().filter { $0.path != path }
        list.insert(RecentProject(path: path, lastOpened: Date()), at: 0)
        save(list)
    }

    /// Fold in every project currently open in herdr, without disturbing the
    /// ordering of entries already known.
    static func merge(snapshot: Snapshot?) {
        guard let snapshot else { return }
        var list = load()
        let known = Set(list.map(\.path))
        var added = false

        for workspace in snapshot.workspaces {
            guard let path = snapshot.projectPath(for: workspace.workspaceId),
                  !known.contains(path) else { continue }
            list.append(RecentProject(path: path, lastOpened: Date()))
            added = true
        }
        if added { save(list) }
    }

    /// On a cold start with no history, borrow the workspace directories herdr
    /// persisted — available even while the server is stopped.
    static func seedIfEmpty() {
        guard load().isEmpty else { return }
        let dirs = HerdrClient.persistedWorkspaceDirs()
        guard !dirs.isEmpty else { return }
        let now = Date()
        save(dirs.enumerated().map {
            RecentProject(path: $1, lastOpened: now.addingTimeInterval(-Double($0)))
        })
    }

    static func remove(_ path: String) {
        save(load().filter { $0.path != path })
    }

    static func clear() { save([]) }
}
