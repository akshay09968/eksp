provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "eksp"
      Environment = local.env
      ManagedBy   = "terraform"
    }
  }
}

# Helm provider talks to the cluster created in this same configuration — the
# standard single-apply pattern: endpoint/CA come from module outputs and auth is
# an exec to `aws eks get-token` at apply time (never a cached token).
provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
    }
  }
}
