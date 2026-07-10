# EKS Platform ("eksp") + costwatch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the production-grade EKS platform + costwatch FinOps app defined in
`docs/superpowers/specs/2026-07-10-eks-platform-design.md`.

**Architecture:** Plain Terraform monorepo (thin wrappers over terraform-aws-modules,
directory-per-env, S3-native locking) provisions VPC/EKS/Karpenter/bootstrap addons and
ArgoCD; ArgoCD (app-of-apps per env) owns platform baseline, Istio ambient mesh,
observability, and the two workloads (sample-api scale demo, costwatch FinOps app).

**Tech Stack:** Terraform ≥1.10 (aws ~>6.0, helm ~>3.0), terraform-aws-modules
vpc ~>6.0 / eks ~>21.0 / eks-pod-identity, Karpenter (oci chart), ArgoCD, Istio ambient,
kube-prometheus-stack + prometheus-adapter, Go 1.26, React+Vite+TS+Tailwind+Recharts,
k6, GitHub Actions OIDC.

## Global Constraints

- Terraform `required_version = ">= 1.10"`; providers: `aws ~> 6.0`, `helm ~> 3.0` (map-style `kubernetes = {}` config with `exec`), no kubernetes provider.
- EKS `kubernetes_version = "1.33"` (variable). EKS module inputs are v21 names: `name`, `kubernetes_version`, `addons`, `endpoint_public_access`.
- Karpenter chart `oci://public.ecr.aws/karpenter/karpenter`; NodePool/EC2NodeClass `apiVersion: karpenter.sh/v1` / `karpenter.k8s.aws/v1`, `nodeClassRef: {group, kind, name}`, AMI `alias: al2023@latest`.
- All helm chart versions get a `# renovate:` comment; resolve current versions via `helm search repo <chart> --versions | head` before pinning.
- Naming: resources prefixed `eksp-<env>`; tags `{Project=eksp, Environment=<env>, ManagedBy=terraform}` via provider `default_tags`.
- Env sizing table and boundaries are in spec §8 / §3 (Terraform-vs-ArgoCD rule) — do not violate.
- Every commit: conventional message + the session trailer. Verification before any "done" claim: `terraform fmt -check -recursive`, `terraform validate` per root, `tflint --recursive`, `terraform test` (network), kubeconform on every overlay, `go vet ./... && go test ./...` per app, `npm run build` for frontend.
- No fabricated benchmark numbers anywhere; scale numbers are labeled design targets.

---

### Task 1: Repo scaffold + AI harness

**Files (create):** `.gitignore`, `.editorconfig`, `mise.toml`, `Makefile`,
`.pre-commit-config.yaml`, `renovate.json`, `LICENSE` (MIT),
`.github/PULL_REQUEST_TEMPLATE.md`, `.github/CODEOWNERS`, `CLAUDE.md`, `AGENTS.md`,
`.claude/settings.json`, `.mcp.json`, `README.md` (stub — finalized in Task 10).

**Interfaces produced:** Makefile targets used by every later task:
`fmt`, `lint`, `validate`, `test`, `kubeconform`, `init/plan/apply ENV=<env>` (init uses
`-backend-config` computing `eksp-tfstate-$(shell aws sts get-caller-identity --query Account --output text)`),
`argocd-ui`, `grafana-ui`, `costwatch-ui`, `k6-smoke/k6-ramp`.

**Steps:**
- [ ] `.claude/settings.json` permissions: allow `terraform fmt/validate/test`, `tflint`, `kubeconform`, `kustomize build`, `helm lint/template/search`, `go build/test/vet`, `npm ci/run`; deny `terraform apply|destroy`, `kubectl delete|apply|patch|edit`, `helm install|upgrade|uninstall`, `aws * delete*`; ask for `terraform plan`, `terraform init`.
- [ ] CLAUDE.md: project map, boundary rule, conventions, definition-of-done checklist, make targets, guardrails ("never apply/destroy; never touch state; no fabricated benchmarks").
- [ ] `.mcp.json`: hashicorp `terraform-mcp-server` via `docker run -i --rm hashicorp/terraform-mcp-server` (stdio).
- [ ] Run `git add -A && git commit -m "chore: repo scaffold + AI harness"`.

