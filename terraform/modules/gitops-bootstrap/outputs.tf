output "argocd_namespace" {
  description = "Namespace ArgoCD runs in."
  value       = "argocd"
}

output "root_app_enabled" {
  description = "Whether the root Application was created (false until repo_url is set)."
  value       = var.repo_url != ""
}
