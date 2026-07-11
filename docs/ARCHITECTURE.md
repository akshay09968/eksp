# ARCHITECTURE

The one-page mental model, then the details that make it hold.

## The two-plane model

```
Terraform  ──creates──►  AWS + cluster-critical software   (slow-changing, IAM-coupled)
ArgoCD     ──syncs────►  everything else in-cluster        (fast-changing, git-driven)
```

**The boundary rule ([ADR-0004](adr/0004-terraform-gitops-boundary.md)):** if it
needs an AWS IAM role or must exist before workloads can schedule, Terraform
owns it (VPC, EKS, Karpenter, ALB controller, EBS CSI, ArgoCD itself + the root
app). Otherwise it lives in `gitops/` and ArgoCD owns it (platform baseline,
mesh, observability, apps). The rule kills the classic failure mode of two
tools fighting over one object.

Handoffs across the boundary are **name-based contracts**, not state sharing:
the Pod Identity association in `terraform/envs/*` names namespace `costwatch`
/ SA `costwatch`; the manifest in `gitops/apps/costwatch` provides exactly that
SA. Same pattern for Karpenter's discovery tags and the ALB controller's SA.

## Request path

```
client → (Route53/CloudFront/WAF: documented edge, not provisioned)
       → dev:            ALB (Ingress, ip targets) ──plaintext──► sample-api
       → staging/prod:   NLB → Istio ingress gateway (Gateway API)
                             ──HBONE mTLS──► sample-api
                             ──mTLS + waypoint (retry/timeout/authz)──► sample-worker
```

Why the split ([ADR-0017](adr/0017-api-gateway-strategy.md)): with STRICT
ambient mTLS, an out-of-mesh ALB targeting pods directly is *rejected* — north-
south must enter through an in-mesh gateway. Dev keeps the plain ALB so both
patterns are on display; the gateway is also where API-gateway-tier policy
(JWT, rate limits) attaches later without touching apps.

## Network design

| Tier | Size/AZ | Holds | Notes |
|---|---|---|---|
| public | /22 | ALB/NLB, NAT | `kubernetes.io/role/elb` tag |
| private | /18 | nodes + pods | prefix delegation; `karpenter.sh/discovery` tag |
| intra | /24 | EKS control-plane ENIs | no internet route |

VPCs: dev `10.10/16` (2 AZ), staging `10.20/16` (3 AZ), prod `10.30/16` (3 AZ)
— non-overlapping for future peering. NAT: single (dev/staging) vs per-AZ
(prod). Gateway endpoints always; interface endpoints scale with env
(ECR/STS/EC2/ELB/logs in prod) to take AWS-bound traffic off NAT.

## Compute model

- **System MNG**: 2–3 Graviton nodes, tainted `CriticalAddonsOnly` — CoreDNS,
  Karpenter, ALB controller, ArgoCD, istiod. Karpenter must not manage the
  capacity it runs on.
- **Everything else**: Karpenter NodePools — `general-spot` (weight 100) and
  `general-on-demand` (weight 10, fallback), c/m/r gen≥5, amd64+arm64, capped
  by per-env CPU limits, 30-day expiry, consolidation with budgets.

## Identity model

- **Humans**: EKS access entries (API mode; no aws-auth ConfigMap). Cluster
  creator is admin; extra admins via `admin_principal_arns`.
- **Workloads**: EKS Pod Identity ([ADR-0005](adr/0005-pod-identity.md)) —
  associations bind (namespace, SA) → IAM role. IRSA retained only where an
  integration demands it (none currently).
- **CI**: GitHub OIDC → three roles (plan: read-only; apply: env-gated;
  ecr-push: main-only). Zero long-lived AWS keys anywhere.

## Observability model

kube-prometheus-stack discovers every ServiceMonitor/Rule in-cluster (nil
selectors off). Apps expose RED metrics with bounded label cardinality (route
label = static string, never raw path). SLOs alert on **burn rate** (fast
14.4×/page, slow 6×/page, on-pace/ticket) — never on raw error percentage.
Dashboards are ConfigMaps (sidecar-loaded), alerts carry `runbook_url` anchors
into [RUNBOOK.md](RUNBOOK.md).

## Environment differences

Same shape, different knobs — the full matrix lives in the
[spec §8](superpowers/specs/2026-07-10-eks-platform-design.md) and each
`terraform/envs/<env>/main.tf` documents its own deltas inline. Highlights:
dev = 2 AZ/1 NAT/no mesh/costwatch on; staging = 3 AZ/mesh on/no costwatch;
prod = 3 NAT/full endpoints/flow logs/NodeLocal DNS/RPS-HPA/disruption freeze.

## Drift model ([ADR-0016](adr/0016-drift-detection.md))

| Layer | Mechanism | Latency | Response |
|---|---|---|---|
| Kubernetes | ArgoCD `selfHeal+prune` | ~minutes, continuous | auto-revert; visible in UI |
| AWS | nightly `terraform plan -detailed-exitcode` | 24h (or dispatch) | GitHub issue opened/updated, closed on clean |

## What I'd change at 10× (the honest section)

Multi-account (workload isolation + CUR at the org payer), private-only API
endpoint behind VPN, IPVS/eBPF if service count explodes, Thanos for metrics
federation, cell-based architecture before a single cluster hits its blast-
radius ceiling, and a real edge (CloudFront+WAF, documented today, built then).
