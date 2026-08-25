# ADR-0007: Manifest-driven rollback

- Status: Accepted
- Date: 2026-08-20

## Context

On production/edge nodes, uninstalling must not damage unrelated state. Pattern-based
cleanup (`apt remove wayvnc`, `rm -rf`) risks removing pre-existing dependencies or
files the operator relied on.

## Decision

The installer records every mutation (packages installed that were absent, files and
directories created, files backed up, units enabled) to
`/var/lib/openremotegui/install-manifest`. Rollback consumes that manifest: it restores
backed-up originals, deletes only what was created, removes only packages that were
absent before install, and refuses to delete directories outside `/opt/openremotegui`.

## Consequences

Positive: precise, auditable, reversible; safe on shared nodes.
Negative: the installer must be disciplined about recording; a corrupted manifest
reduces rollback precision (mitigated by retaining state for audit).
