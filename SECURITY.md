# Security Policy

## Supported versions

| Version | Supported |
| --- | --- |
| 1.0.x | Yes |

## Reporting a vulnerability

Please report security issues **privately**. Do not open a public issue.

- Use GitHub Security Advisories ("Report a vulnerability") on this repository, or
- Contact the maintainer through the profile at https://github.com/855princekumar

Include: affected version, environment (hardware/OS), reproduction steps, and impact.
We aim to acknowledge within 5 business days.

## Validated network scope (v1.0.0)

This release is designed, tested, and validated **only** on trusted **LAN and VPN**
networks (for example WireGuard or Tailscale overlays). Its security guarantees are
limited to that private-network context.

- **In scope and validated:** LAN and VPN access to `http://NODE:6080`.
- **Explicitly out of scope:** direct exposure on the public internet. Do not
  port-forward `:6080` to a WAN interface with this build.
- **Planned for a future release:** a dedicated public-route mode using a **TLS reverse
  proxy** with authentication, plus documented port-forwarding for internet-facing use.
  That path is not part of v1.0.0.

## Trust model (read before deploying)

OpenRemoteGUI does **not** provide network-layer security by itself.

- Raw VNC is bound to `127.0.0.1:5900` and is never exposed to the network.
- Only the browser gateway on `:6080` is reachable, and it speaks plain HTTP.
- **The network is the trust boundary.** Deploy `:6080` behind a VPN/LAN or a
  reverse proxy that terminates TLS and enforces authentication.
- Do not expose `:6080` directly to the public internet.

By default, VNC-layer authentication is disabled (`ENABLE_VNC_AUTH=0`) because the
loopback binding plus network boundary is the intended control. See
`docs/adr/ADR-0010-authentication-default.md`.

## Hardening applied

- systemd sandboxing on both services (`ProtectSystem=strict`, `NoNewPrivileges`,
  `PrivateTmp`, restricted read/write paths, `RestrictSUIDSGID`).
- Least-privilege: the capture service runs as the desktop user, not root.
- Isolated install tree; no modification of unrelated system files.
