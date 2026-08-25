#!/usr/bin/env bash
# =============================================================================
#  OpenRemoteGUI - installer
#  Vendor-neutral browser-based remote GUI for Debian and Raspberry Pi.
#
#  Behaviour:
#   - Detects and disables Raspberry Pi Connect's VNC (its RSA-AES-only wayvnc
#     holds the port and is incompatible with noVNC over plain HTTP).
#   - Pre-flights the VNC port and auto-selects a free one (never segfaults on a clash).
#   - Runs wayvnc / noVNC / watchdog as systemd USER services with linger, so
#     wayvnc attaches to the real Wayland session with a clean, cycle-free boot.
# =============================================================================
set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ORGUI_LIB="$REPO_DIR/lib/common.sh"
# shellcheck source=lib/common.sh
source "$ORGUI_LIB"
# shellcheck source=scripts/detect.sh
source "$REPO_DIR/scripts/detect.sh"

VERSION="$(cat "$REPO_DIR/VERSION" 2>/dev/null || echo 0.0.0)"
OWNER="${ORGUI_OWNER:-855princekumar}"
NOVNC_REPO="${NOVNC_REPO:-https://github.com/novnc/noVNC.git}"
NOVNC_REF="${NOVNC_REF:-master}"
AUTO_ROLLBACK="${ORGUI_AUTO_ROLLBACK:-1}"
SELF_DIR="$ORGUI_PREFIX/.self"
USER_SYSTEMD="/etc/systemd/user"
VNC_PORT_START="${ORGUI_VNC_PORT:-5900}"
HTTP_PORT="${ORGUI_HTTP_PORT:-6080}"
VNC_PORT="$VNC_PORT_START"   # finalised in choose_vnc_port

mkdir -p "$ORGUI_STATE" "$ORGUI_BACKUP" "$ORGUI_ETC" "$ORGUI_PREFIX"
LOG_FILE="$ORGUI_STATE/install.log"; : >"$LOG_FILE"

on_error() {
  local line=$1
  err "Installation failed at line ${line}. See $LOG_FILE"
  if [[ "$AUTO_ROLLBACK" == "1" && -s "$ORGUI_MANIFEST" ]]; then
    warn "Auto-rollback enabled; reverting changes made so far..."
    bash "$REPO_DIR/rollback.sh" || err "Auto-rollback had problems; inspect $ORGUI_STATE"
  fi
  exit 1
}
trap 'on_error $LINENO' ERR

banner() {
  printf '%s\n' "${C_BOLD}================================================${C_RESET}"
  printf '%s\n' "${C_BOLD} ${ORGUI_PROJECT} ${VERSION}${C_RESET}"
  printf '%s\n' "${C_BOLD} Vendor-neutral browser remote GUI${C_RESET}"
  printf '%s\n' "${C_BOLD}================================================${C_RESET}"
}

render_template() {
  local src="$1" dst="$2" tmp; tmp="$(mktemp)"
  sed \
    -e "s|@OWNER@|${OWNER}|g" \
    -e "s|@PREFIX@|${ORGUI_PREFIX}|g" \
    -e "s|@ETC@|${ORGUI_ETC}|g" \
    "$src" >"$tmp"
  install -D -m 0644 "$tmp" "$dst"; rm -f "$tmp"; record FILE "$dst"
}
install_exec() { install -D -m 0755 "$1" "$2"; record FILE "$2"; }
backup_file() {
  local f="$1"; [[ -e "$f" ]] || return 0
  local dst="$ORGUI_BACKUP/${f#/}"; mkdir -p "$(dirname "$dst")"; cp -a "$f" "$dst"; record BACKUP "$f"
}
ensure_dir() { [[ -d "$1" ]] || { mkdir -p "$1"; record DIR "$1"; }; }

# --- steps -------------------------------------------------------------------
gate_wayland() {
  detect_all
  info "OS            : $ORGUI_OS"
  info "Architecture  : $ORGUI_ARCH"
  info "Hardware      : $ORGUI_MODEL (tier: $ORGUI_TIER)"
  info "Desktop user  : $ORGUI_DESKTOP_USER (UID $ORGUI_DESKTOP_UID)"
  local compositor=""
  for c in labwc wayfire sway weston kwin_wayland gnome-shell; do
    have "$c" && { compositor="$c"; break; }
  done
  if [[ -n "$ORGUI_WAYLAND_DISPLAY" ]]; then
    ok "Wayland       : live session ($ORGUI_WAYLAND_DISPLAY)"
  elif [[ -n "$compositor" ]]; then
    warn "Wayland       : no live socket now, but '$compositor' is installed"
  else
    err "No Wayland compositor found and no live session."
    err "OpenRemoteGUI needs an existing Wayland desktop; it will not install one."
    [[ "${ORGUI_FORCE:-0}" == "1" ]] || exit 2
  fi
}

