#!/usr/bin/env bash
# =============================================================================
#  OpenRemoteGUI - rollback
#  Manifest-driven, NOT pattern-driven. Undoes exactly what install.sh
#  recorded, restores backed-up originals, and never blanket-removes.
# =============================================================================
set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ORGUI_LIB="$REPO_DIR/lib/common.sh"
if [[ -r "$ORGUI_LIB" ]]; then
  # shellcheck source=lib/common.sh
  source "$ORGUI_LIB"
else
  # Allow rollback to run even if copied out of the repo.
  ORGUI_STATE="/var/lib/openremotegui"
  ORGUI_BACKUP="$ORGUI_STATE/backups"
  ORGUI_MANIFEST="$ORGUI_STATE/install-manifest"
  ORGUI_PREFIX="/opt/openremotegui"
  RESTORE_ROOT="${ORGUI_RESTORE_ROOT:-/opt/openremotegui-restore}"
  log()  { printf '[%s] %s\n' "$(date -Is)" "$*"; }
  ok()   { printf '[%s]  OK  %s\n' "$(date -Is)" "$*"; }
  warn() { printf '[%s] WARN %s\n' "$(date -Is)" "$*"; }
  err()  { printf '[%s] FAIL %s\n' "$(date -Is)" "$*" >&2; }
  die()  { err "$@"; exit 1; }
  require_root() { [[ $EUID -eq 0 ]] || die "Run as root: sudo $0"; }
  manifest_values() { awk -F'|' -v k="$1" '$1==k{print $2}' "$ORGUI_MANIFEST"; }
fi

# Restore points live OUTSIDE the delete boundary (/opt/openremotegui) so they
# survive rollback and can be reinstalled later. The archival helper lives in
# lib/common.sh; if rollback was copied out on its own we skip archiving.
save_restore_point() {
  local ver
  ver="$(manifest_values META 2>/dev/null | sed -n 's/^VERSION=//p' | head -1)"
  [[ -n "$ver" ]] || ver="unknown"
  if ! declare -F archive_restore_point >/dev/null; then
    warn "restore-point helper unavailable (rollback detached from repo); skipping."
    return 0
  fi
  # One folder per version: only archive if this version isn't already saved.
  if restore_point_exists_for "$ver"; then
    log "restore point for v$ver already exists; not duplicating."
    return 0
  fi
  # Prefer the on-node deployed source; fall back to the repo we run from.
  local src="$ORGUI_PREFIX/.self"
  [[ -f "$src/install.sh" ]] || src="$REPO_DIR"
  archive_restore_point "$src" "$ver" "$ORGUI_MANIFEST"
  if [[ -n "$ORGUI_LAST_RESTORE_POINT" ]]; then
    ok "Restore point saved: $ORGUI_LAST_RESTORE_POINT"
    log "Reinstall this version later with: sudo ./restore.sh $(basename "$ORGUI_LAST_RESTORE_POINT")"
  fi
}

require_root
[[ -f "$ORGUI_MANIFEST" ]] || die "No install manifest at $ORGUI_MANIFEST; nothing to roll back."

LOG_FILE="$ORGUI_STATE/rollback.log"
log "Starting OpenRemoteGUI rollback."

# 0) Archive a restore point BEFORE removing anything, so the version being
#    rolled back can be reinstalled later even if removal is interrupted.
save_restore_point

# 1) Stop & disable USER units we enabled, then any legacy system units.
DUSER="$(manifest_values META 2>/dev/null | sed -n 's/^DESKTOP_USER=//p' | head -1)"
DUID="$(manifest_values META 2>/dev/null | sed -n 's/^DESKTOP_UID=//p' | head -1)"
if [[ -n "$DUSER" && -n "$DUID" ]] && declare -F run_user >/dev/null; then
  while IFS= read -r unit; do
    [[ -n "$unit" ]] || continue
    log "disabling (user) $unit"
    run_user "$DUSER" "$DUID" -- systemctl --user disable --now "$unit" 2>/dev/null || true
  done < <(manifest_values ENABLED_USER | sort -u)
  run_user "$DUSER" "$DUID" -- systemctl --user stop openremotegui-watchdog.service 2>/dev/null || true
  run_user "$DUSER" "$DUID" -- systemctl --user daemon-reload 2>/dev/null || true
fi
# Legacy (system) units, if a 1.0.0 install is being rolled back.
while IFS= read -r unit; do
  [[ -n "$unit" ]] || continue
  log "disabling $unit"
  systemctl disable --now "$unit" 2>/dev/null || true
