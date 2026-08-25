# Contributing to OpenRemoteGUI

Thanks for your interest in improving OpenRemoteGUI.

## Ground rules

- Every shell change must pass ShellCheck (`shellcheck -x`) and `bash -n`. CI enforces this.
- Keep the installer **manifest-driven**: any new mutation must be recorded so rollback
  can undo it.
- Never add steps that install a desktop environment or expose raw VNC to the network.
- Prefer real, lintable script files over heredoc-embedded logic.

## Development setup

```bash
git clone https://github.com/855princekumar/OpenRemoteGUI.git
cd OpenRemoteGUI
shellcheck -x install.sh rollback.sh update.sh scripts/*.sh lib/common.sh
bash -n install.sh rollback.sh update.sh scripts/*.sh
tests/run.sh
```

## Pull requests

1. Fork and branch from `main`.
2. Make focused changes with clear commit messages.
3. Update docs/ADRs when behaviour or decisions change.
4. Ensure CI is green.

## Reporting bugs

Open an issue using the Bug Report template. Include hardware, OS, and the relevant
`journalctl -u openremotegui-*` output.
