# ADR-0005: Bind VNC to localhost; expose only the gateway

- Status: Accepted
- Date: 2026-08-20

## Context

Raw VNC on the network is a large, unauthenticated attack surface. We still want simple
browser access.

## Decision

wayvnc binds to `127.0.0.1:5900`. Only the browser gateway (`websockify`) listens on
`:6080`. Raw VNC is never bound to a routable address.

## Consequences

Positive: one browser-facing port; reduced exposure; easy firewall/VPN integration.
Negative: browser access depends on the local gateway; one extra proxy layer.
