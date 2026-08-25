#!/usr/bin/env bash
# OpenRemoteGUI - wayvnc launcher (runs as a systemd USER service).
# Attaches wayvnc to the running wlroots/Wayland session, bound to loopback.
# Waits for the Wayland socket (absorbs boot races) and pre-flights the VNC
# port so a busy port fails cleanly instead of segfaulting wayvnc.
set -Eeuo pipefail

CONF="${ORGUI_ETC:-/etc/openremotegui}/openremotegui.conf"
# shellcheck disable=SC1090
[[ -r "$CONF" ]] && source "$CONF"

: "${VNC_HOST:=127.0.0.1}"
: "${VNC_PORT:=5900}"
: "${WAYVNC_CONF:=/etc/openremotegui/wayvnc.conf}"
: "${WAYLAND_WAIT_SECS:=60}"

uid_now="$(id -u)"
runtime="${XDG_RUNTIME_DIR:-/run/user/$uid_now}"
[[ -d "$runtime" ]] || { echo "wayvnc-start: no runtime dir $runtime" >&2; exit 1; }

# Wait for a live Wayland socket to appear (desktop session may lag boot).
disp=""
for ((i = 0; i < WAYLAND_WAIT_SECS; i++)); do
  disp="${WAYLAND_DISPLAY:-}"
  if [[ -z "$disp" || ! -S "$runtime/$disp" ]]; then
    disp="$(find "$runtime" -maxdepth 1 -type s -name 'wayland-*' \
      -printf '%f\n' 2>/dev/null | sort | head -n1 || true)"
  fi
  [[ -n "$disp" && -S "$runtime/$disp" ]] && break
  sleep 1
done
if [[ -z "$disp" || ! -S "$runtime/$disp" ]]; then
  echo "wayvnc-start: no Wayland socket under $runtime after ${WAYLAND_WAIT_SECS}s" >&2
  exit 1
fi

export XDG_RUNTIME_DIR="$runtime"
export WAYLAND_DISPLAY="$disp"

# Pre-flight the target port. wayvnc segfaults on a failed bind, so refuse
# cleanly if something (e.g. rpi-connect's wayvnc) still holds it.
if timeout 2 bash -c "exec 3<>/dev/tcp/${VNC_HOST}/${VNC_PORT}" 2>/dev/null; then
  echo "wayvnc-start: ${VNC_HOST}:${VNC_PORT} already in use; another VNC server running?" >&2
  echo "wayvnc-start: on Raspberry Pi Connect nodes run 'rpi-connect vnc off' or reinstall." >&2
  exit 1
fi

exec /usr/bin/wayvnc --config "$WAYVNC_CONF" --render-cursor "$VNC_HOST" "$VNC_PORT"
