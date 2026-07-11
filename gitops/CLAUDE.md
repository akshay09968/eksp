# gitops/ conventions

Loaded when working in this tree. Everything here is ArgoCD-owned (ADR-0004):
after bootstrap, the cluster converges to this directory — a merged PR *is*
the deploy.

## Structure contract

- `envs/<env>/apps/*.yaml` — one ArgoCD Application per component, ordered by
  `argocd.argoproj.io/sync-wave` (platform -5 → CRDs -4 → istio -3..-1 →
  policies/observability 0/1 → workloads 2).
- `platform/`, `mesh/`, `observability/`, `apps/*` — kustomize bases +
  per-env overlays. Env differences must be scalar patches (replicas, HPA
  bounds, labels), not structural forks.
- Third-party software = upstream helm chart + values (multi-source `$values`
  pattern); our workloads = plain YAML + kustomize (ADR-0010). Don't author
  in-house helm charts here.

## Invariants the guards enforce (CI runs both)

- `scripts/validate-manifests.sh` — kubeconform strict on every overlay.
- `scripts/check-gitops-paths.sh` — every Application `path:`/`$values` ref
  must resolve. Renaming a directory means updating every referencing
  Application in the same commit.

## Rules that look optional but aren't

- Workload pods: requests always; memory limits; **no CPU limits**
  (ADR-0012). Probes + `SHUTDOWN_DELAY`-based drain; >1 replica ⇒ PDB +
  topologySpreadConstraints.
- Namespaces get PSS labels in `platform/base/namespaces.yaml`; default-deny
  NetworkPolicy with explicit allowances — mesh envs need the HBONE (15008)
  allowance.
- staging/prod ingress goes through the Istio gateway (`mesh/gateway/`);
  ALB Ingress exists **only in the dev overlay** — STRICT ambient mTLS rejects
  out-of-mesh plaintext (ADR-0017). Don't "add the missing Ingress" to prod.
- Image tags: `newTag` in overlays is bumped by the CI promotion PR — the
  comment `# bumped by the CI promotion PR` is the sed anchor; keep it.
- Chart `targetRevision` pins carry `# renovate:` comments — keep them.
- New alert ⇒ `runbook_url` pointing at an anchor that exists in
  docs/RUNBOOK.md (add the section in the same PR).
