# Design: Production-Grade EKS Platform ("eksp")

- **Date:** 2026-07-10
- **Status:** Approved for implementation
- **Purpose:** Portfolio codebase for a Staff DevOps Engineer application. Demonstrates
  industry-standard AWS EKS infrastructure engineered to serve millions of requests,
  with the judgment calls documented as ADRs.

## 1. Goals and non-goals

### Goals

1. **Scale**: sustain 1,000,000 requests/minute (~17,000 RPS) against a sample API with
   p99 latency < 150 ms at the load balancer, and absorb a 3× spike without manual action.
   Every layer that could bottleneck at this rate is addressed explicitly (§6).
2. **Industry standard**: the stack a strong platform team would actually run in 2026 —
   Terraform, EKS managed control plane, Karpenter, ALB, ArgoCD GitOps, Istio (ambient)
   service mesh, Prometheus/Grafana, GitHub Actions with OIDC. No exotic choices
   without an ADR.
3. **Reviewability**: a hiring panel can clone the repo and follow it. Decisions are
   recorded in `docs/adr/`. The scaling math is in `docs/SCALING.md`, reproducible via k6.
4. **Deployable for real**: `make bootstrap && make apply ENV=dev` stands up a working
   cluster. Cost-conscious defaults in dev (~$150–200/mo), honest cost analysis in
   `docs/COST.md`.
5. **AI harness**: the repo is configured so AI coding agents work safely and well in it
   (CLAUDE.md conventions, permission guardrails that forbid `terraform apply`/`destroy`,
   MCP tooling).
6. **FinOps product — "costwatch"**: a beautiful, intuitive web application running *on*
   the platform that traces AWS spend hourly/daily/monthly, broken down per service and
   per resource (§5.11). It is the platform's flagship real workload and closes the loop
   with the cost-engineering story (COST.md, Karpenter spot savings become visible in
   the app itself).

### Non-goals

- Multi-region active/active (documented as a roadmap item with the design sketch).
- Sidecar-per-pod mesh data plane — the mesh ships in **ambient mode** (§5.9);
  the sidecar trade-off is analyzed in ADR-0011, not built.
- Edge layer (CloudFront/WAF/Route53) is **documented** in the request path but not
  provisioned — the demo focuses on the cluster; the edge is commodity.
- Fabricated benchmark results. The repo ships load-test *method + capacity math*;
  numbers are labeled as design targets until reproduced with `make k6-ramp`.

## 2. Approach decision

**Chosen: plain Terraform monorepo, thin wrappers over community modules,
directory-per-environment, GitOps split with ArgoCD.**

| Approach | Verdict | Why |
|---|---|---|
| A. Plain Terraform + `terraform-aws-modules` wrappers | ✅ chosen | Lingua franca for DevOps hiring; community modules are battle-tested; wrappers show opinionation without NIH; env dirs are the clearest isolation story |
| B. Terragrunt | ❌ | DRY pays off at 10+ envs/accounts; at 3 envs the indirection costs reviewers more than the duplication costs maintainers (ADR-0002) |
| C. CDK / Pulumi | ❌ | Shows SWE depth but isn't what staff DevOps job specs list; diverges from reference architectures reviewers know |

## 3. Architecture overview

```
Client ──► (Route53/CloudFront/WAF — documented, not provisioned)
        ──► ALB (AWS Load Balancer Controller, IP targets, 3 AZ public subnets)
        ──► sample-api pods ──mTLS (Istio ambient)──► sample-worker pods
             ├── HPA: CPU + requests-per-second (prometheus-adapter)
             ├── Istio ambient: ztunnel L4 mTLS, waypoint L7 policy (staging/prod)
             └── Karpenter: provisions spot-first nodes in ~40–90 s
Terraform ──► VPC / EKS control plane / IAM / KMS / bootstrap addons / ArgoCD
ArgoCD    ──► platform baseline / observability stack / applications (app-of-apps)
GitHub Actions ──► plan/apply via OIDC (no static keys); app build → ECR → GitOps PR
```

### Layer boundaries (ADR-0004)

- **Terraform owns**: anything with AWS IAM coupling or needed before workloads can run —
  VPC, EKS, KMS, access entries, Karpenter controller + its NodePools (templated local
  chart), AWS Load Balancer Controller, EBS CSI, ArgoCD itself and the per-env root app.
