import Foundation

/// One agent that herdr reports as waiting for input.
struct WaitingAgent {
    let paneId: String
    let workspaceId: String
    let agent: String
    var workspaceLabel: String?

    /// e.g. "claude — waiting"
    var menuTitle: String { "\(agent) — waiting" }
}

/// Tracks which agents are in herdr's `blocked` state, i.e. waiting for input.
///
/// Live updates arrive from the `pane.agent_status_changed` plugin hook: that
/// event cannot be subscribed to globally over the socket API (it requires a
/// concrete `pane_id`), but herdr's plugin hook allowlist does accept it, so
/// hooks are the only way to observe it for every pane at once.
///
/// This only observes state. herdr keeps full ownership of notification
/// delivery — nothing here posts, suppresses, or reconfigures a notification.
final class AgentWatch {

    private(set) var waiting: [String: WaitingAgent] = [:]
    var onChange: (() -> Void)?

    var isEmpty: Bool { waiting.isEmpty }

    /// Stable ordering so menu rows do not jump around between openings.
    var sorted: [WaitingAgent] {
        waiting.values.sorted {
            ($0.workspaceLabel ?? $0.workspaceId, $0.agent) <
            ($1.workspaceLabel ?? $1.workspaceId, $1.agent)
        }
    }

    /// Apply one forwarded hook event.
    func apply(event: String, data: [String: Any]) {
        guard event == "pane.agent_status_changed" || event == "pane_agent_status_changed",
              let paneId = data["pane_id"] as? String,
              let workspaceId = data["workspace_id"] as? String,
              let status = data["agent_status"] as? String
        else { return }

        let before = waiting.count

        if status == "blocked" {
            let name = (data["display_agent"] as? String)
                ?? (data["agent"] as? String)
                ?? "agent"
            waiting[paneId] = WaitingAgent(paneId: paneId, workspaceId: workspaceId,
                                           agent: name, workspaceLabel: nil)
        } else {
            waiting.removeValue(forKey: paneId)
        }

        if waiting.count != before { onChange?() }
    }

    /// Rebuild from a full snapshot. Covers events missed while the app was not
    /// running, panes that closed while blocked, and fills in workspace labels
    /// the event payload does not carry.
    func reconcile(with snapshot: Snapshot?) {
        guard let snapshot else {
            // No reachable server means nothing can be waiting.
            if !waiting.isEmpty { waiting.removeAll(); onChange?() }
            return
        }

        var rebuilt: [String: WaitingAgent] = [:]
        for pane in snapshot.panes where pane.agentStatus == "blocked" {
            rebuilt[pane.paneId] = WaitingAgent(
                paneId: pane.paneId,
                workspaceId: pane.workspaceId,
                agent: pane.agentName,
                workspaceLabel: snapshot.workspace(pane.workspaceId)?.label)
        }

        let changed = Set(rebuilt.keys) != Set(waiting.keys)
        waiting = rebuilt
        if changed { onChange?() }
    }
}
