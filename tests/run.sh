#!/usr/bin/env bash
# OpenRemoteGUI - local test harness.
# Runs without root or Pi hardware. Validates syntax, linting, template
# rendering, and a simulated manifest -> rollback plan. CI runs this too.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

pass=0; fail=0
ok()   { printf '  [PASS] %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  [FAIL] %s\n' "$1"; fail=$((fail+1)); }

echo "== 1. bash syntax =="
for f in install.sh rollback.sh update.sh restore.sh scripts/*.sh lib/common.sh; do
  if bash -n "$f" 2>/dev/null; then ok "syntax $f"; else bad "syntax $f"; fi
done

echo "== 2. shellcheck (if available) =="
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -x -e SC1091 install.sh rollback.sh update.sh restore.sh scripts/*.sh lib/common.sh; then
    ok "shellcheck clean"
  else
    bad "shellcheck findings"
  fi
else
  echo "  [SKIP] shellcheck not installed"
fi

echo "== 3. systemd templates render with no leftover tokens =="
for f in systemd/*.in; do
  out="$(sed -e 's|@OWNER@|acme|g' -e 's|@PREFIX@|/opt/openremotegui|g' -e 's|@ETC@|/etc/openremotegui|g' "$f")"
  if grep -q '@' <<<"$out"; then bad "unsubstituted token in $f"
  elif ! grep -q '^\[Unit\]' <<<"$out"; then bad "no [Unit] in $f"
  else ok "render $f"; fi
done

echo "== 3b. no system graphical.target ordering cycle (1.0.0 regression) =="
if grep -hE '^(After|Wants|WantedBy|Requires|BindsTo|PartOf|Before)=' systemd/*.in | grep -Fq 'graphical.target'; then
  bad "a unit directive references the system graphical.target (cycle risk)"
else
  ok "unit directives avoid system graphical.target (use user targets)"
fi
if grep -q 'WantedBy=default.target' systemd/openremotegui-wayvnc.service.in; then
  ok "wayvnc is a user service (WantedBy=default.target)"
else
  bad "wayvnc unit is not a user-service target"
fi

echo "== 4. required files present =="
for req in install.sh rollback.sh update.sh restore.sh VERSION LICENSE README.md \
           SECURITY.md CONTRIBUTING.md CODE_OF_CONDUCT.md CHANGELOG.md \
           config/openremotegui.conf.example; do
  if [[ -f "$req" ]]; then ok "exists $req"; else bad "missing $req"; fi
done
if [[ -d docs/adr ]] && (( $(find docs/adr -name 'ADR-*.md' | wc -l) >= 10 )); then
  ok "ADRs present (>=10)"
else
  bad "ADRs missing"
fi

echo "== 5. simulated manifest -> rollback plan (dry run) =="
TMP="$(mktemp -d)"
MAN="$TMP/install-manifest"
cat >"$MAN" <<'EOF'
META|VERSION=1.0.0
PACKAGE|wayvnc
DIR|/opt/openremotegui/noVNC
FILE|/etc/openremotegui/openremotegui.conf
BACKUP|/etc/systemd/system/openremotegui-watchdog.timer
ENABLED|openremotegui-wayvnc.service
EOF
plan_pkgs="$(awk -F'|' '$1=="PACKAGE"{print $2}' "$MAN" | tr '\n' ' ')"
plan_units="$(awk -F'|' '$1=="ENABLED"{print $2}' "$MAN" | tr '\n' ' ')"
plan_dirs="$(awk -F'|' '$1=="DIR"{print $2}' "$MAN" | tr '\n' ' ')"
if [[ "$plan_pkgs" == "wayvnc " && "$plan_units" == *wayvnc* && "$plan_dirs" == *"/opt/openremotegui/noVNC"* ]]; then
  ok "manifest parses into a correct rollback plan"
else
  bad "manifest parse mismatch"
fi
# Ensure the safe boundary would reject an out-of-tree dir.
outside="/etc/passwd"
case "$outside" in
  /opt/openremotegui|/opt/openremotegui/*) bad "boundary allowed $outside" ;;
  *) ok "boundary rejects out-of-tree path" ;;
esac
rm -rf "$TMP"

echo "== 5b. restore-point naming & boundary safety =="
# Restore root must sit OUTSIDE the rollback delete boundary so it survives.
rp="/opt/openremotegui-restore/v1.0.0-20260820-120000"
case "$rp" in
  /opt/openremotegui|/opt/openremotegui/*) bad "restore path inside delete boundary!" ;;
  *) ok "restore root is outside the /opt/openremotegui delete boundary" ;;
esac
if grep -q 'save_restore_point' rollback.sh && grep -q 'RESTORE_ROOT' rollback.sh; then
  ok "rollback.sh archives a restore point"
else
  bad "rollback.sh missing restore-point logic"
fi

echo "== 5c. on-node deploy + fleet-safe prompt guard =="
if grep -q 'deploy_self' install.sh && grep -q '/usr/local/bin/openremotegui-' install.sh; then
  ok "install.sh deploys management commands"
else
  bad "install.sh missing deploy_self / command symlinks"
fi
if grep -q 'archive_previous' install.sh && grep -q 'seed_current' install.sh; then
  ok "install.sh archives previous + seeds baseline restore point"
else
  bad "install.sh missing archive_previous / seed_current"
fi
# The version-selection prompt MUST be gated on a TTY so fleet runs never hang.
if grep -Eq '\-t 0.*ORGUI_NO_PROMPT|ORGUI_NO_PROMPT.*-t 0' install.sh; then
  ok "version prompt is TTY-gated (fleet-safe)"
else
  bad "version prompt not properly TTY-gated"
fi
if declare -F >/dev/null 2>&1 && grep -q 'restore_point_exists_for' lib/common.sh && grep -q 'archive_restore_point' lib/common.sh; then
  ok "shared restore-point helpers present in lib/common.sh"
else
  bad "shared restore-point helpers missing"
fi

echo "== 5d. Pi reliability (rpi-connect, port preflight, user services) =="
chk() { if eval "$1"; then ok "$2"; else bad "$3"; fi; }
chk "grep -q handle_rpi_connect install.sh && grep -q 'rpi-connect vnc off' install.sh" \
    "install disables rpi-connect VNC to free the port" "rpi-connect handling missing"
chk "grep -q choose_vnc_port install.sh && grep -q first_free_port lib/common.sh" \
    "install pre-flights and auto-selects a free VNC port" "port pre-flight missing"
chk "grep -q /etc/systemd/user install.sh && grep -q 'systemctl --user' install.sh" \
    "services deployed and enabled as systemd --user units" "user-service deployment missing"
chk "grep -q enable-linger install.sh" \
    "install enables linger for boot start" "linger not enabled"
chk "grep -q 'systemctl --user' scripts/watchdog.sh && grep -q 'systemctl --user' scripts/healthcheck.sh" \
    "watchdog + healthcheck use --user context" "watchdog/healthcheck not user-context"
chk "grep -q 'already in use' scripts/wayvnc-start.sh && grep -q WAYLAND_WAIT_SECS scripts/wayvnc-start.sh" \
    "wayvnc launcher waits for socket + pre-flights port (no segfault)" "wayvnc launcher missing socket-wait/port-preflight"
chk "grep -q '\. /etc/os-release && printf' scripts/detect.sh" \
    "detect_os reads os-release in a subshell (does not clobber VERSION)" "detect_os may clobber VERSION"

echo "== 6. README sanity =="
if grep -q '```mermaid' README.md && grep -q '## Architecture Decision Records' README.md; then
  ok "README has mermaid + ADR index"
else
  bad "README missing mermaid or ADR index"
fi

echo
echo "Summary: $pass passed, $fail failed."
[[ $fail -eq 0 ]]