- **ArgoCD owns**: everything else in-cluster — platform baseline, kube-prometheus-stack,
  prometheus-adapter, the sample application. Rule: *if it needs an AWS role or the
  cluster can't schedule without it, Terraform; otherwise GitOps.*

## 4. Repository layout

```
.
├── CLAUDE.md / AGENTS.md / .claude/ / .mcp.json     # AI harness
├── Makefile / mise.toml / .pre-commit-config.yaml / renovate.json
├── .github/workflows/                               # CI/CD (§9)
├── terraform/
│   ├── bootstrap/            # S3 state bucket (native locking), GitHub OIDC roles, ECR
│   ├── modules/
│   │   ├── network/          # wraps terraform-aws-modules/vpc ~> 6.0
│   │   ├── eks-cluster/      # wraps terraform-aws-modules/eks ~> 21.0
│   │   ├── karpenter/        # eks//modules/karpenter + helm + local chart for NodePools
│   │   ├── addons/           # ALB controller, external-dns(opt), cert-manager(opt)
│   │   └── gitops-bootstrap/ # ArgoCD + root app-of-apps
│   └── envs/{dev,staging,prod}/
├── gitops/
│   ├── envs/<env>/apps/      # ArgoCD Application manifests (root app syncs this)
│   ├── platform/             # namespaces, PSS, priority classes, netpol, quotas,
│   │                         # NodeLocal DNSCache (prod overlay)
│   ├── mesh/                 # Istio ambient (base, istiod, cni, ztunnel, policies)
│   ├── observability/        # kps values per env, prometheus-adapter, alerts, dashboard
│   └── apps/
│       ├── sample-api/       # kustomize base + overlays (api + worker roles)
│       └── costwatch/        # kustomize base + overlays (FinOps app)
├── apps/
│   ├── sample-api/           # Go service + tests + Dockerfile (scale demo workload)
│   └── costwatch/            # FinOps app: Go backend + React frontend (§5.11)
├── load/k6/                  # smoke, ramp, spike, soak scenarios
├── docs/                     # ARCHITECTURE, SCALING, RUNBOOK, COST, SECURITY, adr/
└── scripts/
```

## 5. Component design

### 5.1 Network (`modules/network`)

- VPC `/16` per env. Subnets per AZ: public `/22` (ALBs, NAT), private `/18` (nodes+pods),
  intra `/24` (EKS control-plane ENIs). Prod 3 AZ; dev 2 AZ.
- NAT: one per AZ in prod (AZ-independence + 5 Gbps×3 headroom); single in dev (cost).
- Gateway endpoints (S3, DynamoDB) always — free. Interface endpoints (ECR×2, STS, EC2,
  ELB, CloudWatch Logs) in prod — cuts NAT data cost and removes NAT from the image-pull
  and IRSA/STS hot paths. List is a variable.
- Karpenter discovery tags on private subnets; ELB role tags on public/private subnets.
- Flow logs to CloudWatch in prod (14-day retention).

### 5.2 EKS cluster (`modules/eks-cluster`)

- `terraform-aws-modules/eks/aws ~> 21.0`, Kubernetes **1.33** (variable).
- Access entries API mode (`authentication_mode = "API"`), cluster creator = admin,
  plus CI role and optional extra admins as variables. No aws-auth ConfigMap.
- KMS envelope encryption for Secrets; control-plane logs (api, audit, authenticator).
- Endpoint: public+private (portfolio usability) with `public_access_cidrs` variable;
  documented hardening step → private-only + VPN/SSM.
- Managed addons: `vpc-cni` (prefix delegation ON, network-policy agent ON,
  `before_compute`), `coredns` (2+ replicas, PDB, topology spread), `kube-proxy`,
  `eks-pod-identity-agent`, `aws-ebs-csi-driver` + gp3 default StorageClass (encrypted),
  `metrics-server` (EKS community addon).
- System node group: 2–3 × Graviton (`t4g.medium` dev / `m7g.large` prod), AL2023,
  tainted `CriticalAddonsOnly=true:NoSchedule` so app pods never land on it.
  Runs: Karpenter, CoreDNS, ALB controller, ArgoCD.

### 5.3 Karpenter (`modules/karpenter`) — ADR-0003

- Controller: helm chart `oci://public.ecr.aws/karpenter/karpenter` `~1.13`, on the
  system MNG, **EKS Pod Identity** (ADR-0005), interruption SQS queue via the
  `eks//modules/karpenter` submodule.
