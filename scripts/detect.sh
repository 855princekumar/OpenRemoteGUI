#!/usr/bin/env bash
# OpenRemoteGUI - detection routines.
# Populates global variables and (when run directly) prints a report.
# Sets: ORGUI_OS, ORGUI_ARCH, ORGUI_MODEL, ORGUI_TIER,
#       ORGUI_DESKTOP_USER, ORGUI_DESKTOP_UID, ORGUI_DESKTOP_HOME,
#       ORGUI_WAYLAND_DISPLAY (may be empty if no live session yet)
set -Eeuo pipefail

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${ORGUI_LIB:-$_here/../lib/common.sh}"

detect_os() {
  [[ -r /etc/os-release ]] || die "/etc/os-release not found; unsupported system."
  # Read os-release in subshells so it does not clobber caller variables such
  # as VERSION (which /etc/os-release also defines).
  local pretty id like
  pretty="$(. /etc/os-release && printf '%s' "${PRETTY_NAME:-${NAME:-unknown}}")"
  id="$(. /etc/os-release && printf '%s' "${ID:-}")"
  like="$(. /etc/os-release && printf '%s' "${ID_LIKE:-}")"
  ORGUI_OS="$pretty"
  case "$id $like" in
    *debian*|*raspbian*|*ubuntu*) : ;;
    *) die "OpenRemoteGUI targets Debian-family systems. Detected: ${ORGUI_OS}" ;;
  esac
  have systemctl || die "systemd is required."
  have apt-get   || die "apt (apt-get) is required."
}

detect_arch() {
  ORGUI_ARCH="$(uname -m)"
}

detect_hardware() {
  if [[ -r /proc/device-tree/model ]]; then
    ORGUI_MODEL="$(tr -d '\0' </proc/device-tree/model)"
  elif [[ -r /sys/firmware/devicetree/base/model ]]; then
    ORGUI_MODEL="$(tr -d '\0' </sys/firmware/devicetree/base/model)"
  else
    ORGUI_MODEL="Generic Debian ($ORGUI_ARCH)"
  fi

  # Performance tier drives wayvnc encoding defaults (see ADR-0008).
  case "$ORGUI_MODEL" in
    *"Pi Zero"*|*"Pi 3"*|*"Compute Module 3"*) ORGUI_TIER="lightweight" ;;
    *"Pi 4"*|*"Compute Module 4"*)             ORGUI_TIER="standard" ;;
    *"Pi 5"*|*"Compute Module 5"*)             ORGUI_TIER="gpu" ;;
    *)                                          ORGUI_TIER="standard" ;;
  esac
}

detect_desktop_user() {
  # Explicit override always wins.
  ORGUI_DESKTOP_USER="${ORGUI_USER:-}"

  if [[ -z "$ORGUI_DESKTOP_USER" ]] && have loginctl; then
    # Prefer a user with an active graphical session.
    local uid user
    while IFS= read -r uid; do
      user="$(getent passwd "$uid" | cut -d: -f1)"
      [[ -n "$user" ]] || continue
      if loginctl show-user "$user" -p State --value 2>/dev/null | grep -qx active; then
        ORGUI_DESKTOP_USER="$user"; break
      fi
    done < <(getent passwd | awk -F: '$3>=1000 && $3<60000 {print $3}')
  fi

  # Fall back to the first regular login account.
  if [[ -z "$ORGUI_DESKTOP_USER" ]]; then
    ORGUI_DESKTOP_USER="$(getent passwd \
      | awk -F: '$3>=1000 && $3<60000 && $1!="nobody"{print $1; exit}')"
  fi

  [[ -n "$ORGUI_DESKTOP_USER" ]] \
    || die "No regular desktop user found. Re-run with ORGUI_USER=<name>."

  ORGUI_DESKTOP_UID="$(id -u "$ORGUI_DESKTOP_USER")"
  # shellcheck disable=SC2034  # consumed by install.sh render_template
  ORGUI_DESKTOP_HOME="$(getent passwd "$ORGUI_DESKTOP_USER" | cut -d: -f6)"
}

detect_wayland() {
  ORGUI_WAYLAND_DISPLAY=""
  local rt="/run/user/${ORGUI_DESKTOP_UID:-}"
  [[ -d "$rt" ]] || return 0
  ORGUI_WAYLAND_DISPLAY="$(find "$rt" -maxdepth 1 -type s -name 'wayland-*' \
    -printf '%f\n' 2>/dev/null | sort | head -n1 || true)"
}

detect_all() {
  detect_os
  detect_arch
  detect_hardware
  detect_desktop_user
  detect_wayland
}

detect_report() {
  detect_all
  printf '%s\n' "OS            : ${ORGUI_OS}"
  printf '%s\n' "Architecture  : ${ORGUI_ARCH}"
  printf '%s\n' "Hardware      : ${ORGUI_MODEL}"
  printf '%s\n' "Tier          : ${ORGUI_TIER}"
  printf '%s\n' "Desktop user  : ${ORGUI_DESKTOP_USER} (UID ${ORGUI_DESKTOP_UID})"
  if [[ -n "$ORGUI_WAYLAND_DISPLAY" ]]; then
    printf '%s\n' "Wayland       : ${ORGUI_WAYLAND_DISPLAY} (live)"
  else
    printf '%s\n' "Wayland       : none live now (discovered at runtime)"
  fi
}

# Allow running standalone: scripts/detect.sh
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  detect_report
fi
