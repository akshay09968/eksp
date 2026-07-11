# 0014 — costwatch reads Cost Explorer first; CUR→Athena is the opt-in deep path

- **Status:** accepted
- **Date:** 2026-07-10

## Context

Two ways to answer "what does each resource cost": the Cost Explorer API
(instant, any account, ~$0.01/request, hourly+resource granularity behind a
billing opt-in) or the CUR 2.0 / Data Exports pipeline (S3 + Athena — the
org-grade FinOps substrate with full lineage and EKS split-cost pod-level
allocation, but real setup and payer-account considerations).

## Decision

v1 ships on the CE API: `GetCostAndUsage`/`GetCostForecast` behind a consumer-
owned interface, TTL cache (6h) + request coalescing as a *correctness* feature
against per-request billing, and the hourly/resource opt-in surfaced as an
actionable 409 rather than an error. The CUR pipeline is designed as an
`enable_cur_pipeline` Terraform flag (off; roadmap) feeding the same API shape.

## Consequences

costwatch works in any account minutes after deploy — the demo never depends
on a data pipeline; costs are bounded (~$1–6/mo, COST.md). Limits accepted:
CE granularity/history caps (hourly=14d), RESOURCE_ID coverage varies by
service, and namespace-level Kubernetes showback waits for the CUR path.

## Rejected

- **CUR-first** — days of pipeline before the first chart; wrong first
  milestone for a product whose job is immediate visibility.
- **Kubecost/OpenCost** — excellent for k8s-allocation; adopted-not-built is
  the roadmap answer, and it doesn't cover the account-wide AWS bill view that
  is costwatch's actual brief.
