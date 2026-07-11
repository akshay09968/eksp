# 0002 — Directory-per-environment over Terragrunt/workspaces

- **Status:** accepted
- **Date:** 2026-07-10

## Context

Three environments need isolated state, different sizing, and identical shape.
Options: Terraform workspaces, Terragrunt, or plain directories composing
shared modules.

## Decision

`terraform/envs/{dev,staging,prod}` — each a full root with its own backend
key, composing the same modules with different knobs. Duplication between env
files is deliberate and small (the modules hold the logic).

## Consequences

An engineer reads one directory and sees the whole environment; blast radius
of an apply is one env by construction; envs can pin different module versions
mid-migration. Cost: ~60 lines of similar composition per env — accepted; the
env diff *is* the documentation of how prod differs from dev.

## Rejected

- **Workspaces** — one backend config and one directory for prod and dev is a
  footgun (`terraform workspace show` before every apply); HashiCorp's own
  guidance says not for strong isolation.
- **Terragrunt** — earns its indirection at 10+ envs/accounts with
  DRY-critical inheritance; at 3 envs the extra tool and mental hop cost
  reviewers more than the duplication costs maintainers.
