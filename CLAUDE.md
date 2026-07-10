# eksp — EKS Platform + costwatch

Production-grade AWS EKS platform (Terraform + ArgoCD GitOps) engineered for
millions of requests, plus **costwatch**, a FinOps web app tracing AWS spend
hourly/daily/monthly. Portfolio project — quality bar is "staff engineer review".

## Map

| Path | What lives there | Owned by |
|---|---|---|
| `terraform/bootstrap` | State bucket, GitHub OIDC roles, ECR (local state, applied once) | Terraform |
| `terraform/modules/*` | Thin opinionated wrappers over `terraform-aws-modules/*` | Terraform |
| `terraform/envs/{dev,staging,prod}` | Env compositions; sizing differs, shape doesn't | Terraform |
| `terraform/charts/karpenter-resources` | Local helm chart templating NodePools/EC2NodeClass | Terraform |
| `gitops/**` | Everything ArgoCD syncs (platform, mesh, observability, apps) | ArgoCD |
| `apps/sample-api` | Go scale-demo service (one binary, ROLE=api\|worker) | app CI |
| `apps/costwatch` | FinOps app: Go backend + embedded React UI | app CI |
| `load/k6` | Load scenarios encoding the SLOs | — |
| `docs/adr/` | Every non-obvious decision has an ADR — read before proposing changes | — |

**The boundary rule (ADR-0004):** needs AWS IAM or must exist before workloads
schedule → Terraform. Everything else in-cluster → `gitops/` (ArgoCD). Never install
cluster software from Terraform unless it meets that test.

## Commands

- `make check` — everything CI runs: fmt-check, tflint, validate (all roots),
  terraform test (mocked), helm-lint, kubeconform, go vet+test. Run before claiming done.
- `make validate` / `make tf-test` / `make kubeconform` / `make app-test` — individually.
- `make costwatch-demo` — run costwatch locally on synthetic data (no AWS).
- `make bootstrap` / `make init plan apply ENV=dev` — real deploys (human only).

## Conventions

- Terraform: resources named `eksp-<env>-*`; tags come from provider `default_tags`
  (never hand-tag); module inputs validated with `validation` blocks; every module has
  `versions.tf` with pessimistic (`~>`) provider constraints.
- Chart/module versions are pinned and carry a `# renovate:` comment — keep the comment
  when editing the pin.
- Kubernetes: kustomize base+overlay; requests always set; **no CPU limits**
  (ADR in docs/adr — don't "fix" this); PDB + topologySpreadConstraints on anything
  with >1 replica; every Deployment has preStop + readiness aligned with ALB
  deregistration (30s).
- Go: stdlib-first; table-driven tests; interfaces at the consumer (see
  `costwatch/internal/costs.CostExplorerAPI` for the pattern).
- Docs: decisions → `docs/adr/NNNN-*.md` (use template); operational knowledge →
  `docs/RUNBOOK.md`; alert annotations must link to a RUNBOOK anchor that exists.

## Definition of done

1. `make check` green locally (paste the tail of the output, don't just say "passes").
2. New decision? → ADR. New alert? → RUNBOOK anchor. New variable? → description +
   validation + sane default.
3. Docs updated in the same commit; conventional-commit message.

## Guardrails (hard)

- **Never** run `terraform apply|destroy`, mutating `kubectl`/`helm`, or anything that
  touches state files — even if asked casually; deploys are explicit human actions via
  the Makefile.
- Never commit secrets, `.env`, kubeconfigs, or state; gitleaks runs in pre-commit.
- Never invent benchmark numbers — scale claims are design targets until someone runs
  `make k6-ramp` and records results in docs/SCALING.md.
- Cost data from costwatch is sensitive; never paste real account spend into docs.
