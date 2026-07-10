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

module "addons" {
  source = "../../modules/addons"

  cluster_name = module.eks.cluster_name
  vpc_id       = module.network.vpc_id
  region       = var.region

  depends_on = [module.karpenter]
}

module "gitops" {
  source = "../../modules/gitops-bootstrap"

  env_name = local.env
  repo_url = var.gitops_repo_url

  depends_on = [module.addons]
}
