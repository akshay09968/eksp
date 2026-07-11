# 0013 — ArgoCD over Flux

- **Status:** accepted
- **Date:** 2026-07-10

## Context

Both are CNCF-graduated GitOps engines; both would work. They differ in
philosophy: ArgoCD is application-centric with a first-class UI; Flux is a
toolkit of controllers, headless by design, strong OCI/multi-tenancy story.

## Decision

ArgoCD (chart 10.x): app-of-apps per environment, sync waves for ordering,
multi-source Applications (upstream chart + values from this repo),
`selfHeal+prune` as the Kubernetes drift layer (ADR-0016). No public ingress;
UI via port-forward, SSO in the hardening backlog.

## Consequences

Sync state, drift, and history are *visible* — which matters for operating and
for demonstrating; the app-of-apps and ApplicationSet patterns are the ones
most orgs run. Costs: heavier footprint than Flux (runs on the system MNG),
and its RBAC/SSO surface is ours to harden.

## Rejected

- **Flux** — the right choice for lighter headless clusters, API-first
  platform teams, or OCI-artifact-driven delivery; loses here on demo
  legibility and market share of the patterns being demonstrated.
- **Both (Argo for apps, Flux for platform)** — real pattern, needless split
  brain at this scale.
