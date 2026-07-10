variable "env_name" {
  description = "Environment this ArgoCD instance manages (dev/staging/prod)."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.env_name)
    error_message = "env_name must be dev, staging, or prod."
  }
}

variable "repo_url" {
  description = "Git URL of this repository (what ArgoCD syncs). Set after the first push; empty skips the root app so a fresh account can bootstrap before the repo exists remotely."
  type        = string
  default     = ""
}

variable "target_revision" {
  description = "Git revision ArgoCD tracks."
  type        = string
  default     = "main"
}

variable "argocd_chart_version" {
  description = "argo-cd helm chart version."
  type        = string
  # renovate: datasource=helm depName=argo-cd registryUrl=https://argoproj.github.io/argo-helm
  default = "10.1.3"
}

variable "argocd_apps_chart_version" {
  description = "argocd-apps helm chart version (renders the root Application)."
  type        = string
  # renovate: datasource=helm depName=argocd-apps registryUrl=https://argoproj.github.io/argo-helm
  default = "2.0.5"
}
