# AUDIT — structural weaknesses, coverage gaps, refactoring candidates

- **Date:** 2026-07-11 · **Scope:** entire repo at `main` · **Method:** fresh-eyes
  read of every layer + repeated test execution + coverage measurement.
- Effort key: **S** < 1h · **M** half-day · **L** multi-day.

**Found-and-fixed during this audit:** demo mode was non-deterministic at the
ULP level (map-iteration order × float non-associativity; 11/25 test-run
failures). Root-caused and fixed in `demo.go` — kept here as evidence the
audit method (run suites repeatedly, don't trust one green run) earns its cost.

## Remediation log (2026-07-11, same day)

| Finding | Status |
|---|---|
| P0-1 TAG-groupBy paid-query surface | ✅ closed by default; `ALLOWED_TAG_KEYS` allowlist, TDD'd |
| P0-2 public-repo plan/drift leakage | ✅ jobs refuse public repos unless `ALLOW_PUBLIC_PLAN_OUTPUT` set consciously |
| P0-3 external TLS | ⏳ open — needs a domain/cert decision (flags exist) |
| P1-4 cache never evicts | ✅ sweep-on-write + 256-entry hard cap, tested |
| P1-5 partial-apply recovery undocumented | ✅ RUNBOOK §"Partial apply failed" |
| P1-7 macOS-only sed | ✅ portable `sedi()` |
| P1-8 env drift unnoticed | ✅ `scripts/check-env-parity.sh` in `make check` + CI |
| Coverage: TF modules 1/5 | ✅ 5/5 — validation suites with `override_module` stubs (10 cases) |
| Coverage: frontend 0 tests | ✅ vitest, 13 tests (format edge cases, palette slot stability) |
| Coverage: ArgoCD path references unchecked | ✅ `scripts/check-gitops-paths.sh` wired into validate-manifests |
| Coverage: no CI coverage gate / k6 lint | ✅ floors 65/75% in app CI; `load-lint.yml` parses every scenario |
| P1-6 `depends_on` plan noise · P1-9 NodeLocal IP assumption · P2 items | ⏳ open, tracked above |

## Remediation log (2026-07-15)

| Finding | Status |
|---|---|
| P1-6 module-level `depends_on` (issue #2) | ✅ removed from all envs — cluster ordering is implicit via the helm provider's `module.eks` outputs; rationale inline in each main.tf |
| P1-9 NodeLocal CIDR assumption (issue #3) | ✅ guarded — `check-env-parity.sh` fails any env VPC outside 10/8; manifest comment points at the guard |
| Supply chain gate (issue #5) | ✅ publish job: trivy blocks promotion on HIGH/CRITICAL, cosign keyless signing binds digest→workflow identity, SPDX SBOM attached per run |
| sample-api coverage (issue #7) | ✅ configFromEnv, panic-recovery, and full drain-choreography tests added (drain extracted from main() into `(*app).shutdown` for testability); CI floor raised to match measured coverage |
| P2-11/12 refactors (issue #8) | ✅ `costs/service.go` split into service/aggregate/summary; the S3-backend init block now lives once in `.github/actions/tf-init` (used by plan, apply, drift) |

## P0 — fix before operating against a real account

| # | Finding | Why it matters | Fix sketch | Effort |
|---|---|---|---|---|
| 1 | **`TAG:*` groupBy is an unbounded paid-query surface** (`costs/service.go: normalize`). Any tag key is accepted; each distinct key is a cache miss = a billed CE call and a new forever-lived cache entry. | Anyone with network reach to costwatch can run up the CE bill and grow memory unboundedly (cache never sweeps expired entries — see P1-4). | Allowlist tag keys via `ALLOWED_TAG_KEYS` env (reject others with a 400 + hint); cap cache at N entries with expiry sweep. | S–M |
| 2 | **Public-repo operational leakage**: PR plan comments and drift issues publish resource names, CIDRs, and account topology. Inert today (jobs no-op until `AWS_*_ROLE_ARN` vars are set) but one variable away from leaking. | A public portfolio repo + live-account CI = infra internals in public issues/PRs. | Either operate from a private fork, or gate the comment/issue steps on `github.event.repository.private`. Documented in COMPLIANCE.md too. | S |
| 3 | **No TLS on external listeners** (ALB `HTTP:80` in dev, Gateway listener 80 in staging/prod). Acceptable for a synthetic demo; disqualifying for anything real. | Plaintext north-south; also the #1 compliance flag (see COMPLIANCE.md). | ACM cert + `443` listener/ssl-redirect on the ALB annotations; `certificateRefs` listener on the Gateway via cert-manager (flag exists, off). | M |

## P1 — structural weaknesses

| # | Finding | Why it matters | Fix sketch | Effort |
|---|---|---|---|---|
| 4 | **costwatch cache never evicts** expired entries (only overwrites on re-fetch); `stats()` counts them forever. | Slow leak; amplifies P0-1. | Sweep on write (or ticker); bound map size. | S |
| 5 | **Same-apply provider coupling**: helm provider config reads `module.eks` outputs. On partial apply failure, provider init errors can mask the root cause; destroy ordering is delicate. | The classic single-apply wart — accepted (ADR-0004) but under-documented operationally. | RUNBOOK section: recover with `terraform apply -target=module.eks`, then full apply; long-term option: split cluster/workload roots. | S doc / L split |
| 6 | **Module-level `depends_on` chains** (`karpenter → addons → gitops` in envs) force conservative planning — data sources in dependent modules defer to apply, producing "known after apply" noise and slower plans. | Plan legibility + occasional spurious replacements. | Replace with implicit dependencies (pass an output through) where ordering truly matters; drop the rest. | M |
| 7 | **`scripts/configure-repo.sh` is macOS-only** (`sed -i ''`). | First Linux contributor hits a wall on step 3 of the quickstart. | Portable in-place sed wrapper (or `perl -pi -e`). | S |
| 8 | **Env `variables.tf` triplication can drift silently** (already diverged deliberately for prod; nothing distinguishes deliberate from accidental). | ADR-0002 accepts duplication; it doesn't accept *unnoticed* divergence. | CI check: diff dev/staging shared blocks, allowlist known prod deltas. | S |
| 9 | **NodeLocal DNSCache hardcodes `172.20.0.10`** with a comment-level assumption (VPC in 10/8 ⇒ EKS picks 172.20/16 service CIDR). | True today for all three envs; silently wrong if someone adds a 172.16/16 VPC. | Assert at apply time: output the cluster service CIDR and fail overlay build on mismatch (script), or template the IP from a Terraform output. | S–M |
| 10 | **Metrics middleware duplicated** (`sample-api/main.go` and `costwatch/internal/api/server.go`: instrument + statusWriter). | Two copies is fine; the third copy is how drift starts. | Note only — extract a tiny shared module when a third service appears. | — |

## Test coverage gaps (measured)

| Area | Now | Gap | Add | Effort |
|---|---|---|---|---|
| sample-api | **67.8%** | panic-recovery path, `configFromEnv`, full SIGTERM→drain→Shutdown sequence (only the readiness flip is tested) | table test for env parsing; drain e2e test with a real `httptest` server + SIGTERM-equivalent trigger; a handler that panics on demand under test | S–M |
| costwatch/costs | **80.1%** | cache expiry/sweep, Summary partial-failure paths (forecast error tolerated — untested), demo monthly partial-month edge | expiry test with fake clock; forecast-error mock; month-boundary demo test | S–M |
| costwatch/api | **87.3%** | built-UI fallback hint page; 502-mapping branch | fstest without index.html; error-injecting service | S |
| costwatch frontend | **0 tests** (typecheck only) | `lib/format` (money/period/csv), `lib/api` error mapping, slot stability in `theme.ts` | vitest + 10–15 unit tests; no DOM testing needed for v1 | M |
| Terraform | **1 of 5 modules** (network: 4 cases) | eks-cluster/karpenter/addons/gitops-bootstrap have zero tftests | mock-provider tests for variable validation + key wiring assertions per module | M |
| Cross-layer | none | an ArgoCD `Application.path` pointing at a renamed dir passes kubeconform but breaks sync | script: assert every `path:` in `gitops/envs/*` exists; wire into `make kubeconform` + CI | S |
| CI | no coverage gate; k6 scripts never parsed | regressions invisible; broken load script found at load-test time | `-coverprofile` + threshold step; `k6 inspect` job (docker) | S |

## P2 — refactoring candidates

| # | Candidate | Trade-off | Effort |
|---|---|---|---|
| 11 | Split `costs/service.go` (368 lines): `aggregate.go`, `summary.go` | pure legibility win | S |
| 12 | The `init -backend-config` block is copy-pasted across 3 workflows → composite action | one place to change the backend contract | S–M |
| 13 | Per-env ArgoCD Application YAML ×3 → ApplicationSet with an env generator | DRY vs. the explicit-per-env legibility ADR-0002 favors; do it only if envs multiply | M |
| 14 | `make validate` re-runs `init` every time (slow) | skip when `.terraform` exists + `-upgrade` escape hatch | S |
| 15 | Frontend bundle 618 KB (Recharts) | code-split the chart lib (`manualChunks`) if the UI grows | S |

## Suggested order of attack

P0-1/2 (S, do together) → P1-7 (S) → coverage quick wins (cross-layer path
check, coverage gate) → P0-3 when a domain/cert enters the picture → P1-5 doc
→ the rest opportunistically.
