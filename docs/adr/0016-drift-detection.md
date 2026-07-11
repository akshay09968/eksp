# 0016 — Two-layer drift detection

- **Status:** accepted
- **Date:** 2026-07-10

## Context

"Is reality what git says?" has two layers with different change velocities:
Kubernetes objects (change constantly, cheap to reconcile) and AWS
infrastructure (changes rarely, expensive to compare). One mechanism can't
serve both well. driftctl, the once-obvious tool, is deprecated.

## Decision

- **Kubernetes layer**: ArgoCD `selfHeal: true, prune: true` — continuous
  (~minutes) detection *and correction*; manual cluster edits revert
  automatically and visibly (app History).
- **AWS layer**: nightly `terraform plan -detailed-exitcode -lock=false` per
  env with the read-only OIDC role (`.github/workflows/drift.yml`). Exit 2 →
  open/update a `drift`-labeled GitHub issue carrying the plan; exit 0 →
  close it. Response procedure: RUNBOOK.md#drift.

## Consequences

In-cluster drift is a non-event; AWS drift is a tracked artifact with a diff,
a timestamp, and a closure condition — and PR plans already catch config-vs-
state divergence intraday. Costs: nightly cadence means up to 24h detection
latency on AWS (dispatch on demand for suspicion), read-only plans can't see
inside opaque values, and `-lock=false` trades lock contention for a tiny race
with concurrent applies (acceptable for detection).

## Rejected

- **driftctl** — deprecated/unmaintained.
- **Continuous plan (15-min cron)** — API-hammering + noise for a signal that
  changes rarely; nightly + on-demand covers the need.
- **Spacelift/env0/TFC drift features** — the managed answer in an org;
  external account dependency this artifact shouldn't require.
- **AWS Config rules** — complementary compliance signal, not a state-file
  comparison; roadmap-compatible, not a substitute.
