# ADR-0004: Use noVNC + websockify as the browser client

- Status: Accepted
- Date: 2026-08-20

## Context

The goal is browser access with no native client install. VNC over WebSocket needs a
web client and a WebSocket-to-TCP bridge.

## Decision

Serve the official noVNC client and bridge WebSocket to VNC with websockify. websockify
is installed into a private virtualenv under `/opt/openremotegui/venv` rather than the
noVNC git submodule.

## Consequences

Positive: zero client install; official, widely used components; isolated Python env.
Negative: an extra local proxy hop; websockify must be kept updated (handled by
`update.sh`).

## Note

The original prototype invoked `noVNC/utils/websockify/run`, which does not exist after
a shallow clone (the submodule is not fetched). Using the venv entrypoint fixes this.
