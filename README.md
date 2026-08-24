# herdr-topbar

**English** · [Türkçe](README.tr.md)

A macOS menu bar companion for [herdr](https://herdr.dev).

herdr lives inside the terminal. This plugin puts a small icon in the menu bar so
you can get back to it from anywhere, start it in any folder, and tell at a
glance when an agent is waiting for you.

```
┌─ menu bar ─────────────────────────────────────────────── ▣ ─┐
                                                            ▲
                                    left click  →  bring herdr to the front
                                    right click →  menu
```

## What it does

**Left click** brings the terminal running herdr to the front. If herdr is not
running, it opens the menu instead so the click still gets you somewhere.

**Right click** opens the menu:

- **Start herdr** / **Bring herdr to Front**
- **Waiting for Input** — which agent is waiting, and in which project. Click a
  row to jump straight to that workspace.
- **Open Folder…** — pick a folder; it opens as a herdr workspace.
- **Recent Projects** — the last 10 projects, including ones you opened from
  inside herdr.
- **Settings** — blink duration, start at login, install Finder integration.

**At rest the icon is always the dark ram**, in either system appearance. It is
deliberately not an AppKit template image: a template gets re-tinted for contrast
and would flip to white on a dark menu bar, and the point here is that the
resting look never changes — the blink is the only thing that moves.

**An agent waiting for input** makes the icon swap to the light ram and back,
three times a second. It stops as soon as herdr comes to the front — by this
icon, by Cmd-Tab, or by clicking the window — and leaves a small dot while the
agent is still waiting. A *different* agent blocking later starts the blink
again.

It also stops on its own after **Settings → Blink Duration**, so an agent left
waiting overnight is not still blinking in the morning:

| Choice | Behaviour |
|---|---|
| 1 minute | Blink for a minute, then show the static dot |
| **3 minutes** | Default |
| 10 minutes | For longer unattended runs |
| Until clicked | Never stops on its own |

The dot stays either way — only the movement stops.

**Finder** gets two entries, both opening herdr in the selected folder (or, for a
file, its parent folder):

- right-click → **Services → Open with herdr** (near the bottom of the menu)
- right-click → **Open With → HerdrBar**

### About notifications

herdr already delivers its own notifications (`[ui.toast]`, `[ui.sound]` in
`config.toml`). **This plugin posts none and changes none of that.** It only
makes an existing "agent is waiting" state easy to notice from across the screen.
Your herdr notification settings are left exactly as you have them.

## Install

```bash
git clone https://github.com/bigbug16/herdr-topbar.git
cd herdr-topbar

herdr plugin link "$PWD"
bash scripts/build.sh
bash scripts/install-finder.sh
bash scripts/install-login-item.sh
```

Or install it straight from GitHub, which runs the build step for you:

```bash
herdr plugin install bigbug16/herdr-topbar
```

`herdr plugin install` runs `scripts/build.sh` for you, but **`herdr plugin link`
does not run build steps** — so when working on a linked copy, run `build.sh`
yourself after changing any Swift source, then `scripts/restart-bar.sh`.

`install-login-item.sh` is what keeps the icon in the menu bar while herdr is
closed. The plugin's `[[startup]]` hook only fires when a herdr server starts,
which cannot cover the "herdr is closed, click the icon to start it" case.

If **Services → Open with herdr** does not appear, enable it under
**System Settings → Keyboard → Keyboard Shortcuts… → Services**, then relaunch
Finder (`killall Finder`).

Note that a `.workflow` in `~/Library/Services` lands in Finder's **Services**
submenu, *not* under **Quick Actions** — macOS reserves that menu for app
extensions and Shortcuts. Both run the same command; only the submenu differs.
If you specifically want it under Quick Actions, create a shortcut in
Shortcuts.app that starts with "Receive files and folders from Quick Actions"
and runs `~/Applications/HerdrBar.app/Contents/MacOS/herdrbar-open "$@"`.

## Plugin actions

| Action | What it does |
|---|---|
| `open-picker` | Show the folder picker |
| `install-finder-integration` | Install the Services entry and Open With handler |
| `install-login-item` | Install the start-at-login LaunchAgent |
| `restart-bar` | Restart the menu bar app after a rebuild |

Bind the picker to a key in `~/.config/herdr/config.toml`:

```toml
[[keys.command]]
key = "prefix+o"
type = "plugin_action"
command = "herdr-topbar.open-picker"
description = "open a folder in herdr"
```

## The icon

The menu bar glyph is herdr's own ram, from
[`herdr.dev/assets/ram.svg`](https://herdr.dev/assets/ram.svg). The source SVG is
kept at `Resources/ram.svg`; `scripts/make-icon.sh` crops it to the ram's head
and writes the vector PDF the app actually bundles.

The crop matters: in the full mark the ram's body runs off the frame as a solid
mass, which at menu bar size collapses into an unreadable block. Cropping to the
head keeps the curled horn and the `>-` prompt face — the parts that identify it
at 17pt. Regenerate after changing the artwork or the crop:

```bash
bash scripts/make-icon.sh && bash scripts/build.sh
```

## Configuration

`~/Library/Application Support/dev.herdr.topbar/config.json`:

```json
{
  "herdrBinary": "/opt/homebrew/bin/herdr",
  "terminalBundleId": "com.apple.Terminal",
  "blinkTimeoutSeconds": 180
}
```

`blinkTimeoutSeconds` mirrors the Blink Duration menu; `0` means "until
clicked". Editing it here works too, but the app reads it at launch, so restart
with `scripts/restart-bar.sh` after a manual edit.

`terminalBundleId` is only used to *launch* a new herdr. Bringing an existing one
to the front works by finding whatever terminal actually hosts the herdr process,
so switching terminals needs no configuration.

## How it works

```
you       ──left click──▶  HerdrBar ──process tree──▶ Terminal.activate()
you       ──right click─▶  HerdrBar ──JSON/unix────▶ herdr.sock
Finder    ──right click─▶  herdrbar-open ──────────▶ HerdrBar
herdr     ──[[events]]──▶  forward-event.sh ───────▶ HerdrBar  (icon blink)
```

Two design notes worth knowing:

**Fronting the terminal uses no permissions.** Driving Terminal with AppleScript
would trigger a TCC automation prompt that can later be revoked, silently
breaking the icon's main job. Instead HerdrBar finds the `herdr` client process,
walks its parent chain to the GUI app that owns it, and calls
`NSRunningApplication.activate()`. No prompt, and it works with any terminal.

**Waiting agents come from a plugin hook, not a socket subscription.**
`pane.agent_status_changed` requires a concrete `pane_id` under
`events.subscribe`, so there is no global form — but herdr's plugin hook
allowlist accepts it, which makes `[[events]]` the way to watch every pane at
once. Full state is re-derived from `session.snapshot` whenever the menu opens,
so nothing goes stale if the app was not running when an event fired.

## Troubleshooting

```bash
# What can the app see?
~/Applications/HerdrBar.app/Contents/MacOS/HerdrBar --diagnose

# Live state as JSON
~/Applications/HerdrBar.app/Contents/MacOS/herdrbar-open --status

# Did the hooks fire?
herdr plugin log list
```

To exercise the blink without waiting for a real agent, make herdr emit a
genuine status event against any pane:

```bash
herdr pane report-agent <PANE_ID> --source selftest --agent claude --state blocked
herdr pane report-agent <PANE_ID> --source selftest --agent claude --state idle
herdr pane release-agent <PANE_ID> --source selftest --agent claude
```

Use this rather than calling `scripts/forward-event.sh` with a hand-written
payload: herdr wraps event data in an `{"event":…,"data":{…}}` envelope, so a
flat hand-made payload tests a shape herdr never sends. Note also that
`herdr plugin log list` reporting `exit 0` does not prove delivery —
`forward-event.sh` always exits 0 so a hook can never stall herdr — check
`--status` instead.

`--diagnose` prints the resolved herdr binary, whether the server is up, which
terminal is hosting it, the open workspaces, and any waiting agents. If
"host terminal: none" shows up while herdr is clearly running, herdr is running
without an attached client — start one and it will resolve.

## Requirements

macOS 13 or later, herdr 0.8.0 or later, and the Swift compiler that ships with
Xcode or the Command Line Tools (for `scripts/build.sh`).

## License

MIT — see [LICENSE](LICENSE).

The licence covers the source code. It does not cover herdr's name or its ram
logo: `Resources/ram.svg` belongs to herdr and is included only to identify the
tool this plugin extends.
