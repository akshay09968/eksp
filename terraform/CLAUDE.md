# terraform/ conventions

Loaded when working in this tree. Root CLAUDE.md has the map + guardrails.

## Shape

- `modules/*` are thin wrappers over `terraform-aws-modules/*`: pin upstream
  with `~>`, encode opinions (taints, tags, validation), expose a small
  surface. Envs compose wrappers — never call community modules directly
  from envs.
- Every module: `versions.tf` (floor `>= 1.10`, pessimistic providers),
  `variables.tf` with descriptions + `validation` blocks, `outputs.tf` with
  descriptions.
- Naming `eksp-<env>-*`; tags come from provider `default_tags` — never
  hand-tag resources.
- Version pins carry `# renovate: datasource=...` comments — keep the comment
  attached when bumping.

## Testing (the part that trips people up)

- Every module has `tests/*.tftest.hcl`, offline: `mock_provider` + plan mode.
- **Stub community modules with `override_module`** — mocked
  `aws_iam_policy_document` returns invalid JSON and drowns `expect_failures`
  otherwise (see any existing suite for the pattern).
- New variable → validation block → `expect_failures` test for the invalid
  case. Valid-path planning of big community modules under mocks is not worth
  the fight; validate contracts, not upstream internals.
- Run: `make tf-test` (loops every `modules/*/tests`).

## Envs

- dev/staging/prod duplication is deliberate (ADR-0002), but guarded:
  `scripts/check-env-parity.sh` requires versions/backend/providers/outputs to
  stay identical (dev↔staging↔prod) and variables.tf identical dev↔staging.
  Prod variables.tf is the documented exception. Diverging a shared file =
  update that script's exception list in the same PR.
- Sizing/knobs live in each env's `main.tf` locals + module args with a
  comment explaining the delta. tfvars is for user-specific values only.
- Backend is partial config — `make init ENV=<env>` injects bucket/key/region/
  `use_lockfile`; never hardcode a bucket.

## Sharp edges

- helm provider reads `module.eks` outputs in the same apply. Partial-failure
  recovery: RUNBOOK §"Partial apply failed" (`-target=module.eks` first).
- Module-level `depends_on` in envs causes plan noise (AUDIT P1-6) — prefer
  passing an output through for ordering; don't add more.
- The karpenter NodePools/EC2NodeClass render from
  `terraform/charts/karpenter-resources` (local chart) so one apply works —
  `helm lint` it after edits (`make helm-lint`).
