#!/usr/bin/env bash
# OpenRemoteGUI - self-healing watchdog (runs as a systemd USER service).
# Restarts ONLY OpenRemoteGUI's own user units and never touches unrelated
# services. A missing Wayland session is treated as a wait condition, not an
# error to fight, so headless nodes are not hammered.
set -uo pipefail

CONF="${ORGUI_ETC:-/etc/openremotegui}/openremotegui.conf"
# shellcheck disable=SC1090
[[ -r "$CONF" ]] && source "$CONF"

: "${HTTP_PORT:=6080}"
: "${VNC_HOST:=127.0.0.1}"
: "${VNC_PORT:=5900}"

TAG="openremotegui-watchdog"
logmsg() { logger -t "$TAG" -- "$*" 2>/dev/null || echo "$TAG: $*"; }
port_open() { timeout 2 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null; }

runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
wayland_present() {
  [[ -d "$runtime" ]] || return 1
  find "$runtime" -maxdepth 1 -type s -name 'wayland-*' 2>/dev/null | grep -q .
}

restart_user_unit() {
  logmsg "restarting $1"
  systemctl --user restart "$1" 2>/dev/null || logmsg "failed to restart $1"
  sleep 3
}

# VNC layer: only act when a desktop session actually exists.
if ! wayland_present; then
  logmsg "no active Wayland session; skipping VNC restart this cycle"
else
  if ! systemctl --user is-active --quiet openremotegui-wayvnc.service \
     || ! port_open "$VNC_HOST" "$VNC_PORT"; then
    restart_user_unit openremotegui-wayvnc.service
  fi
fi

# Gateway layer.
if ! systemctl --user is-active --quiet openremotegui-novnc.service \
   || ! port_open 127.0.0.1 "$HTTP_PORT"; then
  restart_user_unit openremotegui-novnc.service
fi

exit 0
