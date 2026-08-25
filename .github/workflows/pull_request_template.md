## Summary

<!-- What does this PR change and why? -->

## Type of change

- [ ] Bug fix
- [ ] New feature
- [ ] Documentation / ADR
- [ ] Refactor / tooling

## Checklist

- [ ] `shellcheck -x` passes for all changed shell scripts
- [ ] `bash -n` passes
- [ ] `tests/run.sh` passes locally
- [ ] Any new installer mutation is recorded in the manifest (rollback covers it)
- [ ] Docs/ADRs updated if behaviour or decisions changed
- [ ] No step installs a desktop environment or exposes raw VNC to the network