# Raspberry Pi Connect ships a wayvnc that binds the VNC port with RSA-AES-only
# auth, incompatible with noVNC over plain HTTP. Free the port. The CLI
# ('rpi-connect vnc off') only works when signed in, so we ALSO stop/disable its
# wayvnc user unit directly. All actions are recorded for rollback.
handle_rpi_connect() {
  local u="$ORGUI_DESKTOP_USER" uid="$ORGUI_DESKTOP_UID"
  have rpi-connect || { log "rpi-connect not present."; return 0; }
  info "Raspberry Pi Connect detected; freeing the VNC port (CLI + service level)."

  # Best-effort CLI (needs a live, signed-in daemon).
  run_user "$u" "$uid" -- rpi-connect vnc off >/dev/null 2>&1 || true

  # Service-level: stop/disable any rpi-connect wayvnc user unit. This is the
  # reliable path when the CLI cannot reach the daemon.
  local unit found=0
  while IFS= read -r unit; do
    [[ -n "$unit" ]] || continue
    run_user "$u" "$uid" -- systemctl --user disable --now "$unit" >/dev/null 2>&1 || true
    record META "RPI_UNIT_DISABLED=$unit"
    ok "Stopped rpi-connect unit: $unit"; found=1
  done < <(run_user "$u" "$uid" -- systemctl --user list-unit-files --no-legend 2>/dev/null \
             | awk '{print $1}' | grep -Ei 'rpi-connect.*wayvnc|wayvnc.*rpi-connect' || true)

  # Fallback to the well-known unit name if discovery found nothing.
  if [[ "$found" -eq 0 ]]; then
    if run_user "$u" "$uid" -- systemctl --user disable --now rpi-connect-wayvnc.service >/dev/null 2>&1; then
      record META "RPI_UNIT_DISABLED=rpi-connect-wayvnc.service"
      ok "Stopped rpi-connect unit: rpi-connect-wayvnc.service"
    fi
  fi

  record META "RPI_CONNECT_VNC=disabled-by-orgui"
  sleep 2
  if port_in_use "$VNC_PORT_START"; then
    warn "Port $VNC_PORT_START still busy after disabling rpi-connect; will select a free port."
  else
    ok "VNC port $VNC_PORT_START is now free."
  fi
}

choose_vnc_port() {
  VNC_PORT="$(first_free_port "$VNC_PORT_START")"
  if [[ "$VNC_PORT" == "$VNC_PORT_START" ]]; then
    ok "VNC port      : $VNC_PORT (loopback)"
  else
    warn "VNC port      : $VNC_PORT_START busy; using $VNC_PORT instead (loopback)"
  fi
}

install_deps() {
  export DEBIAN_FRONTEND=noninteractive
  info "Updating package lists..."
  apt-get update -qq
  local base=(git python3 python3-venv python3-pip ca-certificates curl openssl)
  have wayvnc || base+=(wayvnc)
  local p
  for p in "${base[@]}"; do
    if dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'install ok installed'; then
      log "dependency present: $p"
    else
      info "installing: $p"; apt-get install -y -qq "$p"; record PACKAGE "$p"
    fi
  done
}

deploy_novnc() {
  ensure_dir "$ORGUI_PREFIX"
  if [[ -f "$ORGUI_PREFIX/noVNC/vnc.html" ]]; then
    log "noVNC already present."
  else
    info "Cloning noVNC ($NOVNC_REF)..."
    git clone --depth 1 --branch "$NOVNC_REF" "$NOVNC_REPO" "$ORGUI_PREFIX/noVNC"
    record DIR "$ORGUI_PREFIX/noVNC"
  fi
  [[ -f "$ORGUI_PREFIX/noVNC/vnc.html" ]] || die "noVNC checkout incomplete."
  if [[ -x "$ORGUI_PREFIX/venv/bin/python" ]]; then
    log "virtualenv present."
  else
    info "Creating private virtualenv for websockify..."
    python3 -m venv "$ORGUI_PREFIX/venv"; record DIR "$ORGUI_PREFIX/venv"
  fi
  "$ORGUI_PREFIX/venv/bin/python" -m pip install --quiet --upgrade pip
  "$ORGUI_PREFIX/venv/bin/python" -m pip install --quiet --upgrade websockify
  [[ -x "$ORGUI_PREFIX/venv/bin/websockify" ]] || die "websockify install failed."
  install -D -m 0644 /dev/stdin "$ORGUI_PREFIX/noVNC/index.html" <<'HTML'
<!doctype html><meta http-equiv="refresh" content="0;url=vnc.html"><title>OpenRemoteGUI</title>
HTML
  record FILE "$ORGUI_PREFIX/noVNC/index.html"
}

