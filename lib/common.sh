#!/usr/bin/env bash
# OpenRemoteGUI - shared shell library
# Sourced by install.sh, rollback.sh, update.sh and the runtime scripts.
# This file must be POSIX-bash and safe to source more than once.

# ---------------------------------------------------------------------------
# Canonical paths (single source of truth for the whole project)
# ---------------------------------------------------------------------------
: "${ORGUI_PROJECT:=OpenRemoteGUI}"
: "${ORGUI_PREFIX:=/opt/openremotegui}"      # isolated install root
: "${ORGUI_ETC:=/etc/openremotegui}"         # configuration
: "${ORGUI_STATE:=/var/lib/openremotegui}"   # manifest, logs, backups
: "${ORGUI_SYSTEMD:=/etc/systemd/system}"    # unit files
: "${ORGUI_BACKUP:=${ORGUI_STATE}/backups}"
: "${ORGUI_MANIFEST:=${ORGUI_STATE}/install-manifest}"

# ---------------------------------------------------------------------------
# Colour handling (auto-disabled when not a TTY or NO_COLOR is set)
# ---------------------------------------------------------------------------
# shellcheck disable=SC2034  # C_BOLD and colours are consumed by sourcing scripts
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'; C_BOLD=$'\033[1m'
else
  C_RESET=''; C_DIM=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_BOLD=''
fi

# ---------------------------------------------------------------------------
# Logging helpers. LOG_FILE, if set, receives an un-coloured copy.
# ---------------------------------------------------------------------------
_ts() { date -Is; }

_emit() {
  # $1 = colour, $2 = level, $3.. = message
  local colour="$1" level="$2"; shift 2
  local line; line="[$(_ts)] [${level}] $*"
  printf '%s%s%s\n' "$colour" "$line" "$C_RESET"
  if [[ -n "${LOG_FILE:-}" ]]; then printf '%s\n' "$line" >>"$LOG_FILE" 2>/dev/null || true; fi
}

log()  { _emit "$C_DIM"    "INFO" "$@"; }
info() { _emit "$C_BLUE"   "INFO" "$@"; }
ok()   { _emit "$C_GREEN"  " OK " "$@"; }
warn() { _emit "$C_YELLOW" "WARN" "$@"; }
err()  { _emit "$C_RED"    "FAIL" "$@" >&2; }
die()  { err "$@"; exit 1; }

# ---------------------------------------------------------------------------
# Guards
# ---------------------------------------------------------------------------
require_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "This command must be run as root. Try: sudo $0"
}

have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# Manifest primitives. The manifest is the single source of truth used by
# rollback. Every mutating action MUST be recorded here.
#   META|key=value            informational
#   PACKAGE|name              apt package installed by us (was absent before)
#   FILE|/abs/path            file we created
#   DIR|/abs/path             directory we created
#   BACKUP|/abs/path          original file we backed up before overwriting
#   ENABLED|unit              systemd unit we enabled
# ---------------------------------------------------------------------------
record() {
  # record KIND VALUE
  printf '%s|%s\n' "$1" "$2" >>"$ORGUI_MANIFEST"
}

manifest_values() {
  # manifest_values KIND -> prints values of that kind, one per line
  [[ -f "$ORGUI_MANIFEST" ]] || return 0
  awk -F'|' -v k="$1" '$1==k{print $2}' "$ORGUI_MANIFEST"
}

# ---------------------------------------------------------------------------
# Port / health primitives (bash /dev/tcp, no external nc dependency)
# ---------------------------------------------------------------------------
port_open() {
  # port_open HOST PORT
  timeout 2 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null
}

http_ok() {
  # http_ok URL  -> succeeds on any HTTP response (even redirects)
  have curl || return 0
  curl -fsS -m 4 -o /dev/null "$1" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Misc
# ---------------------------------------------------------------------------
primary_ip() { hostname -I 2>/dev/null | awk '{print $1}'; }

# Run a command inside a desktop user's systemd/D-Bus session context.
# Usage: run_user <user> <uid> -- cmd args...
run_user() {
  local u="$1" uid="$2"; shift 2
  [[ "${1:-}" == "--" ]] && shift
  sudo -u "$u" \
    XDG_RUNTIME_DIR="/run/user/$uid" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
    "$@"
}

# True if a TCP port already has a listener (any local address).
port_in_use() {
  # port_in_use PORT
  if have ss; then
    ss -ltnH 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${1}\$"
  else
    timeout 2 bash -c "exec 3<>/dev/tcp/127.0.0.1/$1" 2>/dev/null
  fi
}

# Echo the first free port at/after START.
first_free_port() {
  local p="$1"
  while port_in_use "$p"; do p=$((p+1)); done
  printf '%s' "$p"
}

primary_ip_note() { :; }  # placeholder kept for API stability

# ---------------------------------------------------------------------------
# Restore points. Small (scripts-only) snapshots of a version's deployable
# source, kept OUTSIDE the install tree so they survive rollback. One folder
# per version (guarded), tagged with a timestamp.
# ---------------------------------------------------------------------------
: "${ORGUI_RESTORE_ROOT:=/opt/openremotegui-restore}"
RESTORE_ROOT="$ORGUI_RESTORE_ROOT"
# shellcheck disable=SC2034  # set here, consumed by install.sh / rollback.sh
ORGUI_LAST_RESTORE_POINT=""

restore_point_exists_for() {
  # restore_point_exists_for VERSION
  compgen -G "$RESTORE_ROOT/v${1}-*" >/dev/null 2>&1
}

archive_restore_point() {
  # archive_restore_point SRC_DIR VERSION [MANIFEST]
  # Copies the deployable source from SRC_DIR into a new restore point.
  local src="$1" ver="${2:-unknown}" man="${3:-}"
  ORGUI_LAST_RESTORE_POINT=""
  if [[ ! -f "$src/install.sh" || ! -d "$src/scripts" || ! -d "$src/systemd" ]]; then
    warn "restore point skipped: incomplete source at $src"
    return 0
  fi
  local ts dest item
  ts="$(date +%Y%m%d-%H%M%S)"
  dest="$RESTORE_ROOT/v${ver}-${ts}"
  mkdir -p "$dest"
  for item in install.sh rollback.sh update.sh restore.sh VERSION lib scripts systemd config; do
    [[ -e "$src/$item" ]] && cp -a "$src/$item" "$dest/"
  done
  [[ -n "$man" && -f "$man" ]] && cp -a "$man" "$dest/install-manifest.snapshot"
  {
    echo "version=$ver"
    echo "archived_at=$(date -Is)"
    echo "hostname=$(hostname 2>/dev/null || echo unknown)"
    echo "source=$src"
  } >"$dest/RESTORE-INFO.txt"
  chmod +x "$dest"/*.sh 2>/dev/null || true
  chmod +x "$dest"/scripts/*.sh 2>/dev/null || true
  # shellcheck disable=SC2034  # consumed by callers in install.sh / rollback.sh
  ORGUI_LAST_RESTORE_POINT="$dest"
}

# End of library.
