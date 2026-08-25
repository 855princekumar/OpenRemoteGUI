#!/usr/bin/env bash
# =============================================================================
#  OpenRemoteGUI - restore
#  Lists archived restore points (created by rollback.sh) and reinstalls a
#  chosen version. Restore points are tiny (scripts only) and let you move
#  between whichever version feels stable.
#
#    ./restore.sh              # list available restore points
#    sudo ./restore.sh NAME    # reinstall the version in that restore point
# =============================================================================
set -Eeuo pipefail

RESTORE_ROOT="${ORGUI_RESTORE_ROOT:-/opt/openremotegui-restore}"

if [[ ! -d "$RESTORE_ROOT" ]]; then
  echo "No restore points found under $RESTORE_ROOT."
  echo "A restore point is created automatically when you run ./rollback.sh."
  exit 0
fi

mapfile -t POINTS < <(find "$RESTORE_ROOT" -mindepth 1 -maxdepth 1 -type d | sort)
if ((${#POINTS[@]} == 0)); then
  echo "No restore points found under $RESTORE_ROOT."
  exit 0
fi

# --- list mode ---------------------------------------------------------------
if [[ $# -eq 0 ]]; then
  echo "Available OpenRemoteGUI restore points:"
  echo
  for p in "${POINTS[@]}"; do
    ver="$(sed -n 's/^version=//p'     "$p/RESTORE-INFO.txt" 2>/dev/null)"
    at="$(sed -n 's/^archived_at=//p'  "$p/RESTORE-INFO.txt" 2>/dev/null)"
    printf '  %-32s version %-10s archived %s\n' "$(basename "$p")" "${ver:-?}" "${at:-?}"
  done
  echo
  echo "Reinstall a version with:"
  echo "  sudo ./restore.sh $(basename "${POINTS[${#POINTS[@]}-1]}")"
  exit 0
fi

# --- reinstall mode ----------------------------------------------------------
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "Run as root: sudo $0 $*"; exit 1; }

sel="$1"
target="$RESTORE_ROOT/$sel"
[[ -d "$target" ]]            || { echo "No such restore point: $sel"; echo "Run ./restore.sh with no arguments to list them."; exit 1; }
[[ -x "$target/install.sh" ]] || { echo "Restore point is missing an executable install.sh: $target"; exit 1; }

echo "Reinstalling OpenRemoteGUI from restore point: $sel"
echo "(install.sh rewrites the manifest and redeploys this version's files.)"
cd "$target"
exec ./install.sh
