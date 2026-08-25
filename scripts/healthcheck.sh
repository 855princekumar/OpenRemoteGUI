#!/usr/bin/env bash
# OpenRemoteGUI - health check (USER services). Exit 0 = healthy.
set -uo pipefail

CONF="${ORGUI_ETC:-/etc/openremotegui}/openremotegui.conf"
# shellcheck disable=SC1090
[[ -r "$CONF" ]] && source "$CONF"

: "${HTTP_PORT:=6080}"
: "${VNC_HOST:=127.0.0.1}"
: "${VNC_PORT:=5900}"

VERBOSE=0
[[ "${1:-}" == "-v" ]] && VERBOSE=1
fail=0
report() { [[ $VERBOSE -eq 1 ]] && printf '%-34s %s\n' "$1" "$2"; }
port_open() { timeout 2 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null; }

check_user_unit() {
  if systemctl --user is-active --quiet "$1"; then report "$1" "active"
  else report "$1" "INACTIVE"; fail=1; fi
}
check_port() {
  if port_open "$1" "$2"; then report "port $1:$2" "open"
  else report "port $1:$2" "CLOSED"; fail=1; fi
}
check_http() {
  command -v curl >/dev/null 2>&1 || return 0
  if curl -fsS -m 4 -o /dev/null "http://127.0.0.1:${HTTP_PORT}/vnc.html"; then
    report "http gateway" "responding"
  else report "http gateway" "NO RESPONSE"; fail=1; fi
}

check_user_unit "openremotegui-wayvnc.service"
check_user_unit "openremotegui-novnc.service"
check_port "$VNC_HOST" "$VNC_PORT"
check_port "127.0.0.1" "$HTTP_PORT"
check_http
exit "$fail"
