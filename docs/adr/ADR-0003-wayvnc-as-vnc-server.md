# ADR-0003: Use wayvnc as the VNC server

- Status: Accepted
- Date: 2026-08-20

## Context

We need a VNC server that attaches to an existing wlroots Wayland session, works
headless, and is packaged for Debian/Raspberry Pi OS.

## Decision

Use `wayvnc`. It is purpose-built for wlroots compositors, is available via apt, and
can serve a session with no monitor attached.

## Consequences

Positive: native Wayland capture; apt-installable; low footprint.
Negative: requires a wlroots compositor; auth capabilities depend on the packaged
build (see ADR-0010).
