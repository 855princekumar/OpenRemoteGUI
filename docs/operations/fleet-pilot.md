# Fleet Pilot Checklist

Before pushing OpenRemoteGUI to a large fleet (e.g. 100 mixed Pi 3/4/5 nodes),
validate on a small pilot. End-to-end desktop capture depends on the live Wayland
session and cannot be proven in CI, so a hardware pilot is required.

> **Scope reminder:** v1.0.0 is validated for **LAN and VPN** networks only. Do not
> expose `:6080` on the public internet. A TLS reverse-proxy / public-route mode is
> planned for a future release. See `../security/threat-model.md` and `../../SECURITY.md`.

## 0. Preconditions per node

- [ ] Debian-family OS (Raspberry Pi OS Bookworm recommended).
- [ ] The node **boots into a Wayland desktop session** (labwc/Wayfire) with autologin
      for the target user. **Pi OS Lite has no desktop and will be refused by design.**
- [ ] Reachable over your LAN or VPN (WireGuard/Tailscale). Not the public internet.
- [ ] You know the desktop username (pass `ORGUI_USER=<name>` if auto-detect is wrong).

## 1. Pilot on one of each board

Run on a **Pi 3**, a **Pi 4**, and a **Pi 5**, each booted to the desktop:

```bash
git clone https://github.com/855princekumar/OpenRemoteGUI.git
cd OpenRemoteGUI
sudo ./install.sh          # or: sudo ORGUI_USER=pi ./install.sh
```

Verify on each board:

- [ ] Installer completes and prints `Health check: PASS`.
- [ ] `http://NODE-IP:6080/` shows the **real desktop**; mouse and keyboard work.
- [ ] `systemctl status openremotegui-wayvnc openremotegui-novnc` are both active.
- [ ] `systemctl list-timers | grep openremotegui` shows the watchdog scheduled.

## 2. Reboot resilience

```bash
sudo reboot
```

- [ ] After reboot, the desktop reappears at `:6080` without manual intervention.
- [ ] `/opt/openremotegui/scripts/healthcheck.sh -v` passes.

## 3. Self-healing

```bash
sudo systemctl stop openremotegui-novnc
# wait ~60s for the watchdog timer
systemctl is-active openremotegui-novnc     # expect: active (restored)
```

- [ ] Watchdog restarts the gateway on its own.
- [ ] Stopping an **unrelated** service is never touched by the watchdog.

## 4. Clean rollback

```bash
sudo ./rollback.sh
```

- [ ] Services stopped and disabled; `/opt/openremotegui` removed.
- [ ] Packages that were absent before install are removed; pre-existing ones are kept.
- [ ] The node is functionally unchanged from its pre-install state.
- [ ] `journalctl` shows no unrelated services were modified.

## 5. Fleet rollout (only after 1-4 pass on all three boards)

```bash
# Restrict the inventory to nodes that boot to a desktop.
ansible desktop_nodes -m copy -a "src=./ dest=/opt/src/OpenRemoteGUI mode=0755"
ansible desktop_nodes -b -m shell -a "cd /opt/src/OpenRemoteGUI && ORGUI_NO_PROMPT=1 ./install.sh"

# Health sweep
ansible desktop_nodes -b -m shell -a "/opt/openremotegui/scripts/healthcheck.sh -v"

# Fleet rollback if needed
ansible desktop_nodes -b -m shell -a "openremotegui-rollback"
```

## Notes for a mixed 3/4/5 fleet

- The installer auto-detects a hardware tier (Pi 3 lightweight, Pi 4 standard, Pi 5 GPU).
  Behaviour is consistent across tiers in v1.0.0; the tier is recorded for future
  encoding tuning.
- Nodes running **Pi OS Lite** will report "no Wayland compositor found" and make no
  changes. Keep them out of the `desktop_nodes` group, or provision a session first.
- Wayland session startup timing varies most between boards; the reboot test (step 2)
  is the one most likely to surface a per-board quirk. Fix it on the pilot, not on 100
  nodes.
