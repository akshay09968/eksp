# staging: prod's shape at reduced scale — 3 AZ (validates zone spread), single NAT
# (cost), ECR/STS endpoints (validates the endpoint path), mesh enabled (gitops).
# No costwatch here: it reads account-wide billing, dev+prod cover it.

locals {
  env          = "staging"
  cluster_name = "eksp-staging"
}

module "network" {
  source = "../../modules/network"

  name         = local.cluster_name
  cluster_name = local.cluster_name
  vpc_cidr     = "10.20.0.0/16"

  az_count          = 3
  enable_nat_per_az = false
  enable_flow_logs  = false

  interface_endpoints = ["ecr.api", "ecr.dkr", "sts"]
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

  system_node_instance_types = ["m7g.large"]
  system_node_min            = 2
  system_node_max            = 4
  system_node_desired        = 2
}

module "karpenter" {
  source = "../../modules/karpenter"

  cluster_name = module.eks.cluster_name

  cpu_limit_spot      = 200
  cpu_limit_on_demand = 64
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
