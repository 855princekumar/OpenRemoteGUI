# Architecture Overview

OpenRemoteGUI is a four-layer stack plus a lifecycle layer:

```text
Browser ─HTTP/WS:6080─▶ noVNC (client) ─▶ websockify (bridge) ─▶ wayvnc 127.0.0.1:5900 ─▶ Wayland ─▶ Desktop
```

| Layer | Component | Runs as | Bound to |
| --- | --- | --- | --- |
| Client | noVNC (static web) | served by gateway | `:6080` |
| Bridge | websockify (venv) | gateway user | `:6080` ⇄ `127.0.0.1:5900` |
| Capture | wayvnc | desktop user | `127.0.0.1:5900` |
| Session | Wayland compositor | desktop user | local |
| Lifecycle | installer / rollback / watchdog | root | manifest, systemd |

Directories:

- `/opt/openremotegui` — noVNC checkout, venv, runtime scripts (isolated install root).
- `/etc/openremotegui` — configuration (`openremotegui.conf`, `wayvnc.conf`).
- `/var/lib/openremotegui` — manifest, logs, backups (audit + rollback state).

See the ADRs in `../adr/` for the reasoning behind each choice.
