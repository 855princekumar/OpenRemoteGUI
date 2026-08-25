# ADR-0002: Target Wayland rather than X11

- Status: Accepted
- Date: 2026-08-20

## Context

Raspberry Pi OS Bookworm defaults to a Wayland session (labwc/Wayfire), and modern
Debian desktops increasingly default to Wayland. Screen capture differs fundamentally
between X11 and Wayland.

## Decision

OpenRemoteGUI targets wlroots-based Wayland sessions and captures them with wayvnc.
X11-only environments are out of scope for v1.

## Consequences

Positive: aligns with the default Pi OS Bookworm stack; no X11 scraping hacks;
works without a physical monitor.
Negative: X11-only hosts are unsupported; capture depends on a wlroots compositor
being present.
