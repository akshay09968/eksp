# 0006 — Load balancers target pods directly (`ip` mode)

- **Status:** accepted
- **Date:** 2026-07-10

## Context

The AWS Load Balancer Controller can target `instance` (NodePort on every
node, kube-proxy forwards) or `ip` (pod ENI IPs are the targets).

## Decision

`ip` targeting everywhere (`defaultTargetType: ip`; NLB→gateway likewise), with
the deregistration/readiness choreography built around it: deregistration delay
30 s aligned with the app's 15 s in-app drain and 45 s grace period;
`least_outstanding_requests` on target groups.

## Consequences

One hop fewer (no NodePort → kube-proxy → pod indirection), real per-pod
health at the LB, no conntrack entry per connection on an intermediate node,
and target churn follows pod churn — which is precisely why the drain
choreography is load-bearing. Requires VPC CNI (pods hold VPC IPs — they do)
and makes IP capacity planning matter (prefix delegation + /18s, SCALING.md).

## Rejected

- **instance/NodePort mode** — extra hop, `externalTrafficPolicy` trade-offs
  (source-IP loss or imbalance), health checks test nodes rather than pods.
