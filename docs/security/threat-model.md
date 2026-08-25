# Threat Model (summary)

## Assets
- The desktop session and anything reachable from it.
- Node credentials and local files.

## Trust boundary
The **network** is the boundary. Raw VNC is never on the network (loopback only);
only the gateway `:6080` is reachable and it speaks plain HTTP.

## Primary mitigations
- wayvnc bound to `127.0.0.1:5900` (ADR-0005).
- Deploy `:6080` behind VPN/LAN or a TLS-terminating, authenticating reverse proxy
  (ADR-0009, ADR-0010).
- systemd sandboxing; capture runs as the desktop user, not root.
- Manifest-driven rollback avoids collateral damage (ADR-0007).

## Explicit non-goals for v1
- OpenRemoteGUI does not provide network encryption or authentication on `:6080` by
  itself. Do not expose it directly to the internet.
- VNC-layer auth is opt-in and currently deferred (roadmap).

## Recommended hardening
- Restrict `:6080` to the VPN interface via firewall (e.g. nftables/ufw).
- Front with nginx/Caddy for TLS + basic/OAuth auth if exposure is unavoidable.
