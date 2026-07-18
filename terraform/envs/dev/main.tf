# dev: 2 AZ, single NAT, small Graviton system nodes, tight Karpenter ceilings.
# Cost floor ≈ $170/mo idle (see docs/COST.md). Same shape as prod, smaller knobs.

locals {
  env          = "dev"
  cluster_name = "eksp-dev"
}

module "network" {
  source = "../../modules/network"

  name         = local.cluster_name
  cluster_name = local.cluster_name
  vpc_cidr     = "10.10.0.0/16"

  az_count          = 2
  enable_nat_per_az = false # one shared NAT — dev trades AZ-independence for ~$33/mo per extra NAT
  enable_flow_logs  = false

  interface_endpoints = [] # dev eats the NAT data charge instead of $7.3/mo/endpoint/AZ
}

module "eks" {
  source = "../../modules/eks-cluster"

  name               = local.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids
  intra_subnet_ids   = module.network.intra_subnet_ids

  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs
  admin_principal_arns         = var.admin_principal_arns

  system_node_instance_types = ["t4g.medium"]
  system_node_min            = 2
  system_node_max            = 4
  system_node_desired        = 2
}

module "karpenter" {
  source = "../../modules/karpenter"

  cluster_name = module.eks.cluster_name

  cpu_limit_spot      = 48
  cpu_limit_on_demand = 16

  # dev deliberately rides ami_alias = al2023@latest (module default): fresh
  # AMIs get burned in here before the staging/prod dated pins bump (issue #15).

  controller_replicas = 1 # dev: no HA needed; prod runs 2
  controller_resources = {
    cpu    = "100m"
    memory = "256Mi"
  }
}

# No depends_on: the helm provider is configured from module.eks outputs, so
# every release in this module already waits for the cluster (AUDIT P1-6 —
# module-level depends_on only serialized the apply and deferred data sources
# to apply time). Addons schedule on the system MNG, not Karpenter capacity.
module "addons" {
  source = "../../modules/addons"

  cluster_name = module.eks.cluster_name
  vpc_id       = module.network.vpc_id
  region       = var.region
}

# No depends_on (AUDIT P1-6): cluster ordering is implicit via the helm
# provider; ArgoCD needs nothing from addons at install time — apps that
# create Ingresses simply retry until the ALB controller is Ready.
module "gitops" {
  source = "../../modules/gitops-bootstrap"

  env_name = local.env
  repo_url = var.gitops_repo_url

  # SSO (ADR-0019) — off until github_sso_org is set; secrets live in
  # operator-created K8s Secrets, never in state (RUNBOOK #github-sso).
  github_sso_org        = var.github_sso_org
  github_sso_admin_team = var.github_sso_admin_team
  argocd_url            = var.argocd_url
}

# ---------------------------------------------------------------------------
# costwatch: read-only Cost Explorer credentials via Pod Identity. Written as
# raw resources (not the pod-identity module) because the policy is bespoke and
# small enough that explicit is clearer.
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "costwatch_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }

    # Confused-deputy guard: only associations in this account can assume it.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

data "aws_iam_policy_document" "costwatch_read" {
  statement {
    sid = "CostExplorerReadOnly"
    actions = [
      "ce:GetCostAndUsage",
      "ce:GetCostForecast",
      "ce:GetDimensionValues",
      "ce:GetTags",
    ]
    # Cost Explorer does not support resource-level permissions.
    resources = ["*"]
  }
}

resource "aws_iam_role" "costwatch" {
  name               = "${local.cluster_name}-costwatch"
  assume_role_policy = data.aws_iam_policy_document.costwatch_trust.json
}

resource "aws_iam_role_policy" "costwatch" {
  name   = "cost-explorer-read"
  role   = aws_iam_role.costwatch.id
  policy = data.aws_iam_policy_document.costwatch_read.json
}

resource "aws_eks_pod_identity_association" "costwatch" {
  cluster_name    = module.eks.cluster_name
  namespace       = "costwatch"
  service_account = "costwatch"
  role_arn        = aws_iam_role.costwatch.arn
}
