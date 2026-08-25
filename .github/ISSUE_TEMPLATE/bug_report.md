---
name: Bug report
about: Report a problem with OpenRemoteGUI
title: "[bug] "
labels: bug
---

## Description

<!-- What happened vs what you expected -->

## Environment

- Hardware (e.g. Pi 4 / Pi 5 / x86_64):
- OS (`cat /etc/os-release | head -2`):
- Compositor (labwc / Wayfire / sway / other):
- OpenRemoteGUI version (`cat VERSION`):

## Reproduction

1.
2.

## Logs

```text
# paste relevant output
journalctl -u openremotegui-wayvnc -u openremotegui-novnc -n 100 --no-pager
cat /var/lib/openremotegui/install.log
```
