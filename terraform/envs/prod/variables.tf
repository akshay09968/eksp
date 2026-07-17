variable "region" {
  description = "AWS region."
  type        = string
  default     = "ap-south-1"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.33"
}

variable "endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint. No default in prod — you must consciously choose the exposure."
  type        = list(string)

  validation {
    condition     = !contains(var.endpoint_public_access_cidrs, "0.0.0.0/0")
    error_message = "Prod refuses a world-open API endpoint. Use your office/VPN CIDRs, or switch to a private endpoint (see docs/SECURITY.md)."
  }
}

variable "admin_principal_arns" {
  description = "Extra IAM principals granted cluster-admin (the applier is admin automatically)."
  type        = list(string)
  default     = []
}

variable "gitops_repo_url" {
  description = "HTTPS git URL of this repo for ArgoCD. Leave empty on the first apply (before the repo is pushed); set it and re-apply to create the root app."
  type        = string
  default     = ""
}

# --- GitHub SSO (ADR-0019). All default off; secrets never pass through here —
#     see docs/RUNBOOK.md#github-sso.

variable "github_sso_org" {
  description = "GitHub org whose members may log into the platform UIs. Empty disables SSO."
  type        = string
  default     = ""
}

variable "github_sso_admin_team" {
  description = "GitHub team slug (within github_sso_org) mapped to admin roles. Required when github_sso_org is set."
  type        = string
  default     = ""
}

variable "argocd_url" {
  description = "External URL ArgoCD is reached at — the OAuth callback base. Defaults to the port-forward address; set the real https host once ArgoCD has ingress + TLS (issue #1)."
  type        = string
  default     = "http://localhost:8080"
}
