# 0012 — Memory limits yes, CPU limits no

- **Status:** accepted
- **Date:** 2026-07-10

## Context

CPU is compressible (throttling), memory is not (OOM). CFS-quota throttling
penalizes latency-sensitive services in ways that surprise people: a pod
"using 40% CPU" still gets throttled at its quota boundary within each 100 ms
period, adding tail latency exactly when busy.

## Decision

Every container sets CPU **requests** (scheduling/bin-packing truth) and
memory requests *and limits* (requests == limits where practical). No CPU
limits anywhere in this repo; the LimitRange default enforces the same for
unset containers.

## Consequences

Idle node CPU is usable by whoever's busy (better p99 at no cost); noisy-
neighbor pressure is bounded by requests via CFS *shares* (proportional, not
hard caps) plus HPA scaling on utilization-of-request. We accept that a
runaway pod can soak idle CPU — which shares already arbitrate fairly.

## Rejected

- **CPU limits everywhere** — the compliance-brain default; buys predictable
  throttling, pays in tail latency. If a platform mandate ever requires them,
  set limits ≥ 2× requests and monitor `container_cpu_cfs_throttled_periods`.
- **Static CPU manager pinning** — for latency-critical, core-pinned workloads
  (not this one).
