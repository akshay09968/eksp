# COST

Honest numbers (ap-south-1, mid-2026 list prices, USD, ±10%). costwatch — the
app this platform runs — shows you the real ones.

## Baseline (idle platform, no load)

### dev ≈ $170–200/mo

| Item | $/mo | Note |
|---|---|---|
| EKS control plane | 73 | flat |
| NAT gateway ×1 | 27 + data | the single-NAT trade |
| System nodes 2× t4g.medium | 22 | on-demand |
| Karpenter nodes | ~10–30 | 2–4 small spot nodes for platform pods |
| EBS (Prometheus 20Gi + nodes) | ~8 | gp3 |
| ALB | 19 + LCU | dev ingress |
| CloudWatch/ECR/misc | ~10 | |

### staging ≈ $260–320/mo

3 AZ, m7g.large ×2 system (~$92), mesh pods on spot, ECR/STS endpoints
(~$22), single NAT, NLB instead of ALB.

### prod ≈ $600–750/mo idle

| Item | $/mo | Note |
|---|---|---|
| EKS control plane | 73 | |
| NAT ×3 | 81 + data | AZ-independence |
| Interface endpoints ×6×3AZ | ~130 | removes NAT data + latency on AWS APIs |
| System nodes 3× m7g.large | 138 | |
| Karpenter floor (HPA min 6 + platform) | ~80–150 | spot |
| Prometheus 100Gi + assorted EBS | ~15 | |
| NLB + flow logs + CloudWatch | ~50 | |

## Under the 17k-RPS target load (prod)

Dominated by compute + LB capacity units + egress:

```
~32× c7g.2xlarge equivalent at spot (~60-70% off on-demand ≈ $0.10/hr each)
        ≈ $2,300/mo sustained — or ~$770/mo if the load runs 8h/day
NLB NLCU at 17k RPS (new-flow + active-flow dominated)  ≈ $150–400/mo
egress: the real wildcard — 1KB responses × 43B req/mo ≈ 43TB ≈ $4,700/mo
        (this is why real systems put CloudFront in front: cached egress is
        ~half the price and offloads most origin traffic)
```

Takeaway a panel should hear: **at millions of requests, egress and the edge
strategy dominate, not the cluster** — the Kubernetes bill is a rounding error
next to data transfer, which is exactly why the edge tier is in the roadmap.

## The levers (ranked by $/effort)

1. **Spot-first Karpenter** (built): 60–70% off the biggest line item, with
   on-demand fallback + interruption handling so it's not a reliability trade.
2. **Graviton everywhere** (built): ~20% better price/perf; multi-arch images.
3. **Consolidation** (built): `WhenEmptyOrUnderutilized` + 30d expiry defrags
   the fleet; budgets keep it off peak hours.
4. **Interface endpoints vs NAT data** (built, prod): endpoints win once
   AWS-bound traffic exceeds ~1.5TB/mo/AZ; below that, NAT is cheaper — which
   is why dev has none.
5. **Right-size requests** (process): requests drive bin-packing; the
   LimitRange defaults are floors, review actuals in Grafana quarterly.
6. **Destroy dev when idle** (habit): `make destroy ENV=dev` — it rebuilds in
   15 min. $170/mo of always-on dev is a choice, not a fact.

## Guardrails

Karpenter CPU ceilings cap runaway scale (48 vCPU dev / 1000 prod);
ResourceQuota caps the apps namespace; costwatch makes the bill visible daily
(the Overview delta tile is the "did something change" tripwire); AWS Budgets
alerts are a two-minute console add documented in SECURITY.md's ops checklist.

## costwatch's own cost

Cost Explorer bills **$0.01/request**. The 6h TTL cache + singleflight bounds
it: ≤ ~5 query shapes × 4 refreshes/day ≈ **$6/mo** worst case, ~$1 typical.
The hourly/resource-level opt-in adds an AWS charge based on usage records —
that one is your call, the UI degrades gracefully without it.
