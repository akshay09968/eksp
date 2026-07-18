# eksp — EKS Platform + costwatch

Production-grade AWS EKS platform (Terraform + ArgoCD GitOps) engineered for
millions of requests, plus **costwatch**, a FinOps web app tracing AWS spend
hourly/daily/monthly. Portfolio project — quality bar is "staff engineer review".

## Map

| Path | What lives there | Owned by | Layer conventions |
|---|---|---|---|
| `terraform/` | bootstrap, module wrappers, envs, karpenter chart | Terraform | `terraform/CLAUDE.md` |
| `gitops/` | everything ArgoCD syncs (platform, mesh, observability, apps) | ArgoCD | `gitops/CLAUDE.md` |
| `apps/` | sample-api (scale demo) + costwatch (Go+React FinOps) | app CI | `apps/CLAUDE.md` |
| `load/k6/` | load scenarios encoding the SLOs | — | thresholds = SLOs |
| `docs/adr/` | every non-obvious decision — read before proposing changes | — | `/new-adr` skill |
| `docs/AUDIT.md` | known weaknesses + remediation log | — | work top-down; `/debt-review` re-audits |

**The boundary rule (ADR-0004):** needs AWS IAM or must exist before workloads
schedule → Terraform. Everything else in-cluster → `gitops/` (ArgoCD).

## Commands

- `make check` — everything CI runs: fmt, tflint, validate (4 roots),
  tf-test (5 module suites, mocked), helm-lint, kubeconform + path guards,
  go vet+test, env-parity. Run before claiming done; paste the tail.
- `make costwatch-demo` — run costwatch locally on synthetic data (no AWS).
- `make bootstrap` / `make init plan apply ENV=dev` — real deploys (human only).
- Work queue: `gh issue list --label good-for-agents` — sized for a session.

## Definition of done

1. `make check` green locally (paste output, don't assert).
2. New decision → ADR (`/new-adr`). New alert → RUNBOOK anchor. New variable →
   description + validation + tftest. Coverage floors never go down.
3. Docs updated in the same commit; conventional-commit message.

## Guardrails (hard)

- **Never** run `terraform apply|destroy`, mutating `kubectl`/`helm`, or
  anything touching state files — deploys are explicit human actions via the
  Makefile.
- Never commit secrets, `.env`, kubeconfigs, or state; gitleaks runs in
  pre-commit.
- Never invent benchmark numbers — scale claims are design targets until a
  recorded run lands in docs/SCALING.md#results.
- Cost data from costwatch is sensitive; never paste real account spend into
  docs. Plan output stays out of public surfaces (AUDIT P0-2).
