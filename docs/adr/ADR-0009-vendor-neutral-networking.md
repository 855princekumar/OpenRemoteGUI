# ADR-0009: Vendor-neutral networking (bring your own VPN)

- Status: Accepted
- Date: 2026-08-20

## Context

Vendor remote-access services impose accounts, cloud dependencies, and lock-in. The
project's core promise is SSH + VPN + OpenRemoteGUI with nothing proprietary.

## Decision

OpenRemoteGUI does not bundle or require any specific VPN or cloud. It exposes `:6080`
locally and expects operators to reach it over their own LAN, WireGuard/Tailscale, or a
reverse proxy. No outbound control plane is used.

## Consequences

Positive: no lock-in; offline-capable; complements existing SSH/VPN fleet tooling.
Negative: the operator owns network security and reachability (documented explicitly).
