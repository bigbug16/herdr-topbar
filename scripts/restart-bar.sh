#!/bin/bash
# Restart the menu bar app — used after a rebuild to pick up new code.
set -euo pipefail
APP="${HERDR_TOPBAR_APP:-$HOME/Applications/HerdrBar.app}"

if [ ! -d "$APP" ]; then
    echo "HerdrBar is not installed at $APP. Run scripts/build.sh first." >&2
    exit 1
fi

pkill -x HerdrBar >/dev/null 2>&1 || true
sleep 1
open -g "$APP"
echo "Restarted HerdrBar"
