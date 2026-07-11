# RUNBOOK

Operational procedures. Alert annotations link to anchors here — keep headings
stable. Everything assumes `make kubeconfig ENV=<env>` has run.

## Access

| What | How |
|---|---|
| cluster | `make kubeconfig ENV=dev` |
| ArgoCD | `make argocd-ui` · password: `make argocd-password` |
| Grafana | `make grafana-ui` · password: `kubectl -n observability get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' \| base64 -d` |
| costwatch | `make costwatch-ui` |
| a node (no SSH) | `aws ssm start-session --target <instance-id>` |

---

## SLO alerts

### slo-fast-burn

`SampleApiErrorBudgetFastBurn` — 14.4× burn on 5m+1h windows. Budget gone in
<2 days at this rate. **This is a page. Something changed.**

1. `kubectl -n apps get pods -o wide` — crash loops? all in one AZ/node?
2. Grafana → sample-api RED: did a deploy land at the inflection? →
   **rollback = revert the promotion PR** (ArgoCD converges in ~1 min).
3. 5xx from upstream vs app? Check ALB/gateway target health:
   `kubectl -n istio-ingress get gateway,pods` / ALB console target group.
4. Spot interruption storm? `kubectl get events -A --field-selector reason=Interruption`
   — fallback pool should be absorbing; check its CPU ceiling isn't hit.

### slo-slow-burn

`SampleApiErrorBudgetSlowBurn` — 6× on 30m+6h. Same tree as fast-burn, less
adrenaline; usually a partial failure (one AZ, one node class, one dependency).

### slo-ticket-burn

`SampleApiErrorBudgetOnPaceToExhaust` — >1× for days. Not urgent; file the
ticket, find the slow leak (retries masking failures, a client misbehaving).

---

## Capacity alerts

### hpa-at-max

HPA pinned at `maxReplicas` 15 min+. Demand exceeded planning.

1. Real traffic or a runaway client? RED dashboard rate by source (ALB logs if
   enabled).
2. Legit? Raise `maxReplicas` in the env overlay
   (`gitops/apps/sample-api/overlays/<env>`), PR, merge — ArgoCD applies.
3. Check nodes followed: `kubectl get nodeclaims` — if pending pods exist too,
   see [pods-pending](#pods-pending).

### pods-pending

Pods unschedulable 15 min+. Karpenter isn't placing them.

1. `kubectl describe pod <p>` → the scheduler's reason is in Events.
2. `kubectl get nodepools -o wide` — pool at its CPU `limits`? Raise in
   `terraform/envs/<env>/main.tf` (karpenter module) and apply.
3. Spot capacity errors? `kubectl -n karpenter logs deploy/karpenter | grep -i insufficient`
   — the on-demand fallback should catch; verify its ceiling.
4. Quota? ResourceQuota in `apps` ns: `kubectl -n apps describe quota`.

### latency-high

p99 > 150 ms without error-budget burn. Usually saturation, not failure:
CPU throttling is impossible (no CPU limits) so look at: worker fan-out depth,
DNS latency (CoreDNS panel; is NodeLocal healthy on every node —
`kubectl -n kube-system get ds node-local-dns`), noisy-neighbor spot instance
(check per-pod latency spread), or conntrack pressure (`node_nf_conntrack_entries`).

### costwatch-down

costwatch target down 10 min+. Cost visibility lost, nothing user-facing.
`kubectl -n costwatch logs deploy/costwatch` — usual suspects: Pod Identity
association missing after a cluster rebuild (re-apply env), CE permissions
changed, or OOM (raise the memory limit in the overlay).

---

## Drift

Nightly workflow opened a `drift` issue: someone changed AWS outside Terraform.

1. Read the plan diff in the issue. Identify *what* and, via CloudTrail, *who*.
2. Manual hotfix during an incident? Backport it: change the code to match
   reality, plan should go clean. Unsanctioned? `make apply ENV=<env>` reverts.
3. Never `terraform state rm`/`import` as a first move — understand first.
4. Kubernetes-side drift never reaches this workflow: ArgoCD self-heals it
   (check the app's History tab for what it reverted).

---

## Routine operations

### EKS version upgrade

Control plane → addons → nodes, one env at a time, dev soak ≥ 1 week:

1. Bump `kubernetes_version` in `terraform/envs/dev`; `make plan apply ENV=dev`.
2. Addons follow automatically (`most_recent = true`) on the next apply.
3. System MNG: apply rolls it (respects CoreDNS PDB).
4. Karpenter nodes: `al2023@latest` + 30d expiry converge naturally; force with
   `kubectl delete nodeclaim <one-at-a-time>` if a CVE demands speed.
5. Watch: `kubectl get nodes` versions, ArgoCD all-green, RED dashboard flat.

### Rotate/drain a node

`kubectl drain <node> --ignore-daemonsets --delete-emptydir-data` — PDBs
gate it; Karpenter replaces it. Never drain more than one AZ's worth at once.

### Spot interruption drill (game day)

`aws ec2 send-spot-instance-interruptions` (Fault Injection Simulator) against
a workload node → expect: 2-min warning consumed from the SQS queue, node
cordoned+drained, replacement claim in <90 s, zero 5xx on the RED dashboard.

### Scale the platform for a launch

Raise HPA max + Karpenter ceilings ahead of time (PR to overlays + env tf),
pre-warm the LB (§SCALING), schedule a disruption-budget freeze window, run
`k6 ramp` at the expected peak in staging first.

### Partial apply failed (helm provider errors mid-apply)

The env roots configure the helm provider from `module.eks` outputs in the same
apply (documented single-apply pattern, ADR-0004). If an apply dies *while the
cluster is half-created*, subsequent plans can fail at helm-provider init with
connection errors that mask the real problem.

Recovery, in order:

1. `terraform apply -target=module.network -target=module.eks` — converge the
   cluster itself first (targeted apply is fine *as a recovery step*).
2. Then a plain `make apply ENV=<env>` — helm provider now has a live endpoint;
   the remaining releases converge.
3. Still failing? `aws eks describe-cluster --name eksp-<env>` — if the cluster
   is ACTIVE and helm still can't connect, it's credentials/network
   (`aws eks get-token`, endpoint CIDRs), not Terraform.

### State lock stuck

S3-native lock (no DynamoDB): `terraform force-unlock <lock-id>` after
confirming no apply is actually running (check Actions + ask humans).

### Full environment teardown

`make destroy ENV=dev` (asks for the env name). Karpenter nodes go first
automatically (NodePool finalizers); if the VPC hangs, it's almost always a
leftover ALB/NLB from a Service the controller created — delete the k8s
Service/Ingress objects first (`kubectl delete ing,svc -A --field-selector ...`)
or remove the stragglers in the console, then re-run destroy.
