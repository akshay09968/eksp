# Architecture Decision Records

Every non-obvious decision, with the alternatives that lost. New decision →
copy [template.md](template.md), next number, link it from code comments.

| # | Decision |
|---|---|
| [0001](0001-terraform-wrapped-modules.md) | Terraform (over Pulumi/CDK), thin wrappers over community modules |
| [0002](0002-directory-per-env.md) | Directory-per-environment over Terragrunt/workspaces |
| [0003](0003-karpenter.md) | Karpenter over Cluster Autoscaler |
| [0004](0004-terraform-gitops-boundary.md) | The Terraform ↔ GitOps ownership boundary |
| [0005](0005-pod-identity.md) | EKS Pod Identity over IRSA |
| [0006](0006-alb-ip-mode.md) | LB → pod `ip` targeting (no NodePort hop) |
| [0007](0007-self-hosted-prometheus.md) | kube-prometheus-stack over AMP/Container Insights |
| [0008](0008-s3-native-locking.md) | S3-native state locking (no DynamoDB) |
| [0009](0009-spot-graviton.md) | Spot-first + Graviton compute strategy |
| [0010](0010-kustomize-for-apps.md) | Kustomize for apps; helm only for third-party charts |
| [0011](0011-istio-ambient-mesh.md) | Istio **ambient** over sidecars/Linkerd/Cilium/App Mesh |
| [0012](0012-no-cpu-limits.md) | Memory limits yes, CPU limits no |
| [0013](0013-argocd-over-flux.md) | ArgoCD over Flux |
| [0014](0014-cost-explorer-first.md) | costwatch: CE API first, CUR→Athena as opt-in deep path |
| [0015](0015-embedded-spa.md) | costwatch UI embedded via embed.FS |
| [0016](0016-drift-detection.md) | Two-layer drift detection |
| [0017](0017-api-gateway-strategy.md) | API gateway: in-mesh gateway, not Amazon API Gateway |
| [0018](0018-stdlib-sample-app.md) | sample-api stays stdlib-only |
