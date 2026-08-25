# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-08-24

Initial public release. Validated on Raspberry Pi 4 (Bookworm, labwc/Wayland) with
Raspberry Pi Connect present. Other boards are covered by the fleet-pilot checklist.

### Core

- One-command installer with OS/architecture/hardware detection and a safe Wayland gate
  (a desktop environment is never installed).
- Browser desktop via noVNC + websockify on `:6080`, bridging to a loopback-only wayvnc.
- Manifest-driven `rollback.sh`: restores backed-up originals, removes only what was
  created, and removes only packages that were absent before install.
- Self-healing watchdog that restarts only OpenRemoteGUI units and backs off on headless
  nodes.
- Private virtualenv for websockify; isolated install tree under `/opt/openremotegui`.

### Reliability on Raspberry Pi

- **Raspberry Pi Connect coexistence**: detects rpi-connect and stops its wayvnc at the
  service level (the `rpi-connect vnc off` CLI is also attempted but fails when the daemon
  is not signed in), freeing the VNC port. Restored on rollback. Its wayvnc otherwise holds
  `*:5900` with RSA-AES-only auth (VNC security type 262), which is incompatible with noVNC
  over plain HTTP.
- **VNC port pre-flight**: the installer and the wayvnc launcher check the port first and
  auto-select a free one, so a busy port fails cleanly instead of segfaulting wayvnc.
- **systemd user services with linger**: wayvnc, the gateway, and the watchdog run as user
  services ordered on the user `graphical-session.target`, avoiding any system
  `graphical.target` ordering cycle and attaching wayvnc to the real desktop session.
- **Boot-race tolerance**: the wayvnc launcher waits for the Wayland socket and self-heals
  via `Restart=always` and the watchdog, so the desktop returns after any reboot.

### Versioning & lifecycle

- On-node commands `openremotegui-rollback`, `openremotegui-restore`, and
  `openremotegui-install`, so a node is managed without the original clone.
- Restore points: rollback archives the version it removes, and install seeds a baseline
  and archives the previous version on upgrade (one folder per version), so you can move
  between versions and reinstall whichever is stable.
- Interactive version selection when archived versions exist (fleet-safe: never prompts on
  non-TTY runs or with `ORGUI_NO_PROMPT`).

### Documentation & tooling

- Enterprise README with badges, SVG infographics, ten Mermaid diagrams (each explained),
  and a hardware matrix.
- Twelve Architecture Decision Records; SECURITY / CONTRIBUTING / CODE_OF_CONDUCT.
- CI (ShellCheck + unit-template render + structure checks) and a local test harness.
- Explicit network scope: LAN/VPN only; a public-route (TLS reverse proxy) mode is future work.

[1.0.0]: https://github.com/855princekumar/OpenRemoteGUI/releases/tag/v1.0.0
