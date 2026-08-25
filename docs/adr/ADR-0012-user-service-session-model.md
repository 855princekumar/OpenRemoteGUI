# ADR-0012: Run capture as systemd user services with linger

- Status: Accepted
- Date: 2026-08-24
- Refines: ADR-0006 (systemd) for the wayvnc/gateway units

## Context

An early prototype used system services ordered around the system `graphical.target`.
Two defects surfaced on real hardware:

1. An ordering cycle: a unit that is both `WantedBy=graphical.target` and
   `After=graphical.target` forms a self-cycle that systemd breaks by deleting jobs,
   disturbing boot ("Found ordering cycle on graphical.target").
2. A system service running as the desktop user does not reliably share that user's live
   Wayland session/D-Bus context, creating a boot race for socket availability.

## Decision

Run `openremotegui-wayvnc`, `openremotegui-novnc`, and the watchdog as systemd **user**
services for the desktop user, installed under `/etc/systemd/user/` and enabled with
`loginctl enable-linger` so they start at boot. Ordering uses the user
`graphical-session.target`, never the system `graphical.target`, which removes the cycle.
The wayvnc launcher additionally waits for the Wayland socket to appear (bounded by
`WAYLAND_WAIT_SECS`) and pre-flights the VNC port, so boot races and port clashes fail
cleanly and self-heal via `Restart=always` and the watchdog.

## Consequences

Positive: correct session attachment; no ordering cycle; clean boot; auto-start after any
reboot; the watchdog restarts siblings with `systemctl --user`.
Negative: install/rollback must operate in the user's systemd context (handled via a
`run_user` helper); logs are viewed with `journalctl --user` rather than the system journal.
