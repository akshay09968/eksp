# 0004 — The Terraform ↔ GitOps ownership boundary

- **Status:** accepted
- **Date:** 2026-07-10

## Context

The classic failure mode of Terraform+ArgoCD estates is two owners for one
object: helm_release fighting an Application, values drifting between repos,
"who installed this?" archaeology.

## Decision

One test, applied everywhere: **needs an AWS IAM role, or must exist before
workloads can schedule → Terraform. Otherwise → `gitops/`, ArgoCD owns it.**

Terraform side: VPC, EKS+addons, Karpenter (controller *and* NodePools — they
carry IAM role references), ALB controller, optional external-dns/cert-manager,
ArgoCD itself + the per-env root Application. ArgoCD side: platform baseline,
mesh, observability, workloads. Handoffs are name-based contracts (SA names,
discovery tags), never shared state.

## Consequences

Every object has exactly one reconciler; `terraform plan` output stays small
and infrastructure-shaped; app teams ship by PR to `gitops/` without touching
Terraform. Cost: the bootstrap apply installs some helm charts (the acceptable
wart — documented single-apply pattern with exec auth), and cross-boundary
renames need coordinated PRs.

## Rejected

- **Terraform installs everything** — plan noise, state bloat, and every app
  deploy becomes an infra change.
- **ArgoCD installs everything incl. Karpenter/ALB** — chicken-egg sequencing
  plus IAM wiring leaks into chart values; harder to reason about first-boot.
- **Crossplane** — collapses the boundary elegantly but swaps the industry-
  standard toolchain for a niche one; wrong trade for this repo's audience.
