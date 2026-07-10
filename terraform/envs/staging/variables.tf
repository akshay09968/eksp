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
  description = "CIDRs allowed to reach the public API endpoint. Tighten to your IP."
  type        = list(string)
  default     = ["0.0.0.0/0"]
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
