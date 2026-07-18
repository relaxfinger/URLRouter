# Maintenance policy

## Supported releases

The latest tagged release on `master` is supported. Security fixes and
compatibility fixes are normally made there first. Older releases receive fixes
only when a maintainer explicitly commits to a backport.

## Versioning and compatibility

- **PATCH** releases fix behavior, tests, documentation, or tooling without a public API or route-contract break.
- **MINOR** releases add backwards-compatible APIs or route contracts.
- **MAJOR** releases may remove or change a public Swift API or public route contract and must include migration guidance.

PR CI compares public Swift APIs and route contracts with the PR base commit.
Do not bypass these gates for a patch or minor release.

## Maintainer workflow

1. Triage issues into bug, enhancement, question, or security report.
2. Require a focused PR, tests for behavior changes, and both README languages when public integration changes.
3. Require all CI checks, then squash merge to `master`.
4. Publish a semantic-version tag and GitHub release from the merged commit.

## Architecture records

Material cross-cutting decisions are recorded under `docs/adr/`. A new ADR is
expected when a change affects public-package boundaries, route compatibility,
security posture, or long-term maintenance costs.
