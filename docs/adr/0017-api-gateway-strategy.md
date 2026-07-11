# 0017 — API gateway: in-mesh gateway (Gateway API), not Amazon API Gateway

- **Status:** accepted
- **Date:** 2026-07-10

## Context

Two forces converged. First, the platform needs an API-gateway tier: a place
for routing, timeouts, and later JWT authn/rate limits that isn't app code.
Second, a correctness constraint discovered in design review: with STRICT
ambient mTLS, an out-of-mesh ALB targeting pods directly is **rejected** —
ztunnel refuses plaintext to enrolled workloads. North-south must enter the
mesh through an in-mesh hop.

And the cost math that rules out the obvious managed answer: at the design
target (1M req/min ≈ 43B requests/month), Amazon API Gateway HTTP APIs
(~$1.29/M in ap-south-1) cost **≈ $55,000/month for the gateway alone**;
REST APIs ~3× that. An NLB at the same load is a few hundred dollars.

## Decision

- **staging/prod**: NLB → **Istio ingress gateway** provisioned from a Gateway
  API `Gateway` (class `istio`, NLB annotations via `infrastructure`), with
  app-owned `HTTPRoute`s attaching cross-namespace. This is the mesh-coherent
  front door and the future attachment point for gateway-tier policy
  (RequestAuthentication/JWT, rate limiting, header rewrites).
- **dev**: plain ALB Ingress (no mesh) — both patterns stay demonstrable.
- Amazon API Gateway remains the right tool for low-volume, management-heavy
  APIs (usage plans, API keys, Lambda backends) — documented, not deployed.

## Consequences

STRICT mTLS holds end-to-end; gateway policy lands as PRs to `gitops/`;
split ownership (platform owns the Gateway, apps own their routes) matches the
Gateway API model. Costs: the gateway Envoys are ours to size/run (HPA-able),
and TLS termination at the NLB/gateway needs the cert-manager or ACM step from
the hardening list before real domains.

## Rejected

- **Amazon API Gateway** — the per-request pricing math above; built for
  management features at low volume, not high-throughput serving.
- **ALB → pods with permissive mTLS carve-outs** — porous zero-trust posture
  and per-port PeerAuthentication sprawl; fixing the symptom, not the shape.
- **Envoy Gateway / Kong** — credible standalone gateways; adding a second
  Envoy control plane beside istiod duplicates machinery the mesh already has.
