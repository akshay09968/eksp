# SCALING — the millions-of-requests engineering

**Target:** 1,000,000 requests/minute sustained (**~17,000 RPS**) against
`sample-api` with p99 < 150 ms at the load balancer and error rate < 0.1%,
absorbing a **3× spike (~50k RPS)** with no manual action.

**Status: design targets.** Numbers below are engineering math, not measured
results. The methodology (§Method) reproduces them; recorded runs get appended
to §Results. This repo does not invent benchmarks.

## The capacity math

The whole stack is sized from one number: **RPS one pod serves at its CPU
target**.

```
sample-api /work?ms=5:   ~5 ms CPU per request
1 vCPU               ⇒   ~200 req/s at 100% CPU
HPA target 60%       ⇒   ~120 req/s per vCPU sustainably
requests: 250m       ⇒   ~30 req/s per pod floor — but no CPU limit (ADR-0012),
                         so a pod on an idle node bursts far higher; plan on
                         the HPA's RPS metric instead: 800 req/s/pod target
                         at ~4 vCPU of real usage per pod under load.

17,000 RPS ÷ 800 RPS/pod       ≈ 22 pods  (prod HPA min 6, max 200)
3× spike → 50k RPS             ≈ 64 pods
node math: c7g.2xlarge (8 vCPU) ≈ 2 pods/node at full burn ⇒ ~32 nodes at spike
Karpenter cpu ceiling (prod)   = 1000 vCPU spot + 256 on-demand ≫ requirement
```

Every layer below is the answer to "what breaks *before* the pods do?"

## Layer by layer

### Load balancer

ALB/NLB scale on traffic, with lag measured in minutes. Mitigations here:
`ip` target mode (ALB→pod direct, no NodePort/kube-proxy second hop,
[ADR-0006](adr/0006-alb-ip-mode.md)), 3-AZ public subnets,
`least_outstanding_requests` (heterogeneous pod load — spot mixes instance
generations), idle timeout 60 s < app keep-alive 120 s (the backend never closes
a connection the LB thinks is open). For a *known* step event (product launch),
pre-warm via a support ticket or schedule a synthetic ramp 30 min ahead —
documented because "ALB scaled slower than our spike" is a classic incident.

### DNS — the classic first casualty

At high RPS with default `ndots:5`, every unqualified lookup fans out to
multiple queries against CoreDNS ClusterIP, through conntrack, cross-node.
Symptoms: 5 s timeouts (UDP retry), SERVFAIL storms during scale-out.

Defenses shipped: CoreDNS autoscaling (min 2 dev / 3 prod, zone-spread,
managed-addon PDB), **NodeLocal DNSCache in prod**
(`gitops/platform/overlays/prod/nodelocal-dns.yaml`) — per-node cache on a
link-local IP intercepting the kube-dns ClusterIP with NOTRACK (no conntrack
entry, no cross-node hop; works untouched in kube-proxy iptables mode), and the
apps use full-FQDN worker URLs (`sample-worker.apps.svc.cluster.local`) to skip
search-path fan-out.

### Pod IPs

Default VPC CNI hands out individual secondary IPs — pod density dies first.
**Prefix delegation** (`/28` per ENI slot) raises max pods to 110+ on nitro
instances. Subnets are sized for it: private `/18` per AZ = 16k IPs; at ~2
pods/node × 32 nodes the spike needs <1k. Headroom to 10× the target before a
secondary CIDR becomes necessary.

### Nodes

Karpenter ([ADR-0003](adr/0003-karpenter.md)) provisions in ~40–90 s from
pending pods; the spike math needs ~30 nodes in a burst — well inside its batch
capability. Spot-first with on-demand fallback (weights 100/10),
price-capacity-optimized allocation across c/m/r gen≥5 both arches keeps
interruption rates low; the interruption queue drains 2-minute warnings
gracefully. Consolidation is bounded: ≤10% of nodes at once, **frozen during
business hours in prod** — churn at peak is a cost you feel in p99.

