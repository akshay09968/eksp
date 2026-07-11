# 0007 — kube-prometheus-stack over AMP / Container Insights

- **Status:** accepted
- **Date:** 2026-07-10

## Context

Metrics options: CloudWatch Container Insights, Amazon Managed Prometheus +
Managed Grafana, or self-hosted kube-prometheus-stack.

## Decision

Self-hosted kube-prometheus-stack via ArgoCD: Prometheus (24h dev / 15d prod on
gp3), Grafana with dashboards-as-code, Alertmanager, prometheus-adapter for the
custom-metrics API. EKS-hidden control-plane scrape targets disabled explicitly.

## Consequences

Full PromQL + recording/burn-rate rules, the adapter path that powers RPS-based
HPA (Container Insights can't), dashboards versioned in git, no per-sample
pricing surprises at 17k RPS. Costs: we own Prometheus capacity (sized per env)
and durability is single-instance — 15d retention is an operational-metrics
posture, with Thanos/Mimir as the documented long-term path.

## Rejected

- **Container Insights** — per-metric pricing scales badly with cardinality;
  no PromQL ecosystem; no custom-metrics HPA path.
- **AMP + AMG** — credible managed choice in an org (no Prometheus ops);
  rejected here because the portfolio should demonstrate operating the stack,
  and per-sample ingest pricing at load-test cardinality is real money.
