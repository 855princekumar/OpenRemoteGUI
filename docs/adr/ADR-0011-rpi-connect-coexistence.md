# ADR-0011: Coexistence with Raspberry Pi Connect

- Status: Accepted
- Date: 2026-08-24
- Refines: ADR-0003 (wayvnc) for rpi-connect environments

## Context

On Raspberry Pi OS Bookworm, Raspberry Pi Connect runs its own `wayvnc` bound to
`*:5900`. Two problems follow for OpenRemoteGUI:

1. Our wayvnc cannot bind `5900` (the port is taken); the packaged wayvnc then
   segfaults on the failed bind, so our capture never starts.
2. rpi-connect's wayvnc offers only the RSA-AES security type (VNC security type 262),
   which requires WebCrypto. noVNC served over plain HTTP has no secure context, so the
   browser cannot complete that handshake ("Unsupported security types (types: 262)").

Reusing rpi-connect's wayvnc is therefore incompatible with a plain-HTTP browser client,
and also reintroduces the vendor dependency the project exists to avoid.

## Decision

At install time, if `rpi-connect` is present, OpenRemoteGUI turns off its screen sharing
(`rpi-connect vnc off`) to free the port, and records this so rollback re-enables it
(`rpi-connect vnc on`). The rest of rpi-connect and the raspi-config VNC toggle are left
untouched. The installer then pre-flights the VNC port and, if it is still occupied,
selects the next free port automatically. Our own wayvnc runs with `enable_auth=false`
(security type "None"), which noVNC over HTTP supports.

## Consequences

Positive: works out of the box on nodes that ship rpi-connect; stays vendor-neutral; no
segfault on port clash; rollback restores the previous state.
Negative: rpi-connect's own remote screen sharing is disabled while OpenRemoteGUI is
installed (by design); security continues to rely on the network boundary (ADR-0010).
