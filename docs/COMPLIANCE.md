# COMPLIANCE — SOC 2 / GDPR / HIPAA code-level readiness

What an auditor would flag in *this codebase*, mapped to the frameworks a
platform team's market actually asks about. Honest status per item:
✅ implemented · ⚠️ partial/documented gap · ❌ absent.

**Scope statement (read first):** this platform processes **no personal data by
design** — workloads are a synthetic load service and costwatch, whose data is
*corporate billing information* (confidential, not PII; account IDs and
resource names at most). Demo mode is fully synthetic. That determination is
itself a compliance artifact — auditors want it written down, so it lives here.

## SOC 2 (the one your target market actually requires)

### CC6 — Logical access

| Item | Status | Evidence / gap |
|---|---|---|
| Human cluster access via IAM + access entries, no shared creds | ✅ | `eks-cluster` module, `authentication_mode = "API"` |
| CI access via short-lived OIDC, no static keys | ✅ | `terraform/bootstrap` trust policies pin org/repo/ref/environment |
| Workload identity, least privilege | ✅/⚠️ | Pod Identity everywhere; costwatch = 4 read-only CE actions + confused-deputy condition. **Gap:** apply role is `AdministratorAccess` (documented single-account trade, ADR/SECURITY.md) — an auditor will write this up; the answer is permission boundaries + per-stack roles in an org |
| MFA/SSO on operator UIs (ArgoCD, Grafana, costwatch) | ❌ | port-forward-only today; **top hardening item.** SOC2 auditors treat UI auth as table stakes even for "internal" tools |
| Access reviews | ⚠️ | `admin_principal_arns` is code-reviewed (a real control!) but no periodic review procedure is written |

### CC7 — System operations (monitoring, incidents)

| Item | Status | Evidence / gap |
|---|---|---|
| Control-plane audit logs | ✅ | api/audit/authenticator enabled |
| Alerting with response procedures | ✅ | burn-rate + ops alerts; every `runbook_url` resolves to a RUNBOOK anchor |
| **LB access logs** | ✅ | per-env encrypted S3 bucket (`terraform/modules/network`, TLS-only, public-blocked, lifecycle-expiring); dev ALB Ingress + staging/prod NLB gateway overlays carry the `access_logs`/`access-log` annotations. Live-verify logs land after the first deploy |
| **Log retention policy** | ✅ | flow logs 14d, control-plane group `control_plane_log_retention_days` (30d default, validated), LB access logs `lb_access_log_retention_days` (30d) — all explicit, none on never-expire |
| State-bucket access logging | ❌ | S3 server access logs / CloudTrail data events on `eksp-tfstate-*` — auditors ask who touched state |
| Drift detection | ✅ | two layers (ADR-0016): ArgoCD selfHeal + nightly plan→issue |

### CC8 — Change management

| Item | Status | Evidence / gap |
|---|---|---|
| Peer review, protected paths | ✅ | CODEOWNERS, PR template with risk section |
| Environment gates on deploys | ✅ | apply via GitHub environments; prod reviewers configurable |
| **Branch protection** | ⚠️ | can't live in code — repo-settings checklist: require PRs + status checks on `main` (do this right after first push) |
| Full audit trail of infra changes | ✅ | git history + plan artifacts + CloudTrail (account-level, assumed on) |
| Dependency currency | ✅ | Renovate across TF/helm/Go/npm/actions/docker |

### CC — Vulnerability & supply chain

| Item | Status | Evidence / gap |
|---|---|---|
| Image scanning | ⚠️ | ECR scan-on-push ✅; **no CI gate** — add a trivy job failing on HIGH/CRITICAL before push (S) |
| Image provenance | ❌ | no signing/SBOM — cosign + syft in the publish job is the standard answer (M) |
| Secret scanning | ✅ | gitleaks pre-commit; no secrets in repo (identity over secrets by design) |
| Pinned, immutable artifacts | ✅ | immutable ECR tags; lockfiles committed (`.terraform.lock.hcl`, package-lock, go.sum) |

### Availability (if in scope for your report)

⚠️ Single-instance Prometheus (metrics loss on node loss = accepted, documented);
❌ no state-bucket cross-region replication; ❌ no cluster backup (Velero) —
defensible for stateless workloads, write the determination down when scoping.

## GDPR

Mostly *disclosure and discipline* for this platform, because of the scope
statement above:

| Item | Status | Note |
|---|---|---|
| Records of processing (Art. 30) | ⚠️ | The scope statement above is the seed; formalize if any personal data ever lands (user accounts, request logs with IPs) |
| **Personal data in logs** | ✅ | apps don't log request bodies/IPs; **LB access logs contain client IPs = personal data**, so they ship *with* the 30-day lifecycle expiry from day one — the retention control and the PII source landed together, not as an afterthought |
| Storage limitation | ✅ | every log sink has an explicit bounded window (CC7 row) |
| Data residency | ✅ | everything pinned ap-south-1 except the CE API call (us-east-1, billing metadata only — document in DPA review) |
| Processor chain | ✅ | AWS under its DPA; no other subprocessors |
| Erasure/portability | n/a | no data subjects; revisit on first user-facing feature |

## HIPAA

**This platform is not HIPAA-ready, and says so.** If PHI ever enters scope,
the gap list is: AWS BAA + eligible-services-only review; TLS on every hop
(P0-3 plus in-cluster — ambient mTLS ✅ already covers east-west); PHI data-flow
isolation (separate namespace/account, dedicated node pool); application-level
access audit trails (who viewed what, immutable); formal key rotation +
contingency/backup plan (the availability gaps above become mandatory);
workforce access procedures. Nothing here is architecturally blocked — the
mesh, Pod Identity, and account-per-env layout are the right substrate — but
claiming readiness without those would be false.

## The prioritized compliance to-do (code-level, ordered)

1. **TLS on external listeners** (AUDIT P0-3) — every framework starts here.
2. ~~ALB/NLB access logs + explicit CloudWatch retention everywhere~~ ✅ done —
   the GDPR retention note is baked in (logs + lifecycle shipped together).
3. **Trivy gate in the publish workflow**; cosign+SBOM after.
4. **Repo-settings checklist** post-push: branch protection, required checks,
   (private fork if operating a real account — AUDIT P0-2).
5. **SSO for the three UIs** (oauth2-proxy pattern already in SECURITY.md).
6. State-bucket access logging; AWS Budgets alarm (2-minute console add).
7. Keep this document updated per change — an unmaintained compliance doc is
   worse than none in an audit.
