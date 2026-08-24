#!/bin/bash
# herdr [[events]] hook -> HerdrBar.
#
# herdr injects HERDR_PLUGIN_EVENT and HERDR_PLUGIN_EVENT_JSON; the compiled
# helper reads them and writes one line to HerdrBar's socket.
#
# This must never fail or block: a hook runs inside herdr's event loop, and a
# stalled hook would stall the server. The helper exits 0 unconditionally, and
# the `|| true` covers the case where HerdrBar has not been built yet.
APP="${HERDR_TOPBAR_APP:-$HOME/Applications/HerdrBar.app}"
HELPER="$APP/Contents/MacOS/herdrbar-open"

[ -x "$HELPER" ] || exit 0
"$HELPER" --event || true
exit 0
