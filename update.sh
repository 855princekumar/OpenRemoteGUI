#!/usr/bin/env bash
# =============================================================================
#  OpenRemoteGUI - update
#  Refreshes the noVNC checkout and websockify, redeploys the runtime scripts
#  from this repo, then restarts and verifies health.
# =============================================================================
set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ORGUI_LIB="$REPO_DIR/lib/common.sh"
# shellcheck source=lib/common.sh
source "$ORGUI_LIB"

require_root
NOVNC_REF="${NOVNC_REF:-master}"

[[ -d "$ORGUI_PREFIX/noVNC/.git" ]] || die "OpenRemoteGUI is not installed."
LOG_FILE="$ORGUI_STATE/update.log"

info "Pre-update health snapshot:"
"$ORGUI_PREFIX/scripts/healthcheck.sh" -v || warn "currently degraded; continuing."

info "Updating noVNC ($NOVNC_REF)..."
git -C "$ORGUI_PREFIX/noVNC" fetch --depth 1 origin "$NOVNC_REF"
git -C "$ORGUI_PREFIX/noVNC" reset --hard "origin/$NOVNC_REF"

info "Updating websockify..."
"$ORGUI_PREFIX/venv/bin/python" -m pip install --quiet --upgrade websockify

# Redeploy runtime scripts so fixes ship without a full reinstall.
if [[ -d "$REPO_DIR/scripts" ]]; then
  info "Redeploying runtime scripts..."
  for s in wayvnc-start novnc-start healthcheck watchdog; do
    install -D -m 0755 "$REPO_DIR/scripts/$s.sh" "$ORGUI_PREFIX/scripts/$s.sh"
  done
fi

systemctl daemon-reload
systemctl restart openremotegui-wayvnc.service 2>/dev/null || true
systemctl restart openremotegui-novnc.service  2>/dev/null || true
sleep 3

if "$ORGUI_PREFIX/scripts/healthcheck.sh" -v; then
  ok "Update successful."
else
  err "Update finished but health check failed. Inspect:"
  err "  journalctl -u openremotegui-wayvnc -u openremotegui-novnc -n 100 --no-pager"
  exit 1
fi
