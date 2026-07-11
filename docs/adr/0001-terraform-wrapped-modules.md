# 0001 — Terraform, with thin wrappers over community modules

- **Status:** accepted
- **Date:** 2026-07-10

## Context

The IaC tool decides who can review the code, what ecosystem carries the heavy
lifting, and how hiring panels read the repo. Candidates: Terraform, Pulumi,
CDK/CDKTF, raw CloudFormation. Separately: hand-roll resources or build on
`terraform-aws-modules/*`.

## Decision

Terraform (≥1.10), with each concern wrapped in a thin internal module
(`terraform/modules/*`) that pins a community module and encodes our opinions
(taints, tags, prefix delegation, validation). Environments compose wrappers.

**The when-to-choose-Pulumi framework** (asked in every interview): Terraform
when the org's center of gravity is platform/ops — HCL plan-review culture,
the module registry, policy tooling (checkov/OPA/Sentinel), and it's what the
overwhelming majority of DevOps job specs and existing estates use. Pulumi when
platform engineers are SWE-first and need real abstractions (typed components,
loops, unit tests) or its killer feature, the Automation API (embedding IaC in
services). CDK for CloudFormation-committed, AWS-only orgs.

## Consequences

Battle-tested resource coverage for free; upgrades arrive as version bumps
(Renovate). Wrappers keep env code readable and give one place for validation
blocks and `terraform test`. Cost: two layers to look through when debugging a
community-module quirk.

## Rejected

- **Hand-rolled everything** — months of re-deriving edge cases the community
  already fixed; shows time to waste, not judgment.
- **Raw community modules in envs** — no place for opinions; env files balloon.
- **Pulumi/CDK here** — wrong audience for a DevOps portfolio; framework above.
- **OpenTofu** — kept compatible (nothing BSL-sensitive here), but Terraform
  remains what hiring orgs run; revisit if the ecosystems diverge.