write_config() {
  local conf="$ORGUI_ETC/openremotegui.conf"
  backup_file "$conf"
  install -D -m 0644 /dev/stdin "$conf" <<EOF
# OpenRemoteGUI configuration (managed). Generated $(date -Is).
HTTP_PORT=$HTTP_PORT
VNC_HOST=127.0.0.1
VNC_PORT=$VNC_PORT
WAYVNC_USER=$ORGUI_DESKTOP_USER
WAYVNC_UID=$ORGUI_DESKTOP_UID
NOVNC_DIR=$ORGUI_PREFIX/noVNC
NOVNC_VENV=$ORGUI_PREFIX/venv
ENABLE_VNC_AUTH=0
EOF
  record FILE "$conf"

  local wconf="$ORGUI_ETC/wayvnc.conf"
  backup_file "$wconf"
  # Auth disabled -> wayvnc offers security type "None", which noVNC over plain
  # HTTP supports. The trust boundary is the network (VPN/LAN). See ADR-0010.
  install -D -m 0644 /dev/stdin "$wconf" <<'EOF'
# OpenRemoteGUI wayvnc configuration
enable_auth=false
EOF
  record FILE "$wconf"
}

deploy_scripts() {
  ensure_dir "$ORGUI_PREFIX/scripts"
  local s
  for s in wayvnc-start novnc-start healthcheck watchdog; do
    install_exec "$REPO_DIR/scripts/$s.sh" "$ORGUI_PREFIX/scripts/$s.sh"
  done
}

