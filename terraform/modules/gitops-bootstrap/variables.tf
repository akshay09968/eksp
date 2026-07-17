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

# --- GitHub SSO (ADR-0019). Empty github_sso_org keeps SSO off entirely, so
#     the platform still applies clean before an OAuth app is registered.

variable "github_sso_org" {
  description = "GitHub org whose members may log into ArgoCD. Empty disables SSO (Dex stays off). The OAuth app's client id/secret live in the argocd-secret Secret you create — see docs/RUNBOOK.md#github-sso — never here."
  type        = string
  default     = ""
}

variable "github_sso_admin_team" {
  description = "GitHub team (slug, within github_sso_org) mapped to ArgoCD role:admin; everyone else in the org is read-only. E.g. \"platform-admins\"."
  type        = string
  default     = ""
}

variable "argocd_url" {
  description = "External URL ArgoCD is reached at — the OAuth callback base. Defaults to the port-forward address; set to the real https host once ArgoCD has an ingress + TLS (issue #1)."
  type        = string
  default     = "http://localhost:8080"

  validation {
    condition     = can(regex("^https?://", var.argocd_url))
    error_message = "argocd_url must be an http(s) URL — it becomes the OAuth callback base GitHub redirects to."
  }
}
