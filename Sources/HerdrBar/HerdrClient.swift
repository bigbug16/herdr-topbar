import Foundation

/// A pane as reported by `session.snapshot`.
struct PaneSnapshot {
    let paneId: String
    let workspaceId: String
    let cwd: String?
    let agent: String?
    let displayAgent: String?
    let agentStatus: String

    /// What to call the agent in the menu: herdr's own display name when it has
    /// one, otherwise the raw kind ("claude", "codex", ...).
    var agentName: String { displayAgent ?? agent ?? "agent" }
}

/// A workspace as reported by `session.snapshot`.
struct WorkspaceSnapshot {
    let workspaceId: String
    let label: String
    /// Repo root for worktree-backed workspaces; the project path we prefer.
    let repoRoot: String?
}

struct Snapshot {
    let workspaces: [WorkspaceSnapshot]
    let panes: [PaneSnapshot]

    func workspace(_ id: String) -> WorkspaceSnapshot? {
        workspaces.first { $0.workspaceId == id }
    }

    /// Best-effort project directory for a workspace: the worktree repo root if
    /// herdr tracks one, else the cwd of its first pane that has one.
    func projectPath(for workspaceId: String) -> String? {
        if let root = workspace(workspaceId)?.repoRoot, !root.isEmpty { return root }
        return panes.first { $0.workspaceId == workspaceId && $0.cwd != nil }?.cwd
    }
}

/// Client for herdr's socket API. Every call is a fresh short-lived connection;
/// herdr answers one response per connection, and there is no long-lived state
/// worth keeping open (agent state arrives via plugin hooks instead, because
/// `pane.agent_status_changed` cannot be subscribed to globally).
enum HerdrClient {

    private static func call(_ method: String, _ params: [String: Any] = [:],
                             timeout: TimeInterval = 3) -> [String: Any]? {
        let body: [String: Any] = ["id": "herdr-topbar", "method": method, "params": params]
        guard let reply = UnixSocket.request(path: Paths.herdrSocket, json: body, timeout: timeout)
        else { return nil }
        if reply["error"] != nil { return nil }
        return reply["result"] as? [String: Any]
    }

    /// Is a herdr server accepting connections right now?
    static func isRunning() -> Bool {
        call("ping", timeout: 1) != nil
    }

    /// `timeout` is kept short for menu-building calls: the socket is local and
    /// answers in microseconds, but the menu must never stall behind a wedged
    /// server.
    static func snapshot(timeout: TimeInterval = 3) -> Snapshot? {
        guard let result = call("session.snapshot", timeout: timeout),
              let snap = result["snapshot"] as? [String: Any] else { return nil }

        let workspaces = (snap["workspaces"] as? [[String: Any]] ?? []).compactMap {
            ws -> WorkspaceSnapshot? in
            guard let id = ws["workspace_id"] as? String else { return nil }
            let worktree = ws["worktree"] as? [String: Any]
            return WorkspaceSnapshot(
                workspaceId: id,
                label: ws["label"] as? String ?? id,
                repoRoot: worktree?["repo_root"] as? String)
        }

        let panes = (snap["panes"] as? [[String: Any]] ?? []).compactMap {
            p -> PaneSnapshot? in
            guard let id = p["pane_id"] as? String,
                  let wsId = p["workspace_id"] as? String else { return nil }
            return PaneSnapshot(
                paneId: id,
                workspaceId: wsId,
                cwd: p["cwd"] as? String,
                agent: p["agent"] as? String,
                displayAgent: p["display_agent"] as? String,
                agentStatus: p["agent_status"] as? String ?? "unknown")
        }

        return Snapshot(workspaces: workspaces, panes: panes)
    }

    /// Create a workspace rooted at `path` and focus it. Returns false when the
    /// server is not reachable, so the caller can fall back to launching herdr.
    @discardableResult
    static func createWorkspace(cwd: String, label: String?) -> Bool {
        var params: [String: Any] = ["cwd": cwd, "focus": true]
        if let label { params["label"] = label }
        return call("workspace.create", params) != nil
    }

    @discardableResult
    static func focusWorkspace(_ workspaceId: String) -> Bool {
        call("workspace.focus", ["workspace_id": workspaceId]) != nil
    }

    /// Workspace directories persisted by herdr, readable even while the server
    /// is stopped. Used to seed the recents list on a cold first run.
    static func persistedWorkspaceDirs() -> [String] {
        guard let data = FileManager.default.contents(atPath: Paths.herdrSessionFile),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let workspaces = root["workspaces"] as? [[String: Any]] else { return [] }
        return workspaces.compactMap { $0["identity_cwd"] as? String }
    }
}
