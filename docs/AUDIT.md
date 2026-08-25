# OpenRemoteGUI - Architecture & Code Audit

Date: 2026-08-20
Scope: the initial `openremotegui-1_0_0.zip` prototype (install/rollback/update +
one timer + thin README), reviewed before the first public release.
Method: manual review, `bash -n`, ShellCheck 0.9.0, control-flow tracing of the
runtime path (systemd unit → runtime script → dependency), and a simulated
manifest/rollback dry run.

## Verdict

The prototype's design was sound (loopback VNC, isolated tree, manifest-driven
rollback) but the **runtime would not actually work as shipped**. Two defects broke
the core service path, and one security claim could not function under the unit's own
constraints. All are fixed in this release; the design intent is preserved.

## Findings

| ID | Severity | Component | Finding | Status |
| --- | --- | --- | --- | --- |
| F-1 | Critical | gateway | `novnc-start.sh` execs `noVNC/utils/websockify/run`, absent after `git clone --depth 1` (submodule not fetched). `:6080` never comes up. | Fixed |
| F-2 | Critical | watchdog | `openremotegui-watchdog.service` runs `$PREFIX/scripts/watchdog.sh`, but the installer never creates that file. The timer fails every cycle. | Fixed |
| F-3 | High | auth | wayvnc configured for `enable_pam=true` while the unit runs as the desktop user with `NoNewPrivileges=true`; PAM cannot read `/etc/shadow`, so login is broken while the docs claim PAM auth. | Fixed (honest default + ADR-0010) |
| F-4 | Medium | maintainability | All runtime scripts embedded as heredocs inside `install.sh`, so ShellCheck/`bash -n` cannot lint them and they cannot be tested in isolation. | Fixed (real files) |
| F-5 | Low | systemd | `StartLimitIntervalSec=` placed in `[Service]`; modern systemd expects it in `[Unit]`. | Fixed |
| F-6 | Low | rollback | `grep ... && x=1 \|\| true` read/write pattern flagged by ShellCheck (SC2094/SC2015); brittle backup-detection. | Fixed (associative-array plan) |
| F-7 | Low | packaging | ZIP shipped without the service unit files, config, runtime scripts, docs, ADRs, CI, or community health files referenced by the design. | Fixed (complete repo) |

## Remediation summary

- **F-1**: the gateway now uses the private virtualenv entrypoint
  `"$NOVNC_VENV/bin/websockify"` and pre-flights both it and the noVNC web root.
- **F-2**: `scripts/watchdog.sh` is a real, shipped, deployed file; it restarts only
  project-owned units and backs off when no Wayland session exists.
- **F-3**: default is loopback-only VNC with `enable_auth=false` and the network as the
  documented trust boundary; a working opt-in auth path is on the roadmap (ADR-0010).
- **F-4**: runtime scripts live under `scripts/` and are linted by ShellCheck in CI; the
  installer copies them into `/opt/openremotegui/scripts`.
- **F-5 / F-6**: unit templates and rollback rewritten; ShellCheck is clean at
  `warning` and above (SC1091 info excepted for dynamic sources).
- **F-7**: full repository with units, config, docs, 10 ADRs, CI, issue/PR templates,
  and a test harness.

## Architecture review

Strengths retained:

- **Single responsibility per layer** — capture (wayvnc), bridge (websockify), client
  (noVNC), lifecycle (installer/rollback/watchdog).
- **Loopback VNC + single gateway port** minimises attack surface (ADR-0005).
- **Manifest-driven rollback** is precise and reversible; it restores backups, deletes
  only what it created, removes only packages that were absent, and enforces a path
  boundary of `/opt/openremotegui` (ADR-0007).
- **Fail-safe on headless nodes** — no desktop is ever installed (ADR-0008).

Improvements added:

- Auto-rollback if `install.sh` fails partway (a partial install self-reverts).
- Hardened systemd units (`ProtectSystem=strict`, `PrivateTmp`, restricted paths).
- Hardware-tier detection wired through detection for future encoding tuning.
- CI that lints scripts, renders unit templates, and runs a manifest/rollback dry run.

## Residual risks / caveats

- End-to-end capture cannot be verified in CI; it requires a real wlroots session.
  Validate on one clean Pi 3, Pi 4, Pi 5, and Pi Zero 2 W before a fleet rollout, since
  Wayland session startup varies most across those boards.
- Plain HTTP on `:6080` must sit behind a VPN/LAN or a TLS-terminating reverse proxy.
- VNC-layer authentication is deferred (see ADR-0010); do not expose `:6080` publicly.
