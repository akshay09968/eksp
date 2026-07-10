output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 cluster CA bundle (for provider exec auth)."
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_version" {
  description = "Running Kubernetes version."
  value       = module.eks.cluster_version
}

output "node_security_group_id" {
  description = "Shared node security group (tagged for Karpenter discovery)."
  value       = module.eks.node_security_group_id
}

output "oidc_provider_arn" {
  description = "IRSA OIDC provider ARN (Pod Identity is the default; kept for the rare IRSA-only integration)."
  value       = module.eks.oidc_provider_arn
}
