variable "region" {
  description = "AWS region for the state bucket, OIDC roles, and ECR repositories."
  type        = string
  default     = "ap-south-1"
}

variable "github_org" {
  description = "GitHub org/user that owns this repository (OIDC trust condition)."
  type        = string

  validation {
    condition     = length(var.github_org) > 0
    error_message = "github_org is required — OIDC trust must be scoped to your org."
  }
}

variable "github_repo" {
  description = "GitHub repository name (OIDC trust condition)."
  type        = string

  validation {
    condition     = length(var.github_repo) > 0
    error_message = "github_repo is required — OIDC trust must be scoped to your repo."
  }
}

variable "ecr_repositories" {
  description = "ECR repositories to create for application images."
  type        = list(string)
  default     = ["eksp/sample-api", "eksp/costwatch"]
}
