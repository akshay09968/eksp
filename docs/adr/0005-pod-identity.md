# 0005 — EKS Pod Identity over IRSA

- **Status:** accepted
- **Date:** 2026-07-10

## Context

Workloads need AWS credentials without secrets. IRSA (the 2019 answer) binds
service accounts to roles via the cluster's OIDC provider and per-role trust
policies containing the provider ARN. Pod Identity (2023+) replaces that with a
first-class EKS association API and a single service principal.

## Decision

Pod Identity everywhere: Karpenter, ALB controller, EBS CSI, costwatch. Trust
policies are uniform (`pods.eks.amazonaws.com` + `aws:SourceAccount`
confused-deputy condition); associations are explicit Terraform resources
naming (namespace, service account).

## Consequences

Roles are reusable across clusters (no OIDC-provider ARN baked into trust),
associations are visible/auditable EKS API objects, and the trust policy is one
pattern instead of N templated ones. Requires the pod-identity-agent addon
(installed `before_compute`). IRSA remains available for the rare integration
that hasn't caught up — currently none in this stack.

## Rejected

- **IRSA** — works, but per-role OIDC trust wiring is exactly the boilerplate
  Pod Identity was built to delete; new-build default in 2026 is Pod Identity.
- **Node instance roles for workloads** — every pod on the node inherits the
  union of permissions; that's not an identity model, it's an incident.