### Task 2: terraform/bootstrap (state + OIDC + ECR)

**Files:** `terraform/bootstrap/{versions.tf,variables.tf,main.tf,outputs.tf,README.md}`

**Produces:** S3 bucket `eksp-tfstate-<account_id>` (versioned, encrypted, TLS-only
policy, public-access-block); `aws_iam_openid_connect_provider` for
`token.actions.githubusercontent.com`; roles `eksp-github-plan` (ReadOnly + state RW),
`eksp-github-apply` (Admin, trust `refs/heads/main` + environment claim),
`eksp-github-ecr-push`; ECR repos `eksp/sample-api`, `eksp/costwatch` (scan-on-push,
lifecycle keep 20). Outputs consumed by CI docs: `state_bucket`, `plan_role_arn`,
`apply_role_arn`, `ecr_push_role_arn`, `ecr_repository_urls`.

**Steps:**
- [ ] Write files; local state documented in README (chicken-egg).
- [ ] `terraform -chdir=terraform/bootstrap init -backend=false && terraform -chdir=terraform/bootstrap validate` → `Success!`
- [ ] Commit `feat(terraform): bootstrap state backend, GitHub OIDC, ECR`.

### Task 3: Terraform modules

**Files:**
- `terraform/modules/network/{main.tf,variables.tf,outputs.tf,versions.tf}` + `tests/network.tftest.hcl`
- `terraform/modules/eks-cluster/{main.tf,variables.tf,outputs.tf,versions.tf}`
- `terraform/modules/karpenter/{main.tf,variables.tf,outputs.tf,versions.tf}`
- `terraform/charts/karpenter-resources/{Chart.yaml,values.yaml,templates/{nodepool-general.yaml,nodepool-fallback.yaml,ec2nodeclass.yaml}}`
- `terraform/modules/addons/{main.tf,variables.tf,outputs.tf,versions.tf}`
- `terraform/modules/gitops-bootstrap/{main.tf,variables.tf,outputs.tf,versions.tf}`

**Interfaces (module contracts consumed by Task 4):**
- network: in `name, vpc_cidr, az_count(2|3 validated), cluster_name, enable_nat_per_az, enable_flow_logs, interface_endpoints(list), tags` → out `vpc_id, private_subnet_ids, public_subnet_ids, intra_subnet_ids`. CIDR layout for /16: `cidrsubnets(cidr, 2,2,2, 6,6,6, 8,8,8)` = 3×/18 private, 3×/22 public, 3×/24 intra, sliced by az_count. Karpenter discovery + ELB role tags per spec §5.1.
- eks-cluster: in `name, kubernetes_version, vpc_id, private_subnet_ids, intra_subnet_ids, endpoint_public_access_cidrs, system_node{types,min,max,desired}, admin_principal_arns, tags` → out `cluster_name, cluster_endpoint, cluster_certificate_authority_data, node_security_group_id`. v21 module; `authentication_mode="API"`; addons map: vpc-cni (`before_compute`, prefix delegation + netpol agent via `configuration_values`), coredns (2 replicas), kube-proxy, eks-pod-identity-agent (`before_compute`), aws-ebs-csi-driver (pod-identity via terraform-aws-modules/eks-pod-identity), metrics-server; system MNG tainted `CriticalAddonsOnly=true:NoSchedule`, AL2023 arm64; node SG tagged `karpenter.sh/discovery`.
- karpenter: in `cluster_name, cluster_endpoint, chart_version, cpu_limit, tags` → helm karpenter (pod identity, 2 replicas, system-node tolerations) + local chart `karpenter-resources` (templated NodePools: `general` spot weight 100 / `fallback` on-demand weight 10, c/m/r gen≥5, amd64+arm64, expireAfter 720h, WhenEmptyOrUnderutilized + budgets; EC2NodeClass: al2023@latest, IMDSv2 hop 1, encrypted gp3, connectionTracking tcpEstablishedTimeout 300).
- addons: in `cluster_name, vpc_id, region, enable_external_dns, enable_cert_manager, tags` → ALB controller (pod identity, `ip` targets default) always; the two flags off by default.
- gitops-bootstrap: in `enable, cluster_name, env_name, repo_url, target_revision` → argo-cd helm (no ingress, on system nodes) + `argocd-apps` root Application → `gitops/envs/<env>/apps`.

