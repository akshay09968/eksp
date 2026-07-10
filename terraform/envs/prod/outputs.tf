output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = module.eks.cluster_endpoint
}

output "region" {
  description = "AWS region."
  value       = var.region
}

output "kubeconfig_command" {
  description = "Run this to talk to the cluster."
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}

output "next_steps" {
  description = "Post-apply pointers."
  value       = <<-EOT
    1. ${var.gitops_repo_url == "" ? "Push this repo, then re-apply with -var gitops_repo_url=<https url> to create the ArgoCD root app." : "ArgoCD is syncing gitops/envs/dev/apps from ${var.gitops_repo_url}."}
    2. make argocd-ui      # ArgoCD  (password: make argocd-password)
    3. make grafana-ui     # Grafana
    4. make costwatch-ui   # costwatch
  EOT
}
