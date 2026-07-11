# 0010 — Kustomize for our apps; helm only for third-party charts

- **Status:** accepted
- **Date:** 2026-07-10

## Context

In-repo workloads need per-env variation (replicas, HPA targets, image tags).
Third-party platform software ships as helm charts.

## Decision

Our manifests are plain YAML bases + kustomize overlays (patch-by-target,
images transform for the promotion PR). Third-party software is consumed as
upstream helm charts (ArgoCD multi-source with values-in-git, or helm_release
on the Terraform side of the boundary). We author no in-house helm charts for
apps — the one local chart (`karpenter-resources`) exists solely to template
Terraform values into CRs in the same apply.

## Consequences

App manifests are readable diffs (what you review is what applies); the CI
promotion PR is a one-line `newTag` bump; no values-indirection archaeology.
Third-party upgrades stay `targetRevision` bumps handled by Renovate. Cost:
kustomize patches are clumsy for deeply conditional logic — a pressure we
avoid by keeping env differences to scalar knobs.

## Rejected

- **Helm-template our own apps** — templating power we don't need, at the cost
  of reviewing `{{ }}` soup instead of YAML.
- **Rendering helm through kustomize (helmCharts)** — mixes the models and
  breaks ArgoCD's native helm handling.
