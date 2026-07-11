# 0003 — Karpenter over Cluster Autoscaler

- **Status:** accepted
- **Date:** 2026-07-10

## Context

The spike scenario (3× in seconds) makes node-provisioning latency and
bin-packing quality the core compute problem. Cluster Autoscaler scales
pre-defined ASGs by nudging desired counts; Karpenter provisions instances
directly from pending-pod requirements against the whole EC2 catalog.

## Decision

Karpenter (v1.13), controller on the tainted system MNG, Pod Identity, SQS
interruption queue. Two NodePools: `general-spot` (weight 100) and
`general-on-demand` (weight 10 fallback), c/m/r gen≥5, amd64+arm64, per-env CPU
ceilings, 30-day expiry, `WhenEmptyOrUnderutilized` consolidation with budgets
(≤10% at once; frozen business hours in prod). NodePools/EC2NodeClass are
templated by a local helm chart so one apply delivers a working cluster.

## Consequences

40–90 s pod-to-node latency, native spot lifecycle handling, continuous
defragmentation, and the diversity that makes spot statistically safe. Costs:
a controller holding EC2 write permissions in-cluster (bounded by ceilings +
budgets + IAM scoping), and drift-y node fleets that must be reasoned about via
NodePool spec, not node lists.

## Rejected

- **Cluster Autoscaler + managed node groups** — minutes-slower scale-up, per-
  ASG instance-type rigidity, no consolidation; the 2020 answer.
- **Fargate** — per-pod pricing at this RPS is punitive; no DaemonSets (ztunnel,
  NodeLocal DNS both need them).
- **Static overprovisioning** — pays for the spike 24/7; kept as a *pattern*
  note (priority-0 balloon pods) for sub-minute absorption if ever needed.
