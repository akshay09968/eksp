# 0009 — Spot-first + Graviton compute

- **Status:** accepted
- **Date:** 2026-07-10

## Context

Compute dominates the bill (COST.md). Spot is 60–70% off but interruptible
(2-min warning); Graviton (arm64) is ~20% better price/perf but requires
multi-arch images.

## Decision

Workload capacity is spot-first (NodePool weight 100) with an on-demand
fallback pool (weight 10) that provisions only when spot can't. Wide diversity
(c/m/r, gen≥5, both arches, price-capacity-optimized) keeps interruption rates
low. All images build amd64+arm64 (distroless, buildx). System-critical
components stay on a small on-demand Graviton MNG.

Stateless-only rule: anything that can't tolerate a 2-minute eviction doesn't
belong on the spot pool (today: Prometheus is the only stateful pod, and a
restart-with-PVC is acceptable for operational metrics; it would move to the
on-demand pool via nodeSelector if that changed).

## Consequences

~60%+ off the dominant cost line with quantified risk: interruption warnings
are consumed (SQS → Karpenter), drains respect PDBs, capacity replaces in
<90 s, and the RED dashboard is the arbiter that users never noticed. The
fallback pool converts "spot capacity crunch" from an outage into a bill.

## Rejected

- **On-demand + Savings Plans only** — the safe-but-expensive default; SPs
  still make sense *under* the spot strategy for the steady-state floor.
- **amd64-only** — leaves the Graviton discount on the table for one buildx
  flag of effort.
