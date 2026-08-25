# Operations Runbook

## Install
```bash
sudo ./install.sh              # auto-detect desktop user
sudo ORGUI_USER=pi ./install.sh
```

## Status & logs
```bash
systemctl --user status openremotegui-wayvnc openremotegui-novnc
systemctl list-timers | grep openremotegui
journalctl --user -u openremotegui-wayvnc -u openremotegui-novnc -n 100 --no-pager
/opt/openremotegui/scripts/healthcheck.sh -v
```

## Update
```bash
sudo ./update.sh
```

## Rollback
```bash
sudo ./rollback.sh
# state is retained for audit; after verifying:
sudo rm -rf /var/lib/openremotegui /opt/openremotegui
```

## Common recoveries
- Gateway down: `sudo systemctl --user restart openremotegui-novnc`
- Capture down: ensure a Wayland session is active, then
  `sudo systemctl --user restart openremotegui-wayvnc`
- Wrong user captured: rollback, then reinstall with `ORGUI_USER=<name>`.

## Fleet (Ansible)
```bash
ansible all -m copy -a "src=./ dest=/opt/src/OpenRemoteGUI mode=0755"
ansible all -b -m shell -a "cd /opt/src/OpenRemoteGUI && ORGUI_NO_PROMPT=1 ./install.sh"
ansible all -b -m shell -a "cd /opt/src/OpenRemoteGUI && ./rollback.sh"
```