- NodePools via a **local templated chart** (`karpenter-resources`) so `helm_release`
  works in the same apply without plan-time cluster access:
  - `general` — spot-first (`capacity-type: [spot, on-demand]` weighted pools:
    spot weight 100, on-demand fallback weight 10), `c/m/r` families gen ≥ 5,
    amd64 + arm64, limits per env, `expireAfter: 720h`,
    disruption `WhenEmptyOrUnderutilized` + budgets (e.g. 10%, none during
    business-hours schedule in prod).
- EC2NodeClass: AL2023 `alias`, IMDSv2 required hop-limit 1, encrypted gp3,
  `connectionTracking.tcpEstablishedTimeout` tuned down from the 5-day EC2 default
  (conntrack exhaustion is a real high-RPS failure mode).

### 5.4 Addons (`modules/addons`)

- **AWS Load Balancer Controller** (helm, Pod Identity): ALB `ip` target mode (ADR-0006).
- **external-dns** and **cert-manager**: behind `enable_*` flags, default **off**
  (no assumption the reviewer owns a Route53 zone). When off, the sample API is reachable
  via the ALB DNS name over HTTP; docs show the one-variable path to TLS + real DNS.

### 5.5 GitOps (`modules/gitops-bootstrap` + `gitops/`) — ADR-0004

- ArgoCD helm chart (`argo/argo-cd`), no public ingress — access via `make argocd-ui`
  (port-forward). Admin secret in cluster; SSO documented as hardening.
- Root Application per env → `gitops/envs/<env>/apps/` (app-of-apps). `gitops_repo_url`
  variable; module can be disabled (`enable_gitops = false`) for TF-only mode.
- Applications: `platform` (kustomize), `mesh` (Istio ambient, sync-waved),
  `observability` (multi-source: kps chart + values from this repo),
  `prometheus-adapter`, `sample-api` and `costwatch` (kustomize overlay per env).
- **ArgoCD over Flux (ADR-0013)**: CNCF-graduated market leader, the UI makes drift and
  sync state tangible in a demo/interview, app-of-apps + ApplicationSets are the
  patterns hiring panels know. Flux is the right call for lighter-footprint,
  API-first multi-tenancy; documented in the ADR.

### 5.6 Platform baseline (`gitops/platform`)

Namespaces with Pod Security Standards labels (restricted for apps, privileged only where
required), PriorityClasses (`platform-critical`, `app-high`), default-deny NetworkPolicy
+ explicit allows (DNS, ALB→app, Prometheus scrape), LimitRange + ResourceQuota on app
namespaces, NodeLocal DNSCache DaemonSet (prod overlay) — DNS is the classic
millions-of-RPS failure (§6).

### 5.7 Observability (`gitops/observability`)

- kube-prometheus-stack: Prometheus (24 h retention dev / 15 d prod, gp3 PVC), Grafana
  (dashboards-as-code via sidecar: custom RED dashboard for sample-api + built-ins),
  Alertmanager.
- prometheus-adapter exposing `http_requests_per_second` for the HPA custom metric.
- PrometheusRules: **multiwindow multi-burn-rate SLO alerts** (99.9% availability:
  14.4× over 5m/1h page, 6× over 30m/6h page, 1× over 6h/3d ticket) + operational
  alerts (CrashLoopBackOff, pending pods, node NotReady, CoreDNS error rate, HPA at max,
  PVC filling, Karpenter disruption blocked), each annotated with a runbook link.

### 5.8 Sample application (`apps/sample-api`)

- Go 1.26, stdlib `net/http` + `prometheus/client_golang` only. **One binary, two
  roles** via `ROLE=api|worker`: the same image runs as `sample-api` (edge) and
  `sample-worker` (backend), giving the mesh real east-west traffic without a second
  codebase. Endpoints: `/` (JSON), `/work?ms=&kb=` (tunable simulated work),
  `/chain?calls=N` (api → worker fan-out over HTTP — exercises mesh mTLS/L7 policy),
  `/healthz`, `/readyz` (fails during drain), `/metrics`.
- Graceful shutdown: SIGTERM → readiness fails → wait `preStop`-aligned delay → drain
  in-flight with `server.Shutdown`. `terminationGracePeriodSeconds` >
  preStop + drain budget; ALB deregistration delay aligned (30 s). This chain is what
  makes rolling deploys zero-error at high RPS.
