# ADR-0010: Authentication default and trust boundary

- Status: Accepted
- Date: 2026-08-20

## Context

wayvnc authentication (RSA-AES or TLS with username/password) needs key material and,
for PAM, privileges to read `/etc/shadow`. Running the capture service as the desktop
user with `NoNewPrivileges=true` cannot satisfy PAM. The original prototype advertised
PAM auth that would not actually function under those constraints.

## Decision

For v1, the trust boundary is the network. wayvnc binds to loopback only and ships with
VNC-layer auth disabled by default (`ENABLE_VNC_AUTH=0`). Operators are directed to
place `:6080` behind a VPN/LAN or a TLS-terminating, authenticating reverse proxy.
Opt-in wayvnc username/password auth (`ENABLE_VNC_AUTH=1`) with generated TLS material
is planned and tracked on the roadmap.

## Consequences

Positive: honest, working defaults; no false security claims; loopback VNC limits
exposure.
Negative: direct exposure without a proxy is insecure and must be avoided; full VNC-layer
auth is deferred to a follow-up.
