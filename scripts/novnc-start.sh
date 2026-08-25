#!/usr/bin/env bash
# OpenRemoteGUI - browser gateway launcher.
# Serves the noVNC web client and bridges WebSocket -> VNC using the
# websockify installed in the project's private virtualenv.
#
# NOTE: We deliberately use the venv's `websockify` entrypoint rather than
# noVNC's bundled utils/websockify submodule, because a shallow clone of
# noVNC does not fetch that submodule. This was a defect in the original
# prototype and is fixed here.
set -Eeuo pipefail

CONF="${ORGUI_ETC:-/etc/openremotegui}/openremotegui.conf"
# shellcheck disable=SC1090
[[ -r "$CONF" ]] && source "$CONF"

: "${HTTP_PORT:=6080}"
: "${VNC_HOST:=127.0.0.1}"
: "${VNC_PORT:=5900}"
: "${NOVNC_DIR:=/opt/openremotegui/noVNC}"
: "${NOVNC_VENV:=/opt/openremotegui/venv}"

WEBSOCKIFY="$NOVNC_VENV/bin/websockify"
[[ -x "$WEBSOCKIFY" ]] || { echo "novnc-start: websockify not found at $WEBSOCKIFY" >&2; exit 1; }
[[ -f "$NOVNC_DIR/vnc.html" ]] || { echo "novnc-start: noVNC web root missing at $NOVNC_DIR" >&2; exit 1; }

# --web serves the static noVNC client; positional args bind the listener
# and the upstream VNC target. Root (/) is redirected to /vnc.html by the
# static index we ship, so operators land straight on the console.
exec "$WEBSOCKIFY" \
  --web "$NOVNC_DIR" \
  --heartbeat 30 \
  "${HTTP_PORT}" \
  "${VNC_HOST}:${VNC_PORT}"
