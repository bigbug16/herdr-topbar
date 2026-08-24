#!/bin/bash
# Plugin action: show HerdrBar's folder picker.
#
# Lets the picker be bound to a herdr key, e.g. in config.toml:
#   [[keys.command]]
#   key = "prefix+o"
#   type = "plugin_action"
#   command = "herdr-topbar.open-picker"
set -euo pipefail
APP="${HERDR_TOPBAR_APP:-$HOME/Applications/HerdrBar.app}"
HELPER="$APP/Contents/MacOS/herdrbar-open"

if [ ! -x "$HELPER" ]; then
    echo "HerdrBar is not built yet. Run scripts/build.sh first." >&2
    exit 1
fi

exec "$HELPER" --picker
