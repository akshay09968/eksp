# 0008 — S3-native state locking (no DynamoDB)

- **Status:** accepted
- **Date:** 2026-07-10

## Context

Terraform ≥1.10 locks state via S3 conditional writes (`use_lockfile`); the
DynamoDB lock table — mandatory for years — is legacy for new backends.

## Decision

One versioned, encrypted, TLS-only state bucket (`eksp-tfstate-<account>`),
key per env, `use_lockfile=true` injected by `make init`/CI. No DynamoDB table.

## Consequences

One fewer resource to bootstrap/pay for/explain; locking semantics live in the
same service as the state; bucket versioning doubles as state history.
Requires TF ≥1.10 everywhere (pinned in CI, floor in `required_version`).
Stuck locks clear with `terraform force-unlock` (RUNBOOK).

## Rejected

- **DynamoDB lock table** — correct answer until 1.10; today it's an extra
  moving part that mostly signals the repo predates the feature.
- **Terraform Cloud/HCP state** — adds an account dependency to a repo that
  should stand alone; right answer in many orgs, not for this artifact.