**Steps:**
- [ ] Resolve chart versions: `helm repo add` argo/eks/prometheus-community/istio + `helm search repo ... --versions | head -3` each; pin with renovate comments.
- [ ] Write network module; `terraform -chdir=terraform/modules/network init -backend=false && terraform -chdir=terraform/modules/network validate`.
- [ ] Write `tests/network.tftest.hcl` (mock_provider aws + override_data AZs): asserts 3-AZ run yields 3/3/3 subnets and 2-AZ yields 2/2/2; `terraform -chdir=terraform/modules/network test` → `2 passed`.
- [ ] `helm lint terraform/charts/karpenter-resources` → `0 chart(s) failed`.
- [ ] Write remaining modules; validate each root the same way.
- [ ] `terraform fmt -recursive && tflint --recursive` clean.
- [ ] Commit `feat(terraform): network, eks-cluster, karpenter, addons, gitops modules`.

### Task 4: Environments dev/staging/prod

**Files:** per env `terraform/envs/<env>/{versions.tf,providers.tf,backend.tf,main.tf,variables.tf,outputs.tf,terraform.tfvars}`

**Consumes:** module contracts above. Per-env values exactly per spec §8. providers.tf:
aws with `default_tags`; helm with `kubernetes = { host, cluster_ca_certificate, exec = { api_version="client.authentication.k8s.io/v1beta1", command="aws", args=["eks","get-token","--cluster-name", module.eks.cluster_name] } }`.
main.tf also creates costwatch pod-identity role (CE read-only JSON policy) in dev+prod.
backend.tf: empty `backend "s3" {}` (Makefile passes bucket/key/region/use_lockfile).

**Steps:**
- [ ] Write dev fully; `terraform -chdir=terraform/envs/dev init -backend=false && validate` → Success.
- [ ] staging + prod (sizing/flags differ only in locals/tfvars); validate each.
- [ ] `tflint --recursive`; commit `feat(terraform): dev/staging/prod environments`.

### Task 5: GitOps tree

**Files:**
- `gitops/envs/<env>/apps/*.yaml` — ArgoCD Applications: `platform`, `observability` (multi-source: kps chart + values from git), `observability-config`, `prometheus-adapter`, `sample-api`, `costwatch` (dev/prod), mesh apps (staging/prod): `gateway-api-crds` (kustomize remote base v1.3.x), `istio-base`(wave -3), `istiod`(-2), `istio-cni`(-2), `ztunnel`(-1), `mesh-policies`.
- `gitops/platform/{base,overlays/{dev,staging,prod}}`: namespaces (`apps`, `costwatch`; PSS restricted; ambient label in staging/prod overlays), priorityclasses, LimitRange+ResourceQuota, default-deny ingress netpol + allows (ALB→api, api→worker, monitoring scrape; +15008 HBONE in mesh overlays), gp3 default StorageClass + gp2 un-default patch (ServerSideApply), NodeLocal DNSCache (prod overlay).
- `gitops/mesh/policies/`: PeerAuthentication STRICT (apps ns), AuthorizationPolicy api→worker only, waypoint Gateway (`istio-waypoint` class) + ns `use-waypoint` label, HTTPRoute (Service parentRef `sample-worker`, retries+timeout).
- `gitops/observability/values/kps-{dev,staging,prod}.yaml` (retention/PV/resources per env; grafana sidecar dashboards), `values/adapter-{dev,prod...}.yaml` (rule exposing `http_requests_per_second` from `http_requests_total`), `config/{slo-burnrate.yaml,ops-alerts.yaml,dashboard-red.yaml(ConfigMap)}`.
- `gitops/apps/sample-api/{base,overlays/...}`, `gitops/apps/costwatch/{base,overlays/{dev,prod}}` per spec §5.8/§5.11 (probes, preStop, topology spread, no CPU limits, PDBs, HPA v2 — prod adds Pods-metric RPS target; ALB ingress annotations: `target-type: ip`, healthcheck `/healthz`, `deregistration_delay.timeout_seconds=30`).

