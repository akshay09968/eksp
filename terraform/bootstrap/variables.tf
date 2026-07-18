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

variable "state_replica_region" {
  description = "DR region for state-bucket replication (issue #18). Default is Singapore — nearest default-enabled region to ap-south-1. ap-south-2 (Hyderabad) is closer and keeps data in-country, but is opt-in: enable it on the account first if you use it."
  type        = string
  default     = "ap-southeast-1"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.state_replica_region)) && var.state_replica_region != var.region
    error_message = "state_replica_region must be a valid AWS region different from var.region — same-region replication is not DR."
  }
}