- Table-driven handler tests + a graceful-shutdown test.
- Dockerfile: multi-stage, static build, `gcr.io/distroless/static`:nonroot,
  multi-arch (amd64+arm64 — Graviton spot is the cost story).
- Manifests (kustomize): Deployment (probes, preStop, resources with **no CPU limit**
  (documented), topology spread across zones+hosts), Service, Ingress (ALB annotations),
  HPA v2 (CPU 60% + RPS/pod target via adapter in prod overlay), PDB (maxUnavailable 10%),
  ServiceMonitor, NetworkPolicy.

### 5.9 Service mesh — Istio ambient mode (ADR-0011)

- **Why a mesh here**: zero-trust east-west mTLS, L7 authorization between services,
  retries/timeouts/outlier detection as platform policy, and per-hop golden-signal
  telemetry — the things NetworkPolicy and ALB can't give you.
- **Why ambient, not sidecars**: at millions of requests, sidecar-per-pod taxes every
  pod with proxy CPU/memory and injects latency at each hop; ambient's shared ztunnel
  (L4, per-node) + optional waypoint (L7, per-namespace) keeps the data-plane cost
  near-flat as pods scale. Sidecar mode, Linkerd (licensing shift), Cilium mesh
  (CNI replacement — too invasive alongside VPC CNI), and AWS App Mesh (EOL) are
  analyzed and rejected in ADR-0011.
- **Scope**: GitOps-managed component (`gitops/mesh`) with ArgoCD sync waves
  (base CRDs → istiod → CNI node agent → ztunnel), per-env flag — off in dev,
  on in staging/prod. Namespaces opt in via `istio.io/dataplane-mode: ambient`.
- **Policies shipped**: STRICT PeerAuthentication, AuthorizationPolicy allowing only
  api → worker, waypoint for the apps namespace with retry/timeout policy on the
  worker route.
- **Interplay**: default-deny NetworkPolicy gains an HBONE (15008) allowance;
  SCALING.md and the k6 method call out measuring the with/without-mesh delta.

### 5.10 Load testing (`load/k6`)

Scenarios: `smoke` (sanity), `ramp` (constant-arrival-rate to 17k RPS), `spike`
(3× step), `soak` (30 min). Thresholds: p99 < 150 ms, error rate < 0.1%.
`docs/SCALING.md` documents the method, the expected capacity math, and how to run each.

### 5.11 costwatch — FinOps monitoring application

**Purpose**: trace how much every AWS resource is consuming, hourly/daily/monthly, in a
beautiful, intuitive web UI. Runs on the platform it monitors.

**Backend** (Go, `apps/costwatch/backend`):
- Data source v1: **Cost Explorer API** (`ce:GetCostAndUsage`, `ce:GetCostForecast`,
  `ce:GetDimensionValues`) — works in any account with zero data-pipeline setup
  (ADR-0014). Granularity: MONTHLY (13 mo), DAILY (90 d), HOURLY (14 d, requires the
  Cost Management *hourly + resource-level data* opt-in; the API degrades gracefully
  with an actionable message when not enabled).
- Per-resource view: CE `RESOURCE_ID` dimension where available; the deep path —
  **CUR 2.0 Data Exports → S3 → Athena** — is an optional Terraform flag
  (`enable_cur_pipeline`), off by default, giving org-grade per-resource lineage.
  EKS **split cost allocation** (pod-level costs in CUR) is documented for
  namespace/workload showback.
- **Caching is a correctness feature**: CE charges ~$0.01/request and data refreshes
  ~3×/day; an in-memory TTL cache (6 h, per query-shape key) plus request coalescing
  keeps the app snappy and the API bill ~zero. Cache status surfaces in the UI.
- Endpoints: `/api/summary` (MTD, forecast, Δ vs last month, top movers),
  `/api/costs` (granularity × groupBy=SERVICE|LINKED_ACCOUNT|REGION|USAGE_TYPE|TAG|
  RESOURCE_ID), `/api/health`, `/metrics` (Prometheus, reuses platform observability).
- IAM: dedicated Pod Identity role scoped to the `ce:Get*`/`ce:List*` read actions
  (+ Athena/S3/Glue read when the CUR flag is on). No mutating permissions, ever.