**Steps:**
- [ ] Write platform base+overlays; `kustomize build gitops/platform/overlays/dev | kubeconform -strict -ignore-missing-schemas` → 0 errors (repeat per overlay).
- [ ] Write app bases/overlays; kubeconform each.
- [ ] Write env Application sets; kubeconform (Application CRD via `-ignore-missing-schemas`).
- [ ] Add `scripts/validate-manifests.sh` looping every kustomization; wire `make kubeconform`.
- [ ] Commit `feat(gitops): argocd apps, platform baseline, mesh, observability`.

### Task 6: sample-api (TDD)

**Files:** `apps/sample-api/{go.mod,main.go,main_test.go,Dockerfile,.dockerignore}`

**Produces (contract for manifests/k6):** listens `:8080`; `GET /` info JSON
`{service,role,version,hostname}`; `GET /work?ms=<0..5000>&kb=<0..1024>`;
`GET /chain?calls=<1..8>` (role=api only; parallel GETs to `WORKER_URL/work`, transport
`MaxIdleConnsPerHost=256`); `/healthz` 200 always; `/readyz` 503 after SIGTERM;
`/metrics` Prometheus (`http_requests_total{route,method,code}`,
`http_request_duration_seconds` histogram). Env: `PORT,ROLE,WORKER_URL,VERSION,SHUTDOWN_DELAY`.

**Steps:**
- [ ] Write `main_test.go` first: table tests for `/work` bounds-clamping, `/chain` with `httptest` worker, `/readyz` flip on shutdown trigger, metrics exposition contains counter.
- [ ] `go test ./...` → FAIL (nothing implemented).
- [ ] Write `main.go` (~250 lines, stdlib + client_golang only); `go vet ./... && go test ./...` → `ok`.
- [ ] Dockerfile: `golang:1.26` build (CGO_ENABLED=0) → `gcr.io/distroless/static-debian12:nonroot`; `.dockerignore`.
- [ ] Commit `feat(sample-api): two-role HTTP service with graceful drain + metrics`.

### Task 7: costwatch (TDD backend, designed frontend)

**Files:**
- backend: `apps/costwatch/backend/{go.mod,cmd/costwatch/main.go,internal/costs/{types.go,client.go,service.go,service_test.go,cache.go,cache_test.go,demo.go},internal/api/{server.go,handlers.go,handlers_test.go,middleware.go},web/dist/index.html(placeholder)}`
- frontend: `apps/costwatch/frontend/{package.json,vite.config.ts,tsconfig.json,index.html,src/{main.tsx,App.tsx,theme.ts,lib/{api.ts,format.ts,mock.ts},components/{KpiTile,TrendChart,BreakdownDonut,StackedExplore,GranularityToggle,GroupBySelect,ResourceTable,Sparkline,FreshnessBadge,States}.tsx,views/{Overview,Explore,Resources}.tsx,styles.css}`
- `apps/costwatch/Dockerfile` (3 stages: node build → go build embedding dist → distroless)

**Interfaces:**
- `internal/costs`: `type CostExplorerAPI interface { GetCostAndUsage(ctx, *costexplorer.GetCostAndUsageInput, ...) (*costexplorer.GetCostAndUsageOutput, error); GetCostForecast(...) }`; `NewService(api CostExplorerAPI, opts...) *Service`; `(s *Service) Summary(ctx) (Summary, error)`; `(s *Service) Costs(ctx, Query) (Series, error)`; `Query{Granularity ∈ HOURLY|DAILY|MONTHLY, GroupBy ∈ SERVICE|LINKED_ACCOUNT|REGION|USAGE_TYPE|RESOURCE_ID|TAG:<key>}`; TTL cache 6h keyed on query shape + singleflight; hourly-unavailable CE error → typed `ErrHourlyNotEnabled` → HTTP 409 `{error, hint}`; `-demo` flag / `DEMO=true` swaps in seeded synthetic generator (`demo.go`).
- REST: `GET /api/summary`, `GET /api/costs?granularity=&groupBy=&days=`, `GET /api/health` (incl. cache stats + data freshness), `/metrics`; SPA served from `embed.FS` with index fallback.
- frontend `lib/api.ts` mirrors those JSON shapes; `VITE_API_BASE` default same-origin.

