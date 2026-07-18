# ADR 0001: Protect public Swift APIs and route contracts in pull requests

**Status:** Accepted

## Context

URLRouter exposes two public library products and a public URL contract catalog.
Both are consumed outside the repository. Compilation and unit tests alone do
not reveal that a public type, method, or existing URL route was removed.

## Decision

Every pull request compares public Swift APIs with its exact base commit using
SwiftPM's `diagnose-api-breaking-changes` command. It also compares
`RouteContracts.json` with that base commit and rejects removed routes, changed
paths, removed presentation styles, required parameters, or supported versions.

Breaking changes require a major release and migration guidance. The gates are
not bypassed for patch or minor releases.

## Consequences

Contributors get an early, reproducible compatibility signal. The repository
accepts a modest CI cost and full Git history checkout in exchange for avoiding
silent downstream breakage.