deploy_self() {
  ensure_dir "$SELF_DIR"
  local item
  for item in install.sh rollback.sh update.sh restore.sh VERSION lib scripts systemd config; do
    [[ -e "$REPO_DIR/$item" ]] && cp -a "$REPO_DIR/$item" "$SELF_DIR/"
  done
  record FILE "$SELF_DIR/install.sh"; record FILE "$SELF_DIR/rollback.sh"; record FILE "$SELF_DIR/restore.sh"
  chmod +x "$SELF_DIR"/*.sh 2>/dev/null || true
  chmod +x "$SELF_DIR"/scripts/*.sh 2>/dev/null || true
  local verb link
  for verb in install rollback restore; do
    link="/usr/local/bin/openremotegui-$verb"
    ln -sf "$SELF_DIR/$verb.sh" "$link"; record FILE "$link"
  done
  ok "Management commands installed: openremotegui-rollback, openremotegui-restore"
}

deploy_units() {
  ensure_dir "$USER_SYSTEMD"
  render_template "$REPO_DIR/systemd/openremotegui-wayvnc.service.in"   "$USER_SYSTEMD/openremotegui-wayvnc.service"
  render_template "$REPO_DIR/systemd/openremotegui-novnc.service.in"    "$USER_SYSTEMD/openremotegui-novnc.service"
  render_template "$REPO_DIR/systemd/openremotegui-watchdog.service.in" "$USER_SYSTEMD/openremotegui-watchdog.service"
  install -D -m 0644 "$REPO_DIR/systemd/openremotegui-watchdog.timer" "$USER_SYSTEMD/openremotegui-watchdog.timer"
  record FILE "$USER_SYSTEMD/openremotegui-watchdog.timer"
}

enable_services() {
  local u="$ORGUI_DESKTOP_USER" uid="$ORGUI_DESKTOP_UID"
  # Make sure the user manager and /run/user/<uid> exist even before login.
  systemctl start "user@${uid}.service" 2>/dev/null || true
  loginctl enable-linger "$u" 2>/dev/null || true
  record LINGER "$u"

  run_user "$u" "$uid" -- systemctl --user daemon-reload 2>/dev/null || true
  local unit
  for unit in openremotegui-wayvnc.service openremotegui-novnc.service openremotegui-watchdog.timer; do
    run_user "$u" "$uid" -- systemctl --user enable --now "$unit" 2>/dev/null || \
      run_user "$u" "$uid" -- systemctl --user enable "$unit" 2>/dev/null || true
    record ENABLED_USER "$unit"
  done
}

summary() {
  local ip; ip="$(primary_ip)"
  printf '\n'
  ok "$ORGUI_PROJECT $VERSION installation complete."
  printf '%s\n' "----------------------------------------------"
  printf '  %-14s %s\n' "Node"     "${ORGUI_MODEL}"
  printf '  %-14s %s\n' "User"     "${ORGUI_DESKTOP_USER}"
  printf '  %-14s %s\n' "VNC port" "127.0.0.1:${VNC_PORT} (loopback)"
  printf '  %-14s %s\n' "LAN URL"  "http://${ip:-<node-ip>}:${HTTP_PORT}/"
  printf '  %-14s %s\n' "VPN URL"  "http://<vpn-ip>:${HTTP_PORT}/"
  printf '  %-14s %s\n' "Rollback" "sudo openremotegui-rollback"
  printf '  %-14s %s\n' "Versions" "sudo openremotegui-restore"
  printf '  %-14s %s\n' "Logs"     "journalctl --user -u openremotegui-wayvnc -u openremotegui-novnc"
  printf '  %-14s %s\n' "Log file" "$LOG_FILE"
  printf '%s\n' "----------------------------------------------"
  sleep 2
  if run_user "$ORGUI_DESKTOP_USER" "$ORGUI_DESKTOP_UID" -- "$ORGUI_PREFIX/scripts/healthcheck.sh" -v; then
    ok "Health check: PASS"
  else
    warn "Health check: NOT READY (commonly: desktop session not logged in yet)."
    warn "It will self-heal once the Wayland session is active; check after login/reboot:"
    warn "  systemctl --user status openremotegui-wayvnc openremotegui-novnc"
  fi
}

# --- version-management helpers (unchanged behaviour) ------------------------
archive_previous() {
  [[ -f "$SELF_DIR/install.sh" && -f "$ORGUI_MANIFEST" ]] || return 0
  local prev; prev="$(manifest_values META 2>/dev/null | sed -n 's/^VERSION=//p' | head -1)"
  [[ -n "$prev" ]] || return 0
  restore_point_exists_for "$prev" && { log "previous version v$prev already archived."; return 0; }
  archive_restore_point "$SELF_DIR" "$prev" "$ORGUI_MANIFEST"
  [[ -n "$ORGUI_LAST_RESTORE_POINT" ]] && ok "Previous version v$prev archived: $ORGUI_LAST_RESTORE_POINT"
}
seed_current() {
  restore_point_exists_for "$VERSION" && return 0
  archive_restore_point "$SELF_DIR" "$VERSION" "$ORGUI_MANIFEST"
  [[ -n "$ORGUI_LAST_RESTORE_POINT" ]] && log "Baseline restore point created: $ORGUI_LAST_RESTORE_POINT"
}
offer_version_choice() {
  [[ -t 0 && -z "${ORGUI_NO_PROMPT:-}" && -z "${ORGUI_ASSUME_YES:-}" ]] || return 0
  [[ -d "$RESTORE_ROOT" ]] || return 0
  local pts=(); mapfile -t pts < <(find "$RESTORE_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
  ((${#pts[@]})) || return 0
  echo; info "Previously archived version(s) found on this node:"
  local i=1 p ver at
  for p in "${pts[@]}"; do
    ver="$(sed -n 's/^version=//p' "$p/RESTORE-INFO.txt" 2>/dev/null)"
    at="$(sed -n 's/^archived_at=//p' "$p/RESTORE-INFO.txt" 2>/dev/null)"
    printf '   %d) %s   (version %s, %s)\n' "$i" "$(basename "$p")" "${ver:-?}" "${at:-?}"; i=$((i+1))
  done
  printf '   0) install this cloned version (%s) [default]\n' "$VERSION"; echo
  local choice=""; read -r -p "Select a version to install [0-${#pts[@]}]: " choice || choice=0
  [[ -z "$choice" ]] && choice=0
  if [[ "$choice" == "0" ]]; then return 0
  elif [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#pts[@]} )); then
    info "Installing selected version from ${pts[choice-1]}"
    ORGUI_NO_PROMPT=1 exec "${pts[choice-1]}/install.sh"
  fi
  warn "Unrecognized choice '$choice'; continuing with cloned version $VERSION."
}

# --- main --------------------------------------------------------------------
main() {
  require_root
  banner
  offer_version_choice
  archive_previous

  : >"$ORGUI_MANIFEST"
  record META "VERSION=$VERSION"
  record META "OWNER=$OWNER"
  record META "INSTALLED_AT=$(date -Is)"

  gate_wayland
  record META "DESKTOP_USER=$ORGUI_DESKTOP_USER"
  record META "DESKTOP_UID=$ORGUI_DESKTOP_UID"
  record META "PREFIX=$ORGUI_PREFIX"

  handle_rpi_connect
  choose_vnc_port
  record META "VNC_PORT=$VNC_PORT"

  install_deps
  deploy_novnc
  write_config
  deploy_scripts
  deploy_self
  deploy_units
  enable_services
  seed_current
  summary
}

main "$@"