**Steps:**
- [ ] **Invoke dataviz skill, then frontend-design skill, before any UI code.**
- [ ] Backend TDD: write `service_test.go` (mock CE: aggregation across pages, cache single-flight, hourly-409 mapping, demo determinism) + `handlers_test.go` (routes, content-type, error shape) → `go test ./...` FAIL → implement → PASS; `go vet` clean.
- [ ] Frontend: `npm create vite@latest` layout written by hand (no scaffolder churn); `npm install`; implement views per spec §5.11; `npm run build` (vite outputs to `../backend/web/dist`) + `tsc --noEmit` clean.
- [ ] Rebuild backend with real dist embedded: `go build ./...`; run `./costwatch -demo` locally, `curl :8081/api/summary` sane; screenshot-ready.
- [ ] Dockerfile 3-stage; commit `feat(costwatch): FinOps API + embedded React dashboard`.

### Task 8: k6 load suite

**Files:** `load/k6/{lib.js,smoke.js,ramp.js,spike.js,soak.js,README.md}`
`ramp.js`: `constant-arrival-rate` ladder 1k→17k RPS (`TARGET_RPS`, `BASE_URL` envs),
thresholds `http_req_duration{p(99)}<150`, `http_req_failed<0.001`; spike 3× step; soak
30m\@60% target. README = methodology + with/without-mesh delta procedure.

- [ ] Write scenarios; `node --check` not applicable — validate via `k6 inspect` if k6 installed else CI note; commit `feat(load): k6 scenarios encoding the SLOs`.

### Task 9: CI/CD + hygiene

**Files:** `.github/workflows/{terraform.yml,terraform-apply.yml,app.yml,k8s-validate.yml}`, update `.pre-commit-config.yaml` if gaps found.
Behavior per spec §9 (matrix over changed roots; `terraform test` in CI; plan/apply/ECR
jobs conditional on `vars.AWS_*_ROLE_ARN` being set; app matrix sample-api/costwatch
with buildx arm64+amd64; GitOps promotion PR via `peter-evans/create-pull-request`;
concurrency groups; `permissions: id-token: write, contents: read` minimal).

- [ ] Write workflows; `actionlint` if available (brew install actionlint) else YAML-parse check.
- [ ] Commit `ci: terraform, app build+promote, manifest validation pipelines`.

### Task 10: Documentation set

**Files:** `README.md` (rewrite), `docs/{ARCHITECTURE.md,SCALING.md,RUNBOOK.md,COST.md,SECURITY.md}`, `CONTRIBUTING.md`, `docs/adr/{template.md,README.md,0001..0015-*.md}`
Content contracts: README mermaid diagram + quickstart + honest cost banner; SCALING.md
implements spec §6 table with worked capacity math; RUNBOOK anchors match alert
annotations; ADR list = spec §13 (15 ADRs).

- [ ] Write all; ensure every alert `runbook_url` anchor exists in RUNBOOK.md.
- [ ] Commit `docs: architecture, scaling math, runbook, cost, security, 15 ADRs`.

### Task 11: Full verification sweep

- [ ] `make fmt lint validate test kubeconform` equivalents: `terraform fmt -check -recursive`; validate all 4 roots + 5 modules; `terraform test` in network; `tflint --recursive`; `scripts/validate-manifests.sh`; `go vet/test` both apps; `npm run build`; `helm lint` chart.
- [ ] Fix everything found; re-run to green. Commit `chore: verification fixes`.

### Task 12: Wrap-up

- [ ] Final CLAUDE.md accuracy pass (commands actually exist).
- [ ] Write session memory files (project + preferences learned).
- [ ] Final summary to user: what was built, decisions, how to deploy, next steps.
