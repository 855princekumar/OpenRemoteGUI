# ADR-0006: Manage services with systemd

- Status: Accepted
- Date: 2026-08-20

## Context

Services must start at boot, restart on failure, run under the correct user/session,
and be observable. The target platforms use systemd.

## Decision

Ship three units: a wayvnc service (runs as the desktop user, bound to the graphical
target), a gateway service (runs as the gateway user), and a watchdog oneshot driven by
a timer. Units apply standard hardening (`ProtectSystem=strict`, `NoNewPrivileges`,
`PrivateTmp`, restricted read/write paths).

## Consequences

Positive: boot integration, restart policy, journald logs, sandboxing.
Negative: systemd-only; unit templates need per-host substitution at install time.
