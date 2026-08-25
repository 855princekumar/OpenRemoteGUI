# ADR-0001: Record architecture decisions

- Status: Accepted
- Date: 2026-08-20

## Context

OpenRemoteGUI makes several non-obvious choices (Wayland over X11, loopback-only
VNC, manifest-driven rollback). Without a durable record, the reasoning is lost and
future contributors re-litigate settled questions.

## Decision

We keep lightweight Architecture Decision Records in `docs/adr/`, one file per
decision, using the Michael Nygard format (Context / Decision / Consequences). Each
ADR is immutable once Accepted; changes are made by superseding ADRs.

## Consequences

Positive: shared, referenceable rationale; faster review; onboarding aid.
Negative: small authoring overhead per significant decision.
