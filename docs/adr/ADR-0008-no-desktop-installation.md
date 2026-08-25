# ADR-0008: Never install a desktop environment

- Status: Accepted
- Date: 2026-08-20

## Context

Pushing a remote-GUI installer across a fleet must never turn a headless production
node into a full desktop machine.

## Decision

The installer captures an existing session only. If no live Wayland socket and no known
compositor are found, it makes no changes and exits with guidance (overridable with
`ORGUI_FORCE=1`). Hardware tier (Pi Zero/3 lightweight, Pi 4 standard, Pi 5 GPU) tunes
behaviour but never provisions a desktop.

## Consequences

Positive: safe fleet rollout; predictable footprint.
Negative: users on genuinely headless hosts must provide a session themselves.
