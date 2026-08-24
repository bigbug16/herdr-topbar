#!/bin/bash
# herdr [[startup]] hook: make sure the menu bar icon is present once a herdr
# server is up.
#
# This is a convenience, not the main persistence mechanism — it only fires when
# a server starts, so it cannot cover the "herdr is closed, click the icon to
# start it" case. scripts/install-login-item.sh handles that.
APP="${HERDR_TOPBAR_APP:-$HOME/Applications/HerdrBar.app}"

[ -d "$APP" ] || exit 0
pgrep -x HerdrBar >/dev/null 2>&1 && exit 0

# -g keeps focus where it is; herdr just took over the terminal.
open -g "$APP" || true
exit 0
