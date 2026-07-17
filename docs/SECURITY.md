# SECURITY

Threat model summary, the controls that exist, and the hardening honestly left
undone.

## Trust boundaries

```
internet ──► LB / mesh gateway ──► pods (restricted PSS, default-deny netpol)
GitHub ──OIDC──► scoped IAM roles (plan RO / apply env-gated / ecr main-only)
pods ──Pod Identity──► least-privilege IAM (costwatch: 4 read-only CE actions)
humans ──access entries──► cluster RBAC
```

## Controls by layer

**Supply chain & CI** — zero static AWS keys (OIDC only, trust conditions pin
org/repo/ref/environment); fork PRs get no cloud access; workflow-injection
guidance applied (untrusted text never expression-interpolated into scripts);
checkov + tflint + actionlint in CI; gitleaks in pre-commit; Renovate keeps
pins current; ECR scan-on-push with immutable tags; images are distroless
static (no shell, ~2 MB surface), built from lockfiles.

**Cluster** — access entries API mode (no aws-auth ConfigMap drift), KMS
envelope encryption for Secrets, control-plane audit logs on, IMDSv2 required
hop-limit 1 (containers can't reach instance creds), nodes SSM-only (no SSH
keys), gp3 volumes encrypted, 30-day node expiry keeps AMIs fresh.

**Workloads** — restricted Pod Security Standard enforced at admission
(observability privileged only for node-exporter, istio-ingress baseline);
default-deny ingress NetworkPolicy with explicit allowances; STRICT ambient
mTLS + AuthorizationPolicy in staging/prod (identity, not just IP, gates the
worker); containers run non-root, read-only rootfs, all capabilities dropped;
`automountServiceAccountToken: false` where no API access is needed.

**Data** — costwatch is read-only against CE (resource-level perms don't exist
for CE; the role has exactly four `ce:Get*` actions + a confused-deputy
`aws:SourceAccount` condition); cost data never gets a public path
(ClusterIP + VPC-internal netpol); state bucket: versioned, encrypted,
TLS-only policy, public-access-blocked.

## Deliberate exposures (known, documented)

| Exposure | Rationale | Compensating control |
|---|---|---|
| Public EKS endpoint (dev/staging) | portfolio usability | IAM authn + access entries; CIDR variable; **prod refuses 0.0.0.0/0 via validation** |
| `AdministratorAccess` on the apply role | single-account demo; TF manages IAM itself | OIDC trust pinned to main/environments; org guidance: permission boundary + per-stack roles (comment in bootstrap) |
| UI auth (SSO) ships **off by default** | needs a GitHub org + 3 OAuth apps the operator must create | GitHub SSO for all three UIs is built (ADR-0019) — enable per RUNBOOK #github-sso; until then, nothing is publicly routable (port-forward/VPC-only) |
| Open egress from pods | scope control | private subnets, mesh authz east-west; egress policy listed below |

## Hardening backlog (ordered)

1. ~~SSO for ArgoCD, Grafana, costwatch~~ ✅ done — GitHub OIDC per app
   (ADR-0019): ArgoCD bundled Dex, Grafana `auth.github`, costwatch
   oauth2-proxy on an internal ALB. Opt-in: RUNBOOK #github-sso.
2. Private-only API endpoint + SSM/VPN path (flip `endpoint_public_access`).
3. Egress NetworkPolicy + (optionally) mesh egress gateway.
4. Image signing + verification (cosign + Kyverno/ArgoCD plugin).
5. Runtime detection (Falco/GuardDuty EKS protection) + AWS Budgets alarms.
6. Permission boundaries on CI roles; break-glass procedure documentation.

## Reporting

Portfolio project — open a GitHub issue (no sensitive data in issues; use the
repo owner's email for anything account-specific).