### Pods (HPA)

CPU-based HPA lags spikes (metric → decision → scheduling). Prod adds an
**RPS-per-pod metric** (`http_requests_per_second` via prometheus-adapter,
target 800): request rate moves seconds before CPU does. Scale-up policy: +100%
or +8 pods per 15 s, no stabilization; scale-down waits 5 min. Fast readiness
(2 s initial, 5 s period) puts new pods in service quickly.

### Conntrack

Every NAT'd/tracked flow occupies a conntrack slot; EC2's default established
timeout is **5 days**. At 17k RPS with keep-alives it's fine; with churny
clients it isn't. Shipped: `connectionTracking.tcpEstablishedTimeout: 300` on
the EC2NodeClass, keep-alive tuned clients (`MaxIdleConnsPerHost=256` on the
api→worker path), NodeLocal DNS NOTRACK for the highest-volume flow class, and
prod's interface endpoints keep ECR/STS/CloudWatch traffic off the NAT path
entirely.

### NAT

3 NAT gateways in prod (AZ-independence; ~5 GBps each, burst 100 Gbps
aggregate). App traffic ingresses via the LB, so NAT carries only egress
(pulls, AWS APIs) — and the endpoints remove most of that. Single-NAT dev is a
deliberate cost trade ([COST.md](COST.md)).

### East-west (mesh)

Sidecars tax every pod with proxy CPU/RAM and per-hop latency — at hundreds of
pods that's real money and real milliseconds. **Ambient** ([ADR-0011](adr/0011-istio-ambient-mesh.md))
moves L4 mTLS to a per-node ztunnel (cost scales with nodes, not pods) and L7
policy to one waypoint per namespace. The k6 method includes an A/B: `CHAIN=1`
through the mesh path vs. direct, measuring the delta honestly.

### Deploys at full load

The zero-error rollout chain, each link necessary:
`maxUnavailable: 0` (never dip below capacity) → new pod passes readiness →
old pod gets SIGTERM → **app fails `/readyz` but keeps serving 15 s**
(distroless = no shell preStop; the app owns its drain) → ALB deregistration
(30 s) stops new sends while in-flight requests finish →
`terminationGracePeriodSeconds: 45` outlasts all of it. PDB (10% prod) gates
node drains; topology spread keeps any single AZ/host loss ≤ a third of capacity.

### Control plane

EKS scales the API server/etcd automatically, but you can still hurt it:
watch storms from misbehaving controllers, unbounded CRD churn, kubectl in hot
loops. Karpenter batches; ArgoCD reconciles on intervals; nothing in this repo
polls the API per-request. kube-proxy iptables mode is fine at this service
count (few dozen); IPVS/eBPF is the >5k-services conversation, noted in
[ADR-0017](adr/0017-api-gateway-strategy.md) territory, not needed here.

## Method

1. Generator sizing: 17k RPS needs more than a laptop. Use a c7g.4xlarge+ in
   the same region (or distributed k6/k6-operator); confirm the generator isn't
   the bottleneck (its CPU < 70%, no local port exhaustion).
2. `make k6-smoke BASE_URL=http://<lb>` — health gate.
3. `make k6-ramp TARGET_RPS=17000 BASE_URL=...` — 25%→50%→75%→100% steps,
   10 min hold. Watch: Grafana RED dashboard, `kubectl get nodeclaims -w`,
   HPA status, CoreDNS error rate.
4. `k6 run load/k6/spike.js` — the 3× step; record time-to-recovery of p99.
5. `CHAIN=1` variants for the mesh delta.
6. Append k6 summaries + `kubectl top nodes` snapshots to §Results below.

Thresholds fail the run: p99 < 150 ms, errors < 0.1% — the SLO is executable.

## Results

*(none recorded yet — see §Method; PRs adding runs welcome)*
