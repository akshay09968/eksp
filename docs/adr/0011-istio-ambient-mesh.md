# 0011 — Istio ambient over sidecars / Linkerd / Cilium mesh / App Mesh

- **Status:** accepted
- **Date:** 2026-07-10

## Context

Requirements a mesh satisfies that nothing else in the stack does: east-west
mTLS with workload *identity* (not IP), L7 authorization between services,
retries/timeouts as platform policy, per-hop golden signals. The cost question
at millions of requests: sidecar-per-pod taxes every pod with proxy CPU/RAM and
injects latency at each hop.

## Decision

Istio **ambient** (1.30): per-node ztunnel carries L4 mTLS (cost scales with
nodes, not pods), per-namespace waypoint adds L7 where wanted. GitOps-managed
with sync waves (gateway-api CRDs → base → istiod → CNI → ztunnel → policies).
Off in dev, on in staging/prod. Shipped policy: STRICT PeerAuthentication,
AuthorizationPolicy (only sample-api's SA may call the worker), waypoint
HTTPRoute with retry/timeout on the worker service.

Known consequence embraced as architecture: STRICT mTLS rejects out-of-mesh
plaintext, so north-south enters via an in-mesh gateway (ADR-0017) rather than
ALB→pod directly.

## Consequences

Zero-trust east-west with near-flat data-plane cost as pods scale; no
injection/restart lifecycle; policies are platform PRs, not app code. Costs:
waypoints are an extra hop where enabled (measured honestly via the k6
`CHAIN=1` A/B), the istio-cni/VPC-CNI chaining is one more node agent to
operate, and default-deny NetworkPolicy needs the HBONE (15008) allowance.

## Rejected

- **Istio sidecars** — per-pod tax and lifecycle coupling; the thing ambient
  was built to end.
- **Linkerd** — technically lovely; the 2024 licensing shift (stable releases
  behind a commercial edition) makes it a harder default recommendation.
- **Cilium mesh** — requires replacing the VPC CNI; a bigger operational blast
  radius than the mesh feature set justifies here.
- **AWS App Mesh** — EOL'd by AWS; non-choice.
- **No mesh** — was the v1 YAGNI position; overturned by the explicit
  requirement for east-west security and L7 policy demonstration.