**Frontend** (`apps/costwatch/frontend`): React + Vite + TypeScript + Tailwind +
Recharts, built to the dataviz design system, **embedded into the Go binary via
`embed.FS`** — one container, no separate static hosting (ADR-0015). Views:
- **Overview**: KPI tiles (MTD spend, forecasted month-end, Δ vs last month, top
  mover), spend trend area chart, service breakdown donut, anomalies strip
  (largest day-over-day movers).
- **Explore**: hourly/daily/monthly toggle × group-by selector, stacked bar/area with
  drill-down (click a service → its usage types → its resources), CSV export.
- **Resources**: top-N spenders table with 14-day sparklines and tag columns
  (graceful empty-state when resource-level data isn't enabled).
- Light/dark theme, keyboard-navigable, responsive. Intuitive = opinionated defaults,
  one-click drill-downs, relative-time labels, freshness indicator.

**Deploy**: same kustomize+GitOps pattern as sample-api; internal-only Service by
default (port-forward / internal ALB — cost data is sensitive; SSO via oauth2-proxy is
a documented hardening step). Deployed to dev + prod.

**Security note**: costwatch is read-only against billing APIs; its role trusts only
its own service account in its namespace. UI auth is out of v1 scope *because* the
service is not exposed publicly by default.

## 6. The millions-of-requests engineering (SCALING.md contract)

Target: 17k RPS sustained / 50k RPS burst. Per-layer analysis the doc must contain:

| Layer | Bottleneck at ~17k RPS | Mitigation in this repo |
|---|---|---|
| ALB | LCU scale-up lag on spikes | IP targets, 3-AZ, pre-warm note, HTTP/2, idle timeout tuning |
| DNS | CoreDNS throttling/latency at pod churn | CoreDNS replicas+PDB+spread, NodeLocal DNSCache (prod), ndots guidance |
| Pod IPs | ENI/IP exhaustion at scale-out | VPC CNI prefix delegation, /18 private subnets, /16 VPC headroom |
| Nodes | Scale-up speed vs spike | Karpenter (~40–90 s), spot-first with on-demand fallback, consolidation budgets |
| Pods | HPA lag on CPU alone | RPS-based HPA via prometheus-adapter, sensible min replicas, fast readiness |
| Conntrack | Table exhaustion (NAT + nodes) | EC2NodeClass connectionTracking tuning, keep-alives, interface endpoints bypass NAT |
| Kube-proxy | iptables O(n) at huge service counts | Documented: not a bottleneck at this service count; IPVS/eBPF noted as the >10k-services move |
| Deploys | 5xx during rollout at high RPS | readiness gates + preStop/deregistration alignment + PDB + surge tuning |
| Control plane | API/etcd pressure from churn | EKS-managed scaling documented; CRD/watch hygiene; Karpenter batching |
| East-west encryption | Sidecar CPU/latency tax per hop | Istio **ambient**: per-node ztunnel ≈ flat cost vs per-pod sidecars; with/without delta measured in k6 method |
| Capacity math | — | pods = RPS ÷ (per-pod RPS at 60% CPU with headroom); worked example with the sample API |

## 7. Security posture

OIDC-only CI (zero static AWS keys), least-privilege plan (read-only) vs apply roles,
KMS secrets encryption, IMDSv2 hop 1, restricted PSS, default-deny netpol, encrypted
gp3 volumes, ECR scan-on-push, image pinning + Renovate, gitleaks pre-commit, checkov +
tflint in CI, SECURITY.md with the threat model summary. Access entries over aws-auth.

## 8. Environments

| | dev | staging | prod |
|---|---|---|---|
| AZs / NAT | 2 / 1 | 3 / 1 | 3 / 3 |
| System nodes | 2× t4g.medium | 2× m7g.large | 3× m7g.large |
| Karpenter limits | 64 vCPU | 200 vCPU | 1000 vCPU |
| Interface endpoints | none | ECR+STS | full list |
| Prometheus retention | 24 h | 7 d | 15 d |
| SLO alerts | ticket only | page (test) | page |
| Flow logs | off | off | on |
| Istio ambient mesh | off | on | on |
| costwatch | on | off | on |

State: one S3 bucket (from `terraform/bootstrap`, local-state chicken-egg documented),
key per env, **S3 native locking** (`use_lockfile`, TF ≥ 1.10 — ADR-0008). No DynamoDB.

## 9. CI/CD (GitHub Actions)

1. `terraform.yml` (PR): fmt-check → `init -backend=false` → validate → tflint →
   checkov → **terraform test** (mock providers, offline) per changed root (matrix);
   optional real `plan` + PR comment when the OIDC plan role variable is configured.
2. `terraform-apply.yml`: push to main / dispatch, per-env GitHub *environment* with
   protection rules, OIDC apply role.
3. `app.yml` (matrix: sample-api, costwatch): go vet/test/build (+ `npm ci && vite
   build` + typecheck for the costwatch frontend) → buildx multi-arch → push ECR
   (OIDC) → open a **GitOps promotion PR** bumping the image tag in the env overlay
   (the deploy *is* a git change — closes the GitOps loop).
4. `k8s-validate.yml`: kustomize build all overlays → kubeconform (strict, CRDs via
   schema catalog) + validate ArgoCD Application manifests.

Repo hygiene: pre-commit (terraform_fmt, tflint, gitleaks, whitespace), renovate.json
(TF modules, helm charts via regex managers, Go, actions, Docker), PR template,
CODEOWNERS.

## 10. AI harness

- **CLAUDE.md**: project map, conventions (module/naming/tagging standards), the
  TF-vs-GitOps boundary rule, definition-of-done checklist (fmt+validate+tflint+
  kubeconform+tests+ADR-if-decision), commands, guardrails.
- **AGENTS.md**: cross-agent pointer to CLAUDE.md.
- **.claude/settings.json**: allow read-only/validation commands; **deny**
  `terraform apply|destroy`, mutating `kubectl`, `helm upgrade/install` against real
  clusters; `ask` for `terraform plan` (needs credentials).
- **.mcp.json**: HashiCorp `terraform-mcp-server` (provider/module doc lookup) via
  Docker, optional by nature.

## 11. Testing strategy

- **Terraform**: `terraform validate` per root; native `terraform test` with
  `mock_provider` for network CIDR math and eks-cluster wiring (offline, runs in CI);
  tflint + checkov static analysis. `terraform plan` against real AWS is the
  CI-optional integration test.
- **Kubernetes**: kubeconform (strict) on every kustomize overlay build.
- **Apps**: `go test` (handlers, metrics, graceful shutdown), `go vet`; costwatch adds
  a mocked Cost Explorer client (interface-based) so cost aggregation, caching, and
  degradation paths are unit-tested offline, plus `tsc --noEmit` + `vite build` for the
  frontend.
- **Scale**: k6 scenarios with thresholds as executable SLOs.

## 12. Error handling & operability

RUNBOOK.md covers: cluster access, ArgoCD/Grafana access, node drain/rotation, EKS
version upgrade procedure (control plane → addons → nodes, PDB-aware), spot interruption
drill, DNS/ALB 5xx debug trees, HPA-at-max response, state-lock recovery, rollback via
GitOps revert. Alerts link to runbook anchors.

## 13. Decisions to record as ADRs

0001 Terraform over Pulumi/CDK (incl. the when-to-choose-Pulumi framework) + wrapped
community modules · 0002 directory-per-env over Terragrunt/workspaces · 0003 Karpenter
over Cluster Autoscaler · 0004 Terraform/GitOps boundary · 0005 Pod Identity over IRSA ·
0006 ALB IP-mode ingress · 0007 self-hosted kube-prometheus-stack over AMP/Container
Insights · 0008 S3 native state locking · 0009 spot-first + Graviton compute strategy ·
0010 kustomize for apps (helm for third-party charts) · 0011 Istio ambient mesh over
sidecars/Linkerd/App Mesh(EOL)/Cilium mesh · 0012 stdlib-only sample app · 0013 ArgoCD
over Flux · 0014 Cost Explorer API first, CUR/Athena as the opt-in deep path ·
0015 embedded SPA (embed.FS) over separate static hosting.

## 14. Open items deferred to roadmap (documented, not built)

Multi-region, private-only endpoint + VPN, SSO for ArgoCD/Grafana/costwatch
(oauth2-proxy), Loki/log pipeline (CloudWatch is the default sink), CloudFront+WAF edge
module, VPA/goldilocks, multi-account org layout (bootstrap is single-account),
costwatch anomaly detection via AWS Cost Anomaly Detection API, Kubecost/OpenCost
namespace showback (CUR split-allocation is the v1 documentation path).