done < <(manifest_values ENABLED | sort -u)
systemctl daemon-reload || true

# 1b) Restore Raspberry Pi Connect screen sharing if we disabled it.
if manifest_values META 2>/dev/null | grep -q '^RPI_CONNECT_VNC=disabled-by-orgui'; then
  if [[ -n "$DUSER" && -n "$DUID" ]] && declare -F run_user >/dev/null; then
    log "re-enabling Raspberry Pi Connect screen sharing"
    while IFS= read -r rpiunit; do
      [[ -n "$rpiunit" ]] || continue
      run_user "$DUSER" "$DUID" -- systemctl --user enable --now "$rpiunit" 2>/dev/null || true
      log "re-enabled $rpiunit"
    done < <(manifest_values META 2>/dev/null | sed -n 's/^RPI_UNIT_DISABLED=//p' | sort -u)
    run_user "$DUSER" "$DUID" -- rpi-connect vnc on 2>/dev/null || true
  fi
fi

# 1c) Drop linger if we enabled it.
while IFS= read -r luser; do
  [[ -n "$luser" ]] || continue
  log "disabling linger for $luser"
  loginctl disable-linger "$luser" 2>/dev/null || true
done < <(manifest_values LINGER | sort -u)

# 2) Compute the set of paths that had a backup (restore beats delete).
declare -A HAD_BACKUP=()
while IFS= read -r p; do [[ -n "$p" ]] && HAD_BACKUP["$p"]=1; done < <(manifest_values BACKUP)

# 3) Restore originals we backed up.
for path in "${!HAD_BACKUP[@]}"; do
  src="$ORGUI_BACKUP/${path#/}"
  if [[ -e "$src" ]]; then
    mkdir -p "$(dirname "$path")"
    rm -rf "$path"
    cp -a "$src" "$path"
    log "restored $path"
  fi
done

# 4) Remove files we created, unless a backup restored them above.
while IFS= read -r path; do
  [[ -n "$path" ]] || continue
  [[ -n "${HAD_BACKUP[$path]:-}" ]] && continue
  if [[ -e "$path" ]]; then
    rm -f "$path" 2>/dev/null || true
    log "removed file $path"
  fi
done < <(manifest_values FILE)

# 5) Remove directories we created, deepest first, inside the safe boundary.
while IFS= read -r d; do
  [[ -n "$d" ]] || continue
  case "$d" in
    "$ORGUI_PREFIX"|"$ORGUI_PREFIX"/*)
      rm -rf "$d" 2>/dev/null || true
      log "removed directory $d" ;;
    *)
      warn "skipping directory outside safe boundary: $d" ;;
  esac
done < <(manifest_values DIR | awk '{print length, $0}' | sort -rn | cut -d' ' -f2-)

# 5b) Belt-and-suspenders: the entire install tree (incl. /opt/openremotegui/.self)
#     is owned by OpenRemoteGUI by design, so remove it wholesale. This is inside
#     the safe boundary; restore points live elsewhere and are untouched.
if [[ -d "$ORGUI_PREFIX" ]]; then
  rm -rf "$ORGUI_PREFIX" 2>/dev/null || true
  log "removed install tree $ORGUI_PREFIX"
fi

# 5c) Remove the /usr/local/bin command symlinks we created (recorded as FILE,
#     but ensure they are gone even if the manifest was partial).
for verb in install rollback restore; do
  link="/usr/local/bin/openremotegui-$verb"
  [[ -L "$link" || -f "$link" ]] && { rm -f "$link" 2>/dev/null || true; log "removed $link"; }
done

# 6) Remove ONLY packages we installed (that were absent before).
mapfile -t PKGS < <(manifest_values PACKAGE | sort -u)
if ((${#PKGS[@]})); then
  log "removing packages installed by OpenRemoteGUI: ${PKGS[*]}"
  export DEBIAN_FRONTEND=noninteractive
  apt-get remove -y -qq "${PKGS[@]}" 2>/dev/null || true
  apt-get autoremove -y -qq 2>/dev/null || true
fi

systemctl daemon-reload || true

log "Rollback complete."
log "State retained at $ORGUI_STATE for audit."
if [[ -d "$RESTORE_ROOT" ]]; then
  log "Restore points kept under $RESTORE_ROOT (use ./restore.sh to list/reinstall)."
fi
log "To fully purge this version (after verifying the node):"
log "  sudo rm -rf $ORGUI_STATE $ORGUI_PREFIX"
log "Restore points are NOT removed by that command; delete them separately if desired."
